import AppKit
import Combine

/// Defaults affect newly created maps and newly opened editor sessions.
enum AppPreferences {
    static func register() {
        UserDefaults.standard.register(defaults: [
            "appearance": "system", "defaultTheme": "indigo", "defaultLayout": "balanced",
            "defaultFontSize": 14, "showOutlineOnOpen": true, "showInspectorOnOpen": false,
            "backupEnabled": true, "backupRule": "interval", "backupInterval": 5, "backupRetention": 20
        ])
    }
    static func applyAppearance() {
        let value = UserDefaults.standard.string(forKey: "appearance") ?? "system"
        NSApp.appearance = value == "system" ? nil : NSAppearance(named: value == "dark" ? .darkAqua : .aqua)
    }
    static var fontSize: Double {
        let value = UserDefaults.standard.double(forKey: "defaultFontSize")
        return value == 0 ? 14 : min(36, max(10, value))
    }
    static func prepareNewMap(_ document: inout MindMapDocument) {
        document.theme = MapTheme(rawValue: UserDefaults.standard.string(forKey: "defaultTheme") ?? "") ?? .indigo
        document.layout = MindMapLayout(rawValue: UserDefaults.standard.string(forKey: "defaultLayout") ?? "") ?? .balanced
        func style(_ node: inout MindMapNode, root: Bool) {
            node.style = NodeStyle(colorHex: node.style?.colorHex, fontSize: min(36, fontSize + (root ? 3 : 0)), textAlignment: .left)
            for index in node.children.indices { style(&node.children[index], root: false) }
        }
        style(&document.nodes[0], root: true)
    }
}

enum BackupRule: String, CaseIterable, Identifiable {
    case everySave, interval, daily, manual
    var id: String { rawValue }
    var label: String {
        switch self {
        case .everySave: "每次保存"
        case .interval: "按间隔备份"
        case .daily: "每天首次保存"
        case .manual: "仅手动备份"
        }
    }
    var explanation: String {
        switch self {
        case .everySave: "每次成功保存（含系统自动保存）都创建副本，适合重要编辑。"
        case .interval: "成功保存时检查距上次备份的时间，达到间隔才创建副本。"
        case .daily: "每份导图每天首次成功保存时创建副本，适合日常归档。"
        case .manual: "不自动创建副本，使用下方“立即备份当前导图”。"
        }
    }
}

/// Backups contain saved map snapshots, separate from the native autosave mechanism.
@MainActor final class BackupStore: ObservableObject {
    static let shared = BackupStore()
    @Published private(set) var folderURL: URL
    @Published private(set) var status = "尚未备份"
    private var scopedURL: URL?
    private var lastBackup: [UUID: Date] = [:]
    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mindora/Backups", isDirectory: true)
        folderURL = base
        if let bookmark = UserDefaults.standard.data(forKey: "backupFolderBookmark") {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
                if url.startAccessingSecurityScopedResource() { scopedURL = url }
                folderURL = url
            }
        }
    }
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择备份文件夹"; panel.canChooseDirectories = true
        panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.directoryURL = folderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !LibraryStore.shared.contains(url), !Self.contains(LibraryStore.shared.rootURL, in: url) else {
            status = "请选择资料库之外的独立文件夹，备份位置不能与资料库重叠。"
            return
        }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            let accessing = url.startAccessingSecurityScopedResource()
            scopedURL?.stopAccessingSecurityScopedResource(); scopedURL = accessing ? url : nil
            folderURL = url; lastBackup = [:]
            UserDefaults.standard.set(bookmark, forKey: "backupFolderBookmark")
            LibraryStore.shared.reload()
        } catch { status = "无法设置备份位置：\(error.localizedDescription)" }
    }
    func reveal() {
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folderURL)
        } catch { status = "无法打开备份文件夹：\(error.localizedDescription)" }
    }
    nonisolated static func contains(_ url: URL, in folder: URL) -> Bool {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }
    func write(_ map: MindMapDocument, force: Bool = false) {
        let defaults = UserDefaults.standard
        guard force || defaults.bool(forKey: "backupEnabled") else { return }
        let rule = BackupRule(rawValue: defaults.string(forKey: "backupRule") ?? "") ?? .interval
        let dateKey = "backupLastDate.\(map.id.uuidString).\(folderURL.standardizedFileURL.path)"
        let last = lastBackup[map.id] ?? defaults.object(forKey: dateKey) as? Date
        if !force {
            switch rule {
            case .manual: return
            case .everySave: break
            case .interval:
                let interval = Double(max(1, defaults.integer(forKey: "backupInterval"))) * 60
                if let last, Date().timeIntervalSince(last) < interval { return }
            case .daily:
                if let last, Calendar.current.isDateInToday(last) { return }
            }
        }
        guard !Self.contains(LibraryStore.shared.rootURL, in: folderURL) else {
            status = "备份目录与资料库重叠，请在设置中选择独立的备份位置。"
            return
        }
        do {
            let manager = FileManager.default
            let folder = folderURL.appendingPathComponent(map.id.uuidString, isDirectory: true)
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = folder.appendingPathComponent("\(stamp)-\(UUID().uuidString).mindora")
            try MapInterchange.encodeJSON(map).write(to: url, options: .atomic)
            lastBackup[map.id] = Date()
            defaults.set(lastBackup[map.id], forKey: dateKey)
            status = "上次备份：\(Date().formatted(date: .abbreviated, time: .shortened)) · \(map.title)"
            let files = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "mindora" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            let retention = max(1, defaults.integer(forKey: "backupRetention"))
            for old in files.dropFirst(retention) { try manager.removeItem(at: old) }
        } catch { status = "备份失败：\(error.localizedDescription)" }
    }
}
