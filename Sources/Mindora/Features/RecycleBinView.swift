import SwiftUI

struct RecycledItem: Identifiable {
    struct Record: Codable {
        let name: String
        let originalPath: String
        let deletedAt: Date
        let isFolder: Bool
    }
    let id: UUID
    let directory: URL
    let record: Record
    var payload: URL { directory.appendingPathComponent("item") }
}

struct RecycleBinView: View {
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var catalog = WorkspaceCatalog.shared
    @State private var pendingWorkspaceDelete: TrashedWorkspace?
    @State private var pendingDelete: RecycledItem?
    @State private var emptyConfirmation = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("回收箱").font(.system(size: 26, weight: .bold))
                    Text("\(library.recycledItems.count + catalog.trashedWorkspaces.count) 项 · \(library.rootURL.lastPathComponent)")
                        .foregroundStyle(.secondary)
                    Text("恢复到原位置；同名时自动保留两份。不会自动清理。").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("刷新", systemImage: "arrow.clockwise") { library.loadRecycleBin(); catalog.loadWorkspaceTrash() }
                Button("清空…", role: .destructive) { emptyConfirmation = true }
                    .disabled(library.recycledItems.isEmpty && catalog.trashedWorkspaces.isEmpty)
            }.padding(24)
            Divider()
            if library.recycledItems.isEmpty && catalog.trashedWorkspaces.isEmpty {
                ContentUnavailableView("回收箱是空的", systemImage: "trash", description: Text("移除的工作空间、文件和文件夹会暂存在这里。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !catalog.trashedWorkspaces.isEmpty {
                        Section("工作空间") {
                            ForEach(catalog.trashedWorkspaces) { entry in
                                HStack(spacing: 14) {
                                    WorkspaceIcon(workspace: entry.workspace, size: 36)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(entry.workspace.name).fontWeight(.medium).lineLimit(1)
                                        Text(entry.deletedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("恢复空间") { catalog.restoreWorkspace(entry) }
                                    Button("永久删除…", role: .destructive) { pendingWorkspaceDelete = entry }
                                }.padding(.vertical, 8)
                            }
                        }
                    }
                    Section("当前空间的文件") {
                        ForEach(library.recycledItems) { item in
                            HStack(spacing: 14) {
                                Image(systemName: item.record.isFolder ? "folder.fill" : "doc.text")
                                    .font(.title2).foregroundStyle(InterfaceStyle.accent).frame(width: 32)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.record.name).fontWeight(.medium).lineLimit(1)
                                    Text(item.record.originalPath).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    Text(item.record.deletedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Button("恢复") { library.restoreRecycledItem(item) }
                                Button("永久删除…", role: .destructive) { pendingDelete = item }
                            }.padding(.vertical, 8)
                        }
                    }
                }.listStyle(.inset)
            }
            Divider()
            HStack {
                Text(library.recycleNotice.isEmpty ? "永久删除前请确认不再需要这些内容。" : library.recycleNotice)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("在 Finder 中显示") { library.revealRecycleBin() }
            }.padding(16)
        }
        .frame(minWidth: 650, minHeight: 460)
        .background(InterfaceStyle.surface)
        .onAppear { library.loadRecycleBin(); catalog.loadWorkspaceTrash() }
        .onChange(of: library.rootURL) { _, _ in
            pendingDelete = nil; pendingWorkspaceDelete = nil; emptyConfirmation = false; library.loadRecycleBin()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mindoraMainWindowDidClose)) { _ in
            pendingDelete = nil; pendingWorkspaceDelete = nil; emptyConfirmation = false
        }
        .alert("永久删除工作空间？", isPresented: Binding(get: { pendingWorkspaceDelete != nil }, set: { if !$0 { pendingWorkspaceDelete = nil } })) {
            Button("取消", role: .cancel) { pendingWorkspaceDelete = nil }
            Button("永久删除", role: .destructive) {
                if let entry = pendingWorkspaceDelete { catalog.permanentlyDeleteWorkspace(entry) }
                pendingWorkspaceDelete = nil
            }
        } message: { Text("“\(pendingWorkspaceDelete?.workspace.name ?? "")”及其所有导图、附件和空间回收箱将被永久删除，无法恢复。") }
        .alert("永久删除此项目？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("永久删除", role: .destructive) {
                if let item = pendingDelete { library.permanentlyDelete(item) }
                pendingDelete = nil
            }
        } message: { Text("“\(pendingDelete?.record.name ?? "")”将无法从回收箱恢复。") }
        .alert("清空回收箱？", isPresented: $emptyConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { library.emptyRecycleBin(); for entry in catalog.trashedWorkspaces { catalog.permanentlyDeleteWorkspace(entry) } }
        } message: { Text("回收箱中的所有工作空间，以及当前空间回收箱中的文件将被永久删除，无法恢复。") }
        .alert("操作未完成", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
            Button("好") { library.errorMessage = nil }
        } message: { Text(library.errorMessage ?? "") }
    }
}
