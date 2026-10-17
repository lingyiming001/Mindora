import SwiftUI
import UniformTypeIdentifiers

struct EditorSidebar<Outline: View>: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: EditorModel
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var catalog = WorkspaceCatalog.shared
    let outline: Outline
    let allowsOutline: Bool
    @State private var recentExpanded = false

    init(model: EditorModel, allowsOutline: Bool = true, @ViewBuilder outline: () -> Outline) {
        self.model = model; self.allowsOutline = allowsOutline; self.outline = outline()
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                if allowsOutline {
                    Text("大纲")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    WorkspaceSwitcher()
                    Button { newMap() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("新建导图").fontWeight(.medium)
                            Spacer()
                            Text("⌘N").font(.system(size: 10)).opacity(0.7)
                        }.font(.system(size: 12)).foregroundStyle(.white)
                            .padding(.horizontal, 12).frame(height: 34)
                            .background(InterfaceStyle.accent, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 14).padding(.top, 17).padding(.bottom, 14)
            Divider()
            if allowsOutline { outline } else { fileLibrary }
        }
        .background(InterfaceStyle.panel)

    }
    private func newMap() { model.finishEditing?(); library.newMap() }
    private var fileLibrary: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                TextField("搜索当前空间", text: $library.searchText).textFieldStyle(.plain).font(.system(size: 11))
                if !library.searchText.isEmpty {
                    Button { library.searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            }.padding(8).background(.background, in: RoundedRectangle(cornerRadius: 7)).padding(12)
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    if library.searchText.isEmpty && !library.favoriteURLs.isEmpty {
                        sectionHeader("收藏", symbol: "star")
                        ForEach(library.favoriteURLs, id: \.self) { url in
                            Button {
                                model.finishEditing?()
                                if url.hasDirectoryPath { library.selectFolder(url) } else { library.openDocument(url) }
                            } label: {
                                Label(url.deletingPathExtension().lastPathComponent, systemImage: url.hasDirectoryPath ? "folder" : "doc.text")
                                    .lineLimit(1).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(7)
                            }.buttonStyle(.plain).sidebarHoverFeedback(tint: model.document.theme.color)
                                .contextMenu { Button("取消收藏") { library.toggleFavorite(url) } }
                        }
                        Divider().padding(.vertical, 8)
                    }
                    HStack {
                        Button("文件") { library.selectFolder(library.rootURL) }
                            .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            .help("返回工作空间根目录")
                        Spacer()
                        Button { library.promptNewFolder() } label: { Image(systemName: "folder.badge.plus").font(.system(size: 12)) }
                            .buttonStyle(.plain).help("新建文件夹（⇧⌘N）")
                        Button { library.reload() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11)) }
                            .buttonStyle(.plain).help("刷新目录")
                    }.padding(.horizontal, 8).padding(.bottom, 3)
                        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in acceptDrop(providers, to: library.rootURL) }
                    if library.isLoading && library.items.isEmpty { ProgressView().controlSize(.small).padding(18) }
                    ForEach(library.filteredItems) { item in LibraryTreeRow(item: item, library: library, model: model, depth: 0) }
                    if !library.isLoading && library.filteredItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(library.searchText.isEmpty ? "让第一个想法落地" : "没有匹配的文件").font(.system(size: 12, weight: .medium))
                            Text(library.searchText.isEmpty ? "点击上方“新建导图”，或用 ⇧⌘N 创建文件夹。" : "试试其他文件名或文件夹名。")
                                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.padding(12)
                    }
                    if library.searchText.isEmpty && !library.recentURLs.isEmpty {
                        Divider().padding(.vertical, 8)
                        DisclosureGroup(isExpanded: $recentExpanded) {
                            ForEach(library.recentURLs, id: \.self) { url in
                                Button { model.finishEditing?(); library.openDocument(url) } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: "doc.text").foregroundStyle(.tertiary)
                                        Text(url.deletingPathExtension().lastPathComponent).font(.system(size: 11)).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }.padding(.vertical, 7).contentShape(Rectangle())
                                }.buttonStyle(.plain).sidebarHoverFeedback(tint: model.document.theme.color).help(url.path)
                            }
                        } label: {
                            Label("最近打开", systemImage: "clock").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        }.padding(.horizontal, 8)
                    }

                }.padding(.horizontal, 8).padding(.bottom, 12)
            }
            Divider()
            Button { openWindow(id: "recycle-bin") } label: {
                HStack { Label("回收箱", systemImage: "trash"); Spacer(); Image(systemName: "chevron.right").font(.caption2) }
                    .font(.system(size: 12)).padding(12).contentShape(Rectangle())
            }.buttonStyle(.plain).sidebarHoverFeedback()
            HStack {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(library.currentFolderURL == library.rootURL ? (catalog.current(library.rootURL)?.name ?? "工作空间") : library.currentFolderURL.lastPathComponent)
                    .lineLimit(1).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Button { library.revealInFinder(library.currentFolderURL) } label: { Image(systemName: "arrow.up.right.square").font(.system(size: 10)) }.buttonStyle(.plain).help("在 Finder 中显示当前文件夹")
            }.padding(12)
        }
    }
    private func sectionHeader(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.bottom, 3)
    }
    private func acceptDrop(_ providers: [NSItemProvider], to folder: URL) -> Bool {
        LibraryDropHandler.accept(providers, into: folder, library: library)
    }
}

private struct LibraryTreeRow: View {
    let item: LibraryItem
    @ObservedObject var library: LibraryStore
    @ObservedObject var model: EditorModel
    let depth: Int
    @State private var isDropTarget = false
    private var expanded: Bool { !library.searchText.isEmpty || library.expandedFolders.contains(item.url) }
    private var selected: Bool { item.isFolder ? library.currentFolderURL == item.url : library.selectedItemURL == item.url }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                if item.isFolder {
                    Button {
                        library.toggleFolderExpansion(item.url)
                    } label: { Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold)).frame(width: 22, height: 28).contentShape(Rectangle()) }
                        .buttonStyle(.plain).help(expanded ? "折叠文件夹" : "展开文件夹")
                } else { Color.clear.frame(width: 12, height: 1) }
                Button {
                    model.finishEditing?()
                    if item.isFolder { library.selectFolder(item.url) } else { library.selectItem(item.url) }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: item.isFolder ? (expanded ? "folder.fill" : "folder") : "doc.text")
                            .font(.system(size: 12)).foregroundStyle(item.isFolder ? model.document.theme.color : .secondary)
                        Text(item.name).font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 0)
                        if library.isFavorite(item.url) { Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.secondary) }
                        if item.isFolder { Text("\(item.totalMaps)").font(.system(size: 9)).foregroundStyle(.tertiary) }
                    }.padding(.vertical, 7).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        if !item.isFolder { library.openDocument(item.url) }
                    })
                    .onKeyPress(.return) {
                        if item.isFolder { library.selectFolder(item.url) } else { library.openDocument(item.url) }
                        return .handled
                    }
            }
            .padding(.leading, CGFloat(min(depth, 10)) * 11 + 6).padding(.trailing, 8)
            .background((isDropTarget || selected) ? model.document.theme.color.opacity(isDropTarget ? 0.2 : 0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .sidebarHoverFeedback(tint: model.document.theme.color)
            .help(item.url.path)
            .contextMenu {
                if item.isFolder {
                    Button("在此新建思维导图") { library.newMap(in: item.url) }
                    Button("新建子文件夹…") { library.promptNewFolder(in: item.url) }
                } else { Button("打开") { library.openDocument(item.url) } }
                Divider()
                Button("重命名…") { model.finishEditing?(); library.promptRename(item) }
                Button("移动到…") { model.finishEditing?(); library.promptMove(item) }
                MoveToWorkspaceMenu(item: item)
                Button("创建副本") { model.finishEditing?(); library.duplicate(item) }
                Button(library.isFavorite(item.url) ? "取消收藏" : "添加到收藏") { library.toggleFavorite(item.url) }
                Button("在 Finder 中显示") { library.revealInFinder(item.url) }
                Divider()
                Button("移到回收箱", role: .destructive) { model.finishEditing?(); library.moveToTrash(item) }
            }
            .onDrag { NSItemProvider(object: item.url as NSURL) }
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTarget) { providers in
                guard item.isFolder else { return false }
                return LibraryDropHandler.accept(providers, into: item.url, library: library)
            }
            if item.isFolder && expanded {
                ForEach(item.children) { child in LibraryTreeRow(item: child, library: library, model: model, depth: depth + 1) }
            }
        }
    }
}

@MainActor private enum LibraryDropHandler {
    static func accept(_ providers: [NSItemProvider], into folder: URL, library: LibraryStore) -> Bool {
        let supported = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !supported.isEmpty else { return false }
        for provider in supported {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let value = item as? URL { url = value }
                else if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else { url = nil }
                guard let url else { return }
                Task { @MainActor in library.moveItem(at: url, into: folder) }
            }
        }
        return true
    }
}
