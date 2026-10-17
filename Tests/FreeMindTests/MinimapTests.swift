import XCTest
@testable import FreeMind

/// 画布右下角的缩略图。
final class MinimapTests: XCTestCase {
    /// Retina 屏上缩影曾经只画出一半大、偏到左下角（位图上下文建好后才设点尺寸，坐标成了像素）。
    func testContentFillsTheMinimapOnRetina() throws {
        let doc = MindMapDocument()
        var map = MindMap.blank(title: "Root")
        map.structure = .process
        doc.editor.load(map)
        let minimap = MinimapView(canvas: MindMapCanvasView(editor: doc.editor))
        let layout = doc.editor.layout
        let image = minimap.renderContent(layout, world: layout.bounds.insetBy(dx: -40, dy: -40), backingScale: 2)
        let rep = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(rep.pixelsWide, Int(MinimapView.size.width * 2))

        // 画了东西的像素的包围框
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        XCTAssertGreaterThan(maxX, minX)
        // 这张图又宽又矮，按宽度缩放：内容应该横向铺满缩略图（只留边距），并且上下居中
        XCTAssertGreaterThan(CGFloat(maxX - minX), CGFloat(rep.pixelsWide) * 0.75)
        XCTAssertEqual(CGFloat(minY + maxY) / 2, CGFloat(rep.pixelsHigh) / 2, accuracy: CGFloat(rep.pixelsHigh) * 0.1)
    }
}
