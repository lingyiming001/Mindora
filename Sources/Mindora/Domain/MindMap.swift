import Foundation

struct MindMapDocument: Codable, Equatable {
    static let currentSchemaVersion = 1
    static let maximumNodes = 10_000
    static let maximumDepth = 128
    var schemaVersion = currentSchemaVersion
    var id = UUID()
    var title = "未命名导图"
    var layout: MindMapLayout = .balanced
    var theme: MapTheme = .indigo
    var nodes = [MindMapNode(title: "中心主题")]
    var defaultNodeStyle: NodeStyle?

    var root: MindMapNode { nodes[0] }
    var allNodes: [MindMapNode] { root.flattened() }
    var nodeCount: Int { allNodes.count }

    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        layout = try values.decode(MindMapLayout.self, forKey: .layout)
        theme = try values.decodeIfPresent(MapTheme.self, forKey: .theme) ?? .indigo
        nodes = try values.decode([MindMapNode].self, forKey: .nodes)
        defaultNodeStyle = try values.decodeIfPresent(NodeStyle.self, forKey: .defaultNodeStyle)
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else { throw DocumentError.unsupportedVersion(schemaVersion) }
        guard nodes.count == 1 else { throw DocumentError.invalidTree }
        if let defaultNodeStyle {
            var probe = MindMapDocument(); probe.nodes[0].style = defaultNodeStyle
            try probe.validate()
        }
        var ids = Set<UUID>()
        var attachmentBytes = 0
        func visit(_ node: MindMapNode, depth: Int) throws {
            guard depth <= Self.maximumDepth, ids.insert(node.id).inserted,
                  ids.count <= Self.maximumNodes, node.title.count <= 10_000,
                  node.note.count <= 100_000, node.tags.count <= 100,
                  node.tags.allSatisfy({ $0.count <= 200 }), (0...3).contains(node.priority),
                  node.progress == nil || (0...100).contains(node.progress!),
                  node.style?.fontSize == nil || (10...36).contains(node.style!.fontSize!),
                  node.style?.colorHex == nil || (node.style!.colorHex!.count == 6 && node.style!.colorHex!.allSatisfy({ $0.isHexDigit })) else { throw DocumentError.invalidTree }
            guard node.link.count <= 4096, node.code.count <= 100_000, node.codeLanguage.count <= 32,
                  node.codeLanguage.allSatisfy({ $0.isLetter || $0.isNumber || "+-#".contains($0) }),
                  node.attachments.count <= 16, Set(node.attachments.map(\.id)).count == node.attachments.count else { throw DocumentError.invalidTree }
            for attachment in node.attachments {
                attachmentBytes += attachment.data.count
                guard attachment.data.count <= 3 * 1024 * 1024, attachmentBytes <= 8 * 1024 * 1024,
                      !attachment.name.isEmpty, attachment.name.count <= 255,
                      !attachment.name.contains("/"), !attachment.name.contains("\\"), attachment.typeIdentifier.count <= 200 else { throw DocumentError.invalidTree }
            }
            if let style = node.style {
                for hex in [style.textColorHex, style.backgroundHex].compactMap({ $0 }) {
                    guard hex.count == 6, hex.allSatisfy({ $0.isHexDigit }) else { throw DocumentError.invalidTree }
                }
                if let height = style.height, !(44...2400).contains(height) { throw DocumentError.invalidTree }
                if let width = style.width, !(160...1200).contains(width) { throw DocumentError.invalidTree }
                if let width = style.borderWidth, !(0...6).contains(width) { throw DocumentError.invalidTree }
                if let radius = style.cornerRadius, !(0...28).contains(radius) { throw DocumentError.invalidTree }
            }
            for child in node.children { try visit(child, depth: depth + 1) }
        }
        try visit(root, depth: 0)
    }
}

enum MindMapLayout: String, Codable, CaseIterable, Identifiable {
    case balanced, rightTree, leftTree, organization
    var id: String { rawValue }
    var label: String {
        switch self {
        case .balanced: "左右平衡"
        case .rightTree: "向右展开"
        case .leftTree: "向左展开"
        case .organization: "组织结构"
        }
    }
    var symbol: String { self == .organization ? "chart.bar.xaxis" : "point.3.connected.trianglepath.dotted" }
}

enum MapTheme: String, Codable, CaseIterable, Identifiable {
    case indigo, forest, sunset, graphite
    var id: String { rawValue }
    var label: String {
        switch self {
        case .indigo: "鸢尾"
        case .forest: "青林"
        case .sunset: "落日"
        case .graphite: "石墨"
        }
    }
}

struct MindMapNode: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var children: [MindMapNode] = []
    var isCollapsed = false
    var note = ""
    var style: NodeStyle?
    var tags: [String] = []
    var priority = 0
    var progress: Int?
    var link = ""
    var code = ""
    var codeLanguage = ""
    var attachments: [NodeAttachment] = []
    var hasRichContent: Bool { !link.isEmpty || !code.isEmpty || !attachments.isEmpty }

    init(id: UUID = UUID(), title: String, children: [MindMapNode] = []) {
        self.id = id; self.title = title; self.children = children
        self.style = NodeStyle(textAlignment: .left)
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        children = try values.decodeIfPresent([MindMapNode].self, forKey: .children) ?? []
        isCollapsed = try values.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        note = try values.decodeIfPresent(String.self, forKey: .note) ?? ""
        style = try values.decodeIfPresent(NodeStyle.self, forKey: .style)
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        priority = try values.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        progress = try values.decodeIfPresent(Int.self, forKey: .progress)
        link = try values.decodeIfPresent(String.self, forKey: .link) ?? ""
        code = try values.decodeIfPresent(String.self, forKey: .code) ?? ""
        codeLanguage = try values.decodeIfPresent(String.self, forKey: .codeLanguage) ?? ""
        attachments = try values.decodeIfPresent([NodeAttachment].self, forKey: .attachments) ?? []
    }
}

struct NodeAttachment: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var typeIdentifier: String
    var data: Data
}

enum NodeTextAlignment: String, Codable, CaseIterable, Identifiable {
    case left, center, right
    var id: String { rawValue }
    var label: String {
        switch self { case .left: "左对齐"; case .center: "居中"; case .right: "右对齐" }
    }
    var symbol: String {
        switch self { case .left: "text.alignleft"; case .center: "text.aligncenter"; case .right: "text.alignright" }
    }
}

struct NodeStyle: Codable, Equatable {
    var colorHex: String?
    var fontSize: Double?
    var bold: Bool? = nil
    var italic: Bool? = nil
    var textColorHex: String? = nil
    var backgroundHex: String? = nil
    var borderWidth: Double? = nil
    var cornerRadius: Double? = nil
    var shadow: Bool? = nil
    var textAlignment: NodeTextAlignment? = nil
    var width: Double? = nil
    var height: Double? = nil
}

struct NodeProperties: Equatable {
    var title: String
    var note: String
    var tags: [String]
    var priority: Int
    var progress: Int?
    var style: NodeStyle?
    var isCollapsed: Bool
    var link: String
    var code: String
    var codeLanguage: String
    var attachments: [NodeAttachment]

    init(_ node: MindMapNode) {
        title = node.title; note = node.note; tags = node.tags
        priority = node.priority; progress = node.progress; style = node.style; isCollapsed = node.isCollapsed
        link = node.link; code = node.code; codeLanguage = node.codeLanguage; attachments = node.attachments
    }
    func apply(to node: inout MindMapNode) {
        node.title = title; node.note = note; node.tags = tags
        node.priority = priority; node.progress = progress; node.style = style; node.isCollapsed = isCollapsed
        node.link = link; node.code = code; node.codeLanguage = codeLanguage; node.attachments = attachments
    }
}

enum DocumentError: LocalizedError {
    case unsupportedVersion(Int), invalidTree, oversizedFile, invalidImport(String), invalidMove
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "不支持文件版本 \(version)。请更新 Mindora 后打开。"
        case .invalidTree: "导图结构无效，或超过 10,000 个节点 / 128 层深度的限制。"
        case .oversizedFile: "文件超过 20 MB 的读取限制。"
        case .invalidImport(let reason): "无法导入：\(reason)"
        case .invalidMove: "不能把主题移动到自身或其后代中。"
        }
    }
}
