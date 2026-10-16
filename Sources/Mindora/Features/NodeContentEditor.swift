import SwiftUI

struct ContentInsertion: Identifiable {
    enum Kind { case link, code }
    let id = UUID()
    let nodeID: UUID
    let kind: Kind
}

struct NodeContentEditor: View {
    @ObservedObject var model: EditorModel
    let request: ContentInsertion
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var text: String
    @State private var language: String
    private var isCode: Bool { request.kind == .code }
    init(model: EditorModel, request: ContentInsertion) {
        self.model = model; self.request = request
        let node = model.document.root.find(request.nodeID)
        _text = State(initialValue: request.kind == .code ? node?.code ?? "" : node?.link ?? "")
        _language = State(initialValue: node?.codeLanguage ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: isCode ? "chevron.left.forwardslash.chevron.right" : "link")
                    .font(.title2).foregroundStyle(model.document.theme.color)
                    .frame(width: 42, height: 42)
                    .background(model.document.theme.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(isCode ? "代码块" : "网址链接").font(.title3.bold())
                    Text(model.document.root.find(request.nodeID)?.title ?? "当前主题").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(isCode ? "⌥⌘C" : "⌥⌘K").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            if isCode {
                HStack {
                    Text("语言").foregroundStyle(.secondary)
                    TextField("例如 swift / python / sql", text: $language).textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    Spacer()
                    Button("粘贴", systemImage: "doc.on.clipboard") { if let value = NSPasteboard.general.string(forType: .string) { text = value } }
                }
                TextEditor(text: $text).font(.system(size: 13, design: .monospaced)).autocorrectionDisabled()
                    .scrollContentBackground(.hidden).focused($focused).padding(12)
                    .background(InterfaceStyle.panel, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(InterfaceStyle.divider, lineWidth: 0.5))
                    .frame(height: 260)
            } else {
                TextField("粘贴网址，例如 https://example.com", text: $text).textFieldStyle(.roundedBorder).focused($focused)
                Text(text.isEmpty || NodeRichContent.webURL(text) != nil ? "支持 HTTP / HTTPS；留空并保存可移除链接。" : "网址无效，请检查地址。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(isCode ? "原文保存，不执行代码 · 留空可移除" : "保存后可从属性栏打开网址")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }.buttonStyle(.borderedProminent)
                    .disabled(!valid || model.document.root.find(request.nodeID) == nil)
            }
        }.padding(24).frame(width: 620).tint(model.document.theme.color)
            .onAppear { focused = true }
    }
    private var valid: Bool {
        if !isCode { return text.count <= 4096 && (text.isEmpty || NodeRichContent.webURL(text) != nil) }
        return text.count <= 100_000 && language.count <= 32 && language.allSatisfy { $0.isLetter || $0.isNumber || "+-#".contains($0) }
    }
    private func save() {
        model.updateNode(request.nodeID) {
            if isCode { $0.code = text; $0.codeLanguage = language }
            else { $0.link = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        dismiss()
    }
}
