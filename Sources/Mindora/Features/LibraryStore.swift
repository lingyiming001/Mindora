import AppKit
import Combine
import Darwin
import UniformTypeIdentifiers

struct LibraryItem: Identifiable, Equatable {
    let url: URL
    let isFolder: Bool
    let children: [LibraryItem]
    struct ContentVersion: Hashable {
        let modified: Date?
        let bytes: Int?
    }
    let contentVersion: ContentVersion
    var id: URL { url }
    var name: String { isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent }
    let totalMaps: Int
    init(url: URL, isFolder: Bool, children: [LibraryItem], modified: Date? = nil, bytes: Int? = nil) {
        self.url = url; self.isFolder = isFolder; self.children = children
        contentVersion = ContentVersion(modified: modified, bytes: bytes)
        totalMaps = isFolder ? children.reduce(0) { $0 + $1.totalMaps } : 1
    }
    func matching(_ query: String) -> LibraryItem? {
        guard !query.isEmpty else { return self }
        if name.localizedCaseInsensitiveContains(query) { return self }
        let matches = children.compactMap { $0.matching(query) }
        return matches.isEmpty ? nil : LibraryItem(url: url, isFolder: isFolder, children: matches, modified: contentVersion.modified, bytes: contentVersion.bytes)
    }
}

enum EditorSidebarSection: String, CaseIterable, Identifiable {
    case files, outline
    var id: String { rawValue }
    var label: String { self == .files ? "文件" : "大纲" }
}

@MainActor final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()
    @Published private(set) var rootURL: URL
    @Published private(set) var recycleNotice = ""
    @Published private(set) var recycledItems: [RecycledItem] = []
    @Published private(set) var items: [LibraryItem] = []
    @Published var currentFolderURL: URL
    @Published var selectedItemURL: URL?
    @Published var activeDocumentURL: URL?
    @Published var expandedFolders: Set<URL> = []
    @Published var searchText = "" { didSet { updateSearchResults() } }
    @Published private(set) var filteredItems: [LibraryItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var favoritePaths: Set<String>
    private var scopedURL: URL?
    private var reloadPending = false
    private var reloadTask: Task<Void, Never>?
    private var scanTask: Task<[LibraryItem], Error>?
    private var isSuspended = false
    private var folderIndex: [URL: [LibraryItem]] = [:]
    private var watcher: DispatchSourceFileSystemObject?
    private var activationObserver: AnyCancellable?
    private let bookmarkKey = "Mindora.LibraryBookmark"
    private let favoritesKey = "Mindora.LibraryFavorites"

    var currentItems: [LibraryItem] {
        currentFolderURL == rootURL ? items : folderIndex[currentFolderURL] ?? []
    }
    private func updateSearchResults() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredItems = query.isEmpty ? items : items.compactMap { $0.matching(query) }
    }
    var favoriteURLs: [URL] {
        favoritePaths.sorted().map { rootURL.appendingPathComponent($0) }.filter { FileManager.default.fileExists(atPath: $0.path) && !BackupStore.contains($0, in: BackupStore.shared.folderURL) }
    }
    var recentURLs: [URL] {
        Array(NSDocumentController.shared.recentDocumentURLs.filter { contains($0) && $0.pathExtension.lowercased() == "mindora" && FileManager.default.fileExists(atPath: $0.path) && !BackupStore.contains($0, in: BackupStore.shared.folderURL) }.prefix(6))
    }
    var totalMaps: Int { items.reduce(0) { $0 + $1.totalMaps } }

    private init() {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mindora/Library", isDirectory: true)
        var restored = base, scope: URL?
        if let data = UserDefaults.standard.data(forKey: "Mindora.LibraryBookmark") {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
                _ = url.startAccessingSecurityScopedResource()
                restored = url; scope = url
                if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(fresh, forKey: "Mindora.LibraryBookmark")
                }
            }
        }
        rootURL = restored; currentFolderURL = restored; scopedURL = scope
        favoritePaths = Set(UserDefaults.standard.stringArray(forKey: "Mindora.LibraryFavorites." + restored.path) ?? UserDefaults.standard.stringArray(forKey: "Mindora.LibraryFavorites") ?? [])
        do { try manager.createDirectory(at: restored, withIntermediateDirectories: true) }
        catch { errorMessage = "无法打开资料库：\(error.localizedDescription)。可使用“选择资料库位置”重新指定文件夹。" }
        activationObserver = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.reload() } }
        WorkspaceCatalog.shared.register(restored, bookmark: UserDefaults.standard.data(forKey: bookmarkKey))
        watchRoot(); reload()
    }
    func contains(_ url: URL) -> Bool {
        let root = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }
    func reload() {
        guard !isSuspended else { return }
        // One scan at a time. Bursts coalesce into one follow-up scan.
        guard !isLoading else { reloadPending = true; return }
        isLoading = true
        reloadTask = Task {
            repeat {
                reloadPending = false
                let root = rootURL, backupFolder = BackupStore.shared.folderURL
                do {
                    try await Task.sleep(for: .milliseconds(120))
                    let worker = Task.detached(priority: .utility) { try Self.scan(root, excluding: backupFolder) }
                    scanTask = worker
                    let result = try await worker.value
                    guard !Task.isCancelled else { return }
                    scanTask = nil
                    guard root == rootURL, backupFolder == BackupStore.shared.folderURL else {
                        reloadPending = true; continue
                    }
                    var index: [URL: [LibraryItem]] = [root: result]
                    func visit(_ entries: [LibraryItem]) {
                        for entry in entries where entry.isFolder {
                            index[entry.url] = entry.children; visit(entry.children)
                        }
                    }
                    visit(result)
                    folderIndex = index
                    if items != result { items = result; updateSearchResults() }
                    expandedFolders.formIntersection(index.keys)
                    if index[currentFolderURL] == nil { currentFolderURL = rootURL }
                    if let selectedItemURL, !Self.hasItem(selectedItemURL, in: result) { self.selectedItemURL = nil }
                } catch {
                    guard !Task.isCancelled else { return }
                    scanTask = nil
                    if root == rootURL { errorMessage = "无法读取资料库：\(error.localizedDescription)" }
                    else { reloadPending = true }
                }
            } while reloadPending
            isLoading = false; reloadTask = nil
        }
    }
    func suspendBackgroundActivity() {
        isSuspended = true
        reloadTask?.cancel(); reloadTask = nil
        scanTask?.cancel(); scanTask = nil
        reloadPending = false; isLoading = false
        watcher?.cancel(); watcher = nil
    }
    func resumeBackgroundActivity() {
        guard isSuspended else { return }
        isSuspended = false; watchRoot(); reload()
    }
    private static func hasItem(_ url: URL, in entries: [LibraryItem]) -> Bool {
        entries.contains { $0.url == url || hasItem(url, in: $0.children) }
    }
    func toggleFolderExpansion(_ url: URL) {
        guard folderIndex[url] != nil else { return }
        if expandedFolders.contains(url) { expandedFolders.remove(url) }
        else { expandedFolders.insert(url) }
    }
    func selectItem(_ url: URL) { selectedItemURL = url }
    private nonisolated static func scan(_ root: URL, excluding backupFolder: URL, depth: Int = 0) throws -> [LibraryItem] {
        try Task.checkCancellation()
        guard depth < 64, !BackupStore.contains(root, in: backupFolder) else { return [] }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        return try urls.compactMap { url in
            try Task.checkCancellation()
            guard !BackupStore.contains(url, in: backupFolder) else { return nil }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { return nil }
            if values.isDirectory == true {
                return LibraryItem(url: url, isFolder: true, children: try scan(url, excluding: backupFolder, depth: depth + 1))
            }
            guard values.isRegularFile == true, url.pathExtension.lowercased() == "mindora" else { return nil }
            return LibraryItem(url: url, isFolder: false, children: [], modified: values.contentModificationDate, bytes: values.fileSize)
        }.sorted {
            if $0.isFolder != $1.isFolder { return $0.isFolder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    private func watchRoot() {
        watcher?.cancel(); watcher = nil
        guard !isSuspended else { return }
        let descriptor = Darwin.open(rootURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in Task { @MainActor in self?.reload() } }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume(); watcher = source
    }
    func chooseLocation() {
        let panel = NSOpenPanel()
        panel.title = "选择资料库位置"
        panel.message = "使用本机文件夹管理思维导图。文件会直接保存在选中的位置。"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.directoryURL = rootURL; panel.prompt = "使用此文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !BackupStore.contains(url, in: BackupStore.shared.folderURL) else {
            errorMessage = "不能将备份目录用作资料库，请选择导图文件夹。"
            return
        }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            if let existing = WorkspaceCatalog.shared.current(url) { _ = switchWorkspace(existing); return }
            guard !WorkspaceCatalog.shared.overlaps(url) else { errorMessage = "工作空间目录不能相互包含。"; return }
            guard activateWorkspaceFolder(url, bookmark: bookmark) else { return }
            WorkspaceCatalog.shared.register(url, bookmark: bookmark)
        } catch { errorMessage = "无法使用这个位置：\(error.localizedDescription)" }
    }
    @discardableResult private func activateWorkspaceFolder(_ url: URL, bookmark: Data) -> Bool {
        guard !BackupStore.contains(url, in: BackupStore.shared.folderURL),
              (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { errorMessage = "空间位置不可用，请检查文件夹和访问权限。"; return false }
        guard WorkspaceStore.shared.showFolder() else { return false }
        saveFavorites()
        let accessed = url.startAccessingSecurityScopedResource()
        scopedURL?.stopAccessingSecurityScopedResource(); scopedURL = accessed ? url : nil
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        rootURL = url; currentFolderURL = url; selectedItemURL = nil
        recycledItems = []; recycleNotice = ""; expandedFolders = []; searchText = ""
        items = []; folderIndex = [:]; filteredItems = []
        favoritePaths = Set(UserDefaults.standard.stringArray(forKey: favoritesKey + "." + url.path) ?? [])
        saveFavorites(); watchRoot(); reload()
        return true
    }
    @discardableResult func switchWorkspace(_ workspace: LibraryWorkspace) -> Bool {
        do {
            let url = try workspace.resolve()
            if url.standardizedFileURL == rootURL.standardizedFileURL { return true }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            guard activateWorkspaceFolder(url, bookmark: bookmark) else { return false }
            WorkspaceCatalog.shared.register(url, bookmark: bookmark)
            return true
        } catch { errorMessage = "无法切换工作空间：\(error.localizedDescription)"; return false }
    }
    func moveToWorkspace(_ item: LibraryItem, workspace: LibraryWorkspace) {
        guard contains(item.url), item.url != rootURL else { return }
        do {
            let targetRoot = try workspace.resolve()
            guard !BackupStore.contains(targetRoot, in: rootURL), !BackupStore.contains(rootURL, in: targetRoot),
                  !BackupStore.contains(targetRoot, in: BackupStore.shared.folderURL) else { throw LibraryError.invalidLocation }
            if let active = WorkspaceStore.shared.fileURL, BackupStore.contains(active, in: item.url) {
                guard WorkspaceStore.shared.showFolder() else { return }
            }
            guard !hasOpenDocuments(inside: item.url) else { throw LibraryError.openFolder }
            let accessed = targetRoot.startAccessingSecurityScopedResource()
            defer { if accessed { targetRoot.stopAccessingSecurityScopedResource() } }
            guard (try targetRoot.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else { throw LibraryError.invalidLocation }
            var destination = targetRoot.appendingPathComponent(item.url.lastPathComponent, isDirectory: item.isFolder)
            if FileManager.default.fileExists(atPath: destination.path) {
                destination = uniqueURL(name: item.name + " 移入", fileExtension: item.isFolder ? nil : item.url.pathExtension, folder: targetRoot)
            }
            try FileManager.default.moveItem(at: item.url, to: destination)
            let prefix = relativePath(item.url)
            favoritePaths = favoritePaths.filter { $0 != prefix && !$0.hasPrefix(prefix + "/") }
            if selectedItemURL == item.url { selectedItemURL = nil }
            if BackupStore.contains(currentFolderURL, in: item.url) { currentFolderURL = rootURL }
            saveFavorites(); reload()
        } catch { errorMessage = "无法完成跨空间移动，请检查原位置和目标空间：\(error.localizedDescription)" }
    }
    func selectFolder(_ url: URL) {
        guard contains(url) else { return }
        guard currentFolderURL != url || WorkspaceStore.shared.editor != nil else { return }
        if WorkspaceStore.shared.showFolder(url) { selectedItemURL = nil }
    }
    func openDocument(_ url: URL) {
        selectedItemURL = url
        WorkspaceStore.shared.openFile(url)
    }
    func storeManagedCopy(_ map: MindMapDocument, name: String) throws -> URL {
        let folder = contains(currentFolderURL) ? currentFolderURL : rootURL
        let destination = uniqueURL(name: name.isEmpty ? "未命名导图" : name, fileExtension: "mindora", folder: folder)
        try MapInterchange.encodeJSON(map).write(to: destination, options: .atomic)
        reload()
        return destination
    }
    func newMap(in folder: URL? = nil) {
        let destinationFolder = folder ?? currentFolderURL
        guard contains(destinationFolder) else { return }
        do {
            try WorkspaceStore.shared.saveActive()
            let url = uniqueURL(name: "未命名导图", fileExtension: "mindora", folder: destinationFolder)
            var document = MindMapDocument()
            AppPreferences.prepareNewMap(&document)
            document.title = url.deletingPathExtension().lastPathComponent
            document.nodes[0].title = document.title
            try MapInterchange.encodeJSON(document).write(to: url, options: .atomic)
            searchText = ""
            revealFolder(destinationFolder); reload(); openDocument(url)
        } catch { errorMessage = "无法创建导图：\(error.localizedDescription)" }
    }
    func promptNewFolder(in folder: URL? = nil) {
        let parent = folder ?? currentFolderURL
        guard contains(parent), let name = promptName(title: "新建文件夹", message: "创建于 \(parent.lastPathComponent)", initial: "新建文件夹") else { return }
        do {
            try validateName(name)
            let url = parent.appendingPathComponent(name, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: url.path) else { throw LibraryError.nameExists }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            currentFolderURL = url; revealFolder(url); reload()
        } catch { errorMessage = error.localizedDescription }
    }
    func promptRename(_ item: LibraryItem) {
        guard contains(item.url), item.url != rootURL,
              let name = promptName(title: item.isFolder ? "重命名文件夹" : "重命名导图", message: "输入新名称", initial: item.name), name != item.name else { return }
        do {
            try validateName(name)
            let destination = item.url.deletingLastPathComponent().appendingPathComponent(item.isFolder ? name : name + ".mindora", isDirectory: item.isFolder)
            try move(item, to: destination)
        } catch { errorMessage = error.localizedDescription }
    }
    func promptMove(_ item: LibraryItem) {
        let panel = NSOpenPanel()
        panel.title = "移动“\(item.name)”"
        panel.message = "选择资料库中的目标文件夹。"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.directoryURL = rootURL; panel.prompt = "移动到这里"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        moveItem(at: item.url, into: folder)
    }
    func moveItem(at source: URL, into folder: URL) {
        guard contains(source), contains(folder), source != rootURL else { errorMessage = "请选择当前资料库内的文件夹。"; return }
        do {
            let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw LibraryError.invalidLocation }
            let item = LibraryItem(url: source, isFolder: values.isDirectory == true, children: [])
            let destination = folder.appendingPathComponent(source.lastPathComponent, isDirectory: item.isFolder)
            if source.standardizedFileURL == destination.standardizedFileURL { return }
            try move(item, to: destination)
        } catch { errorMessage = error.localizedDescription }
    }
    private func move(_ item: LibraryItem, to destination: URL) throws {
        guard contains(destination), destination != rootURL else { throw LibraryError.invalidLocation }
        if item.isFolder, destination.standardizedFileURL.path.hasPrefix(item.url.standardizedFileURL.path + "/") { throw LibraryError.moveIntoSelf }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw LibraryError.nameExists }
        if item.isFolder, hasOpenDocuments(inside: item.url) { throw LibraryError.openFolder }
        if !item.isFolder, let document = NSDocumentController.shared.document(for: item.url) {
            document.move(to: destination) { [weak self] error in
                Task { @MainActor in
                    if let error { self?.errorMessage = error.localizedDescription }
                    else { self?.didMove(item.url, to: destination) }
                }
            }
        } else {
            try FileManager.default.moveItem(at: item.url, to: destination)
            didMove(item.url, to: destination)
        }
    }
    private func didMove(_ source: URL, to destination: URL) {
        let oldPrefix = relativePath(source), newPrefix = relativePath(destination)
        favoritePaths = Set(favoritePaths.map { path in
            if path == oldPrefix { return newPrefix }
            if path.hasPrefix(oldPrefix + "/") { return newPrefix + String(path.dropFirst(oldPrefix.count)) }
            return path
        })
        if currentFolderURL == source { currentFolderURL = destination }
        if activeDocumentURL == source { activeDocumentURL = destination }
        if selectedItemURL == source { selectedItemURL = destination }
        WorkspaceStore.shared.documentMoved(from: source, to: destination)
        saveFavorites(); revealFolder(destination.deletingLastPathComponent()); reload()
    }
    func duplicate(_ item: LibraryItem) {
        guard contains(item.url), item.url != rootURL else { return }
        do {
            let destination = uniqueURL(name: item.name + " 副本", fileExtension: item.isFolder ? nil : "mindora", folder: item.url.deletingLastPathComponent())
            if item.isFolder { try FileManager.default.copyItem(at: item.url, to: destination) }
            else {
                let documentData = try NSDocumentController.shared.document(for: item.url)?.fileWrapper(ofType: UTType.mindora.identifier).regularFileContents
                var document = try documentData.map(MapInterchange.decodeJSON) ?? MapInterchange.read(item.url)
                document.id = UUID(); document.nodes = [document.root.cloned()]
                try MapInterchange.encodeJSON(document).write(to: destination, options: .atomic)
            }
            reload()
        } catch { errorMessage = "无法复制：\(error.localizedDescription)" }
    }
    func moveToTrash(_ item: LibraryItem) {
        guard contains(item.url), item.url != rootURL,
              !BackupStore.contains(item.url, in: recycleBinURL),
              (try? item.url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return }
        if hasOpenDocuments(inside: item.url) {
            errorMessage = "请先关闭“\(item.name)”及其中已打开的导图，再移到回收箱。关闭时可保存未完成的编辑。"
            return
        }
        do {
            try checkedRecycleBin()
            let manager = FileManager.default
            let container = recycleBinURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try manager.createDirectory(at: container, withIntermediateDirectories: true)
            let record = RecycledItem.Record(name: item.url.lastPathComponent, originalPath: relativePath(item.url), deletedAt: Date(), isFolder: item.isFolder)
            do {
                try JSONEncoder().encode(record).write(to: container.appendingPathComponent("record.json"), options: .atomic)
                try manager.moveItem(at: item.url, to: container.appendingPathComponent("item"))
            } catch {
                // No payload was moved successfully; leave the original untouched.
                try? manager.removeItem(at: container)
                throw error
            }
            if selectedItemURL == item.url { selectedItemURL = nil }
            if BackupStore.contains(currentFolderURL, in: item.url) { currentFolderURL = rootURL }
            loadRecycleBin()
            let path = relativePath(item.url)
            favoritePaths = favoritePaths.filter { $0 != path && !$0.hasPrefix(path + "/") }
            saveFavorites(); reload()
        } catch { errorMessage = "无法移到回收箱：\(error.localizedDescription)" }
    }
    private var recycleBinURL: URL { rootURL.appendingPathComponent(".mindora-trash", isDirectory: true) }
    private func checkedRecycleBin() throws {
        guard contains(recycleBinURL),
              (try? recycleBinURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw LibraryError.invalidLocation
        }
    }
    func loadRecycleBin() {
        do {
            try checkedRecycleBin()
            guard FileManager.default.fileExists(atPath: recycleBinURL.path) else { recycledItems = []; recycleNotice = ""; return }
            let folders = try FileManager.default.contentsOfDirectory(at: recycleBinURL, includingPropertiesForKeys: [.isSymbolicLinkKey])
            recycledItems = folders.compactMap { folder in
                guard let id = UUID(uuidString: folder.lastPathComponent),
                      (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
                      FileManager.default.fileExists(atPath: folder.appendingPathComponent("item").path),
                      let data = try? Data(contentsOf: folder.appendingPathComponent("record.json")),
                      data.count <= 65_536,
                      let record = try? JSONDecoder().decode(RecycledItem.Record.self, from: data) else { return nil }
                return RecycledItem(id: id, directory: folder, record: record)
            }.sorted { $0.record.deletedAt > $1.record.deletedAt }
            recycleNotice = folders.count > recycledItems.count ? "部分项目的恢复信息不可读，已保留原文件。可在 Finder 中检查；清空不会删除这些项目。" : ""
        } catch { errorMessage = "无法读取回收箱：\(error.localizedDescription)" }
    }
    private func validateRecycledItem(_ item: RecycledItem) throws {
        try checkedRecycleBin()
        guard item.directory == recycleBinURL.appendingPathComponent(item.id.uuidString, isDirectory: true),
              (try item.directory.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw LibraryError.invalidLocation }
    }
    func restoreRecycledItem(_ item: RecycledItem) {
        do {
            try validateRecycledItem(item)
            let original = rootURL.appendingPathComponent(item.record.originalPath).standardizedFileURL
            guard contains(original), original != rootURL,
                  !BackupStore.contains(original, in: recycleBinURL) else { throw LibraryError.invalidLocation }
            let parent = original.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let target: URL
            if FileManager.default.fileExists(atPath: original.path) {
                target = uniqueURL(name: original.deletingPathExtension().lastPathComponent + " 恢复", fileExtension: item.record.isFolder ? nil : original.pathExtension, folder: parent)
            } else { target = original }
            try FileManager.default.moveItem(at: item.payload, to: target)
            try? FileManager.default.removeItem(at: item.directory)
            revealFolder(parent); loadRecycleBin(); reload()
        } catch { errorMessage = "恢复失败，项目仍保留在回收箱：\(error.localizedDescription)" }
    }
    func permanentlyDelete(_ item: RecycledItem) {
        do {
            try validateRecycledItem(item)
            try FileManager.default.removeItem(at: item.directory)
            loadRecycleBin()
        } catch { errorMessage = "永久删除失败：\(error.localizedDescription)" }
    }
    func revealRecycleBin() {
        do {
            try checkedRecycleBin()
            try FileManager.default.createDirectory(at: recycleBinURL, withIntermediateDirectories: true)
            revealInFinder(recycleBinURL)
        } catch { errorMessage = "无法打开回收箱：\(error.localizedDescription)" }
    }
    func emptyRecycleBin() {
        // Only delete known entries; preserve unreadable content for manual recovery.
        for item in recycledItems { permanentlyDelete(item) }
    }
    func importMaps() {
        let panel = NSOpenPanel()
        panel.title = "将现有导图复制到资料库"
        panel.allowedContentTypes = [.mindora, .json]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        do {
            for url in panel.urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                var document = try MapInterchange.read(url)
                document.id = UUID(); document.nodes = [document.root.cloned()]
                let destination = uniqueURL(name: url.deletingPathExtension().lastPathComponent, fileExtension: "mindora", folder: currentFolderURL)
                try MapInterchange.encodeJSON(document).write(to: destination, options: .atomic)
            }
            revealFolder(currentFolderURL); reload()
        } catch { reload(); errorMessage = "部分文件未能导入：\(error.localizedDescription)" }
    }
    func toggleFavorite(_ url: URL) {
        guard contains(url) else { return }
        let path = relativePath(url)
        if favoritePaths.contains(path) { favoritePaths.remove(path) } else { favoritePaths.insert(path) }
        saveFavorites()
    }
    func isFavorite(_ url: URL) -> Bool { favoritePaths.contains(relativePath(url)) }
    func revealInFinder(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    private func revealFolder(_ url: URL) {
        var cursor = url
        while contains(cursor), cursor != rootURL { expandedFolders.insert(cursor); cursor.deleteLastPathComponent() }
    }
    private func hasOpenDocuments(inside url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return NSDocumentController.shared.documents.contains { document in
            guard let file = document.fileURL?.standardizedFileURL.path else { return false }
            return file == path || file.hasPrefix(path + "/")
        }
    }
    private func relativePath(_ url: URL) -> String {
        let base = rootURL.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : ""
    }
    private func saveFavorites() { UserDefaults.standard.set(Array(favoritePaths), forKey: favoritesKey + "." + rootURL.path) }
    private func uniqueURL(name: String, fileExtension: String?, folder: URL) -> URL {
        var index = 1
        while true {
            let basename = index == 1 ? name : "\(name) \(index)"
            let url = folder.appendingPathComponent(basename + (fileExtension.map { "." + $0 } ?? ""), isDirectory: fileExtension == nil)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            index += 1
        }
    }
    private func validateName(_ value: String) throws {
        guard !value.isEmpty, value != ".", value != "..", value.count <= 120,
              value.rangeOfCharacter(from: CharacterSet(charactersIn: "/:").union(.controlCharacters)) == nil else { throw LibraryError.invalidName }
    }
    private func promptName(title: String, message: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title; alert.informativeText = message
        let field = NSTextField(string: initial); field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum LibraryError: LocalizedError {
    case invalidName, nameExists, invalidLocation, moveIntoSelf, openFolder
    var errorDescription: String? {
        switch self {
        case .invalidName: "名称不能为空，也不能包含斜杠、冒号或换行；最多 120 个字符。"
        case .nameExists: "这个位置已有同名文件或文件夹，请换一个名称。"
        case .invalidLocation: "请选择当前资料库内的文件夹。"
        case .moveIntoSelf: "不能将文件夹移动到它自己的子目录中。"
        case .openFolder: "请先关闭这个文件夹中已打开的导图，再重命名或移动文件夹。"
        }
    }
}
