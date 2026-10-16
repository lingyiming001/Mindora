import AppKit

struct CanvasRenderer {
    static func colors(for document: MindMapDocument) -> [UUID: NSColor] {
        var colors: [UUID: NSColor] = [document.root.id: document.theme.accent]
        func assign(_ node: MindMapNode, inherited: NSColor) {
            let color = node.style?.colorHex.flatMap(NSColor.init(hex:)) ?? inherited
            colors[node.id] = color
            for child in node.children { assign(child, inherited: color) }
        }
        for (index, branch) in document.root.children.enumerated() {
            assign(branch, inherited: document.theme.branchColors[index % document.theme.branchColors.count])
        }
        return colors
    }
    static func path(from a: CGRect, to b: CGRect, vertical: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        if vertical {
            let start = CGPoint(x: a.midX, y: a.maxY), end = CGPoint(x: b.midX, y: b.minY)
            path.move(to: start)
            path.curve(to: end, controlPoint1: CGPoint(x: start.x, y: (start.y + end.y) / 2),
                       controlPoint2: CGPoint(x: end.x, y: (start.y + end.y) / 2))
        } else {
            let right = b.midX > a.midX
            let start = CGPoint(x: right ? a.maxX : a.minX, y: a.midY)
            let end = CGPoint(x: right ? b.minX : b.maxX, y: b.midY)
            path.move(to: start)
            path.curve(to: end, controlPoint1: CGPoint(x: (start.x + end.x) / 2, y: start.y),
                       controlPoint2: CGPoint(x: (start.x + end.x) / 2, y: end.y))
        }
        return path
    }
    static func draw(document: MindMapDocument, layout: LayoutResult, palette: MapPalette,
                     visibleRect: CGRect? = nil, selectedIDs: Set<UUID> = [], dropTarget: UUID? = nil,
                     scale: CGFloat = 1, drawControls: Bool = true) {
        let colors = layout.colors.isEmpty ? colors(for: document) : layout.colors
        for (from, to) in layout.edges {
            guard let a = layout.frames[from], let b = layout.frames[to],
                  visibleRect == nil || a.union(b).insetBy(dx: -20, dy: -20).intersects(visibleRect!) else { continue }
            (colors[to] ?? document.theme.accent).withAlphaComponent(palette.dark ? 0.65 : 0.5).setStroke()
            let line = path(from: a, to: b, vertical: document.layout == .organization)
            line.lineWidth = 2; line.lineCapStyle = .round; line.stroke()
        }
        for node in layout.visibleNodes {
            guard let frame = layout.frames[node.id], visibleRect == nil || frame.insetBy(dx: -24, dy: -24).intersects(visibleRect!) else { continue }
            let root = node.id == document.root.id, color = colors[node.id] ?? document.theme.accent
            NSGraphicsContext.saveGraphicsState()
            let selected = selectedIDs.contains(node.id), targeted = dropTarget == node.id
            let shape = NSBezierPath(roundedRect: frame, xRadius: CGFloat(node.style?.cornerRadius ?? (root ? 15 : 11)), yRadius: CGFloat(node.style?.cornerRadius ?? (root ? 15 : 11)))
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(node.style?.shadow == false ? 0 : (palette.dark ? 0.13 : 0.045))
            shadow.shadowBlurRadius = node.style?.shadow == false ? 0 : 8; shadow.shadowOffset = NSSize(width: 0, height: -2); shadow.set()
            (node.style?.backgroundHex.flatMap(NSColor.init(hex:)) ?? (root ? color : palette.surface)).setFill(); shape.fill()
            NSGraphicsContext.restoreGraphicsState()
            (selected || targeted ? color : color.withAlphaComponent(palette.dark ? 0.5 : 0.19)).setStroke()
            shape.lineWidth = CGFloat(selected || targeted ? max(2, node.style?.borderWidth ?? 1) : node.style?.borderWidth ?? 1) / max(scale, 0.15); if shape.lineWidth > 0 { shape.stroke() }
            if selected {
                let ring = NSBezierPath(roundedRect: frame.insetBy(dx: -4 / scale, dy: -4 / scale), xRadius: 15, yRadius: 15)
                color.withAlphaComponent(0.16).setStroke(); ring.lineWidth = 3 / scale; ring.stroke()
            }
            let font = LayoutEngine.font(node, isRoot: root)
            let textColor: NSColor = node.style?.textColorHex.flatMap(NSColor.init(hex:)) ?? (root ? .white : palette.text)
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = (node.style?.textAlignment ?? .center).appKit; paragraph.lineBreakMode = .byCharWrapping
            let hasMetadata = node.priority > 0 || node.progress != nil || !node.tags.isEmpty || !node.note.isEmpty 
            let textRect = CGRect(x: frame.minX + 17, y: frame.minY + 12, width: frame.width - 34, height: LayoutEngine.titleSize(node, isRoot: root).height - 24 - (hasMetadata ? 19 : 0))
            ((node.title.isEmpty ? "无标题" : node.title) as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph])
            if hasMetadata {
                var labels: [String] = []
                if node.priority > 0 { labels.append("P\(node.priority)") }
                if let progress = node.progress { labels.append("\(progress)%") }
                if !node.tags.isEmpty { labels.append("#" + node.tags.prefix(2).joined(separator: " #")) }
                if !node.note.isEmpty { labels.append("备注") }
                (labels.joined(separator: "  ·  ") as NSString).draw(in: CGRect(x: frame.minX + 14, y: frame.minY + LayoutEngine.titleSize(node, isRoot: root).height - 24, width: frame.width - 28, height: 16), withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: root ? textColor.withAlphaComponent(0.8) : palette.secondary, .paragraphStyle: paragraph])
            }
            NodeContentLayout.draw(node, frame: frame, isRoot: root, palette: palette, controls: drawControls)
            if drawControls, selected {
                let add = addChildRect(frame, scale: scale, left: !root && frame.midX < (layout.frames[document.root.id]?.midX ?? 0))
                palette.surface.setFill(); NSBezierPath(ovalIn: add).fill()
                color.setStroke(); let outline = NSBezierPath(ovalIn: add); outline.lineWidth = 1 / scale; outline.stroke()
                let plus = NSBezierPath()
                plus.move(to: CGPoint(x: add.midX, y: add.minY + add.height * 0.25)); plus.line(to: CGPoint(x: add.midX, y: add.maxY - add.height * 0.25))
                plus.move(to: CGPoint(x: add.minX + add.width * 0.25, y: add.midY)); plus.line(to: CGPoint(x: add.maxX - add.width * 0.25, y: add.midY))
                plus.lineWidth = 1.2 / scale; plus.stroke()

                let grip = resizeRect(frame, scale: scale, left: !root && frame.midX < (layout.frames[document.root.id]?.midX ?? 0))
                palette.surface.setFill(); NSBezierPath(roundedRect: grip, xRadius: 3 / scale, yRadius: 3 / scale).fill()
                color.setStroke(); let border = NSBezierPath(roundedRect: grip, xRadius: 3 / scale, yRadius: 3 / scale)
                border.lineWidth = 1 / scale; border.stroke()
                let mark = NSBezierPath()
                mark.move(to: CGPoint(x: grip.minX + grip.width * 0.3, y: grip.maxY - grip.height * 0.3))
                mark.line(to: CGPoint(x: grip.maxX - grip.width * 0.3, y: grip.minY + grip.height * 0.3))
                mark.lineWidth = 1 / scale; mark.stroke()
            }
            if drawControls, !node.children.isEmpty {
                let badge = collapseRect(frame)
                palette.surface.setFill(); NSBezierPath(ovalIn: badge).fill()
                color.withAlphaComponent(0.55).setStroke(); let border = NSBezierPath(ovalIn: badge); border.lineWidth = 1 / scale; border.stroke()
                let mark = NSBezierPath(); mark.move(to: CGPoint(x: badge.minX + 4, y: badge.midY)); mark.line(to: CGPoint(x: badge.maxX - 4, y: badge.midY))
                if node.isCollapsed { mark.move(to: CGPoint(x: badge.midX, y: badge.minY + 4)); mark.line(to: CGPoint(x: badge.midX, y: badge.maxY - 4)) }
                color.setStroke(); mark.lineWidth = 1.3; mark.stroke()
            }
        }
    }
    static func addChildRect(_ frame: CGRect, scale: CGFloat, left: Bool) -> CGRect {
        let scale = max(scale, 0.15), size = 18 / max(scale, 0.15)
        return CGRect(x: left ? frame.minX - 30 / scale : frame.maxX + 12 / scale, y: frame.midY - size / 2, width: size, height: size)
    }
    static func resizeRect(_ frame: CGRect, scale: CGFloat, left: Bool = false) -> CGRect {
        let size = 14 / max(scale, 0.15)
        return CGRect(x: left ? frame.minX : frame.maxX - size, y: frame.maxY - size, width: size, height: size)
    }
    static func collapseRect(_ frame: CGRect) -> CGRect { CGRect(x: frame.maxX - 7, y: frame.midY - 7, width: 14, height: 14) }
}
