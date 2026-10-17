import SwiftUI

struct AIAssistantView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var assistant = AIAssistantStore.shared
    @ObservedObject private var configuration = AIConfiguration.shared
    @FocusState private var inputFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    private var ready: Bool {
        guard let model = configuration.selectedModel else { return false }
        return !model.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (try? AIJSON.endpoint(model.baseURL)) != nil
    }
    private var canSend: Bool { ready && !assistant.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && assistant.input.count <= 30_000 && !assistant.isRunning }
    private var inputHeight: CGFloat { CGFloat(min(6, max(3, assistant.input.components(separatedBy: "\n").count))) * 19 + 12 }
    var body: some View {
        VStack(spacing: 0) {
            header
            contextBar
            if !ready { configurationPrompt }
            conversation.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let approval = assistant.approval { approvalCard(approval).padding(.horizontal, 20).padding(.bottom, 8) }
            composer
        }.background(InterfaceStyle.surface)
            .frame(minWidth: 480, idealWidth: 560, minHeight: 620, idealHeight: 760)
            .tint(InterfaceStyle.accent)
            .onAppear {
                assistant.openWindow = { id in if id == "settings" { showSettings() } else { openWindow(id: id) } }
                inputFocused = true
            }
            .background(PanelWindowCloseObserver { assistant.stop() })
            .onDisappear { assistant.stop() }
    }
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").font(.system(size: 19, weight: .medium)).foregroundStyle(InterfaceStyle.accent)
                .frame(width: 38, height: 38).background(InterfaceStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text("Mindora AI").font(.system(size: 16, weight: .semibold))
                Text("从灵感到清晰的结构").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            QuietIconButton(title: "新对话", symbol: "square.and.pencil") { assistant.clear(); inputFocused = true }.disabled(assistant.isRunning)
            QuietIconButton(title: "模型与 MCP 设置", symbol: "slider.horizontal.3", action: showSettings)
        }.padding(.horizontal, 20).padding(.vertical, 16)
    }
    private var contextBar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(configuration.models) { model in
                    Button { configuration.selectedModelID = model.id } label: {
                        if configuration.selectedModelID == model.id { Label(model.name, systemImage: "checkmark") } else { Text(model.name) }
                    }
                }
                Divider()
                Button("管理模型…", action: showSettings)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "cpu").font(.system(size: 12))
                    Text(configuration.selectedModel?.name ?? "选择模型").font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
            }.menuStyle(.borderlessButton).frame(maxWidth: 220, alignment: .leading).disabled(assistant.isRunning)
            Spacer(minLength: 0)
            Toggle(isOn: $configuration.sharesDocument) {
                Label("共享导图", systemImage: configuration.sharesDocument ? "doc.text.fill" : "doc.text")
                    .font(.system(size: 11, weight: .medium))
            }.toggleStyle(.button).buttonStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .foregroundStyle(configuration.sharesDocument ? InterfaceStyle.accent : .secondary)
                .background(configuration.sharesDocument ? InterfaceStyle.accent.opacity(0.08) : Color.primary.opacity(0.04), in: Capsule())
                .help("允许模型读取当前导图的文字、代码及附件名称；不发送附件二进制。")
                .disabled(assistant.isRunning)
        }.padding(.horizontal, 20).padding(.vertical, 9)
            .background(Color.primary.opacity(0.02))
            .overlay(alignment: .top) { Divider().opacity(0.6) }
            .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }
    private var configurationPrompt: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "cpu").foregroundStyle(InterfaceStyle.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("先连接一个模型").font(.system(size: 12, weight: .semibold))
                Text("填写接口地址和模型 ID 后，即可发送消息。你也可以先写下想法。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("去配置", action: showSettings).controlSize(.small)
        }.padding(12).background(InterfaceStyle.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20).padding(.top, 14)
    }
    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if assistant.entries.isEmpty { welcome.padding(.horizontal, 28).padding(.vertical, 30) }
                else {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(assistant.entries) { entry in message(entry).id(entry.id) }
                        if assistant.isRunning {
                            HStack(spacing: 9) { ProgressView().controlSize(.small); Text(assistant.phase).font(.system(size: 12)).foregroundStyle(.secondary) }
                        }
                        Color.clear.frame(height: 1).id("conversation-end")
                    }.padding(20)
                }
            }.onChange(of: assistant.entries.count) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("conversation-end", anchor: .bottom) }
            }
        }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("让想法更进一步").font(.system(size: 23, weight: .semibold))
                Text("一起整理思路，完善内容，或直接操作导图。")
                    .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 9) {
                suggestion("整理当前导图", detail: "梳理层级，让结构更清晰", symbol: "point.3.connected.trianglepath.dotted", prompt: "请整理当前导图的层级结构，保留所有重要内容。")
                suggestion("从想法生成计划", detail: "将目标拆分为可执行的主题", symbol: "list.bullet.rectangle", prompt: "请帮我创建一份项目计划导图，包含目标、里程碑、任务和风险。")
                suggestion("优化页面样式", detail: "统一字号、对齐和配色", symbol: "paintpalette", prompt: "请优化当前导图的页面样式，使用协调的配色、清晰的字号和左对齐文字。")
            }
            Label("工具操作由你确认，随时可以停止执行。", systemImage: "hand.raised")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: 460, alignment: .leading).frame(maxWidth: .infinity, alignment: .center)
    }
    private func suggestion(_ title: String, detail: String, symbol: String, prompt: String) -> some View {
        Button { assistant.input = prompt; inputFocused = true } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(InterfaceStyle.accent).frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.left").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(13).background(InterfaceStyle.panel.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(InterfaceStyle.divider, lineWidth: 0.7))
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain)
    }
    @ViewBuilder private func message(_ entry: AIChatEntry) -> some View {
        if entry.role == "user" {
            HStack {
                Spacer(minLength: 40)
                Text(entry.text).font(.system(size: 13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 15).padding(.vertical, 12)
                    .background(InterfaceStyle.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            }
        } else if entry.role == "tool" || entry.role == "status" {
            Label(entry.text, systemImage: entry.role == "tool" ? "checkmark.circle" : "info.circle")
                .font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        } else if entry.role == "error" {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                Text(entry.text).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.15), lineWidth: 1))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles").foregroundStyle(InterfaceStyle.accent)
                    Text("Mindora AI").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    QuietIconButton(title: "复制回复", symbol: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.text, forType: .string) }
                }
                Text(entry.text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func approvalCard(_ approval: AIApproval) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label("等待你的确认", systemImage: "hand.raised").font(.system(size: 12, weight: .semibold)); Spacer(); AIBadge(title: "操作审核", highlighted: true) }
            Text(approval.title).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView { Text(approval.arguments).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10) }
                .frame(height: 96).background(InterfaceStyle.panel, in: RoundedRectangle(cornerRadius: 8))
            HStack { Text("请核对操作与参数").font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); Button("拒绝") { assistant.approve(false) }; Button("允许执行") { assistant.approve(true) }.buttonStyle(.borderedProminent) }.controlSize(.small)
        }.padding(15).background(InterfaceStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(InterfaceStyle.accent.opacity(0.25), lineWidth: 1))
    }
    private var composer: some View {
        VStack(spacing: 10) {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $assistant.input).font(.system(size: 13)).scrollContentBackground(.hidden)
                        .focused($inputFocused).frame(height: inputHeight).padding(.horizontal, 9).padding(.top, 9)
                        .accessibilityLabel("消息输入框").help("支持多行输入，⌘Return 发送")
                    if assistant.input.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("描述你的想法，或让 AI 帮你操作导图…").font(.system(size: 13))
                            Text("例如：调整全图字号，或添加一个项目计划").font(.system(size: 11)).foregroundStyle(.tertiary)
                        }.foregroundStyle(.secondary).padding(.horizontal, 15).padding(.top, 15).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "text.alignleft").font(.system(size: 11)).foregroundStyle(.tertiary)
                    Text("多行输入 · ⌘↩ 发送").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    if assistant.input.count > 25_000 {
                        Text("\(assistant.input.count) / 30,000").font(.system(size: 9)).foregroundStyle(assistant.input.count > 30_000 ? Color.red : Color.secondary)
                    }
                    if assistant.isRunning {
                        Button { assistant.stop() } label: { Label("停止", systemImage: "stop.fill").font(.system(size: 12, weight: .medium)) }
                            .buttonStyle(.bordered).controlSize(.small)
                    } else {
                        Button { assistant.send(); inputFocused = true } label: {
                            HStack(spacing: 6) { Text("发送"); Image(systemName: "arrow.up") }.font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 13).padding(.vertical, 8)
                                .foregroundStyle(canSend ? Color.white : Color.secondary)
                                .background(canSend ? InterfaceStyle.accent : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).keyboardShortcut(.return, modifiers: .command).disabled(!canSend)
                            .help(ready ? "发送消息 ⌘Return" : "请先配置模型")
                    }
                }.padding(.horizontal, 12).padding(.vertical, 10)
            }.background(InterfaceStyle.surface, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(inputFocused ? InterfaceStyle.accent.opacity(0.55) : Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.09), radius: 14, x: 0, y: 4)
                .shadow(color: inputFocused ? InterfaceStyle.accent.opacity(0.08) : .clear, radius: 5, x: 0, y: 1)
            Text("消息与已授权内容发送至所选模型 · 附件仅共享元数据").font(.system(size: 9)).foregroundStyle(.tertiary)
        }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 14)
    }
    private func showSettings() {
        UserDefaults.standard.set("ai", forKey: "Mindora.Settings.Section")
        openSettings()
    }
}

/// SwiftUI may retain window content after close; observe the actual AppKit event.
struct PanelWindowCloseObserver: NSViewRepresentable {
    var onClose: () -> Void
    func makeNSView(context: Context) -> Reader { let view = Reader(); view.onClose = onClose; return view }
    func updateNSView(_ view: Reader, context: Context) { view.onClose = onClose }
    final class Reader: NSView {
        var onClose: (() -> Void)?
        private var observer: NSObjectProtocol?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
            if let window {
                observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in self?.onClose?() }
            }
        }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}
