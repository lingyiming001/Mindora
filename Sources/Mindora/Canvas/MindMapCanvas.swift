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
    private var pointer = CGPoint.zero

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        model.finishEditing = { [weak self] in self?.finishResize(commit: true); self?.endEditing(commit: true) }
        model.canvasAction = { [weak self] action in self?.handle(action) }
        setAccessibilityLabel("思维导图画布")
        setAccessibilityRole(.group)
        setAccessibilityElement(true)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refresh() {
        if let id = editingID, model.document.root.find(id) == nil { endEditing(commit: false) }
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
        DispatchQueue.main.async { [weak self] in self?.updateAccessibility() }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func layout() { super.layout(); repositionEditor(); updateAccessibility() }

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
                            visibleRect: visible, selectedIDs: model.selectedIDs, dropTarget: dropTarget, scale: model.viewport.scale)
        context.restoreGState()
        if dragActive, !isPanning {
            let label = dropTarget == nil ? "拖到其他主题上，移动分支" : "松开以移入该主题"
            let width = min(196.0, max(0, bounds.width - 16))
            let rect = CGRect(x: min(max(8, pointer.x + 15), max(8, bounds.width - width - 8)),
                              y: min(max(8, pointer.y + 15), max(8, bounds.height - 38)),
                              width: width, height: 30)
            palette.surface.setFill(); NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            (label as NSString).draw(at: CGPoint(x: rect.minX + 10, y: rect.minY + 7), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: palette.text])
        }
    }
    private func drawGrid(_ palette: MapPalette) {
        let step: CGFloat = 24 * model.viewport.scale
        guard step > 9 else { return }
        palette.grid.setFill()
        let origin = model.viewport.screenPoint(.zero, in: bounds.size)
        let xStart = origin.x.truncatingRemainder(dividingBy: step)
        let yStart = origin.y.truncatingRemainder(dividingBy: step)
        for x in stride(from: xStart, through: bounds.width, by: step) {
            for y in stride(from: yStart, through: bounds.height, by: step) {
                NSBezierPath(ovalIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)).fill()
            }
        }
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
        draggingNode = nil; dropTarget = nil
        isPanning = spaceHeld || event.modifierFlags.contains(.option)
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
        if hypot(position.x - mouseStart.x, position.y - mouseStart.y) > 5 { dragActive = true }
        if isPanning {
            model.viewport.offset.x += position.x - lastMouse.x
            model.viewport.offset.y += position.y - lastMouse.y
        } else if draggingNode != nil, dragActive {
            let target = node(at: position)
            dropTarget = target.flatMap { model.canMoveSelection(to: $0) ? $0 : nil }
        }
        lastMouse = position; needsDisplay = true
    }
    private func finishResize(commit: Bool) {
        guard resizingNode != nil else { return }
        model.finishWidthResize(commit: commit)
        resizingNode = nil; draggingNode = nil; dragActive = false; dropTarget = nil
        NSCursor.arrow.set(); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if resizingNode != nil { finishResize(commit: true); updateAccessibility(); return }
        let position = convert(event.locationInWindow, from: nil)
        if dragActive, !isPanning, let target = node(at: position), model.canMoveSelection(to: target) {
            model.moveSelection(to: target)
        }
        draggingNode = nil; dragActive = false; isPanning = false; dropTarget = nil
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
        endEditing(commit: true)
        let editor = CanvasTextView(frame: .zero)
        editor.isRichText = false; editor.importsGraphics = false; editor.allowsUndo = true
        editor.font = LayoutEngine.font(item, isRoot: id == model.document.root.id); editor.textColor = .labelColor; editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 10, height: 9)
        editor.isHorizontallyResizable = false; editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = self
        editor.wantsLayer = true; editor.layer?.cornerRadius = 10; editor.layer?.borderWidth = 2
        editor.layer?.borderColor = model.document.theme.accent.cgColor
        editor.string = initialText ?? item.title
        editor.alignment = (item.style?.textAlignment ?? .center).appKit
        editor.onFinish = { [weak self] commit in self?.endEditing(commit: commit) }
        editor.onResign = { [weak self, weak editor] in
            DispatchQueue.main.async {
                guard let self, let editor, self.inlineEditor === editor else { return }
                self.endEditing(commit: true, restoreFocus: false)
            }
        }
        editingID = id; inlineEditor = editor; addSubview(editor); repositionEditor()
        window?.makeFirstResponder(editor)
        editor.setSelectedRange(initialText == nil ? NSRange(location: 0, length: (editor.string as NSString).length) : NSRange(location: (editor.string as NSString).length, length: 0))
    }
    func textDidChange(_ notification: Notification) {
        repositionEditor()
    }
    private func repositionEditor() {
        guard let editor = inlineEditor, let id = editingID, let frame = model.layoutResult.frames[id] else { return }
        var titleFrame = frame
        if let node = model.document.root.find(id) { titleFrame.size.height = LayoutEngine.titleSize(node, isRoot: id == model.document.root.id).height }
        var screen = model.viewport.screenRect(titleFrame, in: bounds.size)
        screen.size.width = max(screen.width, 160)
        if let node = model.document.root.find(id) {
            let baseFont = LayoutEngine.font(node, isRoot: id == model.document.root.id)
            editor.font = NSFontManager.shared.convert(baseFont, toSize: max(4, baseFont.pointSize * model.viewport.scale))
        }
        if let font = editor.font {
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byCharWrapping
            let measured = (editor.string as NSString).boundingRect(with: CGSize(width: max(1, screen.width - 20), height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .paragraphStyle: paragraph])
            screen.size.height = max(64, ceil(measured.height) + 24)
        }
        screen.origin.x = min(max(8, screen.origin.x), max(8, bounds.width - screen.width - 8))
        screen.origin.y = min(max(8, screen.origin.y), max(8, bounds.height - screen.height - 8))
        editor.frame = screen
        updateAccessibility()
    }
    func endEditing(commit: Bool, restoreFocus: Bool = true) {
        guard let editor = inlineEditor, let id = editingID else { return }
        let value = editor.string
        inlineEditor = nil; editingID = nil; editor.onResign = nil; editor.removeFromSuperview()
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
