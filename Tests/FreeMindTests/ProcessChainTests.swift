import XCTest
@testable import FreeMind

/// 流程串结构：阶段横排、箭头依次串联、细节挂在各阶段下面。
final class ProcessChainTests: XCTestCase {
    private static func sampleMap() -> MindMap {
        MindMap(root: Topic(title: "流程", children: [
            Topic(title: "需求分析", children: [
                Topic(title: "结构化分析", children: [Topic(title: "数据流图"), Topic(title: "数据字典")]),
                Topic(title: "产出：需求规格说明书"),
            ]),
            Topic(title: "设计", children: [
                Topic(title: "这一条细节特别长，比阶段标题宽得多，会把这一列撑宽，下一列要让开"),
            ]),
            Topic(title: "测试"),
            Topic(title: "维护", children: [Topic(title: "四类维护")]),
        ]), structure: .process)
    }

    private func layout(_ map: MindMap) -> MapLayout {
        LayoutEngine(map: map, measurer: TopicMeasurer()).run()
    }

    func testStagesInARowWithDetailsBelow() throws {
        let map = Self.sampleMap()
        let layout = layout(map)
        let root = try XCTUnwrap(layout.nodes[map.root.id])
        let stages = try map.root.children.map { try XCTUnwrap(layout.nodes[$0.id]) }

        var columnRight = root.frame.maxX
        for (stage, topic) in zip(stages, map.root.children) {
            XCTAssertEqual(stage.side, .chain)
            // 所有阶段在同一条水平线上，按顺序从左往右，不压到前一列
            XCTAssertEqual(stage.frame.midY, root.frame.midY, accuracy: 0.5)
            XCTAssertGreaterThan(stage.frame.minX, columnRight)
            // 细节都在阶段下面、阶段左边线的右侧
            for id in descendants(of: topic) {
                let detail = try XCTUnwrap(layout.nodes[id])
                XCTAssertEqual(detail.side, .tree)
                XCTAssertGreaterThan(detail.frame.minY, stage.frame.maxY)
                XCTAssertGreaterThan(detail.frame.minX, stage.frame.minX)
            }
            columnRight = stage.subtreeBounds.maxX
        }
        // 第二列被长细节撑宽：第三个阶段要排在这条细节的右边
        let longDetail = try XCTUnwrap(layout.nodes[map.root.children[1].children[0].id])
        XCTAssertGreaterThan(longDetail.frame.maxX, stages[1].frame.maxX)
        XCTAssertGreaterThan(stages[2].frame.minX, longDetail.frame.maxX)
    }

    func testArrowsChainTheStagesInOrder() throws {
        let map = Self.sampleMap()
        let layout = layout(map)
        let chain = layout.connectors.filter { $0.orientation == .chain }
        XCTAssertEqual(chain.map(\.childID), map.root.children.map(\.id))

        // 第一支箭头从中心主题出发，之后每一支从上一个阶段出发，指向下一个阶段的左边
        var previous = try XCTUnwrap(layout.nodes[map.root.id])
        for c in chain {
            let stage = try XCTUnwrap(layout.nodes[c.childID])
            XCTAssertEqual(c.from.x, previous.frame.maxX, accuracy: 0.5)
            XCTAssertEqual(c.to.x, stage.frame.minX, accuracy: 0.5)
            XCTAssertEqual(c.from.y, c.to.y, accuracy: 0.5)
            previous = stage
        }
        // 细节仍然用树状连线，从各自的阶段出发
        let detail = map.root.children[0].children[0].id
        XCTAssertEqual(layout.connectors.first { $0.childID == detail }?.orientation, .tree)
        XCTAssertEqual(layout.connectors.first { $0.childID == detail }?.parentID, map.root.children[0].id)
    }

    func testCollapsedStageKeepsItsColumnNarrow() throws {
        var map = Self.sampleMap()
        map.root.children[1].collapsed = true
        let layout = layout(map)
        let design = try XCTUnwrap(layout.nodes[map.root.children[1].id])
        let test = try XCTUnwrap(layout.nodes[map.root.children[2].id])
        XCTAssertNil(layout.nodes[map.root.children[1].children[0].id])
        // 折叠按钮在阶段下方，不压在左右的箭头上
        XCTAssertGreaterThan(design.foldCenter.y, design.frame.maxY)
        XCTAssertLessThan(test.frame.minX - design.frame.maxX, 120)
    }

    func testArrowKeysMoveAlongTheChain() throws {
        let doc = MindMapDocument()
        let editor = doc.editor
        editor.load(Self.sampleMap())
        let stages = editor.map.root.children.map(\.id)

        editor.select(editor.rootID)
        editor.navigate(.right)
        XCTAssertEqual(editor.selection, [stages[0]])
        editor.navigate(.right)
        XCTAssertEqual(editor.selection, [stages[1]])
        editor.navigate(.left)
        XCTAssertEqual(editor.selection, [stages[0]])
        // 向下进入细节，细节向左回到阶段
        editor.navigate(.down)
        XCTAssertEqual(editor.selection, [editor.map.root.children[0].children[0].id])
        editor.navigate(.left)
        XCTAssertEqual(editor.selection, [stages[0]])
        // 第一个阶段向左回到中心主题
        editor.navigate(.left)
        XCTAssertEqual(editor.selection, [editor.rootID])
    }

    func testStructureSurvivesSaveAndLoad() throws {
        let data = try DocumentContent(map: Self.sampleMap(), view: nil).encoded()
        XCTAssertEqual(try DocumentContent.decode(data).map.structure, .process)
        XCTAssertEqual(XMindImporter.structure(from: "org.xmind.ui.timeline.horizontal"), .process)
    }

    private func descendants(of topic: Topic) -> [UUID] {
        topic.children.flatMap { [$0.id] + descendants(of: $0) }
    }
}
