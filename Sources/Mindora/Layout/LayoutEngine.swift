import AppKit

struct LayoutResult {
    var frames: [UUID: CGRect]
    var edges: [(UUID, UUID)]
    var bounds: CGRect
    var visibleNodes: [MindMapNode]
    var colors: [UUID: NSColor] = [:]
    var depths: [UUID: Int] = [:]
}

enum LayoutEngine {
    private static let titleCache: NSCache<NSString, NSValue> = {
        let cache = NSCache<NSString, NSValue>(); cache.countLimit = 4096; cache.totalCostLimit = 4 * 1024 * 1024; return cache
    }()
    static func font(_ node: MindMapNode, isRoot: Bool) -> NSFont {
        var font = NSFont.systemFont(ofSize: CGFloat(node.style?.fontSize ?? (isRoot ? 17 : 14)),
                                     weight: node.style?.bold == true ? .bold : (isRoot ? .semibold : .medium))
        if node.style?.italic == true { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }
    static let levelGap: CGFloat = 76
    static let siblingGap: CGFloat = 22

    static func titleSize(_ node: MindMapNode, isRoot: Bool) -> CGSize {
        let key = "\(node.id)|\(isRoot)|\(node.style?.fontSize ?? 0)|\(node.style?.bold ?? false)|\(node.style?.italic ?? false)|\(node.hasRichContent)|\(node.style?.width ?? 0)|\(node.priority > 0 || node.progress != nil || !node.tags.isEmpty || !node.note.isEmpty)|\(node.title)" as NSString
        if let cached = titleCache.object(forKey: key) { return cached.sizeValue }
        let font = Self.font(node, isRoot: isRoot)
        let text = node.title.isEmpty ? "无标题" : node.title
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byCharWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        // Respect explicit source line breaks; only soft-wrap very long lines.
        let longestLine = text.components(separatedBy: "\n").map {
            ($0 as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        let automatic = min(720, max(node.hasRichContent ? 310 : (isRoot ? 150 : 126), ceil(longestLine) + 36))
        let width = node.style?.width.map { CGFloat($0) } ?? automatic
        let rect = (text as NSString).boundingRect(with: CGSize(width: width - 34, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
        let hasMetadata = node.priority > 0 || node.progress != nil || !node.tags.isEmpty || !node.note.isEmpty
        let size = CGSize(width: width, height: max(isRoot ? 54 : 44, ceil(rect.height) + 28 + (hasMetadata ? 19 : 0)))
        titleCache.setObject(NSValue(size: size), forKey: key, cost: key.length * 2 + 64)
        return size
    }
    static func measure(_ node: MindMapNode, isRoot: Bool) -> CGSize {
        let title = titleSize(node, isRoot: isRoot)
        return CGSize(width: title.width, height: max(CGFloat(node.style?.height ?? 0), title.height + NodeContentLayout.height(node, width: title.width)))
    }
    static func layout(_ document: MindMapDocument) -> LayoutResult {
        let root = document.root, visibleNodes = root.flattened(visibleOnly: true)
        let sizes = Dictionary(uniqueKeysWithValues: visibleNodes.map { ($0.id, measure($0, isRoot: $0.id == root.id)) })
        var weights: [UUID: CGFloat] = [:], frames: [UUID: CGRect] = [:], edges: [(UUID, UUID)] = []
        let vertical = document.layout == .organization
        func calculateWeight(_ node: MindMapNode) -> CGFloat {
            let own = vertical ? sizes[node.id]!.width : sizes[node.id]!.height
            guard !node.isCollapsed, !node.children.isEmpty else { weights[node.id] = own; return own }
            let span = node.children.reduce(CGFloat.zero) { $0 + calculateWeight($1) } + siblingGap * CGFloat(node.children.count - 1)
            weights[node.id] = max(own, span)
            return weights[node.id]!
        }
        _ = calculateWeight(root)
        let rootSize = sizes[root.id]!
        frames[root.id] = CGRect(x: -rootSize.width / 2, y: -rootSize.height / 2, width: rootSize.width, height: rootSize.height)

        func place(_ node: MindMapNode, origin: CGPoint, direction: CGFloat) {
            let size = sizes[node.id]!
            let frame = CGRect(origin: origin, size: size)
            frames[node.id] = frame
            guard !node.isCollapsed, !node.children.isEmpty else { return }
            let total = node.children.reduce(CGFloat.zero) { $0 + weights[$1.id]! } + siblingGap * CGFloat(node.children.count - 1)
            var cursor = (vertical ? frame.midX : frame.midY) - total / 2
            for child in node.children {
                let childSize = sizes[child.id]!, weight = weights[child.id]!
                let position: CGPoint
                if vertical {
                    position = CGPoint(x: cursor + (weight - childSize.width) / 2, y: frame.maxY + levelGap)
                } else {
                    position = CGPoint(x: direction > 0 ? frame.maxX + levelGap : frame.minX - levelGap - childSize.width,
                                       y: cursor + (weight - childSize.height) / 2)
                }
                place(child, origin: position, direction: direction)
                edges.append((node.id, child.id)); cursor += weight + siblingGap
            }
        }
        if vertical { place(root, origin: frames[root.id]!.origin, direction: 1) }
        else {
            var right: [MindMapNode] = [], left: [MindMapNode] = []
            var rightWeight: CGFloat = 0, leftWeight: CGFloat = 0
            for child in root.isCollapsed ? [] : root.children {
                if document.layout == .leftTree || (document.layout == .balanced && leftWeight < rightWeight) {
                    left.append(child); leftWeight += weights[child.id]! + siblingGap
                } else { right.append(child); rightWeight += weights[child.id]! + siblingGap }
            }
            for (children, direction) in [(right, CGFloat(1)), (left, CGFloat(-1))] {
                let total = children.reduce(CGFloat.zero) { $0 + weights[$1.id]! } + siblingGap * CGFloat(max(0, children.count - 1))
                var cursor = -total / 2
                for child in children {
                    let size = sizes[child.id]!, weight = weights[child.id]!
                    let x = direction > 0 ? rootSize.width / 2 + levelGap : -rootSize.width / 2 - levelGap - size.width
                    place(child, origin: CGPoint(x: x, y: cursor + (weight - size.height) / 2), direction: direction)
                    edges.append((root.id, child.id)); cursor += weight + siblingGap
                }
            }
        }
        var depths: [UUID: Int] = [:]
        func indexDepth(_ node: MindMapNode, depth: Int) {
            depths[node.id] = depth
            for child in node.children { indexDepth(child, depth: depth + 1) }
        }
        indexDepth(root, depth: 0)
        return LayoutResult(frames: frames, edges: edges, bounds: frames.values.reduce(CGRect.null) { $0.union($1) }, visibleNodes: visibleNodes, colors: CanvasRenderer.colors(for: document), depths: depths)
    }
}


extension NodeTextAlignment {
    var appKit: NSTextAlignment {
        switch self { case .left: .left; case .center: .center; case .right: .right }
    }
}
