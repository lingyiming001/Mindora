import AppKit
import SwiftUI

struct CanvasRequest: Equatable {
    enum Action { case fit, centerSelection, editSelection, focus }
    let id = UUID()
    let action: Action
}

@MainActor final class EditorModel: ObservableObject {
    @Published private(set) var document: MindMapDocument { didSet { if !isResizePreview { documentDidChange?(document) } } }
    @Published private(set) var layoutResult: LayoutResult
    @Published private(set) var selectedIDs: Set<UUID>
    @Published private(set) var selectedID: UUID?
    @Published var viewport = CanvasViewport()
    @Published var searchText = ""
    @Published var isSearchPresented = false
    @Published var sidebarSection: EditorSidebarSection = .outline
    @Published var showsOutline = true
    @Published var showsInspector = false
    @Published private(set) var isFocusMode = false
    private var panelsBeforeFocus: (outline: Bool, inspector: Bool)?
    @Published var errorMessage: String?
    @Published private(set) var historyRevision = 0

    private var isResizePreview = false
    private var resizeOrigin: (UUID, NodeProperties)?
    var editingTransactionDidBegin: (() -> Void)?
    func beginWidthResize(_ id: UUID) {
        guard let node = document.root.find(id) else { return }
        resizeOrigin = (id, NodeProperties(node)); editingTransactionDidBegin?()
    }
    func previewSize(width: Double, height: Double) {
        guard let (id, _) = resizeOrigin else { return }
        isResizePreview = true
        var next = document
        _ = next.nodes[0].update(id) { node in
            var style = node.style ?? NodeStyle(); style.width = min(1200, max(160, width)); style.height = min(2400, max(44, height)); node.style = style
        }
        document = next; refreshLayoutAndSelection(); isResizePreview = false
    }
    func finishWidthResize(commit: Bool) {
        guard let (id, before) = resizeOrigin, let node = document.root.find(id) else { resizeOrigin = nil; return }
        let after = NodeProperties(node); resizeOrigin = nil
        isResizePreview = true
        var restored = document
        _ = restored.nodes[0].update(id) { before.apply(to: &$0) }
        document = restored; refreshLayoutAndSelection(); isResizePreview = false
        if commit, before != after { execute(.update(id, before: before, after: after), name: "调整主题尺寸") }
        else { documentDidChange?(document) }
    }
    var canvasAction: ((CanvasRequest.Action) -> Void)?
    var documentDidChange: ((MindMapDocument) -> Void)?
    var finishEditing: (() -> Void)?
    @Published var showsTemplates = false
    @Published var showsCommandPalette = false
    @Published var inspectorContentRequest = UUID()
    @Published var contentInsertion: ContentInsertion?
    func insertContent(_ kind: ContentInsertion.Kind) {
        finishEditing?()
        guard let selectedID else { return }
        contentInsertion = ContentInsertion(nodeID: selectedID, kind: kind)
    }

    private struct HistoryEntry {
        var command: EditCommand
        let name: String
        let beforeSelection: Set<UUID>
        let beforeFocus: UUID?
        var afterSelection: Set<UUID>
        var afterFocus: UUID?
        var coalescingKey: String?
        var timestamp: Date
    }
    private var undoStack: [HistoryEntry] = []
    private var redoStack: [HistoryEntry] = []
    private static let clipboardType = NSPasteboard.PasteboardType("app.mindora.nodes")

    init(document: MindMapDocument) {
        showsOutline = UserDefaults.standard.object(forKey: "showOutlineOnOpen") as? Bool ?? true
        showsInspector = UserDefaults.standard.bool(forKey: "showInspectorOnOpen")
        self.document = document
        layoutResult = LayoutEngine.layout(document)
        selectedID = document.root.id
        selectedIDs = [document.root.id]
    }
    var selectedNode: MindMapNode? { selectedID.flatMap { document.root.find($0) } }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoName: String { undoStack.last?.name ?? "" }
    var redoName: String { redoStack.last?.name ?? "" }
    var searchMatches: [MindMapNode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return document.allNodes.filter { node in
            node.title.localizedCaseInsensitiveContains(query) || node.note.localizedCaseInsensitiveContains(query)
                || node.code.localizedCaseInsensitiveContains(query) || node.link.localizedCaseInsensitiveContains(query)
                || node.attachments.contains(where: { $0.name.localizedCaseInsensitiveContains(query) })
                || node.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    func toggleFocusMode() {
        finishEditing?()
        if isFocusMode {
            showsOutline = panelsBeforeFocus?.outline ?? true
            showsInspector = panelsBeforeFocus?.inspector ?? false
            panelsBeforeFocus = nil; isFocusMode = false
        } else {
            panelsBeforeFocus = (showsOutline, showsInspector)
            showsOutline = false; showsInspector = false; isFocusMode = true
        }
    }

    func select(_ id: UUID?, extending: Bool = false) {
        guard let id else { selectedIDs = []; selectedID = nil; return }
        guard document.root.find(id) != nil else { return }
        if extending {
            if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
            selectedID = selectedIDs.contains(id) ? id : selectedIDs.first
        } else { selectedIDs = [id]; selectedID = id }
    }
    func selectAll() { selectedIDs = Set(layoutResult.frames.keys); selectedID = document.root.id }
    func request(_ action: CanvasRequest.Action) { canvasAction?(action) }

    @discardableResult private func execute(_ command: EditCommand, name: String, selection: Set<UUID>? = nil,
                                            focus: UUID? = nil, coalescingKey: String? = nil) -> Bool {
        var candidate = document
        do {
            try command.apply(to: &candidate)
            try candidate.validate()
        } catch { errorMessage = error.localizedDescription; return false }
        guard candidate != document else { return false }
        let beforeSelection = selectedIDs, beforeFocus = selectedID
        document = candidate
        if let selection { selectedIDs = selection; selectedID = focus ?? selection.first }
        refreshLayoutAndSelection()
        let now = Date()
        if let key = coalescingKey, var last = undoStack.last, last.coalescingKey == key,
           now.timeIntervalSince(last.timestamp) < 0.8,
           let merged = last.command.merged(with: command) {
            last.command = merged
            last.afterSelection = selectedIDs; last.afterFocus = selectedID; last.timestamp = now
            undoStack[undoStack.count - 1] = last
        } else {
            undoStack.append(HistoryEntry(command: command, name: name, beforeSelection: beforeSelection, beforeFocus: beforeFocus,
                                          afterSelection: selectedIDs, afterFocus: selectedID, coalescingKey: coalescingKey, timestamp: now))
            if undoStack.count > 200 { undoStack.removeFirst() }
        }
        redoStack.removeAll(); historyRevision += 1
        return true
    }
    private func refreshLayoutAndSelection() {
        layoutResult = LayoutEngine.layout(document)
        selectedIDs.formIntersection(layoutResult.frames.keys)
        if let id = selectedID, !selectedIDs.contains(id) { selectedID = selectedIDs.first }
        if selectedIDs.isEmpty { selectedID = document.root.id; selectedIDs = [document.root.id] }
    }
    func replaceFromFile(_ incoming: MindMapDocument) {
        guard incoming != document else { return }
        document = incoming; undoStack = []; redoStack = []; historyRevision += 1
        refreshLayoutAndSelection()
    }
    func undo() {
        guard let entry = undoStack.popLast() else { return }
        var candidate = document
        do { try entry.command.inverse.apply(to: &candidate); try candidate.validate() }
        catch { undoStack.append(entry); errorMessage = error.localizedDescription; return }
        document = candidate; selectedIDs = entry.beforeSelection; selectedID = entry.beforeFocus
        redoStack.append(entry); refreshLayoutAndSelection(); historyRevision += 1
    }
    func redo() {
        guard let entry = redoStack.popLast() else { return }
        var candidate = document
        do { try entry.command.apply(to: &candidate); try candidate.validate() }
        catch { redoStack.append(entry); errorMessage = error.localizedDescription; return }
        document = candidate; selectedIDs = entry.afterSelection; selectedID = entry.afterFocus
        undoStack.append(entry); refreshLayoutAndSelection(); historyRevision += 1
    }
    func updateNode(_ id: UUID, key: String? = nil, _ mutation: (inout NodeProperties) -> Void) {
        guard let node = document.root.find(id) else { return }
        let before = NodeProperties(node)
        var after = before; mutation(&after)
        guard before != after else { return }
        execute(.update(id, before: before, after: after), name: "编辑主题", coalescingKey: key.map { "\(id)-\($0)" })
    }
    func updateSelectedProperties(_ name: String, key: String? = nil, _ mutation: (inout NodeProperties) -> Void) {
        var commands: [EditCommand] = []
        for node in document.allNodes where selectedIDs.contains(node.id) {
            let before = NodeProperties(node)
            var after = before; mutation(&after)
            if before != after { commands.append(.update(node.id, before: before, after: after)) }
        }
        if !commands.isEmpty {
            let selectionKey = selectedIDs.map(\.uuidString).sorted().joined(separator: ",")
            execute(.batch(commands), name: name, coalescingKey: key.map { selectionKey + ":" + $0 })
        }
    }
    func setPageStyle<T>(_ keyPath: WritableKeyPath<NodeStyle, T?>, value: T) {
        finishEditing?()
        let previous = document.defaultNodeStyle
        var defaults = previous ?? NodeStyle()
        defaults[keyPath: keyPath] = value
        var commands: [EditCommand] = [.pageStyle(previous, defaults)]
        for node in document.allNodes {
            let before = NodeProperties(node)
            var after = before, style = before.style ?? NodeStyle()
            style[keyPath: keyPath] = value; after.style = style
            if before != after { commands.append(.update(node.id, before: before, after: after)) }
        }
        execute(.batch(commands), name: "设置全图样式", coalescingKey: "page.\(String(describing: keyPath))")
    }
    private func newNodeStyle() -> NodeStyle {
        var style = document.defaultNodeStyle ?? NodeStyle()
        if style.fontSize == nil { style.fontSize = AppPreferences.fontSize }
        if style.textAlignment == nil { style.textAlignment = .left }
        return style
    }
    func updateTitle(_ title: String, for id: UUID) { updateNode(id) { $0.title = title } }
    func addChild(to id: UUID? = nil) {
        let parentID = id ?? selectedID ?? document.root.id
        guard let parent = document.root.find(parentID) else { return }
        var child = MindMapNode(title: "新主题")
        child.style = newNodeStyle()
        var commands: [EditCommand] = []
        if parent.isCollapsed {
            var expanded = NodeProperties(parent); expanded.isCollapsed = false
            commands.append(.update(parentID, before: NodeProperties(parent), after: expanded))
        }
        commands.append(.insert(child, NodeLocation(parentID: parentID, index: parent.children.count)))
        execute(.batch(commands), name: "添加子主题", selection: [child.id], focus: child.id)
        request(.editSelection)
    }
    func addSibling(to id: UUID? = nil) {
        let id = id ?? selectedID ?? document.root.id
        guard id != document.root.id else { addChild(to: id); return }
        guard var location = document.root.location(of: id) else { return }
        location.index += 1
        var node = MindMapNode(title: "新主题")
        node.style = newNodeStyle()
        execute(.insert(node, location), name: "添加同级主题", selection: [node.id], focus: node.id)
        request(.editSelection)
    }
    private func selectionRoots(excludingRoot: Bool = false) -> [MindMapNode] {
        let selection = excludingRoot ? selectedIDs.subtracting([document.root.id]) : selectedIDs
        return document.allNodes.filter { node in
            selection.contains(node.id) && !(document.root.ancestors(of: node.id) ?? []).contains(where: { selection.contains($0) })
        }
    }
    func deleteSelected() {
        let roots = selectionRoots(excludingRoot: true)
        guard !roots.isEmpty else { return }
        var candidate = document
        var commands: [EditCommand] = []
        var nextFocus = document.root.id
        for node in roots {
            if let location = candidate.root.location(of: node.id) {
                nextFocus = location.parentID
                let command = EditCommand.remove(node, location)
                commands.append(command); try? command.apply(to: &candidate)
            }
        }
        execute(.batch(commands), name: "删除主题", selection: [nextFocus], focus: nextFocus)
    }
    func toggleCollapse(_ id: UUID? = nil) {
        guard let id = id ?? selectedID, let node = document.root.find(id), !node.children.isEmpty else { return }
        updateNode(id) { $0.isCollapsed.toggle() }
    }
    func changeLayout(_ layout: MindMapLayout) {
        execute(.layout(document.layout, layout), name: "切换布局"); request(.fit)
    }
    func changeTheme(_ theme: MapTheme) { execute(.theme(document.theme, theme), name: "切换主题") }
    func reveal(_ id: UUID) {
        var commands: [EditCommand] = []
        for ancestorID in document.root.ancestors(of: id) ?? [] {
            if let node = document.root.find(ancestorID), node.isCollapsed {
                var after = NodeProperties(node); after.isCollapsed = false
                commands.append(.update(ancestorID, before: NodeProperties(node), after: after))
            }
        }
        if !commands.isEmpty { execute(.batch(commands), name: "展开主题") }
        select(id); request(.centerSelection)
    }
    func canMoveSelection(to parentID: UUID) -> Bool {
        let roots = selectionRoots()
        return !roots.isEmpty && document.root.find(parentID) != nil
            && roots.allSatisfy { $0.id != document.root.id && $0.find(parentID) == nil }
    }
    func moveSelection(to parentID: UUID) {
        guard canMoveSelection(to: parentID) else { return }
        var commands: [EditCommand] = []
        var candidate = document
        if let parent = candidate.root.find(parentID), parent.isCollapsed {
            var after = NodeProperties(parent); after.isCollapsed = false
            let command = EditCommand.update(parentID, before: NodeProperties(parent), after: after)
            commands.append(command); try? command.apply(to: &candidate)
        }
        for node in selectionRoots() {
            guard let from = candidate.root.location(of: node.id), let parent = candidate.root.find(parentID) else { continue }
            let remainingCount = parent.children.count - (from.parentID == parentID ? 1 : 0)
            let command = EditCommand.move(node.id, from: from, to: NodeLocation(parentID: parentID, index: remainingCount))
            commands.append(command); try? command.apply(to: &candidate)
        }
        execute(.batch(commands), name: "移动主题")
    }
    func reorderSelected(by delta: Int) {
        guard let id = selectedID, let from = document.root.location(of: id), let parent = document.root.find(from.parentID) else { return }
        let index = from.index + delta
        guard parent.children.indices.contains(index) else { return }
        execute(.move(id, from: from, to: NodeLocation(parentID: from.parentID, index: index)), name: "调整主题顺序")
    }
    func navigate(dx: CGFloat, dy: CGFloat, extending: Bool = false) {
        guard let id = selectedID, let current = layoutResult.frames[id] else { select(document.root.id); return }
        let candidate = layoutResult.frames.filter { $0.key != id }.compactMap { pair -> (UUID, CGFloat)? in
            let vx = pair.value.midX - current.midX, vy = pair.value.midY - current.midY
            let along = vx * dx + vy * dy
            guard along > 1 else { return nil }
            let across = abs(vx * dy - vy * dx)
            return (pair.key, along + across * 2.5)
        }.min { $0.1 < $1.1 }
        if let candidate { select(candidate.0, extending: extending); request(.centerSelection) }
    }
    func copySelection() {
        let nodes = selectionRoots()
        guard !nodes.isEmpty, let data = try? JSONEncoder().encode(nodes) else { return }
        let board = NSPasteboard.general
        board.clearContents(); board.setData(data, forType: Self.clipboardType)
        board.setString(nodes.map { MapInterchange.markdown(for: $0, includeHeading: false) }.joined(separator: "\n"), forType: .string)
    }
    func cutSelection() { copySelection(); deleteSelected() }
    func paste() {
        do {
            let board = NSPasteboard.general
            let nodes: [MindMapNode]
            if let data = board.data(forType: Self.clipboardType) {
                guard data.count <= MapInterchange.maximumFileBytes else { throw DocumentError.oversizedFile }
                nodes = try MapInterchange.decodeClipboard(data).map { $0.cloned() }
            } else if let text = board.string(forType: .string), !text.isEmpty {
                nodes = [try MapInterchange.importMarkdown(text).root.cloned()]
            } else { return }
            let parentID = selectedID ?? document.root.id
            guard let parent = document.root.find(parentID) else { return }
            var commands: [EditCommand] = []
            if parent.isCollapsed {
                var after = NodeProperties(parent); after.isCollapsed = false
                commands.append(.update(parentID, before: NodeProperties(parent), after: after))
            }
            commands += nodes.enumerated().map { .insert($0.element, NodeLocation(parentID: parentID, index: parent.children.count + $0.offset)) }
            execute(.batch(commands), name: "粘贴主题", selection: Set(nodes.map(\.id)), focus: nodes.first?.id)
        } catch { errorMessage = error.localizedDescription }
    }
    func duplicateSelection() {
        let roots = selectionRoots(excludingRoot: true)
        var candidate = document, commands: [EditCommand] = [], ids: [UUID] = []
        for node in roots {
            guard var location = candidate.root.location(of: node.id) else { continue }
            location.index += 1
            let copy = node.cloned()
            let insertion = EditCommand.insert(copy, location)
            commands.append(insertion); ids.append(copy.id); try? insertion.apply(to: &candidate)
        }
        if !commands.isEmpty { execute(.batch(commands), name: "复制主题", selection: Set(ids), focus: ids.first) }
    }
    func replaceDocument(_ incoming: MindMapDocument, name: String) {
        execute(.replace(document, incoming), name: name, selection: [incoming.root.id], focus: incoming.root.id)
        viewport = CanvasViewport(); request(.fit)
    }
}
