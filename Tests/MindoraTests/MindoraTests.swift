import XCTest
@testable import Mindora

final class MindoraTests: XCTestCase {
    @MainActor func testEditUndoAndSelection() {
        let original = MindMapDocument(), model = EditorModel(document: MindMapDocument())
        let initial = model.document
        model.addChild()
        let child = model.selectedID!
        XCTAssertNotNil(model.document.root.find(child))
        model.updateTitle("子主题", for: child)
        model.undo(); XCTAssertEqual(model.document.root.find(child)?.title, "新主题")
        model.undo(); XCTAssertEqual(model.document, initial)
        XCTAssertEqual(model.selectedID, initial.root.id)
        model.redo(); XCTAssertEqual(model.selectedID, child)
        XCTAssertEqual(model.layoutResult.frames.count, 2)
        XCTAssertEqual(original.nodeCount, 1)
    }
    @MainActor func testMoveAndUndoPreserveOrder() {
        var document = MapTemplate.project.document
        let a = document.root.children[0].id, b = document.root.children[1].id
        document.nodes[0].children[0].isCollapsed = false
        let model = EditorModel(document: document)
        model.select(a); model.moveSelection(to: b)
        XCTAssertEqual(model.document.root.find(b)?.children.last?.id, a)
        XCTAssertNil(model.document.root.children.first(where: { $0.id == a }))
        model.undo(); XCTAssertEqual(model.document, document)
        model.redo(); XCTAssertEqual(model.document.root.find(b)?.children.last?.id, a)
    }
    @MainActor func testRejectMoveIntoDescendant() {
        let document = MapTemplate.project.document, model = EditorModel(document: MapTemplate.blank.document)
        model.replaceDocument(document, name: "测试")
        let branch = document.root.children[0]
        model.select(branch.id)
        XCTAssertFalse(model.canMoveSelection(to: branch.children[0].id))
        model.moveSelection(to: branch.children[0].id)
        XCTAssertEqual(model.document, document)
    }
    @MainActor func testMultiDeleteAndUndo() {
        let document = MapTemplate.project.document, model = EditorModel(document: MapTemplate.project.document)
        model.replaceFromFile(document)
        model.select(document.root.children[0].id)
        model.select(document.root.children[1].id, extending: true)
        model.deleteSelected()
        XCTAssertEqual(model.document.root.children.count, 2)
        model.undo(); XCTAssertEqual(model.document, document)
    }
    @MainActor func testSelectAllDeleteKeepsRoot() {
        let document = MapTemplate.project.document, model = EditorModel(document: MapTemplate.blank.document)
        model.replaceFromFile(document); model.selectAll(); model.deleteSelected()
        XCTAssertEqual(model.document.nodeCount, 1)
        XCTAssertEqual(model.document.root.id, document.root.id)
        model.undo(); XCTAssertEqual(model.document, document)
    }
    @MainActor func testReorderUndoAndDuplicateIDs() throws {
        let document = MapTemplate.project.document, model = EditorModel(document: MapTemplate.blank.document)
        model.replaceFromFile(document)
        let id = document.root.children[0].id
        model.select(id); model.reorderSelected(by: 1)
        XCTAssertEqual(model.document.root.children[1].id, id)
        model.undo(); XCTAssertEqual(model.document, document)
        model.duplicateSelection()
        XCTAssertEqual(model.document.root.children.count, 5)
        XCTAssertEqual(Set(model.document.allNodes.map(\.id)).count, model.document.nodeCount)
        try model.document.validate()
        model.undo(); XCTAssertEqual(model.document, document)
    }
    @MainActor func testCollapsedChildAddedAndUndo() {
        var document = MapTemplate.project.document
        let id = document.root.children[0].id
        document.nodes[0].children[0].isCollapsed = true
        let model = EditorModel(document: document)
        model.addChild(to: id)
        XCTAssertFalse(model.document.root.find(id)!.isCollapsed)
        XCTAssertNotNil(model.layoutResult.frames[model.selectedID!])
        model.undo(); XCTAssertEqual(model.document, document)
    }
    @MainActor func testRootRenameUndoRestoresFullDocument() {
        let document = MindMapDocument(), model = EditorModel(document: MindMapDocument())
        model.replaceFromFile(document)
        model.updateTitle("改名", for: document.root.id)
        model.undo(); XCTAssertEqual(model.document, document)
    }
    @MainActor func testCoalescingInspectorEdits() {
        let model = EditorModel(document: MindMapDocument()), id = model.document.root.id
        model.updateNode(id, key: "title") { $0.title = "A" }
        model.updateNode(id, key: "title") { $0.title = "AB" }
        model.updateNode(id, key: "title") { $0.title = "ABC" }
        model.undo(); XCTAssertEqual(model.document.root.title, "中心主题")
        XCTAssertFalse(model.canUndo)
    }
    func testRoundTripWithMetadataAndLegacyDefaults() throws {
        var document = MapTemplate.project.document
        document.theme = .forest
        document.nodes[0].note = "中文备注\n第二行"
        document.nodes[0].tags = ["待办", "灵感"]
        document.nodes[0].priority = 1; document.nodes[0].progress = 25
        document.nodes[0].style = NodeStyle(colorHex: "2C8A78", fontSize: 20)
        XCTAssertEqual(try MapInterchange.decodeJSON(MapInterchange.encodeJSON(document)), document)
        var object = try JSONSerialization.jsonObject(with: MapInterchange.encodeJSON(document)) as! [String: Any]
        object.removeValue(forKey: "theme")
        var root = (object["nodes"] as! [[String: Any]])[0]
        for key in ["note", "tags", "priority", "progress", "style", "isCollapsed"] { root.removeValue(forKey: key) }
        object["nodes"] = [root]
        let legacy = try MapInterchange.decodeJSON(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(legacy.theme, .indigo); XCTAssertEqual(legacy.root.tags, []); XCTAssertEqual(legacy.root.priority, 0)
    }
    func testRejectDuplicateAndExcessiveNodeCount() throws {
        var document = MindMapDocument()
        document.nodes[0].children = [MindMapNode(id: document.root.id, title: "重复")]
        XCTAssertThrowsError(try document.validate())
        document.nodes[0].children = (0..<10_000).map { MindMapNode(title: "\($0)") }
        XCTAssertThrowsError(try document.validate())
    }
    func testRejectDeepTreeAndUnknownSchema() throws {
        var node = MindMapNode(title: "叶")
        for _ in 0..<129 { node = MindMapNode(title: "层", children: [node]) }
        var document = MindMapDocument(); document.nodes = [node]
        XCTAssertThrowsError(try document.validate())
        document = MindMapDocument(); document.schemaVersion = 999
        XCTAssertThrowsError(try document.validate())
        XCTAssertThrowsError(try MapInterchange.decodeJSON(Data(String(repeating: "[", count: 300).utf8)))
    }
    func testRejectInvalidStyleAndClipboard() throws {
        var document = MindMapDocument()
        document.nodes[0].style = NodeStyle(colorHex: "oops", fontSize: -4)
        XCTAssertThrowsError(try document.validate())
        let node = MindMapNode(title: "重复")
        XCTAssertThrowsError(try MapInterchange.decodeClipboard(JSONEncoder().encode([node, node])))
    }
    func testMarkdownAndOPMLRoundTrip() throws {
        let document = MapTemplate.project.document
        let markdown = MapInterchange.markdown(for: document.root)
        let parsed = try MapInterchange.importMarkdown(markdown)
        XCTAssertEqual(parsed.allNodes.map(\.title), document.allNodes.map(\.title))
        let opml = try MapInterchange.importOPML(Data(MapInterchange.opml(document).utf8))
        XCTAssertEqual(opml.allNodes.map(\.title), document.allNodes.map(\.title))
        XCTAssertThrowsError(try MapInterchange.importMarkdown("# Root\n      - invalid indent"))
        XCTAssertThrowsError(try MapInterchange.importOPML(Data("<wrong/>".utf8)))
    }
    func testOPMLEscapeAndRejectEntity() throws {
        var document = MindMapDocument(); document.nodes[0].title = "A & B <test> \"中文\""
        document.nodes[0].note = "两行\n第二行"
        let parsed = try MapInterchange.importOPML(Data(MapInterchange.opml(document).utf8))
        XCTAssertEqual(parsed.root.title, document.root.title); XCTAssertEqual(parsed.root.note, document.root.note)
        let malicious = "<!DOCTYPE opml [<!ENTITY x 'bad'>]><opml><body><outline text='&x;'/></body></opml>"
        XCTAssertThrowsError(try MapInterchange.importOPML(Data(malicious.utf8)))
    }
    func testLayoutsHaveNoOverlapsAndAreDeterministic() throws {
        var document = MapTemplate.project.document
        for layout in MindMapLayout.allCases {
            document.layout = layout
            let result = LayoutEngine.layout(document), frames = Array(result.frames.values)
            XCTAssertEqual(result.frames.count, document.nodeCount)
            XCTAssertEqual(result.frames, LayoutEngine.layout(document).frames)
            for a in frames.indices { for b in frames.indices where a < b { XCTAssertFalse(frames[a].intersects(frames[b]), "\(layout): overlap") } }
        }
    }
    func testViewportZoomAnchorAndFit() {
        var viewport = CanvasViewport(offset: CGPoint(x: 42, y: -23))
        let size = CGSize(width: 800, height: 600), anchor = CGPoint(x: 150, y: 220)
        let world = viewport.worldPoint(anchor, in: size)
        viewport.zoom(by: 1.7, at: anchor, in: size)
        let actual = viewport.screenPoint(world, in: size)
        XCTAssertEqual(actual.x, anchor.x, accuracy: 0.001); XCTAssertEqual(actual.y, anchor.y, accuracy: 0.001)
        viewport.fit(CGRect(x: -500, y: -300, width: 1000, height: 600), in: size)
        XCTAssertEqual(viewport.offset, .zero); XCTAssertLessThan(viewport.scale, 1)
    }
    @MainActor func testAllExportsHaveValidContainers() throws {
        let document = MapTemplate.project.document
        for format in ExportFormat.allCases {
            let data = try ImportExportService.exportData(document, format: format)
            XCTAssertFalse(data.isEmpty)
            switch format {
            case .json: XCTAssertEqual(try MapInterchange.decodeJSON(data), document)
            case .opml: XCTAssertEqual(try MapInterchange.importOPML(data).nodeCount, document.nodeCount)
            case .png, .jpeg: XCTAssertNotNil(NSBitmapImageRep(data: data))
            case .pdf: XCTAssertNotNil(CGPDFDocument(CGDataProvider(data: data as CFData)!))
            case .svg: XCTAssertTrue(XMLParser(data: data).parse())
            case .markdown: XCTAssertEqual(try MapInterchange.importMarkdown(String(data: data, encoding: .utf8)!).nodeCount, document.nodeCount)
            }
        }
    }
    func testThousandNodeLayout() throws {
        var document = MindMapDocument()
        document.nodes[0].children = (0..<20).map { index in
            MindMapNode(title: "分支 \(index)", children: (0..<49).map { MindMapNode(title: "主题 \($0)") })
        }
        try document.validate()
        let start = Date(), result = LayoutEngine.layout(document)
        XCTAssertEqual(result.frames.count, 1001)
        print("LAYOUT_1001_NODES_MS=\(Int(Date().timeIntervalSince(start) * 1000))")
    }
}
