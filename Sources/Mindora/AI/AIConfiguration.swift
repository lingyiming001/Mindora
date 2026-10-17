import Foundation
import Security
import Combine

struct AIModelProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "自定义模型"
    var baseURL = "https://api.openai.com/v1"
    var model = ""
}
struct MCPServerConfiguration: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "MCP 服务"
    var enabled = false
    var transport = "stdio"
    var endpoint = ""
    var command = ""
    var arguments: [String] = []
    // Environment values and bearer tokens live in Keychain, never in defaults.
}

@MainActor final class AIConfiguration: ObservableObject {
    static let shared = AIConfiguration()
    @Published var models: [AIModelProfile] { didSet { persist() } }
    @Published var servers: [MCPServerConfiguration] { didSet { persist() } }
    @Published var selectedModelID: UUID? { didSet { persist() } }
    @Published var confirmActions: Bool { didSet { persist() } }
    @Published var sharesDocument: Bool { didSet { persist() } }
    @Published var status = ""
    private struct Saved: Codable {
        var models: [AIModelProfile]; var servers: [MCPServerConfiguration]
        var selectedModelID: UUID?; var confirmActions: Bool; var sharesDocument: Bool
    }
    private init() {
        let saved = UserDefaults.standard.data(forKey: "Mindora.AI.Configuration")
            .flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        let initialModels = saved?.models ?? [AIModelProfile()]
        models = initialModels
        servers = saved?.servers ?? []
        selectedModelID = saved?.selectedModelID ?? initialModels.first?.id
        confirmActions = saved?.confirmActions ?? true
        sharesDocument = saved?.sharesDocument ?? false
    }
    var selectedModel: AIModelProfile? { models.first { $0.id == selectedModelID } }
    private func persist() {
        let saved = Saved(models: models, servers: servers, selectedModelID: selectedModelID, confirmActions: confirmActions, sharesDocument: sharesDocument)
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: "Mindora.AI.Configuration") }
    }
    func setSecret(_ value: String, account: String) {
        do { try AISecrets.set(value, account: account); status = "配置已保存" }
        catch { status = error.localizedDescription }
    }
}

enum AISecrets {
    static func get(_ account: String) -> String {
        var query = base(account); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func set(_ value: String, account: String) throws {
        let query = base(account)
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AIError.message("钥匙串删除失败（\(status)）") }; return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var entry = query; entry[kSecValueData as String] = data
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(entry as CFDictionary, nil)
            guard added == errSecSuccess else { throw AIError.message("钥匙串保存失败（\(added)）") }
        } else if status != errSecSuccess { throw AIError.message("钥匙串保存失败（\(status)）") }
    }
    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Mindora.AI", kSecAttrAccount as String: account]
    }
}
enum AIError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}
enum AIJSON {
    static func string(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]), as: UTF8.self)
    }
    static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.message("服务返回了无效的 JSON 对象") }; return value
    }
    static func endpoint(_ text: String) throws -> URL {
        guard let url = URL(string: text), let host = url.host,
              url.user == nil, url.password == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)) else {
            throw AIError.message("地址需使用 HTTPS；本机服务可以使用 HTTP。")
        }
        return url
    }
}
