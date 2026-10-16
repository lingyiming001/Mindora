import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Coordinates folder browsing and one active editor without creating document windows.
@MainActor final class WorkspaceStore: ObservableObject {
    static let shared = WorkspaceStore()
    @Published private(set) var editor: EditorModel?
    @Published private(set) var fileURL: URL?
    @Published private(set) var sessionID = UUID()
    @Published private(set) var saveStatus = ""
    @Published var errorMessage: String?
    var presentWorkspace: (() -> Void)?
    private var autosaveTask: Task<Void, Never>?
    private var document: MindoraDocument?
    private var scopedURL: URL?
    private weak var window: NSWindow?
    private var windowDelegate: WorkspaceWindowDelegate?
    private let library = LibraryStore.shared

    private init() {}

    func attach(to window: NSWindow) {
        guard self.window !== window else { updateWindow(); return }
        self.window = window
        let delegate = WorkspaceWindowDelegate(workspace: self, original: window.delegate)
        windowDelegate = delegate; window.delegate = delegate
        updateWindow()
    }
    private func updateWindow() {
        window?.title = fileURL.map { "\($0.deletingPathExtension().lastPathComponent) — Mindora" } ?? "Mindora · 资料库"
        window?.representedURL = fileURL
        window?.isDocumentEdited = document?.isDocumentEdited ?? false
    }
    private func activateWindow() {
        presentWorkspace?()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func openFile(_ url: URL) {
        if fileURL?.standardizedFileURL == url.standardizedFileURL { activateWindow(); return }
        let accessed = url.startAccessingSecurityScopedResource()
        do {
            // Decode the destination before replacing a working editor.
            let incoming = try MindoraDocument(contentsOf: url, ofType: UTType.mindora.identifier)
            try install(incoming, accessedURL: accessed ? url : nil)
        } catch {
            if accessed { url.stopAccessingSecurityScopedResource() }
            errorMessage = "无法打开导图：\(error.localizedDescription)"
        }
    }
    func adopt(_ incoming: MindoraDocument) {
        if incoming === document { activateWindow(); return }
        let url = incoming.fileURL
        let accessed = url?.startAccessingSecurityScopedResource() ?? false
        do { try install(incoming, accessedURL: accessed ? url : nil) }
        catch {
            if accessed { url?.stopAccessingSecurityScopedResource() }
            incoming.close()
            errorMessage = "未能切换导图，当前内容已保留：\(error.localizedDescription)"
        }
    }
    private func install(_ source: MindoraDocument, accessedURL: URL?) throws {
        try saveActive()
        var incoming = source
        var scope = accessedURL
        if source.fileURL == nil || !library.contains(source.fileURL!) {
            var managed = source.map; managed.id = UUID()
            let url = try library.storeManagedCopy(managed, name: source.fileURL?.deletingPathExtension().lastPathComponent ?? managed.title)
            incoming = try MindoraDocument(contentsOf: url, ofType: UTType.mindora.identifier)
            source.close()
            scope?.stopAccessingSecurityScopedResource(); scope = nil
        }
        closeActiveDocument()
        document = incoming; scopedURL = scope
        if !NSDocumentController.shared.documents.contains(where: { $0 === incoming }) {
            NSDocumentController.shared.addDocument(incoming)
        }
        let nextEditor = EditorModel(document: incoming.map)
        nextEditor.editingTransactionDidBegin = { [weak self] in self?.autosaveTask?.cancel(); self?.autosaveTask = nil }
        nextEditor.documentDidChange = { [weak self, weak incoming] updated in
            guard let self, let incoming, self.document === incoming else { return }
            incoming.map = updated
            incoming.updateChangeCount(.changeDone)
            self.saveStatus = "等待自动保存"; self.updateWindow()
            self.scheduleAutosave()
        }
        incoming.didWrite = { [weak self, weak incoming] in
            guard let self, let incoming, self.document === incoming else { return }
            self.saveStatus = incoming.isDocumentEdited ? "等待自动保存" : (incoming.conflictCopyURL == nil ? "已自动保存" : "已保存 · 外部修改已保留为副本")
            self.fileURL = incoming.fileURL
            self.library.activeDocumentURL = incoming.fileURL
            self.updateWindow()
        }
        editor = nextEditor; fileURL = incoming.fileURL; sessionID = UUID(); saveStatus = "已保存"
        library.activeDocumentURL = incoming.fileURL
        if let url = incoming.fileURL {
            if library.contains(url) { library.currentFolderURL = url.deletingLastPathComponent() }
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        }
        updateWindow(); activateWindow()
    }
    @discardableResult func showFolder(_ url: URL? = nil) -> Bool {
        do {
            try saveActive()
            closeActiveDocument()
            editor = nil; fileURL = nil; sessionID = UUID(); saveStatus = ""
            library.activeDocumentURL = nil
            if let url, library.contains(url) {
                library.currentFolderURL = url; library.expandedFolders.insert(url)
            }
            updateWindow()
            return true
        } catch {
            errorMessage = "当前导图未能保存，已保留在编辑器中：\(error.localizedDescription)"
            return false
        }
    }
    func saveActive() throws {
        editor?.finishEditing?()
        guard let document, document.isDocumentEdited else { return }
        autosaveTask?.cancel(); autosaveTask = nil
        if document.fileURL == nil {
            document.fileURL = try library.storeManagedCopy(document.map, name: document.map.title)
            document.fileType = UTType.mindora.identifier
            fileURL = document.fileURL
        }
        try document.saveImmediately()
        saveStatus = document.conflictCopyURL == nil ? "已自动保存" : "已保存 · 外部修改已保留为副本"; updateWindow(); library.reload()
    }
    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(800)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            do { try self.saveActive() }
            catch {
                self.saveStatus = "自动保存失败 · 请重试"
                self.errorMessage = "自动保存失败，当前编辑仍保留。请检查存储位置后按 ⌘S 重试：\(error.localizedDescription)"
            }
        }
    }
    func save(asCopy: Bool = false) {
        do {
            try saveActive()
            if asCopy { saveCopy() }
        } catch { errorMessage = "保存失败：\(error.localizedDescription)" }
    }
    private func saveCopy() {
        guard let document else { return }
        let panel = NSSavePanel()
        panel.title = "另存一份副本"
        panel.message = "当前导图继续自动保存到资料库；此操作只复制一份文件。"
        panel.allowedContentTypes = [.mindora]
        panel.directoryURL = fileURL?.deletingLastPathComponent() ?? library.currentFolderURL
        panel.nameFieldStringValue = (fileURL?.deletingPathExtension().lastPathComponent ?? "未命名导图") + " 副本.mindora"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard destination.resolvingSymlinksInPath().standardizedFileURL != fileURL?.resolvingSymlinksInPath().standardizedFileURL,
              NSDocumentController.shared.document(for: destination) == nil else {
            errorMessage = "请选择其他文件名，不能覆盖当前导图或已打开的文档。"; return
        }
        let accessed = destination.startAccessingSecurityScopedResource()
        defer { if accessed { destination.stopAccessingSecurityScopedResource() } }
        do {
            var copy = document.map; copy.id = UUID()
            let data = try MapInterchange.encodeJSON(copy)
            var coordinationError: NSError?, writeError: Error?
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { target in
                do { try data.write(to: target, options: .atomic) } catch { writeError = error }
            }
            if let coordinationError { throw coordinationError }
            if let writeError { throw writeError }
            library.reload()
        } catch { errorMessage = "副本保存失败，当前导图不受影响：\(error.localizedDescription)" }
    }
    func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "打开思维导图"
        panel.message = "资料库之外的文件会先复制到资料库，后续编辑自动保存到资料库，原文件保持不变。"
        panel.allowedContentTypes = [.mindora]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.directoryURL = library.currentFolderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFile(url)
    }
    func documentMoved(from source: URL, to destination: URL) {
        guard fileURL?.standardizedFileURL == source.standardizedFileURL else { return }
        fileURL = destination; updateWindow()
    }
    private func closeActiveDocument() {
        autosaveTask?.cancel(); autosaveTask = nil
        editor?.editingTransactionDidBegin = nil
        editor?.documentDidChange = nil
        document?.didWrite = nil
        document?.close(); document = nil
        scopedURL?.stopAccessingSecurityScopedResource(); scopedURL = nil
    }
    func canCloseWindow() -> Bool {
        do { try saveActive(); return true }
        catch { errorMessage = "当前导图尚未保存：\(error.localizedDescription)"; return false }
    }
}

@MainActor private final class WorkspaceWindowDelegate: NSObject, NSWindowDelegate {
    weak var workspace: WorkspaceStore?
    weak var original: NSWindowDelegate?
    init(workspace: WorkspaceStore, original: NSWindowDelegate?) {
        self.workspace = workspace; self.original = original
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard workspace?.canCloseWindow() != false else { return false }
        return original?.windowShouldClose?(sender) ?? true
    }
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }
    override func forwardingTarget(for selector: Selector!) -> Any? {
        if original?.responds(to: selector) == true { return original }
        return super.forwardingTarget(for: selector)
    }
}
