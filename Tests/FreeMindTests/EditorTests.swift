import XCTest
@testable import FreeMind

/// 编辑操作与撤销。
final class EditorTests: XCTestCase {
    private var doc: MindMapDocument!
    private var editor: MapEditor { doc.editor }

    override func setUp() {
        doc = MindMapDocument()
        doc.editor.load(MindMap.blank(title: "Root"))
        doc.undoManager?.groupsByEvent = false
    }

    private func step(_ body: () -> Void) {
        doc.undoManager?.beginUndoGrouping()
        body()
        doc.undoManager?.endUndoGrouping()
    }

    func testAddChildAndUndo() {
        let before = editor.map
        step { editor.addChild(to: editor.rootID, edit: false) }
        XCTAssertEqual(editor.map.root.children.count, 5)
        XCTAssertEqual(editor.selection, [editor.map.root.children[4].id])
        doc.undoManager?.undo()
        XCTAssertEqual(editor.map, before)
        doc.undoManager?.redo()
        XCTAssertEqual(editor.map.root.children.count, 5)
    }

    func testSiblingBeforeAndAfter() {
        let first = editor.map.root.children[0].id
        editor.select(first)
        step { editor.addSibling(before: true, edit: false) }
        XCTAssertEqual(editor.map.root.children.firstIndex { $0.id == first }, 1)
        editor.select(first)
        step { editor.addSibling(before: false, edit: false) }
        XCTAssertEqual(editor.map.root.children.firstIndex { $0.id == first }, 1)
        XCTAssertEqual(editor.map.root.children.count, 6)
    }

    func testInsertParentWrapsSelection() {
        let ids = editor.map.root.children.prefix(2).map(\.id)
        editor.setSelection(Array(ids))
        step { editor.insertParent() }
        editor.commitEditingIfNeeded()
        let parent = editor.map.root.children[0]
        XCTAssertEqual(parent.children.map(\.id), Array(ids))
        XCTAssertEqual(editor.map.root.children.count, 3)
    }

    func testDeleteSelectsNeighbor() {
        let children = editor.map.root.children.map(\.id)
        editor.select(children[1])
        step { editor.deleteSelection() }
        XCTAssertEqual(editor.selection, [children[2]])
        editor.select(children[3])
        step { editor.deleteSelection() }
        XCTAssertEqual(editor.selection, [children[2]])
    }

    func testDeleteKeepingChildren() {
        let parent = editor.map.root.children[0].id
        step { editor.addChild(to: parent, edit: false) }
        step { editor.addChild(to: parent, edit: false) }
        editor.select(parent)
        step { editor.deleteKeepingChildren() }
        XCTAssertEqual(editor.map.root.children.count, 5)
        XCTAssertFalse(editor.map.contains(parent))
    }

    func testFoldIsNotUndoableButSurvivesUndo() {
        let branch = editor.map.root.children[0].id
        step { editor.addChild(to: branch, edit: false) }
        editor.setCollapsed([branch], true)
        XCTAssertTrue(editor.map.topic(branch)!.collapsed)
        XCTAssertTrue(doc.isDocumentEdited)
        // 撤销“添加子主题”时，折叠状态保持当前值
        step { editor.setTitle(editor.rootID, "Renamed") }
        doc.undoManager?.undo()
        XCTAssertEqual(editor.map.root.title, "Root")
        XCTAssertTrue(editor.map.topic(branch)!.collapsed)
    }

    func testMoveIntoOwnSubtreeIsRejected() {
        let a = editor.map.root.children[0].id
        step { editor.addChild(to: a, edit: false) }
        let child = editor.map.topic(a)!.children[0].id
        let before = editor.map
        editor.move([a], to: child, at: nil)
        XCTAssertEqual(editor.map, before)
    }

    func testMoveReordersWithinSameParent() {
        let ids = editor.map.root.children.map(\.id)
        step { editor.move([ids[0]], to: editor.rootID, at: 3) }
        XCTAssertEqual(editor.map.root.children.map(\.id), [ids[1], ids[2], ids[0], ids[3]])
    }

    func testPromoteAndDemote() {
        let ids = editor.map.root.children.map(\.id)
        editor.select(ids[1])
        step { editor.demoteSelection() }
        XCTAssertEqual(editor.map.parentID(of: ids[1]), ids[0])
        step { editor.promoteSelection() }
        XCTAssertEqual(editor.map.parentID(of: ids[1]), editor.rootID)
        XCTAssertEqual(editor.map.root.children.map(\.id), ids)
    }

    func testMarkersAreExclusivePerGroup() {
        editor.select(editor.rootID)
        step { editor.toggleMarker(MarkerID("priority-1")) }
        step { editor.toggleMarker(MarkerID("priority-3")) }
        step { editor.toggleMarker(MarkerID("symbol-idea")) }
        step { editor.toggleMarker(MarkerID("symbol-heart")) }
        XCTAssertEqual(editor.map.root.markers, [MarkerID("priority-3"), MarkerID("symbol-heart"), MarkerID("symbol-idea")])
    }

    func testNoteEditsCoalesceIntoOneUndoStep() {
        let id = editor.rootID
        step {
            editor.setNote(id, "a")
            editor.setNote(id, "ab")
            editor.setNote(id, "abc")
        }
        XCTAssertEqual(editor.map.root.note, "abc")
        doc.undoManager?.undo()
        XCTAssertEqual(editor.map.root.note, "")
    }

    func testCopyPasteAcrossDocuments() throws {
        let other = MindMapDocument()
        other.editor.load(MindMap.blank(title: "Other"))
        let data = Data("x".utf8)
        let resID = doc.attachments.add(data: data, name: "x.txt")
        let source = editor.map.root.children[0].id
        step { _ = editor.perform("t") { $0.update(source) { $0.attachments = [Attachment(id: resID, name: "x.txt", size: 1)] } } }
        editor.select(source)
        let pb = NSPasteboard(name: NSPasteboard.Name("FreeMindTest-\(UUID().uuidString)"))
        editor.copySelection(to: pb)
        other.editor.select(other.editor.rootID)
        try other.editor.paste(from: pb)
        let pasted = other.editor.map.root.children.last!
        XCTAssertEqual(pasted.title, editor.map.topic(source)!.title)
        XCTAssertNotEqual(pasted.id, source)
        XCTAssertEqual(other.attachments.data(for: resID), data)
        pb.releaseGlobally()
    }

    func testRelationshipsFollowTopicLifecycle() throws {
        let a = editor.map.root.children[0].id, b = editor.map.root.children[2].id
        step { editor.addRelationship(from: a, to: b) }
        let rel = try XCTUnwrap(editor.map.relationships.first)
        XCTAssertEqual(editor.selectedRelationship, rel.id)
        XCTAssertTrue(editor.selection.isEmpty)
        XCTAssertEqual(editor.layout.relationships.count, 1)
        // 删除端点主题，联系线一并删除；撤销后恢复
        editor.select(b)
        XCTAssertNil(editor.selectedRelationship)
        step { editor.deleteSelection() }
        XCTAssertTrue(editor.map.relationships.isEmpty)
        doc.undoManager?.undo()
        XCTAssertEqual(editor.map.relationships.map(\.id), [rel.id])
        // 折叠端点所在分支：连线改连到可见祖先
        step { editor.addChild(to: b, edit: false) }
        let child = editor.map.topic(b)!.children[0].id
        step { editor.addRelationship(from: a, to: child) }
        editor.setCollapsed([b], true)
        let layout = try XCTUnwrap(editor.layout.relationships.first { $0.to == child })
        XCTAssertEqual(layout.toCenter, CGPoint(x: editor.layout.nodes[b]!.frame.midX, y: editor.layout.nodes[b]!.frame.midY))
    }

    func testFreshIDsKeepRelationships() {
        var map = editor.map
        map.relationships = [Relationship(from: map.root.children[0].id, to: map.root.children[1].id)]
        let fresh = map.withFreshTopicIDs()
        XCTAssertNotEqual(fresh.root.id, map.root.id)
        XCTAssertEqual(fresh.relationships.first?.from, fresh.root.children[0].id)
        XCTAssertEqual(fresh.relationships.first?.to, fresh.root.children[1].id)
    }

    func testRelationshipRoundTripsThroughJSON() throws {
        var map = editor.map
        var rel = Relationship(from: map.root.children[0].id, to: map.root.children[1].id, title: "因果")
        rel.control1 = .init(dx: 10, dy: -20)
        rel.dashed = false
        map.relationships = [rel]
        let data = try DocumentContent(map: map, view: nil).encoded()
        XCTAssertEqual(try DocumentContent.decode(data).map.relationships, [rel])
    }

    func testFind() {
        step { editor.setNote(editor.map.root.children[2].id, "包含关键字") }
        editor.findQuery = "关键字"
        XCTAssertEqual(editor.findResults, [editor.map.root.children[2].id])
        editor.findInNotes = false
        XCTAssertTrue(editor.findResults.isEmpty)
    }

    func testNavigationInMindMap() {
        let root = editor.rootID
        editor.select(root)
        editor.navigate(.right)
        let right = editor.selection.first!
        XCTAssertEqual(editor.layout.nodes[right]?.side, .right)
        editor.navigate(.left)
        XCTAssertEqual(editor.selection, [root])
        editor.navigate(.left)
        XCTAssertEqual(editor.layout.nodes[editor.selection.first!]?.side, .left)
    }
}
