import SwiftUI

struct LibraryHomeView: View {
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var catalog = WorkspaceCatalog.shared
    @StateObject private var navigation = EditorModel(document: MindMapDocument())
    @State private var showsSidebar = true
    @State private var showsNewWorkspace = false
    @AppStorage("libraryDisplayMode") private var displayMode = "grid"

    private var items: [LibraryItem] {
        library.currentItems.compactMap { $0.matching(library.searchText.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
    private var folders: [LibraryItem] { items.filter(\.isFolder) }
    private var maps: [LibraryItem] { items.filter { !$0.isFolder } }
    private var breadcrumbs: [URL] {
        var paths: [URL] = [], cursor = library.currentFolderURL
        while cursor != library.rootURL, library.contains(cursor) {
            paths.insert(cursor, at: 0); cursor.deleteLastPathComponent()
        }
        return paths
    }
    var body: some View {
        HStack(spacing: 0) {
            if showsSidebar {
                EditorSidebar(model: navigation, allowsOutline: false) { EmptyView() }
                    .frame(width: InterfaceStyle.sidebarWidth)
                Rectangle().fill(InterfaceStyle.divider).frame(width: 1)
            }
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    if items.isEmpty { emptyState }
                    else if displayMode == "list" { listContent.padding(.horizontal, 28).padding(.bottom, 28) }
                    else { gridContent.padding(.horizontal, 28).padding(.bottom, 28) }
                }
                Rectangle().fill(InterfaceStyle.divider).frame(height: 1)
                HStack {
                    Image(systemName: "externaldrive").font(.system(size: 10))
                    Text(catalog.current(library.rootURL)?.name ?? "工作空间")
                    Spacer()
                    Text("\(items.count) 项")
                }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 24).frame(height: 32)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 540)
        .background(InterfaceStyle.surface)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { showsSidebar.toggle() } label: { Label("侧边栏", systemImage: "sidebar.left") }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                SettingsLink { Label("设置", systemImage: "gearshape") }
                Button { workspace.chooseFile() } label: { Label("打开", systemImage: "folder") }
                Menu {
                    Button("新建工作空间…") { showsNewWorkspace = true }
                    Button("新建文件夹…") { library.promptNewFolder() }
                    Button("导入现有导图…") { library.importMaps() }
                    Divider()
                    Button("选择资料库位置…") { library.chooseLocation() }
                    Button("在 Finder 中显示") { library.revealInFinder(library.currentFolderURL) }
                    Button("刷新目录") { library.reload() }
                } label: { Label("文件管理", systemImage: "ellipsis") }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mindoraMainWindowDidClose)) { _ in showsNewWorkspace = false }
        .sheet(isPresented: $showsNewWorkspace) { WorkspaceDetailsEditor(workspace: nil) }
        .onAppear {
            library.reload()
            let value = UserDefaults.standard.string(forKey: "appearance") ?? "system"
            NSApp.appearance = value == "system" ? nil : NSAppearance(named: value == "dark" ? .darkAqua : .aqua)
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 6) {
                Button(catalog.current(library.rootURL)?.name ?? "工作空间") { library.selectFolder(library.rootURL) }.buttonStyle(.plain)
                ForEach(breadcrumbs, id: \.self) { url in
                    Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                    Button(url.lastPathComponent) { library.selectFolder(url) }.buttonStyle(.plain).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(library.currentFolderURL == library.rootURL ? "我的导图" : library.currentFolderURL.lastPathComponent)
                        .font(.system(size: 23, weight: .semibold))
                    if library.currentFolderURL == library.rootURL,
                       let intro = catalog.current(library.rootURL)?.introduction, !intro.isEmpty {
                        Text(intro).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("\(folders.count) 个文件夹 · \(maps.count) 份导图")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                QuietIconButton(title: "网格视图", symbol: "square.grid.2x2", isSelected: displayMode == "grid") { displayMode = "grid" }
                QuietIconButton(title: "列表视图", symbol: "list.bullet", isSelected: displayMode == "list") { displayMode = "list" }
                Rectangle().fill(InterfaceStyle.divider).frame(width: 1, height: 18).padding(.horizontal, 4)
                QuietIconButton(title: "新建文件夹（⇧⌘N）", symbol: "folder.badge.plus") { library.promptNewFolder() }
                if !showsSidebar {
                    Button { library.newMap() } label: { Label("新建导图", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(InterfaceStyle.accent)
                }
            }
        }.padding(.horizontal, 28).padding(.top, 25).padding(.bottom, 26)
    }
    private var gridContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !folders.isEmpty {
                sectionLabel("文件夹")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 14)], alignment: .leading, spacing: 14) {
                    ForEach(folders) { item in
                        Button { library.selectFolder(item.url) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill").font(.system(size: 27, weight: .light)).foregroundStyle(InterfaceStyle.accent.opacity(0.65))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
                                    Text("\(item.totalMaps) 份导图").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(InterfaceStyle.panel.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(InterfaceStyle.divider, lineWidth: 0.5))
                        }.buttonStyle(.plain).contextMenu { LibraryItemActions(item: item, library: library) }
                    }
                }
            }
            if !maps.isEmpty {
                sectionLabel("思维导图")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 265), spacing: 18)], alignment: .leading, spacing: 22) {
                    ForEach(maps) { item in LibraryMapCard(item: item, library: library) }
                }
            }
        }
    }
    private var listContent: some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    if item.isFolder { library.selectFolder(item.url) } else { library.openDocument(item.url) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.isFolder ? "folder.fill" : "doc.text")
                            .foregroundStyle(item.isFolder ? InterfaceStyle.accent.opacity(0.7) : Color.secondary).frame(width: 22)
                        Text(item.name).font(.system(size: 12)).lineLimit(1)
                        Spacer()
                        if library.isFavorite(item.url) { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.secondary) }
                        Text(item.isFolder ? "\(item.totalMaps) 份导图" : "思维导图").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 74, alignment: .trailing)
                    }.padding(.horizontal, 14).frame(height: 46).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .background(library.selectedItemURL == item.url ? InterfaceStyle.accent.opacity(0.1) : .clear)
                    .onKeyPress(.return) {
                        if item.isFolder { library.selectFolder(item.url) } else { library.openDocument(item.url) }
                        return .handled
                    }
                    .contextMenu { LibraryItemActions(item: item, library: library) }
                Rectangle().fill(InterfaceStyle.divider).frame(height: 0.5)
            }
        }
    }
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(.tertiary)
            Text(library.searchText.isEmpty ? "从一个想法开始" : "没有匹配的文件").font(.system(size: 16, weight: .medium))
            Text(library.searchText.isEmpty ? "新建一份导图，或打开已有文件。" : "试试其他文件或文件夹名称。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if library.searchText.isEmpty {
                Button("新建思维导图") { library.newMap() }.buttonStyle(.borderedProminent).tint(InterfaceStyle.accent).padding(.top, 8)
            }
        }.frame(maxWidth: .infinity, minHeight: 310)
    }
    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
    }
}

private struct LibraryMapCard: View {
    let item: LibraryItem
    @ObservedObject var library: LibraryStore
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Button { library.openDocument(item.url) } label: {
            VStack(alignment: .leading, spacing: 11) {
                DocumentThumbnail(url: item.url, version: item.contentVersion).frame(height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke((hovered || library.selectedItemURL == item.url) ? InterfaceStyle.accent.opacity(0.6) : InterfaceStyle.divider, lineWidth: 1))
                    .shadow(color: .black.opacity(hovered ? (colorScheme == .dark ? 0.3 : 0.14) : 0.04), radius: hovered ? 10 : 2, x: 0, y: hovered ? 4 : 1)
                HStack(spacing: 5) {
                    Text(item.name).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
                    Spacer(minLength: 0)
                    if library.isFavorite(item.url) { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
                }.padding(.horizontal, 2)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
            .onKeyPress(.return) { library.openDocument(item.url); return .handled }
            .help("点击或按 Return 打开导图")
            .onHover { hovered = $0 }
            .onDisappear { hovered = false }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
            .contextMenu { LibraryItemActions(item: item, library: library) }
    }
}

private struct LibraryItemActions: View {
    let item: LibraryItem
    @ObservedObject var library: LibraryStore
    var body: some View {
        if item.isFolder {
            Button("在此新建导图") { library.newMap(in: item.url) }
            Button("新建子文件夹…") { library.promptNewFolder(in: item.url) }
        } else { Button("打开") { library.openDocument(item.url) } }
        Divider()
        Button("重命名…") { library.promptRename(item) }
        Button("移动到…") { library.promptMove(item) }
        MoveToWorkspaceMenu(item: item)
        Button("创建副本") { library.duplicate(item) }
        Button(library.isFavorite(item.url) ? "取消收藏" : "收藏") { library.toggleFavorite(item.url) }
        Button("在 Finder 中显示") { library.revealInFinder(item.url) }
        Divider()
        Button("移到回收箱", role: .destructive) { library.moveToTrash(item) }
    }
}

private struct DocumentThumbnail: View {
    let url: URL
    let version: LibraryItem.ContentVersion
    @State private var document: MindMapDocument?
    @State private var layout: LayoutResult?
    @State private var unavailable = false
    private struct PreviewIdentity: Hashable {
        let url: URL
        let version: LibraryItem.ContentVersion
    }
    var body: some View {
        ZStack {
            InterfaceStyle.panel.opacity(0.55)
            if let document, let layout {
                Canvas { context, size in
                    let bounds = layout.bounds.insetBy(dx: -35, dy: -35)
                    let scale = min(size.width / max(bounds.width, 1), size.height / max(bounds.height, 1))
                    func point(_ world: CGPoint) -> CGPoint {
                        CGPoint(x: (world.x - bounds.midX) * scale + size.width / 2, y: (world.y - bounds.midY) * scale + size.height / 2)
                    }
                    let colors = layout.colors
                    for (from, to) in layout.edges {
                        guard let a = layout.frames[from], let b = layout.frames[to] else { continue }
                        var path = Path()
                        let start = point(CGPoint(x: a.midX, y: a.midY)), end = point(CGPoint(x: b.midX, y: b.midY))
                        path.move(to: start)
                        if document.layout == .organization {
                            path.addCurve(to: end, control1: CGPoint(x: start.x, y: (start.y + end.y) / 2), control2: CGPoint(x: end.x, y: (start.y + end.y) / 2))
                        } else {
                            path.addCurve(to: end, control1: CGPoint(x: (start.x + end.x) / 2, y: start.y), control2: CGPoint(x: (start.x + end.x) / 2, y: end.y))
                        }
                        context.stroke(path, with: .color(Color(nsColor: colors[to] ?? document.theme.accent).opacity(0.55)), lineWidth: max(0.5, scale * 1.5))
                    }
                    for node in layout.visibleNodes {
                        guard let frame = layout.frames[node.id] else { continue }
                        let center = point(CGPoint(x: frame.midX, y: frame.midY))
                        let rect = CGRect(x: center.x - frame.width * scale / 2, y: center.y - frame.height * scale / 2, width: frame.width * scale, height: frame.height * scale)
                        let color = Color(nsColor: colors[node.id] ?? document.theme.accent)
                        let root = node.id == document.root.id
                        let shape = Path(roundedRect: rect, cornerRadius: max(0, CGFloat(node.style?.cornerRadius ?? 9) * scale))
                        context.fill(shape, with: .color(node.style?.backgroundHex.flatMap(NSColor.init(hex:)).map(Color.init(nsColor:)) ?? (root ? color : InterfaceStyle.surface)))
                        if node.style?.borderWidth != 0 { context.stroke(shape, with: .color(color.opacity(0.45)), lineWidth: max(0.5, CGFloat(node.style?.borderWidth ?? 1) * scale)) }
                        if rect.width > 28 && rect.height > 9 {
                            var textContext = context
                            textContext.clip(to: Path(rect.insetBy(dx: 2, dy: 1)))
                            let title = node.title.count > 48 ? String(node.title.prefix(47)) + "…" : node.title
                            let alignment = node.style?.textAlignment ?? .center
                            let position = CGPoint(x: alignment == .left ? rect.minX + 3 : alignment == .right ? rect.maxX - 3 : center.x, y: center.y)
                            let anchor: UnitPoint = alignment == .left ? .leading : alignment == .right ? .trailing : .center
                            textContext.draw(Text(title).font(.system(size: max(3, min(9, 14 * scale)), weight: node.style?.bold == true ? .bold : .medium))
                                .foregroundColor(node.style?.textColorHex.flatMap(NSColor.init(hex:)).map(Color.init(nsColor:)) ?? (root ? .white : .primary)), at: position, anchor: anchor)
                        }
                    }
                }.padding(6)
            } else {
                Text(unavailable ? "预览不可用" : "载入预览…").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .task(id: PreviewIdentity(url: url, version: version), priority: .utility) {
            unavailable = false
            let worker = Task { try await LibraryPreviewCache.shared.preview(url) }
            let activityID = PanelActivityStore.shared.register(worker)
            defer { PanelActivityStore.shared.finish(activityID) }
            do {
                let preview = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled, !worker.isCancelled else { return }
                document = preview.0; layout = preview.1
            } catch {
                if !Task.isCancelled, !worker.isCancelled {
                    document = nil; layout = nil; unavailable = true
                }
            }
        }
        .accessibilityLabel("思维导图内容预览")
    }
}


/// A bounded, serialized cache avoids duplicate decoding and unbounded preview tasks.
private actor LibraryPreviewCache {
    static let shared = LibraryPreviewCache()
    private struct Entry {
        let modified: Date?
        let bytes: Int?
        let document: MindMapDocument
        let layout: LayoutResult
    }
    private var entries: [URL: Entry] = [:]
    private var recency: [URL] = []
    private var nodeCost = 0
    func preview(_ url: URL) throws -> (MindMapDocument, LayoutResult) {
        try Task.checkCancellation()
        let metadata = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        if let entry = entries[url], entry.modified == metadata.contentModificationDate, entry.bytes == metadata.fileSize {
            recency.removeAll { $0 == url }; recency.append(url)
            return (entry.document, entry.layout)
        }
        if let old = entries.removeValue(forKey: url) { nodeCost -= old.document.nodeCount }
        recency.removeAll { $0 == url }
        let document = try MapInterchange.read(url)
        try Task.checkCancellation()
        let layout = LayoutEngine.layout(document)
        try Task.checkCancellation()
        entries[url] = Entry(modified: metadata.contentModificationDate, bytes: metadata.fileSize, document: document, layout: layout)
        recency.append(url); nodeCost += document.nodeCount
        while entries.count > 24 || nodeCost > 20_000 {
            let oldest = recency.removeFirst()
            if let entry = entries.removeValue(forKey: oldest) { nodeCost -= entry.document.nodeCount }
        }
        return (document, layout)
    }
}
