import SwiftUI

private enum AISettingsTab: String, CaseIterable {
    case models = "模型服务", mcp = "MCP 扩展", permissions = "使用权限"
    var symbol: String { switch self { case .models: "cpu"; case .mcp: "puzzlepiece.extension"; case .permissions: "slider.horizontal.3" } }
}

struct AISettingsView: View {
    @ObservedObject private var configuration = AIConfiguration.shared
    @ObservedObject private var assistant = AIAssistantStore.shared
    @State private var tab = AISettingsTab.models
    @State private var profileID: UUID?
    @State private var serverID: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 4) {
                ForEach(AISettingsTab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
                        Label(item.rawValue, systemImage: item.symbol).font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .foregroundStyle(tab == item ? Color.primary : .secondary)
                            .background(tab == item ? InterfaceStyle.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .shadow(color: .black.opacity(tab == item ? 0.06 : 0), radius: 3, y: 1)
                    }.buttonStyle(.plain).accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }.padding(4).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if tab == .models { models }
                    else if tab == .mcp { servers }
                    else { permissions }
                    if !configuration.status.isEmpty {
                        Label(configuration.status, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }.padding(.bottom, 22)
            }
        }.padding(.horizontal, 28).padding(.bottom, 12).disabled(assistant.isRunning)
            .overlay(alignment: .bottom) {
                if assistant.isRunning { Text("助手运行中，停止后可编辑配置").font(.caption).padding(10).background(.regularMaterial, in: Capsule()).padding(12) }
            }
            .onAppear { profileID = configuration.selectedModelID ?? configuration.models.first?.id; serverID = configuration.servers.first?.id }
    }
    private var models: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("连接你的模型", subtitle: "选择一个配置编辑，支持云端接口与本机模型。", add: "添加模型") {
                let profile = AIModelProfile(); configuration.models.append(profile); profileID = profile.id
                if configuration.selectedModelID == nil { configuration.selectedModelID = profile.id }
            }
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                    Text("模型列表 · \(configuration.models.count)").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.bottom, 5)
                    ForEach(configuration.models) { profile in
                        selectionRow(profile.name, detail: profile.model.isEmpty ? "待填写模型 ID" : profile.model, symbol: "cpu", selected: profileID == profile.id, badge: configuration.selectedModelID == profile.id ? "默认" : nil) { profileID = profile.id }
                    }
                    }
                }.frame(width: 142, height: 360)
                VStack {
                    if configuration.models.isEmpty {
                        empty("还没有模型", subtitle: "添加一个模型配置，开始使用 AI 助手。", symbol: "cpu")
                    } else {
                        ForEach($configuration.models) { $profile in
                            if profile.id == profileID {
                                AIModelEditor(profile: $profile, selected: configuration.selectedModelID == profile.id, select: { configuration.selectedModelID = profile.id }, remove: { removeModel(profile.id) }).id(profile.id)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Label("消息会发送至所选模型服务。API 密钥仅保存在 macOS 钥匙串。", systemImage: "lock.shield").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var servers: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("连接扩展工具", subtitle: "通过 MCP，为助手扩展外部工具。", add: "添加服务") {
                let server = MCPServerConfiguration(); configuration.servers.append(server); serverID = server.id
            }
            if configuration.servers.isEmpty {
                empty("连接你的第一个工具", subtitle: "支持本地 stdio 与远程 HTTP。添加服务后，可先测试连接，再决定是否启用。", symbol: "puzzlepiece.extension")
            } else {
                HStack(alignment: .top, spacing: 16) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                        Text("服务列表 · \(configuration.servers.count)").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.bottom, 5)
                        ForEach(configuration.servers) { server in
                            selectionRow(server.name, detail: server.transport == "stdio" ? "本地进程" : "远程 HTTP", symbol: "puzzlepiece.extension", selected: serverID == server.id, badge: server.enabled ? "启用" : nil) { serverID = server.id }
                        }
                        }
                    }.frame(width: 142, height: 360)
                    VStack {
                        ForEach($configuration.servers) { $server in
                            if server.id == serverID { MCPServerEditor(server: $server, remove: { removeServer(server.id) }).id(server.id) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            Label("仅启用可信服务。MCP 工具每次调用前都会展示参数并请求确认。", systemImage: "hand.raised").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var permissions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("由你掌控助手的每一步").font(.system(size: 16, weight: .semibold))
            AICard {
                VStack(spacing: 20) {
                    permission("修改前确认", detail: "助手修改导图、文件与设置前，先展示操作。", value: $configuration.confirmActions)
                    Divider()
                    permission("共享当前导图", detail: "允许模型读取文字、备注、代码、链接及附件名称；不发送附件二进制。", value: $configuration.sharesDocument)
                }
            }
            AICard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("始终保留的控制", systemImage: "checkmark.shield").font(.system(size: 13, weight: .semibold))
                    Text("MCP 调用、删除和移除操作始终需要确认。对话仅保留在内存；停止或关闭助手会取消尚未完成的请求。原生文件面板由你选择位置。").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private func permission(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
    private func sectionHeader(_ title: String, subtitle: String, add: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: action) { Label(add, systemImage: "plus") }.controlSize(.small)
        }
    }
    private func selectionRow(_ title: String, detail: String, symbol: String, selected: Bool, badge: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: symbol).font(.system(size: 12))
                    Text(title.isEmpty ? "未命名" : title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                }
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                if let badge { AIBadge(title: badge, highlighted: selected) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(selected ? InterfaceStyle.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? InterfaceStyle.accent.opacity(0.25) : .clear, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func empty(_ title: String, subtitle: String, symbol: String) -> some View {
        AICard {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(InterfaceStyle.accent)
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(.vertical, 24)
        }
    }
    private func removeModel(_ id: UUID) {
        do { try AISecrets.set("", account: "model.\(id)") }
        catch { configuration.status = error.localizedDescription; return }
        configuration.models.removeAll { $0.id == id }
        if configuration.selectedModelID == id { configuration.selectedModelID = configuration.models.first?.id }
        profileID = configuration.models.first?.id
    }
    private func removeServer(_ id: UUID) {
        do { try AISecrets.set("", account: "mcp.env.\(id)"); try AISecrets.set("", account: "mcp.token.\(id)") }
        catch { configuration.status = error.localizedDescription; return }
        configuration.servers.removeAll { $0.id == id }; serverID = configuration.servers.first?.id
    }
}

private struct AIModelEditor: View {
    @Binding var profile: AIModelProfile
    let selected: Bool
    let select: () -> Void
    let remove: () -> Void
    @State private var key = ""
    @State private var savedKey = ""
    @State private var status = ""
    @State private var saveFailed = false
    @State private var confirmsRemoval = false
    var body: some View {
        AICard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("模型配置", systemImage: "cpu").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if selected { AIBadge(title: "默认模型", highlighted: true) }
                }
                AIField("配置名称") { TextField("配置名称", text: $profile.name, prompt: Text("例如：工作助手")) }
                AIField("API 根地址", hint: "使用 OpenAI 兼容接口；本机可填 http://localhost:11434/v1。") {
                    TextField("API 根地址", text: $profile.baseURL, prompt: Text("https://api.example.com/v1"))
                }
                AIField("模型 ID", hint: "使用服务商提供的 ID，并选择支持工具调用的模型。") {
                    TextField("模型 ID", text: $profile.model, prompt: Text("填写模型 ID"))
                }
                AIField("API 密钥", hint: "保存至系统钥匙串；无鉴权的本机服务可留空。") {
                    SecureField("API 密钥", text: $key, prompt: Text("输入 API Key")).privacySensitive().onSubmit(saveKey)
                }
                HStack(spacing: 10) {
                    Button("保存密钥", action: saveKey).buttonStyle(.borderedProminent).controlSize(.small).disabled(key == savedKey)
                    if !selected { Button("设为默认", action: select).controlSize(.small) }
                    Spacer(minLength: 0)
                }
                if !status.isEmpty { Label(status, systemImage: saveFailed ? "exclamationmark.circle" : "checkmark.circle").font(.system(size: 11)).foregroundStyle(saveFailed ? Color.red : Color.secondary).fixedSize(horizontal: false, vertical: true) }
                Divider()
                HStack {
                    Text("常规字段即时保存").font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer()
                    Button("删除配置", role: .destructive) { confirmsRemoval = true }.buttonStyle(.borderless).font(.system(size: 11))
                }
            }
        }.onAppear { key = AISecrets.get("model.\(profile.id)"); savedKey = key }
            .confirmationDialog("删除此模型配置？", isPresented: $confirmsRemoval, titleVisibility: .visible) {
                Button("删除配置及密钥", role: .destructive, action: remove)
                Button("取消", role: .cancel) {}
            }
    }
    private func saveKey() {
        do { try AISecrets.set(key, account: "model.\(profile.id)"); savedKey = key; status = key.isEmpty ? "已移除密钥" : "密钥已安全保存"; saveFailed = false }
        catch { status = error.localizedDescription; saveFailed = true }
    }
}

private struct MCPServerEditor: View {
    @Binding var server: MCPServerConfiguration
    let remove: () -> Void
    @State private var arguments = "[]"
    @State private var environment = "{}"
    @State private var token = ""
    @State private var status = ""
    @State private var failed = false
    @State private var confirmsRemoval = false
    @State private var task: Task<Void, Never>?
    var body: some View {
        AICard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("连接配置", systemImage: "puzzlepiece.extension").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Toggle("启用服务", isOn: $server.enabled).toggleStyle(.switch).controlSize(.small)
                }
                AIField("服务名称") { TextField("服务名称", text: $server.name, prompt: Text("为工具服务命名")) }
                VStack(alignment: .leading, spacing: 7) {
                    Text("连接方式").font(.system(size: 12, weight: .medium))
                    Picker("连接方式", selection: $server.transport) { Text("本地 stdio").tag("stdio"); Text("远程 HTTP").tag("http") }.pickerStyle(.segmented).labelsHidden()
                }
                if server.transport == "stdio" {
                    AIField("可执行程序", hint: "填写绝对路径，参数单独输入。") { TextField("可执行程序", text: $server.command, prompt: Text("/opt/homebrew/bin/npx")) }
                    AIField("启动参数", hint: "JSON 数组，每个参数一项；不通过 shell 执行。") {
                        TextField("启动参数", text: $arguments, axis: .vertical).lineLimit(2...4).font(.system(size: 12, design: .monospaced))
                    }
                    AIField("环境变量", hint: "JSON 对象，如 {\"TOKEN\":\"…\"}；存入钥匙串。") { SecureField("环境变量", text: $environment).privacySensitive() }
                } else {
                    AIField("MCP 端点", hint: "填写 MCP 统一端点；不支持旧式独立 SSE 或 OAuth 登录。") { TextField("MCP 端点", text: $server.endpoint, prompt: Text("https://example.com/mcp")) }
                    AIField("Bearer Token", hint: "可选；存入系统钥匙串。") { SecureField("Bearer Token", text: $token, prompt: Text("输入访问令牌")).privacySensitive() }
                }
                HStack(spacing: 10) {
                    Button("保存连接") { _ = save() }.buttonStyle(.borderedProminent).disabled(task != nil)
                    if task == nil { Button("测试连接") { test() } }
                    else { ProgressView().controlSize(.small); Button("取消") { task?.cancel() } }
                }.controlSize(.small)
                if !status.isEmpty { Label(status, systemImage: failed ? "exclamationmark.circle" : "info.circle").font(.system(size: 11)).foregroundStyle(failed ? Color.red : Color.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                Divider()
                HStack {
                    Text("测试只读取工具列表").font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer()
                    Button("删除服务", role: .destructive) { confirmsRemoval = true }.buttonStyle(.borderless).font(.system(size: 11)).disabled(task != nil)
                }
            }
        }.onAppear {
            arguments = (try? AIJSON.string(server.arguments)) ?? "[]"
            environment = AISecrets.get("mcp.env.\(server.id)"); if environment.isEmpty { environment = "{}" }
            token = AISecrets.get("mcp.token.\(server.id)")
        }
        .confirmationDialog("删除此 MCP 服务？", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("删除服务及凭据", role: .destructive, action: remove); Button("取消", role: .cancel) {}
        }
        .background(PanelWindowCloseObserver { task?.cancel() })
        .onDisappear { task?.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .mindoraMainWindowDidClose)) { _ in task?.cancel() }
    }
    private func save() -> Bool {
        do {
            let args = try JSONDecoder().decode([String].self, from: Data(arguments.utf8))
            let env = try JSONDecoder().decode([String: String].self, from: Data(environment.utf8))
            guard args.count <= 100, env.count <= 100 else { throw AIError.message("参数或环境变量数量过多") }
            if server.transport == "http" { _ = try AIJSON.endpoint(server.endpoint) }
            else { guard server.command.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: server.command) else { throw AIError.message("请填写可执行程序的绝对路径") } }
            try AISecrets.set(try AIJSON.string(env), account: "mcp.env.\(server.id)")
            try AISecrets.set(token, account: "mcp.token.\(server.id)")
            server.arguments = args; status = "连接配置已保存"; failed = false; return true
        } catch { status = error.localizedDescription; failed = true; return false }
    }
    private func test() {
        guard save() else { return }
        let client = MCPClient(server); status = "正在连接…"
        task = Task {
            defer { task = nil }
            do {
                let tools = try await client.connect(); try Task.checkCancellation()
                status = "连接成功 · \(tools.count) 个工具\n" + tools.compactMap { $0["name"] as? String }.prefix(20).joined(separator: "、"); failed = false
            } catch { status = Task.isCancelled ? "已取消连接测试" : error.localizedDescription; failed = !Task.isCancelled }
            await client.close()
        }
        if let task {
            let id = PanelActivityStore.shared.register(task)
            Task { await task.value; PanelActivityStore.shared.finish(id) }
        }
    }
}
