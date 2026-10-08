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

    /// 直接拖动联系线：抓住的曲线点跟着鼠标走，一次拖动只占一个撤销步骤。
    func testDraggingRelationshipMovesGrabbedPoint() throws {
        let a = editor.map.root.children[0].id, b = editor.map.root.children[2].id
        step { editor.addRelationship(from: a, to: b) }
        let id = try XCTUnwrap(editor.selectedRelationship)
        let start = try XCTUnwrap(editor.layout.relationship(id))
        for t: CGFloat in [0.5, 0.3] {
            let grabbed = try XCTUnwrap(editor.layout.relationship(id)).point(at: t)
            let target = CGPoint(x: grabbed.x + 60, y: grabbed.y - 90)
            // 和画布一样，每个拖动事件按当前布局重新计算；端点在主题边框上滑动的偏差几次之内就补上。
            // App 里撤销分组按事件自动建立，合并掉的事件不注册撤销、也就没有分组，这里一次拖动放进一个分组。
            step {
                for _ in 0..<5 {
                    guard let r = editor.layout.relationship(id) else { return }
                    let (c1, c2) = r.controlOffsets(moving: t, to: target)
                    editor.updateRelationship(id, actionName: "Reshape", coalesce: "drag-\(t)") {
                        $0.control1 = c1
                        $0.control2 = c2
                    }
                }
            }
            let moved = try XCTUnwrap(editor.layout.relationship(id)).point(at: t)
            XCTAssertEqual(moved.x, target.x, accuracy: 1)
            XCTAssertEqual(moved.y, target.y, accuracy: 1)
        }
        // 两次拖动各是一步撤销
        doc.undoManager?.undo()
        doc.undoManager?.undo()
        XCTAssertNil(editor.map.relationships.first?.control1)
        XCTAssertEqual(editor.layout.relationship(id)?.c1, start.c1)
    }

    /// 隐藏联系线：不进布局（不画、点不中）、取消选中、不进撤销栈但随文件保存；新建联系线时自动显示。
    func testHidingRelationships() throws {
        let a = editor.map.root.children[0].id, b = editor.map.root.children[2].id
        step { editor.addRelationship(from: a, to: b) }
        XCTAssertNotNil(editor.selectedRelationship)
        editor.setRelationshipsHidden(true)
        XCTAssertTrue(editor.layout.relationships.isEmpty)
        XCTAssertNil(editor.selectedRelationship)
        XCTAssertEqual(editor.map.relationships.count, 1, "隐藏只影响显示，联系线数据还在")
        XCTAssertTrue(doc.isDocumentEdited)
        // 撤销别的修改时，联系线保持隐藏
        step { editor.setTitle(a, "新标题") }
        doc.undoManager?.undo()
        XCTAssertTrue(editor.map.relationshipsHidden)
        // 随文件保存；显示状态不写这个字段
        let data = try DocumentContent(map: editor.map, view: nil).encoded()
        XCTAssertTrue(try DocumentContent.decode(data).map.relationshipsHidden)
        // 新建联系线时自动显示
        step { editor.addRelationship(from: b, to: a) }
        XCTAssertFalse(editor.map.relationshipsHidden)
        XCTAssertEqual(editor.layout.relationships.count, 2)
        let shown = try DocumentContent(map: editor.map, view: nil).encoded()
        XCTAssertFalse(String(decoding: shown, as: UTF8.self).contains("relationshipsHidden"))
    }

    /// 联系线标签自动避让：同样两端的几条联系线，标签沿各自的曲线错开，互不重叠；
    /// 固定过位置的标签不动，其他标签让开；重置弧度后回到自动放置。
    func testRelationshipLabelsAvoidEachOther() throws {
        let a = editor.map.root.children[0].id, b = editor.map.root.children[2].id
        for title in ["关系一", "关系二", "关系三"] {
            step { editor.addRelationship(from: a, to: b) }
            let id = try XCTUnwrap(editor.selectedRelationship)
            step { editor.updateRelationship(id, actionName: "Label") { $0.title = title } }
        }
        func labels() -> [(t: CGFloat, rect: CGRect)] {
            editor.layout.relationships.compactMap { r in r.labelRect.map { (r.labelT, $0) } }
        }
        var placed = labels()
        XCTAssertEqual(placed.count, 3)
        XCTAssertEqual(placed[0].t, 0.5, "第一条标签在中点")
        for i in placed.indices {
            for j in placed.indices where j > i {
                XCTAssertFalse(placed[i].rect.intersects(placed[j].rect), "标签 \(i) 和 \(j) 重叠")
            }
        }

        // 第二条固定在中点：它不动，第一条让开
        let second = editor.map.relationships[1].id
        step { editor.updateRelationship(second, actionName: "Pin") { $0.labelPosition = 0.5 } }
        placed = labels()
        XCTAssertEqual(placed[1].t, 0.5)
        XCTAssertNotEqual(placed[0].t, 0.5)
        XCTAssertFalse(placed[0].rect.intersects(placed[1].rect))

        step { editor.resetRelationshipShape(second) }
        XCTAssertNil(editor.map.relationships[1].labelPosition)
        XCTAssertEqual(labels()[0].t, 0.5)
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
        rel.labelPosition = 0.3
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
