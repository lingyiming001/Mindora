import AppKit
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case markdown, opml, json, svg, png, jpeg, pdf
    var id: String { rawValue }
    var label: String {
        switch self {
        case .markdown: "Markdown 大纲"
        case .opml: "OPML 大纲"
        case .json: "JSON 文档"
        case .svg: "SVG 矢量图"
        case .png: "PNG 图片"
        case .jpeg: "JPEG 图片"
        case .pdf: "PDF 文档"
        }
    }
    var fileExtension: String { self == .markdown ? "md" : self == .jpeg ? "jpg" : rawValue }
    var type: UTType {
        switch self {
        case .markdown: .plainText
        case .opml: .xml
        case .json: .json
        case .svg: .svg
        case .png: .png
        case .jpeg: .jpeg
        case .pdf: .pdf
        }
    }
}

@MainActor enum ImportExportService {
    static func importFile(into model: EditorModel) {
        let panel = NSOpenPanel()
        panel.title = "导入思维导图"
        panel.message = "支持 Markdown、OPML 和 Mindora JSON。导入会替换当前内容，可通过撤销恢复。"
        panel.allowedContentTypes = [.plainText, .xml, .json, .mindora, UTType(filenameExtension: "opml", conformingTo: .xml)!]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { model.replaceDocument(try MapInterchange.read(url), name: "导入文件") }
        catch { model.errorMessage = error.localizedDescription }
    }
    static func export(_ document: MindMapDocument, format: ExportFormat, model: EditorModel) {
        let panel = NSSavePanel()
        panel.title = "导出\(format.label)"
        // Use filename-based UTTypes so Markdown and OPML retain their expected suffix.
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? format.type]
        panel.nameFieldStringValue = safeFilename(document.root.title) + "." + format.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try exportData(document, format: format).write(to: url, options: .atomic) }
        catch { model.errorMessage = error.localizedDescription }
    }
    static func safeFilename(_ title: String) -> String {
        let value = title.components(separatedBy: CharacterSet(charactersIn: "/:\n\r")).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? "Mindora" : String(value.prefix(80))
    }
    static func exportData(_ document: MindMapDocument, format: ExportFormat) throws -> Data {
        try document.validate()
        switch format {
        case .markdown: return Data(MapInterchange.markdown(for: document.root).utf8)
        case .opml: return Data(MapInterchange.opml(document).utf8)
        case .json: return try MapInterchange.encodeJSON(document)
        case .svg: return Data(svg(document).utf8)
        case .png, .jpeg: return try image(document, jpeg: format == .jpeg)
        case .pdf: return try pdf(document)
        }
    }
    private static func image(_ document: MindMapDocument, jpeg: Bool) throws -> Data {
        let layout = LayoutEngine.layout(document), padded = layout.bounds.insetBy(dx: -48, dy: -48)
        let scale: CGFloat = 2
        guard padded.width * scale <= 16_000, padded.height * scale <= 16_000,
              padded.width * padded.height * scale * scale <= 40_000_000 else {
            throw DocumentError.invalidImport("图片尺寸过大，请使用 SVG 或 PDF 导出。")
        }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(padded.width * scale)), pixelsHigh: Int(ceil(padded.height * scale)), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw CocoaError(.fileWriteUnknown) }
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: graphics.cgContext, flipped: true)
        let context = graphics.cgContext
        context.translateBy(x: 0, y: CGFloat(bitmap.pixelsHigh)); context.scaleBy(x: scale, y: -scale)
        context.setFillColor(MapPalette(theme: document.theme, dark: false).canvas.cgColor)
        context.fill(CGRect(origin: .zero, size: padded.size)); context.translateBy(x: -padded.minX, y: -padded.minY)
        CanvasRenderer.draw(document: document, layout: layout, palette: MapPalette(theme: document.theme, dark: false), drawControls: false)
        guard let data = bitmap.representation(using: jpeg ? .jpeg : .png, properties: jpeg ? [.compressionFactor: 0.9] : [:]) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
    private static func pdf(_ document: MindMapDocument) throws -> Data {
        let layout = LayoutEngine.layout(document), padded = layout.bounds.insetBy(dx: -48, dy: -48)
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: padded.size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        context.beginPDFPage(nil)
        context.translateBy(x: 0, y: box.height); context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -padded.minX, y: -padded.minY)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        CanvasRenderer.draw(document: document, layout: layout, palette: MapPalette(theme: document.theme, dark: false), drawControls: false)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage(); context.closePDF()
        return data as Data
    }
    private static func svg(_ document: MindMapDocument) -> String {
        let layout = LayoutEngine.layout(document), padded = layout.bounds.insetBy(dx: -48, dy: -48)
        let colors = CanvasRenderer.colors(for: document)
        func color(_ id: UUID) -> String {
            guard let rgb = colors[id]?.usingColorSpace(.sRGB) else { return "#6264D9" }
            return String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
        }
        func n(_ value: CGFloat) -> String { String(format: "%.2f", value) }
        var result = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(n(padded.width))\" height=\"\(n(padded.height))\" viewBox=\"\(n(padded.minX)) \(n(padded.minY)) \(n(padded.width)) \(n(padded.height))\">\n"
        result += "<rect x=\"\(n(padded.minX))\" y=\"\(n(padded.minY))\" width=\"\(n(padded.width))\" height=\"\(n(padded.height))\" fill=\"#F7F8FC\"/>\n"
        result += #"<defs><filter id="node-shadow" x="-30%" y="-50%" width="160%" height="220%"><feDropShadow dx="0" dy="2" stdDeviation="3" flood-opacity="0.08"/></filter></defs>"#
        for (from, to) in layout.edges {
            let a = layout.frames[from]!, b = layout.frames[to]!
            let start: CGPoint, end: CGPoint, c1: CGPoint, c2: CGPoint
            if document.layout == .organization {
                start = CGPoint(x: a.midX, y: a.maxY); end = CGPoint(x: b.midX, y: b.minY)
                c1 = CGPoint(x: start.x, y: (start.y + end.y) / 2); c2 = CGPoint(x: end.x, y: c1.y)
            } else {
                let right = b.midX > a.midX
                start = CGPoint(x: right ? a.maxX : a.minX, y: a.midY); end = CGPoint(x: right ? b.minX : b.maxX, y: b.midY)
                c1 = CGPoint(x: (start.x + end.x) / 2, y: start.y); c2 = CGPoint(x: c1.x, y: end.y)
            }
            result += "<path d=\"M \(n(start.x)) \(n(start.y)) C \(n(c1.x)) \(n(c1.y)), \(n(c2.x)) \(n(c2.y)), \(n(end.x)) \(n(end.y))\" fill=\"none\" stroke=\"\(color(to))\" stroke-opacity=\"0.6\" stroke-width=\"2\"/>\n"
        }
        for node in layout.visibleNodes {
            let frame = layout.frames[node.id]!, root = node.id == document.root.id
            let fill = node.style?.backgroundHex.map { "#" + $0 } ?? (root ? color(node.id) : "#FFFFFF")
            let textColor = node.style?.textColorHex.map { "#" + $0 } ?? (root ? "#FFFFFF" : "#303444")
            let radius = CGFloat(node.style?.cornerRadius ?? (root ? 15 : 11))
            let border = CGFloat(node.style?.borderWidth ?? 1)
            let shadowAttribute = node.style?.shadow == false ? "" : #" filter="url(#node-shadow)""#
            result += "<rect x=\"\(n(frame.minX))\" y=\"\(n(frame.minY))\" width=\"\(n(frame.width))\" height=\"\(n(frame.height))\" rx=\"\(n(radius))\" fill=\"\(fill)\" stroke=\"\(color(node.id))\" stroke-width=\"\(n(border))\"\(shadowAttribute)/>\n"
            let fontSize = CGFloat(node.style?.fontSize ?? (root ? 17 : 14))
            let title = node.title.isEmpty ? "无标题" : node.title
            let lines = wrappedLines(title, width: frame.width - 34, font: LayoutEngine.font(node, isRoot: root))
            let alignment = node.style?.textAlignment ?? .center
            let anchor = alignment == .left ? "start" : alignment == .right ? "end" : "middle"
            let textX = alignment == .left ? frame.minX + 17 : alignment == .right ? frame.maxX - 17 : frame.midX
            let startY = frame.minY + LayoutEngine.titleSize(node, isRoot: root).height / 2 - CGFloat(lines.count - 1) * fontSize * 0.65 + fontSize * 0.35
            result += "<text text-anchor=\"\(anchor)\" font-family=\"-apple-system, BlinkMacSystemFont, sans-serif\" font-size=\"\(n(fontSize))\" fill=\"\(textColor)\" font-weight=\"\(node.style?.bold == true ? "700" : (root ? "600" : "500"))\" font-style=\"\(node.style?.italic == true ? "italic" : "normal")\">"
            for (index, line) in lines.enumerated() {
                result += "<tspan x=\"\(n(textX))\" y=\"\(n(startY + CGFloat(index) * fontSize * 1.3))\">\(MapInterchange.xmlEscape(line))</tspan>"
            }
            result += "</text>\n"
            result += NodeContentLayout.svg(node, frame: frame, isRoot: root)
        }
        return result + "</svg>\n"
    }
    private static func wrappedLines(_ title: String, width: CGFloat, font: NSFont) -> [String] {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        var lines: [String] = [], current = ""
        for character in title {
            if character == "\n" { lines.append(current); current = ""; continue }
            let next = current + String(character)
            if !current.isEmpty, (next as NSString).size(withAttributes: attributes).width > width { lines.append(current); current = String(character) }
            else { current = next }
        }
        lines.append(current); return lines
    }
}
