import AppKit
import UniformTypeIdentifiers
import ImageIO

/// Shared geometry for measurement, drawing and click handling.
enum NodeContentLayout {
    enum Kind { case link, code, attachment(UUID) }
    struct Section {
        let kind: Kind
        let rect: CGRect
        var deleteRect: CGRect { CGRect(x: rect.maxX - 25, y: rect.minY + 5, width: 20, height: 20) }
    }
    static func isImage(_ attachment: NodeAttachment) -> Bool {
        UTType(attachment.typeIdentifier)?.conforms(to: .image) == true
    }
    static func sectionLabel(_ kind: Kind, node: MindMapNode) -> String {
        switch kind {
        case .link: "↗ " + node.link
        case .code: (node.codeLanguage.isEmpty ? "代码" : node.codeLanguage) + " · \(node.code.components(separatedBy: "\n").count) 行"
        case .attachment(let id): node.attachments.first(where: { $0.id == id })?.name ?? ""
        }
    }
    private static let textCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>(); cache.countLimit = 2048; cache.totalCostLimit = 4 * 1024 * 1024; return cache
    }()
    static func textHeight(_ value: String, width: CGFloat, mono: Bool = false) -> CGFloat {
        let key = "\(width)|\(mono)|\(value)" as NSString
        if let cached = textCache.object(forKey: key) { return CGFloat(cached.doubleValue) }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byCharWrapping
        let font = mono ? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular) : NSFont.systemFont(ofSize: 11, weight: .medium)
        let rect = (value as NSString).boundingRect(with: CGSize(width: max(1, width), height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .paragraphStyle: paragraph])
        let height = max(18, ceil(rect.height) + 2)
        textCache.setObject(NSNumber(value: Double(height)), forKey: key, cost: key.length * 2 + 64)
        return height
    }
    static func sectionHeight(_ kind: Kind, node: MindMapNode, width: CGFloat) -> CGFloat {
        let header = textHeight(sectionLabel(kind, node: node), width: width - 62)
        switch kind {
        case .link: return header + 22
        case .code: return header + 28 + textHeight(node.code, width: width - 38, mono: true)
        case .attachment(let id):
            return header + 22 + (node.attachments.first(where: { $0.id == id }).map(isImage) == true ? 120 : 0)
        }
    }
    static func kinds(_ node: MindMapNode) -> [Kind] {
        var result: [Kind] = []
        if !node.link.isEmpty { result.append(.link) }
        if !node.code.isEmpty { result.append(.code) }
        return result + node.attachments.map { .attachment($0.id) }
    }
    static func height(_ node: MindMapNode, width: CGFloat) -> CGFloat {
        let sections = kinds(node)
        return sections.isEmpty ? 0 : sections.reduce(8) { $0 + sectionHeight($1, node: node, width: width) }
    }
    static func sections(_ node: MindMapNode, frame: CGRect, isRoot: Bool) -> [Section] {
        var y = frame.minY + LayoutEngine.titleSize(node, isRoot: isRoot).height
        return kinds(node).map { kind in
            let height = sectionHeight(kind, node: node, width: frame.width)
            defer { y += height }
            return Section(kind: kind, rect: CGRect(x: frame.minX + 10, y: y, width: frame.width - 20, height: height - 6))
        }
    }
    private static let images: NSCache<NSUUID, NSImage> = {
        let cache = NSCache<NSUUID, NSImage>(); cache.totalCostLimit = 24 * 1024 * 1024; cache.countLimit = 64; return cache
    }()
    static func thumbnail(_ item: NodeAttachment) -> NSImage? {
        if let cached = images.object(forKey: item.id as NSUUID) { return cached }
        guard let source = CGImageSourceCreateWithData(item.data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 512, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: CGSize(width: CGFloat(cg.width), height: CGFloat(cg.height)))
        images.setObject(image, forKey: item.id as NSUUID, cost: cg.width * cg.height * 4)
        return image
    }
    static func draw(_ node: MindMapNode, frame: CGRect, isRoot: Bool, palette: MapPalette, controls: Bool) {
        for section in sections(node, frame: frame, isRoot: isRoot) {
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSBezierPath(roundedRect: section.rect, xRadius: 7, yRadius: 7).addClip()
            palette.surface.setFill(); section.rect.fill()
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byCharWrapping
            let header = CGRect(x: section.rect.minX + 9, y: section.rect.minY + 7, width: section.rect.width - 42, height: textHeight(sectionLabel(section.kind, node: node), width: section.rect.width - 42))
            var label = ""
            switch section.kind {
            case .link:
                label = "↗ " + node.link
            case .code:
                label = (node.codeLanguage.isEmpty ? "代码" : node.codeLanguage) + " · \(node.code.components(separatedBy: "\n").count) 行"
                let code = node.code
                (code as NSString).draw(with: CGRect(x: header.minX, y: header.maxY + 6, width: section.rect.width - 18, height: section.rect.maxY - header.maxY - 10), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: palette.text, .paragraphStyle: paragraph])
            case .attachment(let id):
                guard let item = node.attachments.first(where: { $0.id == id }) else { continue }
                label = item.name
                if isImage(item), let image = thumbnail(item) {
                    let area = CGRect(x: section.rect.minX + 8, y: header.maxY + 6, width: section.rect.width - 16, height: section.rect.maxY - header.maxY - 12)
                    let scale = min(area.width / image.size.width, area.height / image.size.height)
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    image.draw(in: CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
            }
            (label as NSString).draw(with: header, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: palette.text, .paragraphStyle: paragraph])
            if controls {
                palette.secondary.withAlphaComponent(0.12).setFill()
                NSBezierPath(ovalIn: section.deleteRect).fill()
                ("×" as NSString).draw(in: section.deleteRect.offsetBy(dx: 5, dy: 0), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: palette.text])
            }
        }
    }
}

extension NodeContentLayout {
    static func svg(_ node: MindMapNode, frame: CGRect, isRoot: Bool) -> String {
        var output = ""
        func n(_ value: CGFloat) -> String { String(format: "%.2f", value) }
        func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, mono: Bool = false) -> String {
            let font = mono ? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular) : NSFont.systemFont(ofSize: 11, weight: .medium)
            var lines: [String] = [], line = "", used: CGFloat = 0
            for character in value {
                if character == "\n" { lines.append(line); line = ""; used = 0; continue }
                let w = (String(character) as NSString).size(withAttributes: [.font: font]).width
                if used + w > width - 2, !line.isEmpty { lines.append(line); line = ""; used = 0 }
                line.append(character); used += w
            }
            lines.append(line)
            let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
            return lines.enumerated().map { index, line in
                "<text x=\"\(n(x))\" y=\"\(n(y + CGFloat(index) * lineHeight))\" font-size=\"11\" font-family=\"\(mono ? "monospace" : "sans-serif")\" xml:space=\"preserve\" fill=\"#303444\">\(MapInterchange.xmlEscape(line))</text>\n"
            }.joined()
        }
        for (index, section) in sections(node, frame: frame, isRoot: isRoot).enumerated() {
            let rect = section.rect
            let clip = "content-\(node.id.uuidString)-\(index)"
            output += "<defs><clipPath id=\"\(clip)\"><rect x=\"\(n(rect.minX))\" y=\"\(n(rect.minY))\" width=\"\(n(rect.width))\" height=\"\(n(rect.height))\" rx=\"7\"/></clipPath></defs><g clip-path=\"url(#\(clip))\">"
            output += "<rect x=\"\(n(rect.minX))\" y=\"\(n(rect.minY))\" width=\"\(n(rect.width))\" height=\"\(n(rect.height))\" fill=\"#FFFFFF\"/>"
            switch section.kind {
            case .link: output += text("↗ " + node.link, x: rect.minX + 9, y: rect.minY + 20, width: rect.width - 42)
            case .code:
                let label = sectionLabel(.code, node: node)
                let headerHeight = textHeight(label, width: rect.width - 42)
                output += text(label, x: rect.minX + 9, y: rect.minY + 20, width: rect.width - 42)
                output += text(node.code, x: rect.minX + 9, y: rect.minY + headerHeight + 26, width: rect.width - 18, mono: true)
            case .attachment(let id):
                if let item = node.attachments.first(where: { $0.id == id }) {
                    let headerHeight = textHeight(item.name, width: rect.width - 42)
                    output += text(item.name, x: rect.minX + 9, y: rect.minY + 20, width: rect.width - 42)
                    if isImage(item), let image = thumbnail(item), let tiff = image.tiffRepresentation,
                       let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                        output += "<image x=\"\(n(rect.minX + 8))\" y=\"\(n(rect.minY + headerHeight + 13))\" width=\"\(n(rect.width - 16))\" height=\"\(n(rect.height - headerHeight - 19))\" preserveAspectRatio=\"xMidYMid meet\" href=\"data:image/png;base64,\(png.base64EncodedString())\"/>"
                    }
                }
            }
            output += "</g>\n"
        }
        return output
    }
}
