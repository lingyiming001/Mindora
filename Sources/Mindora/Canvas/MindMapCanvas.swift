import AppKit
import SwiftUI

struct MindMapCanvas: NSViewRepresentable {
    @ObservedObject var model: EditorModel
    func makeNSView(context: Context) -> CanvasClipContainer { CanvasClipContainer(model: model) }
    func updateNSView(_ view: CanvasClipContainer, context: Context) { view.canvas.refresh() }
}

/// Keep the native view sized to the SwiftUI viewport, including inline editor subviews.
@MainActor final class CanvasClipContainer: NSView {
    let canvas: MindMapCanvasView
    override var wantsDefaultClipping: Bool { true }
    init(model: EditorModel) {
        canvas = MindMapCanvasView(model: model)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        canvas.autoresizingMask = [.width, .height]
        addSubview(canvas)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        canvas.frame = bounds
    }
}

@MainActor final class MindMapCanvasView: NSView, NSTextViewDelegate {
    let model: EditorModel
    override var isFlipped: Bool { true }
    override var wantsDefaultClipping: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private var inlineEditor: CanvasTextView?
    private var editingID: UUID?
    private var mouseStart = CGPoint.zero
    private var lastMouse = CGPoint.zero
    private var resizingNode: UUID?
    private var initialResizeWidth: CGFloat = 0
    private var initialResizeHeight: CGFloat = 0
    private var resizeStartY: CGFloat = 0
    private var resizeScale: CGFloat = 1
    private var resizeStartX: CGFloat = 0
    private var resizingRoot = false
    private var resizeFromLeft = false
    private var draggingNode: UUID?
    private var dragActive = false
    private var isPanning = false
    private var spaceHeld = false
    private var dropTarget: UUID?
    private var dragSession: NodeDragSession?
    private var dropProposal: NodeDropTarget?
    private let dragFeedback = DragFeedbackView()
    private var dragTimer: Timer?
    private var dragFlags: NSEvent.ModifierFlags = []
    private var pointer = CGPoint.zero
    private struct AccessibilitySnapshot: Equatable {
        let layoutRevision: Int
        let viewport: CanvasViewport
        let frame: CGRect
        let selection: Set<UUID>
        let editingID: UUID?
        let windowNumber: Int
    }
    private var accessibilitySnapshot: AccessibilitySnapshot?


    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        dragFeedback.autoresizingMask = [.width, .height]
        addSubview(dragFeedback)
        model.finishEditing = { [weak self] in self?.finishResize(commit: true); self?.endEditing(commit: true) }
        model.canvasAction = { [weak self] action in self?.handle(action) }
        setAccessibilityLabel("思维导图画布")
        setAccessibilityRole(.group)
        setAccessibilityElement(true)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refresh() {
        if let id = editingID, model.document.root.find(id) == nil { endEditing(commit: false) }
        if inlineEditor != nil { repositionEditor() }
        needsDisplay = true
        updateAccessibility()
    }
    private func handle(_ action: CanvasRequest.Action) {
        switch action {
        case .fit: model.viewport.fit(model.layoutResult.bounds, in: bounds.size)
        case .centerSelection:
            if let id = model.selectedID, let rect = model.layoutResult.frames[id] {
                model.viewport.offset = CGPoint(x: -rect.midX * model.viewport.scale, y: -rect.midY * model.viewport.scale)
            }
        case .editSelection: beginEditing(model.selectedID)
        case .focus: endEditing(commit: true); window?.makeFirstResponder(self)
        }
        repositionEditor(); needsDisplay = true
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); window?.makeFirstResponder(self)
        if window == nil { cancelDrag() }
        DispatchQueue.main.async { [weak self] in self?.updateAccessibility() }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); if inlineEditor != nil { repositionEditor() }; needsDisplay = true }
    override func layout() { super.layout(); dragFeedback.frame = bounds; repositionEditor(); updateAccessibility() }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: bounds)
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let palette = MapPalette(theme: model.document.theme, dark: dark)
        palette.canvas.setFill(); bounds.fill()
        drawGrid(palette)
        context.saveGState()
        context.translateBy(x: bounds.midX + model.viewport.offset.x, y: bounds.midY + model.viewport.offset.y)
        context.scaleBy(x: model.viewport.scale, y: model.viewport.scale)
        let topLeft = model.viewport.worldPoint(bounds.origin, in: bounds.size)
        let visible = CGRect(origin: topLeft, size: CGSize(width: bounds.width / model.viewport.scale, height: bounds.height / model.viewport.scale))
        CanvasRenderer.draw(document: model.document, layout: model.layoutResult, palette: palette,
                            visibleRect: visible, selectedIDs: model.selectedIDs, dropTarget: dropTarget, scale: model.viewport.scale, editingNodeID: editingID)
        context.restoreGState()
    }
    private func drawGrid(_ palette: MapPalette) {
        let step: CGFloat = 24 * model.viewport.scale
        guard step > 9 else { return }
        palette.grid.setFill()
        let origin = model.viewport.screenPoint(.zero, in: bounds.size)
        let xStart = origin.x.truncatingRemainder(dividingBy: step)
        let yStart = origin.y.truncatingRemainder(dividingBy: step)
        let dots = NSBezierPath()
        for x in stride(from: xStart, through: bounds.width, by: step) {
            for y in stride(from: yStart, through: bounds.height, by: step) {
                dots.appendOval(in: CGRect(x: x, y: y, width: 1.5, height: 1.5))
            }
        }
        dots.fill()
    }
    private func node(at screen: CGPoint) -> UUID? {
        guard bounds.contains(screen) else { return nil }
        let world = model.viewport.worldPoint(screen, in: bounds.size)
        return model.layoutResult.visibleNodes.reversed().first { node in
            model.layoutResult.frames[node.id]?.insetBy(dx: -6 / model.viewport.scale, dy: -4 / model.viewport.scale).contains(world) == true
        }?.id
    }
    override func mouseDown(with event: NSEvent) {
        endEditing(commit: true); window?.makeFirstResponder(self)
        let position = convert(event.locationInWindow, from: nil)
        mouseStart = position; lastMouse = position; pointer = position; dragActive = false
        draggingNode = nil; dropTarget = nil; dragSession = nil; dropProposal = nil
        isPanning = spaceHeld
        if !isPanning {
            let world = model.viewport.worldPoint(position, in: bounds.size)
            for id in model.selectedIDs {
                guard let frame = model.layoutResult.frames[id] else { continue }
                let left = id != model.document.root.id && frame.midX < (model.layoutResult.frames[model.document.root.id]?.midX ?? 0)
                if CanvasRenderer.addChildRect(frame, scale: model.viewport.scale, left: left).contains(world) {
                    if event.clickCount == 1 { model.addChild(to: id) }
                    return
                }
            }
        }
        if !isPanning, let id = node(at: position), let frame = model.layoutResult.frames[id], let item = model.document.root.find(id) {
            let world = model.viewport.worldPoint(position, in: bounds.size)
            let leftSide = id != model.document.root.id && frame.midX < (model.layoutResult.frames[model.document.root.id]?.midX ?? 0)
            if model.selectedIDs.contains(id), CanvasRenderer.resizeRect(frame, scale: model.viewport.scale, left: leftSide).insetBy(dx: -3 / model.viewport.scale, dy: -3 / model.viewport.scale).contains(world) {
                model.select(id); resizingNode = id; initialResizeWidth = frame.width; initialResizeHeight = frame.height; resizeStartY = position.y
                resizeScale = model.viewport.scale; resizeStartX = position.x; resizingRoot = id == model.document.root.id; resizeFromLeft = leftSide
                model.beginWidthResize(id); NSCursor.crosshair.set(); return
            }
            let sections = NodeContentLayout.sections(item, frame: frame, isRoot: id == model.document.root.id)
            for section in sections where section.rect.contains(world) {
                model.select(id)
                if section.deleteRect.contains(world) {
                    guard event.clickCount == 1 else { return }
                    model.updateNode(id) {
                        switch section.kind {
                        case .link: $0.link = ""
                        case .code: $0.code = ""; $0.codeLanguage = ""
                        case .attachment(let attachmentID): $0.attachments.removeAll { $0.id == attachmentID }
                        }
                    }
                } else {
                    switch section.kind {
                    case .link: if let url = NodeRichContent.webURL(item.link) { NSWorkspace.shared.open(url) }
                    case .code: model.insertContent(.code)
                    case .attachment: model.showsInspector = true; model.inspectorContentRequest = UUID()
                    }
                }
                return
            }
            if !item.children.isEmpty, CanvasRenderer.collapseRect(frame).insetBy(dx: -3, dy: -3).contains(world) {
                model.toggleCollapse(id); return
            }
            if event.clickCount == 2 { model.select(id); beginEditing(id); return }
            let extending = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift)
            if extending || !model.selectedIDs.contains(id) { model.select(id, extending: extending) }
            draggingNode = id
        } else {
            draggingNode = nil; isPanning = true
            if !spaceHeld && !event.modifierFlags.contains(.option) { model.select(nil) }
        }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        let position = convert(event.locationInWindow, from: nil); pointer = position
        if resizingNode != nil {
            let delta = (position.x - resizeStartX) / resizeScale
            model.previewSize(width: Double(initialResizeWidth + delta * (resizingRoot ? 2 : resizeFromLeft ? -1 : 1)), height: Double(initialResizeHeight + (position.y - resizeStartY) / resizeScale * 2))
            needsDisplay = true; return
        }
        if !dragActive, hypot(position.x - mouseStart.x, position.y - mouseStart.y) > 5 {
            dragActive = true
            if !isPanning {
                dragSession = model.makeDragSession()
                if dragSession != nil {
                    NSCursor.closedHand.set()
                    let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                        MainActor.assumeIsolated { self?.panDuringDrag() }
                    }
                    dragTimer = timer; RunLoop.main.add(timer, forMode: .common)
                }
            }
        }
        if isPanning {
            model.viewport.offset.x += position.x - lastMouse.x
            model.viewport.offset.y += position.y - lastMouse.y
        } else if draggingNode != nil, dragActive {
            updateDrag(at: position, flags: event.modifierFlags)
            lastMouse = position
            return
        }
        lastMouse = position; needsDisplay = true
    }
    private func updateDrag(at position: CGPoint, flags: NSEvent.ModifierFlags) {
        guard let session = dragSession, session.revision == model.historyRevision else { cancelDrag(); return }
        dragFlags = flags
        guard bounds.contains(position) else { dropProposal = nil; dragFeedback.feedback = nil; return }
        dropProposal = session.resolve(at: position, viewport: model.viewport, size: bounds.size,
            previous: dropProposal, forceChild: flags.contains(.option))
        let target = dropProposal.flatMap { proposal in session.targets.first(where: { $0.id == proposal.id }) }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        dragFeedback.feedback = DragFeedback(title: session.title, count: session.count, pointer: position,
            targetTitle: target?.title, targetFrame: target.map { model.viewport.screenRect($0.frame, in: bounds.size) },
            placement: dropProposal?.placement, vertical: session.verticalSiblings,
            palette: MapPalette(theme: model.document.theme, dark: dark))
    }
    private func panDuringDrag() {
        guard dragSession != nil, dragActive, bounds.contains(pointer) else { return }
        let inset: CGFloat = 42
        func speed(_ value: CGFloat, max extent: CGFloat) -> CGFloat {
            if value < inset { return min(12, (inset - value) * 0.3) }
            if value > extent - inset { return -min(12, (value - extent + inset) * 0.3) }
            return 0
        }
        let dx = speed(pointer.x, max: bounds.width), dy = speed(pointer.y, max: bounds.height)
        guard dx != 0 || dy != 0 else { return }
        model.viewport.offset.x += dx; model.viewport.offset.y += dy
        updateDrag(at: pointer, flags: dragFlags); needsDisplay = true
    }
    private func cancelDrag() {
        dragTimer?.invalidate(); dragTimer = nil
        dragSession = nil; dropProposal = nil; draggingNode = nil; dragActive = false; dropTarget = nil
        dragFeedback.feedback = nil; NSCursor.arrow.set()
    }
    override func flagsChanged(with event: NSEvent) {
        if dragSession != nil { updateDrag(at: pointer, flags: event.modifierFlags) }
        else { super.flagsChanged(with: event) }
    }
    private func finishResize(commit: Bool) {
        guard resizingNode != nil else { return }
        model.finishWidthResize(commit: commit)
        resizingNode = nil; draggingNode = nil; dragActive = false; dropTarget = nil
        NSCursor.arrow.set(); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if resizingNode != nil { finishResize(commit: true); updateAccessibility(); return }
        if dragActive, !isPanning, let session = dragSession, session.revision == model.historyRevision {
            updateDrag(at: convert(event.locationInWindow, from: nil), flags: event.modifierFlags)
            if let proposal = dropProposal { model.moveSelection(relativeTo: proposal) }
        }
        cancelDrag(); isPanning = false
        needsDisplay = true; updateAccessibility()
    }
    override func scrollWheel(with event: NSEvent) {
        endEditing(commit: true)
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            let anchor = convert(event.locationInWindow, from: nil)
            model.viewport.zoom(by: exp(-event.scrollingDeltaY * 0.012), at: anchor, in: bounds.size)
        } else {
            let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
            model.viewport.offset.x += event.scrollingDeltaX * factor
            model.viewport.offset.y += event.scrollingDeltaY * factor
        }
        needsDisplay = true; updateAccessibility()
    }
    override func magnify(with event: NSEvent) {
        endEditing(commit: true)
        model.viewport.zoom(by: 1 + event.magnification, at: convert(event.locationInWindow, from: nil), in: bounds.size)
        needsDisplay = true; updateAccessibility()
    }
    override func keyDown(with event: NSEvent) {
        if dragSession != nil { if event.keyCode == 53 { cancelDrag() }; return }
        if resizingNode != nil { if event.keyCode == 53 { finishResize(commit: false) }; return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 49, !flags.contains(.command) { spaceHeld = true; NSCursor.openHand.set(); return }
        if flags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a": model.selectAll()
            case "c": flags.contains(.option) ? model.insertContent(.code) : model.copySelection()
            case "x": model.cutSelection()
            case "v": model.paste()
            case "d": model.duplicateSelection()
            case "k":
                if flags.contains(.option) { model.insertContent(.link) }
                else { flags.contains(.shift) ? model.addSibling() : model.addChild() }
            case "z": flags.contains(.shift) ? model.redo() : model.undo()
            default: super.keyDown(with: event)
            }
            return
        }
        switch event.keyCode {
        case 48: model.addChild()
        case 36, 76: break // Return does not create nodes.
        case 51, 117: model.deleteSelected()
        case 123: model.navigate(dx: -1, dy: 0, extending: flags.contains(.shift))
        case 124: model.navigate(dx: 1, dy: 0, extending: flags.contains(.shift))
        case 125: model.navigate(dx: 0, dy: 1, extending: flags.contains(.shift))
        case 126: model.navigate(dx: 0, dy: -1, extending: flags.contains(.shift))
        case 53: model.select(model.document.root.id)
        case 120: beginEditing(model.selectedID)
        default:
            if let text = event.characters, !text.isEmpty, text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                beginEditing(model.selectedID, initialText: "")
                inlineEditor?.keyDown(with: event)
            } else { super.keyDown(with: event) }
        }
    }
    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { spaceHeld = false; NSCursor.arrow.set() } else { super.keyUp(with: event) }
    }
    override func resignFirstResponder() -> Bool { spaceHeld = false; return super.resignFirstResponder() }

    func beginEditing(_ id: UUID?, initialText: String? = nil) {
        guard let id, let item = model.document.root.find(id), model.layoutResult.frames[id] != nil else { return }
        if editingID == id, let inlineEditor { window?.makeFirstResponder(inlineEditor); return }
        endEditing(commit: true)
        let editor = CanvasTextView(frame: .zero)
        editor.isRichText = false; editor.importsGraphics = false; editor.allowsUndo = true
        editor.font = LayoutEngine.font(item, isRoot: id == model.document.root.id)
        editor.drawsBackground = false; editor.backgroundColor = .clear
        editor.focusRingType = .none
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = (item.style?.textAlignment ?? .center).appKit
        paragraph.lineBreakMode = .byCharWrapping
        editor.defaultParagraphStyle = paragraph
        editor.isHorizontallyResizable = false; editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = self
        editor.wantsLayer = true; editor.layer?.borderWidth = 0
        editor.layer?.backgroundColor = NSColor.clear.cgColor
        editor.string = initialText ?? item.title
        editor.alignment = (item.style?.textAlignment ?? .center).appKit
        editor.onFinish = { [weak self] commit in self?.endEditing(commit: commit) }
        editor.onResign = { [weak self, weak editor] in
            DispatchQueue.main.async {
                guard let self, let editor, self.inlineEditor === editor else { return }
                self.endEditing(commit: true, restoreFocus: false)
            }
        }
        editingID = id; inlineEditor = editor; addSubview(editor); repositionEditor(); needsDisplay = true
        window?.makeFirstResponder(editor)
        editor.setSelectedRange(initialText == nil ? NSRange(location: 0, length: (editor.string as NSString).length) : NSRange(location: (editor.string as NSString).length, length: 0))
    }
    func textDidChange(_ notification: Notification) {
        repositionEditor()
    }
    private func repositionEditor() {
        guard let editor = inlineEditor, let id = editingID, let frame = model.layoutResult.frames[id] else { return }
        guard let node = model.document.root.find(id) else { return }
        let isRoot = id == model.document.root.id
        // Use exactly the same title inset as drawing; never recenter or shift the editor.
        let titleRect = CanvasRenderer.titleTextRect(node, frame: frame, isRoot: isRoot)
        var screen = model.viewport.screenRect(titleRect, in: bounds.size)
        screen.size.width = max(1, screen.width)
        let baseFont = LayoutEngine.font(node, isRoot: isRoot)
        let font = NSFontManager.shared.convert(baseFont, toSize: max(1, baseFont.pointSize * model.viewport.scale))
        editor.font = font
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        editor.textColor = CanvasRenderer.titleTextColor(node, isRoot: isRoot, palette: MapPalette(theme: model.document.theme, dark: dark))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.alignment = (node.style?.textAlignment ?? .center).appKit
        let measured = (editor.string as NSString).boundingRect(with: CGSize(width: screen.width, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .paragraphStyle: paragraph])
        screen.size.height = max(screen.height, max(ceil(measured.height) + 2, font.ascender - font.descender + 2))
        editor.frame = screen
        updateAccessibility()
    }
    func endEditing(commit: Bool, restoreFocus: Bool = true) {
        guard let editor = inlineEditor, let id = editingID else { return }
        let value = editor.string
        inlineEditor = nil; editingID = nil; editor.onResign = nil; editor.delegate = nil; editor.removeFromSuperview()
        needsDisplay = true
        if commit { model.updateTitle(value, for: id) }
        if restoreFocus { window?.makeFirstResponder(self) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        endEditing(commit: true)
        if let id = node(at: convert(event.locationInWindow, from: nil)), !model.selectedIDs.contains(id) { model.select(id) }
        let menu = NSMenu()
        let items: [(String, Selector)] = [
            ("编辑文字    ⌘E / F2", #selector(editNode)), ("添加子主题    Tab / ⌘K", #selector(addChild)), ("添加同级主题    ⇧⌘K", #selector(addSibling)),
            ("插入网址…    ⌥⌘K", #selector(insertLink)), ("插入代码…    ⌥⌘C", #selector(insertCode)),
            ("展开 / 折叠    ⌘.", #selector(collapseNode)), ("复制    ⌘C", #selector(copyNodes)), ("粘贴为子主题    ⌘V", #selector(pasteNodes)),
            ("创建副本    ⌘D", #selector(duplicateNodes)), ("上移    ⌥⌘↑", #selector(reorderNodeUp)), ("下移    ⌥⌘↓", #selector(reorderNodeDown)), ("删除主题    Delete", #selector(deleteNodes))
        ]
        for (title, action) in items { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item) }
        return menu
    }
    @objc func copy(_ sender: Any?) { model.copySelection() }
    @objc func cut(_ sender: Any?) { model.cutSelection() }
    @objc func paste(_ sender: Any?) { model.paste() }
    override func selectAll(_ sender: Any?) { model.selectAll() }
    @objc private func insertLink() { model.insertContent(.link) }
    @objc private func insertCode() { model.insertContent(.code) }
    @objc private func editNode() { beginEditing(model.selectedID) }
    @objc private func addChild() { model.addChild() }
    @objc private func addSibling() { model.addSibling() }
    @objc private func collapseNode() { model.toggleCollapse() }
    @objc private func copyNodes() { model.copySelection() }
    @objc private func pasteNodes() { model.paste() }
    @objc private func duplicateNodes() { model.duplicateSelection() }
    @objc private func reorderNodeUp() { model.reorderSelected(by: -1) }
    @objc private func reorderNodeDown() { model.reorderSelected(by: 1) }
    @objc private func deleteNodes() { model.deleteSelected() }

    private func updateAccessibility() {
        guard let window else { return }
        let snapshot = AccessibilitySnapshot(layoutRevision: model.layoutRevision, viewport: model.viewport,
            frame: window.convertToScreen(convert(bounds, to: nil)), selection: model.selectedIDs,
            editingID: editingID, windowNumber: window.windowNumber)
        guard snapshot != accessibilitySnapshot else { return }
        accessibilitySnapshot = snapshot
        let children = model.layoutResult.visibleNodes.compactMap { node -> NSAccessibilityElement? in
            guard let world = model.layoutResult.frames[node.id] else { return nil }
            let screen = model.viewport.screenRect(world, in: bounds.size)
            guard screen.intersects(bounds) else { return nil }
            let element = CanvasAccessibilityElement()
            element.setAccessibilityRole(.button)
            element.setAccessibilityEnabled(true)
            let depth = model.layoutResult.depths[node.id] ?? 0
            element.setAccessibilityLabel("\(node.title.isEmpty ? "无标题" : node.title)，第 \(depth + 1) 层，\(node.children.count) 个子主题\(node.isCollapsed ? "，已折叠" : "")")
            element.setAccessibilityHelp("按 ⌘K 添加子主题，⇧⌘K 添加同级主题，F2 编辑。")
            element.setAccessibilityParent(self)
            element.setAccessibilityFrame(window.convertToScreen(convert(screen, to: nil)))
            element.setAccessibilityValue(model.selectedIDs.contains(node.id) ? "已选中" : "")
            element.onPress = { [weak self] in self?.model.select(node.id); self?.window?.makeFirstResponder(self) }
            return element
        }
        if let inlineEditor { setAccessibilityChildren([inlineEditor] + children) }
        else { setAccessibilityChildren(children) }
    }
}

private final class CanvasTextView: NSTextView {
    var onFinish: ((Bool) -> Void)?
    var onResign: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(false); return }
        if (event.keyCode == 36 || event.keyCode == 76), !event.modifierFlags.contains(.shift), !hasMarkedText() {
            onFinish?(true); return
        }
        super.keyDown(with: event)
    }
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onResign?() }
        return result
    }
}

private final class CanvasAccessibilityElement: NSAccessibilityElement {
    var onPress: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { onPress?(); return true }
}

private struct DragFeedback {
    let title: String
    let count: Int
    let pointer: CGPoint
    let targetTitle: String?
    let targetFrame: CGRect?
    let placement: NodeDropPlacement?
    let vertical: Bool
    let palette: MapPalette
}

/// Separate backing layer keeps pointer motion from redrawing every node, edge and grid dot.
@MainActor private final class DragFeedbackView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    var feedback: DragFeedback? { didSet { needsDisplay = true } }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; setAccessibilityElement(false) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        guard let value = feedback else { return }
        let accent = value.palette.theme.accent
        if let frame = value.targetFrame, let placement = value.placement {
            if placement == .inside {
                let shape = NSBezierPath(roundedRect: frame.insetBy(dx: -5, dy: -5), xRadius: 13, yRadius: 13)
                accent.withAlphaComponent(0.14).setFill(); shape.fill()
                accent.setStroke(); shape.lineWidth = 2.5; shape.stroke()
            } else {
                let line = NSBezierPath()
                if value.vertical {
                    let x = placement == .before ? frame.minX - 9 : frame.maxX + 9
                    line.move(to: CGPoint(x: x, y: frame.minY - 12)); line.line(to: CGPoint(x: x, y: frame.maxY + 12))
                } else {
                    let y = placement == .before ? frame.minY - 9 : frame.maxY + 9
                    line.move(to: CGPoint(x: frame.minX - 12, y: y)); line.line(to: CGPoint(x: frame.maxX + 12, y: y))
                }
                accent.setStroke(); line.lineWidth = 3; line.lineCapStyle = .round; line.stroke()
            }
        }
        let action: String
        let name = String((value.targetTitle ?? "").prefix(18))
        switch value.placement {
        case .before: action = "插入「\(name)」之前"
        case .after: action = "插入「\(name)」之后"
        case .inside: action = "移为「\(name)」的子主题"
        case nil: action = "靠近主题选择位置 · Esc 取消"
        }
        let title = String(value.title.prefix(22)) + (value.count > 1 ? " 等 \(value.count) 个主题" : "")
        let width: CGFloat = min(280, bounds.width - 16)
        let rect = CGRect(x: max(8, min(value.pointer.x + 22, bounds.width - width - 8)),
                          y: max(8, min(value.pointer.y + 22, bounds.height - 80)), width: width, height: 66)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
        shadow.shadowBlurRadius = 12; shadow.shadowOffset = CGSize(width: 0, height: -3); shadow.set()
        let card = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        value.palette.surface.setFill(); card.fill()
        NSGraphicsContext.restoreGraphicsState()
        accent.withAlphaComponent(0.45).setStroke(); card.lineWidth = 1; card.stroke()
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in: rect.insetBy(dx: 13, dy: 10), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: value.palette.text, .paragraphStyle: paragraph])
        (action as NSString).draw(in: CGRect(x: rect.minX + 13, y: rect.minY + 36, width: width - 26, height: 20),
            withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: value.placement == nil ? value.palette.secondary : accent, .paragraphStyle: paragraph])
    }
}
