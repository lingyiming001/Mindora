import XCTest
import AppKit
@testable import Mindora

final class MindoraTests: XCTestCase {
    func testLibraryRefreshDetectsContentChangesWithoutInvalidatingOtherFiles() {
        let url = URL(fileURLWithPath: "/Library/Ideas.mindora")
        let original = LibraryItem(url: url, isFolder: false, children: [], modified: Date(timeIntervalSince1970: 100), bytes: 200)
        let unchanged = LibraryItem(url: url, isFolder: false, children: [], modified: Date(timeIntervalSince1970: 100), bytes: 200)
        let edited = LibraryItem(url: url, isFolder: false, children: [], modified: Date(timeIntervalSince1970: 101), bytes: 200)
        let resized = LibraryItem(url: url, isFolder: false, children: [], modified: Date(timeIntervalSince1970: 100), bytes: 250)
        XCTAssertEqual(original, unchanged)
        XCTAssertNotEqual(original.contentVersion, edited.contentVersion)
        XCTAssertNotEqual(original.contentVersion, resized.contentVersion)
        let folderURL = url.deletingLastPathComponent()
        let folder = LibraryItem(url: folderURL, isFolder: true, children: [original])
        let updatedFolder = LibraryItem(url: folderURL, isFolder: true, children: [edited])
        XCTAssertNotEqual(folder, updatedFolder)
        XCTAssertEqual(folder.matching("Ideas")?.children.first?.contentVersion, original.contentVersion)
    }

    @MainActor func testSiblingDropReordersWithoutLosingBranches() throws {
        let original = MapTemplate.project.document
        let model = EditorModel(document: original)
        let first = original.root.children[0], last = original.root.children.last!
        model.select(first.id); model.dropSelection(on: last.id)
        XCTAssertEqual(model.document.root.children.last, first)
        XCTAssertEqual(model.document.nodeCount, original.nodeCount)
        XCTAssertEqual(Set(model.document.allNodes.map(\.id)), Set(original.allNodes.map(\.id)))
        let reordered = model.document
        try reordered.validate()
        model.undo(); XCTAssertEqual(model.document, original)
        model.redo(); XCTAssertEqual(model.document, reordered)
        model.dropSelection(on: original.root.children[1].id)
        XCTAssertEqual(model.document.root.children.first, first)
    }
    @MainActor func testMultiSiblingDropPreservesOrderAndUndo() {
        let original = MapTemplate.project.document
        let model = EditorModel(document: original)
        let ids = original.root.children.map(\.id)
        model.select(ids[0]); model.select(ids[1], extending: true)
        model.dropSelection(on: ids[3])
        XCTAssertEqual(model.document.root.children.map(\.id), [ids[2], ids[3], ids[0], ids[1]])
        XCTAssertEqual(model.document.nodeCount, original.nodeCount)
        model.undo(); XCTAssertEqual(model.document, original)
        model.select(ids[0]); model.dropSelection(on: ids[0])
        XCTAssertEqual(model.document, original)
    }
    @MainActor func testExpandedHistoryAndMultiStepRecovery() {
        let original = MindMapDocument()
        let model = EditorModel(document: original)
        for index in 0..<220 { model.updateTitle("主题 \(index)", for: original.root.id) }
        XCTAssertEqual(model.undoCount, 220)
        let edited = model.document
        model.undo(steps: 220)
        XCTAssertEqual(model.document, original)
        XCTAssertEqual(model.redoCount, 220)
        model.redo(steps: 220)
        XCTAssertEqual(model.document, edited)
    }
    @MainActor func testNewEditAfterUndoKeepsSeparateRecoveryStep() {
        let original = MindMapDocument(), model = EditorModel(document: MindMapDocument())
        model.updateNode(model.document.root.id, key: "title") { $0.title = "A" }
        model.addChild(); model.undo()
        model.updateNode(model.document.root.id, key: "title") { $0.title = "B" }
        XCTAssertFalse(model.canRedo)
        model.undo(); XCTAssertEqual(model.document.root.title, "A")
        model.undo(); XCTAssertEqual(model.document.root.title, original.root.title)
    }

    @MainActor func testSiblingCanBeMovedAsChildAndUndone() throws {
        let original = MapTemplate.project.document
        let model = EditorModel(document: original)
        let source = original.root.children[0], target = original.root.children[1]
        model.select(source.id)
        model.dropSelection(on: target.id, asChild: true)
        XCTAssertEqual(model.document.root.children.count, original.root.children.count - 1)
        XCTAssertEqual(model.document.root.find(target.id)?.children.last, source)
        XCTAssertEqual(model.document.nodeCount, original.nodeCount)
        try model.document.validate()
        model.undo(); XCTAssertEqual(model.document, original)
        model.redo(); XCTAssertEqual(model.document.root.find(target.id)?.children.last, source)
    }
    @MainActor func testHistoryLimitAndBatchRecoveryPublishOnce() {
        let model = EditorModel(document: MindMapDocument())
        for index in 0..<450 { model.updateTitle("标题 \(index)", for: model.document.root.id) }
        XCTAssertEqual(model.undoCount, 400)
        XCTAssertEqual(model.undoSteps.count, 50)
        var notifications = 0
        model.documentDidChange = { _ in notifications += 1 }
        let revision = model.layoutRevision
        model.undo(steps: 400)
        XCTAssertEqual(model.document.root.title, "标题 49")
        XCTAssertEqual(model.redoCount, 400)
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(model.layoutRevision, revision + 1)
        model.redo(steps: 400)
        XCTAssertEqual(model.document.root.title, "标题 449")
        XCTAssertEqual(notifications, 2)
        XCTAssertEqual(model.undoCount, 400)
    }
    @MainActor func testSearchCacheTracksEditsAndUndo() {
        let model = EditorModel(document: MindMapDocument())
        model.searchText = "测试"
        XCTAssertTrue(model.searchMatches.isEmpty)
        model.updateTitle("测试", for: model.document.root.id)
        XCTAssertEqual(model.searchMatches.count, 1)
        model.undo(); XCTAssertTrue(model.searchMatches.isEmpty)
        model.redo(); XCTAssertEqual(model.searchMatches.count, 1)
    }

    func testDragLandingZonesAndHysteresis() {
        let id = UUID()
        let session = NodeDragSession(revision: 0, title: "主题", count: 1,
            targets: [.init(id: id, title: "目标", frame: CGRect(x: 0, y: 0, width: 160, height: 60), isRoot: false)], verticalSiblings: false)
        let size = CGSize.zero, viewport = CanvasViewport()
        let before = session.resolve(at: CGPoint(x: 80, y: -12), viewport: viewport, size: size)
        XCTAssertEqual(before?.placement, .before)
        XCTAssertEqual(session.resolve(at: CGPoint(x: 80, y: 19), viewport: viewport, size: size, previous: before)?.placement, .before)
        XCTAssertEqual(session.resolve(at: CGPoint(x: 80, y: 30), viewport: viewport, size: size, previous: before)?.placement, .inside)
        XCTAssertEqual(session.resolve(at: CGPoint(x: 80, y: 70), viewport: viewport, size: size)?.placement, .after)
        XCTAssertEqual(session.resolve(at: CGPoint(x: 80, y: -12), viewport: viewport, size: size, previous: before, forceChild: true)?.placement, .inside)
        XCTAssertNil(session.resolve(at: CGPoint(x: 400, y: 200), viewport: viewport, size: size))
        let organization = NodeDragSession(revision: 0, title: "主题", count: 1, targets: session.targets, verticalSiblings: true)
        XCTAssertEqual(organization.resolve(at: CGPoint(x: -10, y: 30), viewport: viewport, size: size)?.placement, .before)
        XCTAssertEqual(organization.resolve(at: CGPoint(x: 170, y: 30), viewport: viewport, size: size)?.placement, .after)
    }
    @MainActor func testExplicitInsertionAndCrossParentRecovery() throws {
        let original = MapTemplate.project.document, model = EditorModel(document: MapTemplate.project.document)
        model.replaceFromFile(original)
        let ids = original.root.children.map(\.id)
        model.select(ids[0])
        model.moveSelection(relativeTo: .init(id: ids[2], placement: .before))
        XCTAssertEqual(model.document.root.children.map(\.id), [ids[1], ids[0], ids[2], ids[3]])
        model.undo(); XCTAssertEqual(model.document, original)
        let branch = original.root.children[1], target = branch.children[0]
        model.moveSelection(relativeTo: .init(id: target.id, placement: .after))
        XCTAssertEqual(model.document.root.find(branch.id)?.children[1].id, ids[0])
        XCTAssertEqual(model.document.nodeCount, original.nodeCount)
        try model.document.validate()
        model.undo(); XCTAssertEqual(model.document, original)
        model.redo(); XCTAssertEqual(model.document.root.find(branch.id)?.children[1].id, ids[0])
    }
    @MainActor func testDragPreviewIsReadOnlyAndExcludesMovingSubtree() {
        let original = MapTemplate.project.document, model = EditorModel(document: MapTemplate.project.document)
        model.replaceFromFile(original)
        let branch = original.root.children[0]
        model.select(branch.id)
        let session = model.makeDragSession()!
        let blocked = Set(branch.flattened().map(\.id))
        XCTAssertTrue(session.targets.allSatisfy { !blocked.contains($0.id) })
        let revision = model.layoutRevision
        let start = Date()
        for index in 0..<1000 {
            _ = session.resolve(at: CGPoint(x: index % 500, y: index % 300), viewport: model.viewport, size: CGSize(width: 800, height: 600))
        }
        print("DRAG_1000_HIT_TESTS_MS=\(Int(Date().timeIntervalSince(start) * 1000))")
        XCTAssertEqual(model.document, original)
        XCTAssertEqual(model.layoutRevision, revision)
        XCTAssertEqual(model.undoCount, 0)
        model.moveSelection(relativeTo: .init(id: branch.children[0].id, placement: .inside))
        XCTAssertEqual(model.document, original)
        model.select(original.root.id)
        XCTAssertNil(model.makeDragSession())
    }

    @MainActor func testDragMultiSelectionIsOneStepAndKeepsViewport() {
        let original = MapTemplate.project.document, model = EditorModel(document: MapTemplate.project.document)
        model.replaceFromFile(original)
        let ids = original.root.children.map(\.id)
        model.viewport.offset = CGPoint(x: 30, y: 80)
        let viewport = model.viewport
        model.select(ids[0]); model.select(ids[2], extending: true)
        model.moveSelection(relativeTo: .init(id: ids[3], placement: .after))
        XCTAssertEqual(model.document.root.children.map(\.id), [ids[1], ids[3], ids[0], ids[2]])
        XCTAssertEqual(model.undoCount, 1)
        XCTAssertEqual(model.viewport, viewport)
        model.undo(); XCTAssertEqual(model.document, original)
        model.redo(); XCTAssertEqual(model.document.root.children.map(\.id), [ids[1], ids[3], ids[0], ids[2]])
    }
    @MainActor func testDragAdjacentNoOpAndRootPlacementProtection() {
        let original = MapTemplate.project.document, model = EditorModel(document: MapTemplate.project.document)
        model.replaceFromFile(original)
        model.select(original.root.children[0].id)
        model.moveSelection(relativeTo: .init(id: original.root.children[1].id, placement: .before))
        XCTAssertEqual(model.document, original)
        XCTAssertEqual(model.undoCount, 0)
        model.moveSelection(relativeTo: .init(id: original.root.id, placement: .before))
        XCTAssertEqual(model.document, original)
        XCTAssertEqual(model.undoCount, 0)
    }

    @MainActor func testCanvasDragEventsPreviewCommitAndCancel() throws {
        var original = MindMapDocument()
        original.layout = .rightTree
        original.nodes[0].children = [MindMapNode(title: "Alpha"), MindMapNode(title: "Beta"), MindMapNode(title: "Gamma")]
        let model = EditorModel(document: original)
        let view = MindMapCanvasView(model: model)
        view.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        view.layout()
        let ids = original.root.children.map(\.id)
        func center(_ id: UUID) -> CGPoint {
            let frame = model.viewport.screenRect(model.layoutResult.frames[id]!, in: view.bounds.size)
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        func event(_ type: NSEvent.EventType, _ point: CGPoint, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let start = center(ids[0])
        let lastFrame = model.viewport.screenRect(model.layoutResult.frames[ids[2]]!, in: view.bounds.size)
        let end = CGPoint(x: lastFrame.midX, y: lastFrame.maxY + 10)
        view.mouseDown(with: event(.leftMouseDown, start))
        view.mouseDragged(with: event(.leftMouseDragged, end))
        XCTAssertEqual(model.document, original)
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".agents/test/drag-insert-preview.png")
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: output)
        }
        view.mouseUp(with: event(.leftMouseUp, end))
        XCTAssertEqual(model.document.root.children.map(\.id), [ids[1], ids[2], ids[0]])
        XCTAssertEqual(model.undoCount, 1)
        model.undo(); XCTAssertEqual(model.document, original)
        let source = center(ids[0]), target = center(ids[1])
        view.mouseDown(with: event(.leftMouseDown, source, flags: .option))
        view.mouseDragged(with: event(.leftMouseDragged, target, flags: .option))
        view.mouseUp(with: event(.leftMouseUp, target, flags: .option))
        XCTAssertEqual(model.document.root.find(ids[1])?.children.first?.id, ids[0])
        model.undo(); XCTAssertEqual(model.document, original)
        view.mouseDown(with: event(.leftMouseDown, source))
        view.mouseDragged(with: event(.leftMouseDragged, target))
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        view.keyDown(with: escape)
        view.mouseUp(with: event(.leftMouseUp, target))
        XCTAssertEqual(model.document, original)
        XCTAssertEqual(model.undoCount, 0)
    }

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
    @MainActor func testReorderWrapsFirstToLastAndUndoRedo() throws {
        let original = MapTemplate.project.document
        let model = EditorModel(document: original)
        let first = original.root.children[0]
        model.select(first.id)
        model.reorderSelected(by: -1)
        XCTAssertEqual(model.document.root.children.map(\.id), Array(original.root.children.dropFirst()).map(\.id) + [first.id])
        XCTAssertEqual(model.document.root.children.last, first)
        XCTAssertEqual(model.selectedID, first.id)
        let reordered = model.document
        try reordered.validate()
        model.undo(); XCTAssertEqual(model.document, original)
        model.redo(); XCTAssertEqual(model.document, reordered)
    }
    @MainActor func testReorderWrapsLastToFirstAndUndoRedo() throws {
        let original = MapTemplate.project.document
        let model = EditorModel(document: original)
        let last = original.root.children.last!
        model.select(last.id)
        model.reorderSelected(by: 1)
        XCTAssertEqual(model.document.root.children.map(\.id), [last.id] + Array(original.root.children.dropLast()).map(\.id))
        XCTAssertEqual(model.document.root.children.first, last)
        XCTAssertEqual(model.selectedID, last.id)
        let reordered = model.document
        try reordered.validate()
        model.undo(); XCTAssertEqual(model.document, original)
        model.redo(); XCTAssertEqual(model.document, reordered)
    }
    @MainActor func testReorderSingleSiblingAndRootDoNotCreateUndo() {
        var original = MindMapDocument()
        original.nodes[0].children = [MindMapNode(title: "唯一子主题")]
        let model = EditorModel(document: original)
        model.select(original.root.children[0].id)
        model.reorderSelected(by: -1); model.reorderSelected(by: 1)
        XCTAssertEqual(model.document, original)
        XCTAssertFalse(model.canUndo)
        model.select(original.root.id)
        model.reorderSelected(by: -1); model.reorderSelected(by: 1)
        XCTAssertEqual(model.document, original)
        XCTAssertFalse(model.canUndo)
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
