import Foundation

struct MapInterchange {
    static let maximumFileBytes = 20 * 1_024 * 1_024

    private static func checkJSONNesting(_ data: Data) throws {
        guard data.count <= maximumFileBytes else { throw DocumentError.oversizedFile }
        // Reject excessive nesting before the recursive Codable tree is constructed.
        var depth = 0, inString = false, escaped = false
        for byte in data {
            if inString {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { inString = false }
            } else if byte == 34 { inString = true }
            else if byte == 91 || byte == 123 {
                depth += 1
                guard depth <= 2 * MindMapDocument.maximumDepth + 16 else { throw DocumentError.invalidTree }
            } else if byte == 93 || byte == 125 { depth -= 1 }
        }
    }
    static func decodeJSON(_ data: Data) throws -> MindMapDocument {
        try checkJSONNesting(data)
        let document = try JSONDecoder().decode(MindMapDocument.self, from: data)
        try document.validate()
        return document
    }
    static func decodeClipboard(_ data: Data) throws -> [MindMapNode] {
        try checkJSONNesting(data)
        let nodes = try JSONDecoder().decode([MindMapNode].self, from: data)
        var container = MindMapDocument()
        container.nodes = [MindMapNode(title: "Clipboard", children: nodes)]
        try container.validate()
        return nodes
    }
    static func encodeJSON(_ document: MindMapDocument) throws -> Data {
        try document.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= maximumFileBytes else { throw DocumentError.oversizedFile }
        return data
    }
    static func read(_ url: URL) throws -> MindMapDocument {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumFileBytes else { throw DocumentError.oversizedFile }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        switch url.pathExtension.lowercased() {
        case "json", "mindora": return try decodeJSON(data)
        case "opml", "xml": return try importOPML(data)
        default:
            guard let string = String(data: data, encoding: .utf8) else { throw DocumentError.invalidImport("需要 UTF-8 编码的文本。") }
            return try importMarkdown(string, defaultTitle: url.deletingPathExtension().lastPathComponent)
        }
    }
    static func markdown(for node: MindMapNode, includeHeading: Bool = true) -> String {
        func clean(_ value: String) -> String { value.replacingOccurrences(of: "\n", with: "<br>") }
        func details(_ value: MindMapNode, indent: String) -> [String] {
            var lines: [String] = []
            if !value.note.isEmpty { lines.append(indent + "> " + clean(value.note)) }
            if !value.link.isEmpty {
                if let url = NodeRichContent.webURL(value.link) { lines.append(indent + "网址：<" + url.absoluteString + ">") }
                else { lines.append(indent + "网址：" + clean(value.link)) }
            }
            if !value.code.isEmpty {
                var fence = "~~~"
                while value.code.contains(fence) { fence += "~" }
                lines.append(indent + fence + value.codeLanguage)
                lines += value.code.components(separatedBy: "\n").map { indent + $0 }
                lines.append(indent + fence)
            }
            for attachment in value.attachments { lines.append(indent + "附件：" + clean(attachment.name) + "（请从 Mindora 中导出原文件）") }
            return lines
        }
        func visit(_ value: MindMapNode, depth: Int) -> [String] {
            let indent = String(repeating: "  ", count: depth)
            return [indent + "- " + clean(value.title)] + details(value, indent: indent + "  ") + value.children.flatMap { visit($0, depth: depth + 1) }
        }
        if includeHeading {
            return "# \(clean(node.title))\n\n" + (details(node, indent: "") + node.children.flatMap { visit($0, depth: 0) }).joined(separator: "\n") + "\n"
        }
        return visit(node, depth: 0).joined(separator: "\n")
    }

    private final class DraftNode {
        var title: String
        var note = ""
        var children: [DraftNode] = []
        init(_ title: String) { self.title = title }
        func materialize() -> MindMapNode {
            var result = MindMapNode(title: title, children: children.map { $0.materialize() })
            result.note = note; return result
        }
    }
    static func importMarkdown(_ text: String, defaultTitle: String = "导入的导图") throws -> MindMapDocument {
        guard text.utf8.count <= maximumFileBytes else { throw DocumentError.oversizedFile }
        let root = DraftNode(defaultTitle)
        var stack = [root], hasContent = false, count = 1
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            var title = trimmed, requestedDepth = 1
            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            if hashes > 0, trimmed.dropFirst(hashes).first == " " {
                title = String(trimmed.dropFirst(hashes + 1))
                if hashes == 1 && !hasContent { root.title = title; hasContent = true; continue }
                requestedDepth = max(1, hashes - 1)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                let whitespace = rawLine.prefix(while: { $0 == " " || $0 == "\t" })
                let units = whitespace.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
                requestedDepth = units / 2 + 1
                title = String(trimmed.dropFirst(2))
            } else if !hasContent {
                root.title = title; hasContent = true; continue
            }
            guard requestedDepth <= MindMapDocument.maximumDepth, count < MindMapDocument.maximumNodes else { throw DocumentError.invalidTree }
            guard requestedDepth <= stack.count else { throw DocumentError.invalidImport("缩进层级跳跃，请每层使用两个空格。") }
            title = title.replacingOccurrences(of: "<br>", with: "\n")
            let node = DraftNode(title)
            stack = Array(stack.prefix(requestedDepth))
            stack.last!.children.append(node); stack.append(node)
            count += 1; hasContent = true
        }
        guard hasContent else { throw DocumentError.invalidImport("文本为空。") }
        var document = MindMapDocument(); document.nodes = [root.materialize()]; document.title = root.title
        try document.validate(); return document
    }
    static func xmlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;").replacingOccurrences(of: "\n", with: "&#10;")
    }
    static func opml(_ document: MindMapDocument) -> String {
        func visit(_ node: MindMapNode, depth: Int) -> String {
            let indent = String(repeating: "  ", count: depth)
            let attributes = "text=\"\(xmlEscape(node.title))\" _note=\"\(xmlEscape(node.note))\""
            if node.children.isEmpty { return "\(indent)<outline \(attributes)/>\n" }
            return "\(indent)<outline \(attributes)>\n" + node.children.map { visit($0, depth: depth + 1) }.joined() + "\(indent)</outline>\n"
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<opml version=\"2.0\"><head><title>\(xmlEscape(document.title))</title></head><body>\n" + visit(document.root, depth: 1) + "</body></opml>\n"
    }
    static func importOPML(_ data: Data) throws -> MindMapDocument {
        guard data.count <= maximumFileBytes else { throw DocumentError.oversizedFile }
        let delegate = OPMLReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse(), delegate.failure == nil, delegate.sawOPML, !delegate.roots.isEmpty else {
            throw delegate.failure ?? DocumentError.invalidImport(parser.parserError?.localizedDescription ?? "未找到 OPML 大纲。")
        }
        var document = MindMapDocument()
        let nodes = delegate.roots.map { $0.materialize() }
        document.nodes = nodes.count == 1 ? nodes : [MindMapNode(title: delegate.title.isEmpty ? "导入的大纲" : delegate.title, children: nodes)]
        document.title = document.root.title
        try document.validate(); return document
    }
    private final class OPMLReader: NSObject, XMLParserDelegate {
        var roots: [DraftNode] = [], stack: [DraftNode] = []
        var failure: Error?, title = "", inTitle = false, inBody = false, sawOPML = false, count = 0
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
            if elementName == "opml" { sawOPML = true }
            if elementName == "body" { inBody = true }
            if elementName == "title" { inTitle = true }
            guard elementName == "outline", inBody else { return }
            count += 1
            guard count <= MindMapDocument.maximumNodes, stack.count <= MindMapDocument.maximumDepth else {
                failure = DocumentError.invalidTree; parser.abortParsing(); return
            }
            let node = DraftNode(attributes["text"] ?? attributes["title"] ?? "无标题")
            node.note = attributes["_note"] ?? ""
            if let parent = stack.last { parent.children.append(node) } else { roots.append(node) }
            stack.append(node)
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == "outline", inBody, !stack.isEmpty { stack.removeLast() }
            if elementName == "title" { inTitle = false }
            if elementName == "body" { inBody = false }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if inTitle { title += string } }
        func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
            failure = DocumentError.invalidImport("不支持带自定义实体的 OPML。"); parser.abortParsing()
        }
    }
}
