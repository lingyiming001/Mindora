import AppKit
import SwiftUI

struct LibraryWorkspace: Codable, Identifiable {
    let id: UUID
    var name: String
    var path: String
    var bookmark: Data?
    var iconSymbol: String? = nil
    var iconText: String? = nil
    var introduction: String? = nil
    var iconColorHex: String? = nil
    func resolve() throws -> URL {
        if let bookmark {
            var stale = false
            return try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

struct TrashedWorkspace: Codable, Identifiable {
    let id: UUID
    let workspace: LibraryWorkspace
    let deletedAt: Date
}

@MainActor final class WorkspaceCatalog: ObservableObject {
    static let shared = WorkspaceCatalog()
    @Published private(set) var workspaces: [LibraryWorkspace]
    @Published private(set) var trashedWorkspaces: [TrashedWorkspace] = []
    private let key = "Mindora.Workspaces"
    private static var trashURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mindora/WorkspaceTrash", isDirectory: true)
    }
    private init() {
        workspaces = UserDefaults.standard.data(forKey: "Mindora.Workspaces")
            .flatMap { try? JSONDecoder().decode([LibraryWorkspace].self, from: $0) } ?? []
        loadWorkspaceTrash()
        for record in workspaces { writeWorkspaceMetadata(record) }
    }
    func current(_ root: URL) -> LibraryWorkspace? {
        workspaces.first { URL(fileURLWithPath: $0.path, isDirectory: true).standardizedFileURL.path == root.standardizedFileURL.path }
    }
    func register(_ url: URL, bookmark: Data?, name: String? = nil) {
        if let index = workspaces.firstIndex(where: { URL(fileURLWithPath: $0.path, isDirectory: true).standardizedFileURL.path == url.standardizedFileURL.path || (try? $0.resolve().standardizedFileURL.path) == url.standardizedFileURL.path }) {
            workspaces[index].path = url.path
            if let bookmark { workspaces[index].bookmark = bookmark }
        } else {
            workspaces.append(LibraryWorkspace(id: UUID(), name: name ?? (url.lastPathComponent == "Library" ? "个人空间" : url.lastPathComponent), path: url.path, bookmark: bookmark))
        }
        persist()
        if let record = current(url) { writeWorkspaceMetadata(record) }
    }
    private func writeWorkspaceMetadata(_ record: LibraryWorkspace) {
        guard let root = try? record.resolve(), FileManager.default.fileExists(atPath: root.path) else { return }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        var portable = record; portable.path = ""; portable.bookmark = nil
        if let data = try? JSONEncoder().encode(portable) {
            try? data.write(to: root.appendingPathComponent(".mindora-workspace.json"), options: .atomic)
        }
    }
    nonisolated static func discoverableWorkspaces(in base: URL) throws -> [LibraryWorkspace] {
        let folders = try FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        return folders.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.compactMap { folder in
            guard let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let data = try? Data(contentsOf: folder.appendingPathComponent(".mindora-workspace.json")), data.count < 65_536,
                  var record = try? JSONDecoder().decode(LibraryWorkspace.self, from: data) else { return nil }
            record.path = folder.path; record.bookmark = nil
            return record
        }
    }
    func discoverWorkspaces(in base: URL) {
        guard let discovered = try? Self.discoverableWorkspaces(in: base) else { return }
        var changed = false
        for var record in discovered {
            let url = URL(fileURLWithPath: record.path, isDirectory: true)
            guard !BackupStore.contains(url, in: BackupStore.shared.folderURL), current(url) == nil else { continue }
            record.bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            if let existing = workspaces.firstIndex(where: { $0.id == record.id }) {
                if FileManager.default.fileExists(atPath: workspaces[existing].path) {
                    record = LibraryWorkspace(id: UUID(), name: record.name, path: record.path, bookmark: record.bookmark,
                                              iconSymbol: record.iconSymbol, iconText: record.iconText,
                                              introduction: record.introduction, iconColorHex: record.iconColorHex)
                    workspaces.append(record)
                } else { workspaces[existing] = record }
            } else { workspaces.append(record) }
            writeWorkspaceMetadata(record); changed = true
        }
        if changed { persist() }
    }
    func overlaps(_ url: URL, except id: UUID? = nil) -> Bool {
        workspaces.contains { record in
            guard record.id != id else { return false }
            let other = (try? record.resolve()) ?? URL(fileURLWithPath: record.path)
            return BackupStore.contains(url, in: other) || BackupStore.contains(other, in: url)
        }
    }
    @discardableResult func create(name suppliedName: String? = nil, iconSymbol: String? = nil, iconText: String? = nil, introduction: String? = nil, colorHex: String? = nil) -> Bool {
        guard let name = suppliedName ?? prompt("新建工作空间", initial: "新的工作空间") else { return false }
        guard validDetails(name: name, iconText: iconText ?? "", introduction: introduction ?? "") else { return false }
        let base = LibraryStore.shared.storageRootURL
        let root = Self.availableWorkspaceDirectory(in: base, name: name)
        guard !overlaps(root, except: current(base)?.id) else { LibraryStore.shared.errorMessage = "工作空间目录不能相互包含，请先调整现有资料库位置。"; return false }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let bookmark = try root.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            register(root, bookmark: bookmark, name: name)
            if let record = current(root) {
                _ = updateDetails(record.id, name: name, symbol: iconSymbol ?? "square.stack.3d.up.fill", iconText: iconText ?? "", introduction: introduction ?? "", colorHex: colorHex ?? "6264D9")
                _ = LibraryStore.shared.switchWorkspace(record)
            }
            return true
        } catch { LibraryStore.shared.errorMessage = "无法创建工作空间：\(error.localizedDescription)"; return false }
    }
    nonisolated static func availableWorkspaceDirectory(in base: URL, name: String) -> URL {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/:").union(.controlCharacters))
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let folderName = cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "工作空间" : String(cleaned.prefix(60))
        var suffix = 1
        var candidate = base.appendingPathComponent(folderName, isDirectory: true)
        while FileManager.default.fileExists(atPath: candidate.path) {
            suffix += 1
            candidate = base.appendingPathComponent("\(folderName) \(suffix)", isDirectory: true)
        }
        return candidate
    }

    private func validDetails(name: String, iconText: String, introduction: String) -> Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 60, iconText.count <= 2, introduction.count <= 500 else {
            LibraryStore.shared.errorMessage = "名称需1–60字、图标文字最多2字、介绍最多500字。"; return false
        }
        return true
    }
    @discardableResult func updateDetails(_ id: UUID, name: String, symbol: String, iconText: String, introduction: String, colorHex: String) -> Bool {
        guard validDetails(name: name, iconText: iconText, introduction: introduction),
              let index = workspaces.firstIndex(where: { $0.id == id }), NSColor(hex: colorHex) != nil else { return false }
        workspaces[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        workspaces[index].iconSymbol = symbol
        workspaces[index].iconText = iconText.trimmingCharacters(in: .whitespacesAndNewlines)
        workspaces[index].introduction = introduction.trimmingCharacters(in: .whitespacesAndNewlines)
        workspaces[index].iconColorHex = colorHex
        persist(); writeWorkspaceMetadata(workspaces[index]); return true
    }
    func rename(_ record: LibraryWorkspace) {
        guard let name = prompt("重命名工作空间", initial: record.name), let index = workspaces.firstIndex(where: { $0.id == record.id }) else { return }
        workspaces[index].name = name; persist(); writeWorkspaceMetadata(workspaces[index])
    }
    func remove(_ record: LibraryWorkspace) {
        guard workspaces.count > 1 else { LibraryStore.shared.errorMessage = "请至少保留一个工作空间。"; return }
        let alert = NSAlert()
        alert.messageText = "将“\(record.name)”移到回收箱？"
        alert.informativeText = "空间及其文件会保留在 Mindora 回收箱中，可以恢复。只有在回收箱中永久删除后才会清理文件。"
        alert.addButton(withTitle: "移到回收箱"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if current(LibraryStore.shared.rootURL)?.id == record.id {
            guard let next = workspaces.first(where: { $0.id != record.id }), LibraryStore.shared.switchWorkspace(next) else { return }
        }
        let entry = TrashedWorkspace(id: UUID(), workspace: record, deletedAt: Date())
        let container = Self.trashURL.appendingPathComponent(entry.id.uuidString, isDirectory: true)
        do {
            let source = try record.resolve()
            let accessed = source.startAccessingSecurityScopedResource()
            defer { if accessed { source.stopAccessingSecurityScopedResource() } }
            let protected = workspaces.filter { $0.id != record.id }.compactMap { try? $0.resolve() }
                + [LibraryStore.shared.storageRootURL, Self.trashURL, BackupStore.shared.folderURL]
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
            try JSONEncoder().encode(entry).write(to: container.appendingPathComponent("record.json"), options: .atomic)
            try Self.moveWorkspaceToTrash(source: source, payload: container.appendingPathComponent("item", isDirectory: true), protecting: protected)
            workspaces.removeAll { $0.id == record.id }; persist(); loadWorkspaceTrash()
            LibraryStore.shared.reload()
        } catch {
            LibraryStore.shared.errorMessage = "无法移到回收箱，空间记录已保留：\(error.localizedDescription)"
        }
    }

    /// A legacy library can also contain other spaces. Move only its own entries.
    nonisolated static func moveWorkspaceToTrash(source: URL, payload: URL, protecting protected: [URL]) throws {
        let manager = FileManager.default
        guard (try source.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true,
              !BackupStore.contains(payload, in: source) else { throw CocoaError(.fileWriteInvalidFileName) }
        let ownsContainer = protected.contains { BackupStore.contains($0, in: source) }
        if !ownsContainer { try manager.moveItem(at: source, to: payload); return }
        try manager.createDirectory(at: payload, withIntermediateDirectories: true)
        var moved: [URL] = []
        do {
            for child in try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                guard !protected.contains(where: { BackupStore.contains($0, in: child) }) else { continue }
                try manager.moveItem(at: child, to: payload.appendingPathComponent(child.lastPathComponent))
                moved.append(child)
            }
        } catch {
            for child in moved.reversed() {
                try manager.moveItem(at: payload.appendingPathComponent(child.lastPathComponent), to: child)
            }
            try? manager.removeItem(at: payload)
            throw error
        }
    }

    func loadWorkspaceTrash() {
        let manager = FileManager.default
        let folders = (try? manager.contentsOfDirectory(at: Self.trashURL, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
        trashedWorkspaces = folders.compactMap { folder in
            guard (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
                  let data = try? Data(contentsOf: folder.appendingPathComponent("record.json")), data.count < 65_536,
                  let entry = try? JSONDecoder().decode(TrashedWorkspace.self, from: data),
                  folder.lastPathComponent == entry.id.uuidString,
                  manager.fileExists(atPath: folder.appendingPathComponent("item").path) else { return nil }
            return entry
        }.sorted { $0.deletedAt > $1.deletedAt }
    }
    private func trashContainer(_ entry: TrashedWorkspace) throws -> URL {
        let folder = Self.trashURL.appendingPathComponent(entry.id.uuidString, isDirectory: true)
        guard trashedWorkspaces.contains(where: { $0.id == entry.id }),
              (try folder.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw CocoaError(.fileWriteInvalidFileName) }
        return folder
    }
    func restoreWorkspace(_ entry: TrashedWorkspace) {
        do {
            let container = try trashContainer(entry)
            var record = entry.workspace
            let original = URL(fileURLWithPath: record.path, isDirectory: true)
            let destination = FileManager.default.fileExists(atPath: original.path)
                ? Self.availableWorkspaceDirectory(in: LibraryStore.shared.storageRootURL, name: record.name + " 恢复") : original
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let payload = container.appendingPathComponent("item", isDirectory: true)
            try FileManager.default.moveItem(at: payload, to: destination)
            record.path = destination.path
            record.bookmark = try? destination.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            if let favorites = UserDefaults.standard.stringArray(forKey: "Mindora.LibraryFavorites." + entry.workspace.path) {
                UserDefaults.standard.set(favorites, forKey: "Mindora.LibraryFavorites." + destination.path)
            }
            workspaces.append(record); persist(); writeWorkspaceMetadata(record)
            try? FileManager.default.removeItem(at: container)
            loadWorkspaceTrash(); LibraryStore.shared.reload()
        } catch { LibraryStore.shared.errorMessage = "恢复工作空间失败：\(error.localizedDescription)" }
    }
    func permanentlyDeleteWorkspace(_ entry: TrashedWorkspace) {
        do {
            let container = try trashContainer(entry)
            try FileManager.default.removeItem(at: container)
            loadWorkspaceTrash()
        } catch { LibraryStore.shared.errorMessage = "永久删除工作空间失败：\(error.localizedDescription)" }
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(workspaces) { UserDefaults.standard.set(data, forKey: key) }
    }
    private func prompt(_ title: String, initial: String) -> String? {
        let alert = NSAlert(); alert.messageText = title
        let field = NSTextField(string: initial); field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60 else { LibraryStore.shared.errorMessage = "空间名称需为 1–60 个字符。"; return nil }
        return name
    }
}

struct WorkspaceSwitcher: View {
    private enum DetailsSheet: Identifiable {
        case create
        case edit(LibraryWorkspace)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let workspace): return workspace.id.uuidString
            }
        }

        var workspace: LibraryWorkspace? {
            switch self {
            case .create: return nil
            case .edit(let workspace): return workspace
            }
        }
    }

    @State private var detailsSheet: DetailsSheet?
    @State private var showsSwitcher = false
    @State private var hovered = false
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var catalog = WorkspaceCatalog.shared
    private var current: LibraryWorkspace? { catalog.current(library.rootURL) }

    var body: some View {
        Button { showsSwitcher.toggle() } label: {
            HStack(spacing: 10) {
                WorkspaceIcon(workspace: current, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(current?.name ?? "个人空间")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(current?.introduction.flatMap { $0.isEmpty ? nil : $0 } ?? "工作空间")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(InterfaceStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(hovered || showsSwitcher ? InterfaceStyle.accent.opacity(0.4) : InterfaceStyle.divider, lineWidth: 0.75))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
            .onHover { hovered = $0 }
            .accessibilityLabel("工作空间：\(current?.name ?? "个人空间")")
            .help("切换或管理工作空间")
            .popover(isPresented: $showsSwitcher, arrowEdge: .trailing) { switcherPanel }
            .onReceive(NotificationCenter.default.publisher(for: .mindoraMainWindowDidClose)) { _ in
                showsSwitcher = false; detailsSheet = nil
            }
            .sheet(item: $detailsSheet) { sheet in WorkspaceDetailsEditor(workspace: sheet.workspace) }
    }

    private var switcherPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("工作空间").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(catalog.workspaces.count) 个空间").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(catalog.workspaces) { record in
                        WorkspaceSelectionRow(workspace: record, isSelected: current?.id == record.id) {
                            if library.switchWorkspace(record) { showsSwitcher = false }
                        }
                    }
                }.padding(.horizontal, 8)
            }.frame(maxHeight: 280)
            Divider().padding(.top, 10).padding(.bottom, 6)
            VStack(spacing: 2) {
                panelAction("新建工作空间", symbol: "plus.circle") { detailsSheet = .create }
                if let current {
                    panelAction("编辑工作空间", symbol: "slider.horizontal.3") { detailsSheet = .edit(current) }
                    HStack {
                        Button { showsSwitcher = false; library.revealInFinder(library.rootURL) } label: {
                            Label("在 Finder 中显示", systemImage: "folder")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                        Spacer()
                        Menu {
                            Button("移到回收箱…", role: .destructive) {
                                showsSwitcher = false; catalog.remove(current)
                            }.disabled(catalog.workspaces.count < 2)
                        } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .help("更多空间操作")
                    }.padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
                }
            }.padding(.horizontal, 8).padding(.bottom, 10)
        }.frame(width: 300).background(InterfaceStyle.surface)
    }

    private func panelAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button { showsSwitcher = false; action() } label: {
            Label(title, systemImage: symbol).font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 9)
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).sidebarHoverFeedback()
    }
}

private struct WorkspaceSelectionRow: View {
    let workspace: LibraryWorkspace
    let isSelected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                WorkspaceIcon(workspace: workspace, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(workspace.name).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
                    Text(workspace.introduction.flatMap { $0.isEmpty ? nil : $0 } ?? "独立的导图与文件")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(InterfaceStyle.accent)
                }
            }.padding(10).contentShape(RoundedRectangle(cornerRadius: 9))
                .background(isSelected ? InterfaceStyle.accent.opacity(0.08) : hovered ? Color.primary.opacity(0.04) : .clear,
                            in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .accessibilityValue(isSelected ? "当前工作空间" : "")
    }
}

struct MoveToWorkspaceMenu: View {
    let item: LibraryItem
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var catalog = WorkspaceCatalog.shared
    var body: some View {
        Menu("移动到工作空间") {
            ForEach(catalog.workspaces.filter { $0.id != catalog.current(library.rootURL)?.id }) { record in
                Button(record.name) { library.moveToWorkspace(item, workspace: record) }
            }
        }.disabled(catalog.workspaces.count < 2)
    }
}
