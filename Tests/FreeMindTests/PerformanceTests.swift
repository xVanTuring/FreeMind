import XCTest
@testable import FreeMind

final class PerformanceTests: XCTestCase {
    /// 生成约 3000 个主题的导图：12 个分支 × 15 个子主题 × 16 个孙主题。
    private func bigMap() -> MindMap {
        var root = Topic(title: "大型导图")
        for i in 0..<12 {
            var branch = Topic(title: "分支 \(i)")
            for j in 0..<15 {
                var sub = Topic(title: "子主题 \(i)-\(j) 有一段稍微长一点的文字")
                sub.children = (0..<16).map { Topic(title: "孙主题 \(i)-\(j)-\($0)") }
                branch.children.append(sub)
            }
            root.children.append(branch)
        }
        return MindMap(root: root)
    }

    func testLargeMapLayoutIsFast() {
        let map = bigMap()
        XCTAssertGreaterThan(map.topicCount, 3000)
        let measurer = TopicMeasurer()
        _ = LayoutEngine(map: map, measurer: measurer).run()  // 预热文字测量缓存
        let start = Date()
        let layout = LayoutEngine(map: map, measurer: measurer).run()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(layout.nodes.count, map.topicCount)
        XCTAssertLessThan(elapsed, 0.25, "重排 3000 个主题耗时 \(elapsed)s")
    }

    func testEditOnLargeMapIsFast() {
        let doc = MindMapDocument()
        doc.editor.load(bigMap())
        let target = doc.editor.map.root.children[5].children[7].id
        let start = Date()
        for _ in 0..<10 { doc.editor.addChild(to: target, edit: false) }
        let elapsed = Date().timeIntervalSince(start) / 10
        XCTAssertLessThan(elapsed, 0.1, "每次编辑耗时 \(elapsed)s")
    }
}
