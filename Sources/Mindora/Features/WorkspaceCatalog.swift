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

@MainActor final class WorkspaceCatalog: ObservableObject {
    static let shared = WorkspaceCatalog()
    @Published private(set) var workspaces: [LibraryWorkspace]
    private let key = "Mindora.Workspaces"
    private init() {
        workspaces = UserDefaults.standard.data(forKey: "Mindora.Workspaces")
            .flatMap { try? JSONDecoder().decode([LibraryWorkspace].self, from: $0) } ?? []
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
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mindora/Workspaces/" + UUID().uuidString, isDirectory: true)
        guard !overlaps(root) else { LibraryStore.shared.errorMessage = "工作空间目录不能相互包含，请先调整现有资料库位置。"; return false }
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
        persist(); return true
    }
    func rename(_ record: LibraryWorkspace) {
        guard let name = prompt("重命名工作空间", initial: record.name), let index = workspaces.firstIndex(where: { $0.id == record.id }) else { return }
        workspaces[index].name = name; persist()
    }
    func remove(_ record: LibraryWorkspace) {
        guard workspaces.count > 1 else { LibraryStore.shared.errorMessage = "请至少保留一个工作空间。"; return }
        let alert = NSAlert()
        alert.messageText = "移除“\(record.name)”？"
        alert.informativeText = "只从空间列表中移除，导图、附件和回收箱仍保存在原文件夹，可通过选择资料库位置重新加入。\n\n原位置：\(record.path)"
        alert.addButton(withTitle: "移除工作空间"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if current(LibraryStore.shared.rootURL)?.id == record.id {
            guard let next = workspaces.first(where: { $0.id != record.id }), LibraryStore.shared.switchWorkspace(next) else { return }
        }
        workspaces.removeAll { $0.id == record.id }; persist()
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
    @State private var showsDetails = false
    @State private var detailsWorkspace: LibraryWorkspace?
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var catalog = WorkspaceCatalog.shared
    var body: some View {
        Menu {
            Section("切换工作空间") {
                ForEach(catalog.workspaces) { record in
                    Button { library.switchWorkspace(record) } label: {
                        Label((record.iconText?.isEmpty == false ? record.iconText! + " " : "") + record.name, systemImage: catalog.current(library.rootURL)?.id == record.id ? "checkmark.circle.fill" : (record.iconSymbol ?? "square.stack"))
                    }
                }
            }
            Divider()
            Button("新建工作空间…", systemImage: "plus") { detailsWorkspace = nil; showsDetails = true }
            if let current = catalog.current(library.rootURL) {
                Button("编辑工作空间…", systemImage: "pencil") { detailsWorkspace = current; showsDetails = true }
                Button("在 Finder 中显示", systemImage: "folder") { library.revealInFinder(library.rootURL) }
                Button("移除工作空间…", role: .destructive) { catalog.remove(current) }.disabled(catalog.workspaces.count < 2)
            }
        } label: {
            HStack(spacing: 10) {
                WorkspaceIcon(workspace: catalog.current(library.rootURL))
                VStack(alignment: .leading, spacing: 3) {
                    Text(catalog.current(library.rootURL)?.name ?? "个人空间").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(catalog.current(library.rootURL)?.introduction.flatMap { $0.isEmpty ? nil : $0 } ?? "工作空间").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }.padding(8).background(InterfaceStyle.surface, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(InterfaceStyle.divider, lineWidth: 0.5))
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(horizontal: false, vertical: true)
            .help(catalog.current(library.rootURL)?.introduction.flatMap { $0.isEmpty ? nil : $0 } ?? "切换或管理工作空间")
            .onReceive(NotificationCenter.default.publisher(for: .mindoraMainWindowDidClose)) { _ in showsDetails = false; detailsWorkspace = nil }
            .sheet(isPresented: $showsDetails) { WorkspaceDetailsEditor(workspace: detailsWorkspace) }
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
