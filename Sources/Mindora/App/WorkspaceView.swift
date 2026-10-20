import SwiftUI

struct WorkspaceView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject private var library = LibraryStore.shared

    var body: some View {
        Group {
            if let editor = workspace.editor {
                EditorView(model: editor, fileURL: workspace.fileURL)
                    .id(workspace.sessionID)
            } else {
                LibraryHomeView(workspace: workspace)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let url = workspace.openingURL {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在打开 \(url.deletingPathExtension().lastPathComponent)…").lineLimit(1)
                    Button("取消") { workspace.cancelOpen() }
                }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).padding(16)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { openWindow(id: "ai-assistant") } label: { Label("AI 助手", systemImage: "sparkles") }.help("AI 助手 ⇧⌘A")
            }
        }
        .background(WorkspaceWindowReader(workspace: workspace))
        .onAppear { workspace.presentWorkspace = { openWindow(id: "workspace") } }
        .onOpenURL { url in
            if url.hasDirectoryPath && library.contains(url) { library.selectFolder(url) }
            else { workspace.openFile(url) }
        }
        .alert("操作未完成", isPresented: Binding(get: { workspace.errorMessage != nil || library.errorMessage != nil }, set: { shown in
            if !shown { workspace.errorMessage = nil; library.errorMessage = nil }
        })) {
            Button("好", role: .cancel) { workspace.errorMessage = nil; library.errorMessage = nil }
        } message: { Text(workspace.errorMessage ?? library.errorMessage ?? "") }
    }
}

private struct WorkspaceWindowReader: NSViewRepresentable {
    let workspace: WorkspaceStore
    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.onWindow = { [weak workspace] window in workspace?.attach(to: window) }
        return view
    }
    func updateNSView(_ view: WindowReaderView, context: Context) {
        if let window = view.window { workspace.attach(to: window) }
    }
    final class WindowReaderView: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}

