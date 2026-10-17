import Foundation
import Darwin

/// No credentials are forwarded through redirects, including between local endpoints.
private final class AINoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum AIHTTP {
    static func send(_ request: URLRequest, rpcID: String? = nil) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = request.timeoutInterval
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        let session = URLSession(configuration: configuration, delegate: AINoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw AIError.message("无效的 HTTP 响应") }
        guard (200..<300).contains(response.statusCode) else { throw AIError.message("服务请求失败（HTTP \(response.statusCode)），请检查地址、模型和凭据。") }
        if response.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true {
            var event = "", total = 0
            for try await line in bytes.lines {
                try Task.checkCancellation(); total += line.utf8.count
                guard total <= 8 * 1024 * 1024 else { throw AIError.message("服务响应过大") }
                if line.isEmpty {
                    if let data = event.data(using: .utf8), let object = try? AIJSON.object(data),
                       rpcID == nil || object["id"] as? String == rpcID { return (data, response) }
                    event = ""
                } else if line.hasPrefix("data:") {
                    if !event.isEmpty { event += "\n" }
                    event += String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                }
            }
            throw AIError.message("MCP 事件流未返回对应请求结果")
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation(); data.append(byte)
            guard data.count <= 8 * 1024 * 1024 else { throw AIError.message("服务响应过大") }
        }
        return (data, response)
    }
}

/// JSON-RPC stdio with bounded buffers, deadlines and cancellation of its child process.
final class MCPStdio: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe(), output = Pipe(), errors = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var pending: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var closed = false
    init(configuration: MCPServerConfiguration, environment: [String: String]) throws {
        guard configuration.command.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: configuration.command) else {
            throw AIError.message("stdio 命令必须为可执行文件的绝对路径")
        }
        process.executableURL = URL(fileURLWithPath: configuration.command)
        process.arguments = configuration.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { self?.close() } else { self?.receive(data) }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        process.terminationHandler = { [weak self] _ in self?.close() }
        do { try process.run() } catch { close(); throw error }
    }
    func call(_ method: String, params: [String: Any], notification: Bool = false) async throws -> [String: Any] {
        let id = UUID().uuidString
        var object: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        if !notification { object["id"] = id }
        let data = try JSONSerialization.data(withJSONObject: object) + Data([10])
        if notification { try write(data); return [:] }
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if closed { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                pending[id] = continuation; lock.unlock()
                do { try write(data) } catch { finish(id, result: .failure(error)) }
                DispatchQueue.global().asyncAfter(deadline: .now() + 90) { [weak self] in
                    self?.finish(id, result: .failure(AIError.message("MCP 请求超时")))
                }
            }
        }, onCancel: { self.close() })
    }
    private func write(_ data: Data) throws {
        lock.lock(); let isClosed = closed; lock.unlock()
        guard !isClosed else { throw CancellationError() }
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    private func receive(_ data: Data) {
        lock.lock(); buffer.append(data)
        guard buffer.count <= 8 * 1024 * 1024 else { lock.unlock(); close(); return }
        var messages: [Data] = []
        while let end = buffer.firstIndex(of: 10) { messages.append(buffer.subdata(in: 0..<end)); buffer.removeSubrange(0...end) }
        lock.unlock()
        for data in messages {
            guard let object = try? AIJSON.object(data), let requestID = object["id"] else { continue }
            if object["method"] != nil {
                // Server-initiated sampling/elicitation is deliberately not advertised.
                if let data = try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": requestID, "error": ["code": -32601, "message": "Client method not supported"]]) { try? write(data + Data([10])) }
            } else if let id = requestID as? String { finish(id, result: .success(object)) }
        }
    }
    private func finish(_ id: String, result: Result<[String: Any], Error>) {
        lock.lock(); let continuation = pending.removeValue(forKey: id); lock.unlock()
        continuation?.resume(with: result)
    }
    func close() {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true; let callbacks = Array(pending.values); pending.removeAll(); buffer.removeAll(); lock.unlock()
        output.fileHandleForReading.readabilityHandler = nil; errors.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
            let child = process
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if child.isRunning { Darwin.kill(child.processIdentifier, SIGKILL) }
            }
        }
        try? input.fileHandleForWriting.close()
        for callback in callbacks { callback.resume(throwing: CancellationError()) }
    }
    deinit { close() }
}

actor MCPClient {
    let configuration: MCPServerConfiguration
    private var stdio: MCPStdio?
    private var sessionID: String?
    private var version = "2025-06-18"
    private var ready = false
    init(_ configuration: MCPServerConfiguration) { self.configuration = configuration }
    func connect() async throws -> [[String: Any]] {
        if configuration.transport == "stdio", stdio == nil {
            let text = AISecrets.get("mcp.env.\(configuration.id)")
            let env = text.isEmpty ? [:] : try JSONDecoder().decode([String: String].self, from: Data(text.utf8))
            stdio = try MCPStdio(configuration: configuration, environment: env)
        }
        if !ready {
            let result = try await rpc("initialize", params: ["protocolVersion": version, "capabilities": [:], "clientInfo": ["name": "Mindora", "version": "0.3"]])
            guard let negotiated = result["protocolVersion"] as? String, ["2025-06-18", "2025-03-26", "2024-11-05"].contains(negotiated) else { throw AIError.message("MCP 协议版本不兼容") }
            version = negotiated
            _ = try await rpc("notifications/initialized", params: [:], notification: true); ready = true
        }
        var tools: [[String: Any]] = [], cursor: String?
        for _ in 0..<20 {
            let result = try await rpc("tools/list", params: cursor.map { ["cursor": $0] } ?? [:])
            tools += result["tools"] as? [[String: Any]] ?? []
            cursor = result["nextCursor"] as? String
            if cursor == nil { return tools }
        }
        throw AIError.message("MCP 工具列表分页超过限制")
    }
    func call(_ name: String, arguments: [String: Any]) async throws -> [String: Any] {
        try await rpc("tools/call", params: ["name": name, "arguments": arguments])
    }
    func close() { stdio?.close(); stdio = nil; ready = false; sessionID = nil }
    private func rpc(_ method: String, params: [String: Any], notification: Bool = false) async throws -> [String: Any] {
        try Task.checkCancellation()
        let object: [String: Any]
        if let stdio { object = try await stdio.call(method, params: params, notification: notification) }
        else {
            let id = UUID().uuidString
            var payload: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
            if !notification { payload["id"] = id }
            var request = URLRequest(url: try AIJSON.endpoint(configuration.endpoint)); request.httpMethod = "POST"; request.timeoutInterval = 90
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
            if method != "initialize" { request.setValue(version, forHTTPHeaderField: "MCP-Protocol-Version") }
            let token = AISecrets.get("mcp.token.\(configuration.id)")
            if !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let outgoing = request
            var cancellation = request
            cancellation.timeoutInterval = 5
            cancellation.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": id, "reason": "User stopped the request"]])
            let cancelledRequest = cancellation
            let (data, response) = try await withTaskCancellationHandler(operation: {
                try await AIHTTP.send(outgoing, rpcID: notification ? nil : id)
            }, onCancel: {
                if !notification && method != "initialize" {
                    Task { _ = try? await AIHTTP.send(cancelledRequest) }
                }
            })
            if method == "initialize" { sessionID = response.value(forHTTPHeaderField: "Mcp-Session-Id") }
            if notification { return [:] }
            object = try AIJSON.object(data)
            guard object["id"] as? String == id else { throw AIError.message("MCP 响应 ID 不匹配") }
        }
        if let error = object["error"] as? [String: Any] { throw AIError.message("MCP 错误：\(error["message"] as? String ?? "未知错误")") }
        if notification { return [:] }
        guard let result = object["result"] as? [String: Any] else { throw AIError.message("MCP 响应缺少 result") }
        return result
    }
}
