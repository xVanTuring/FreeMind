import XCTest
@testable import FreeMind

final class SmokeTests: XCTestCase {
    func testBlankMapLayout() {
        let map = MindMap.blank()
        let layout = LayoutEngine(map: map, measurer: TopicMeasurer()).run()
        XCTAssertEqual(layout.nodes.count, 5)
    }
}
