import AppKit
import QuickLookUI

/// Finder 里按空格预览 .fmind：可以拖动、缩放的导图（视图型预览，QLIsDataBasedPreview = false）。
/// 打开时缩放到放得下整张图，但不小于 50%：导图太大时缩到一屏字就看不清了，这时以中心主题为准显示一部分，拖动查看其余部分。
/// 按住拖动平移，双指滚动平移，捏合或 ⌘ + 滚轮缩放。双击由 Quick Look 面板处理（用 FreeMind 打开文件），扩展收不到。
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let scrollView = PreviewScrollView()
    private var canvas: MapExportView?
    /// 最近一次自动缩放的比例。比例没被用户改过时，窗口大小变化（拉大、全屏）后重新缩放。
    private var autoZoom: CGFloat?

    /// 打开预览时的最小缩放比例。
    private static let readableZoom: CGFloat = 0.5
    /// 导图四周的空白（布局坐标），同编辑画布：整张图都在窗口里时也能拖动。
    private static let padding: CGFloat = 640
    /// 缩放到放得下整张图时，导图四周留的边距。
    private static let fitMargin: CGFloat = 40

    override func loadView() {
        scrollView.contentView = CenteringClipView()
        // 不显示滚动条：四周有拖动用的空白，内容总比窗口大，滚动条会一直显示；拖动和双指滚动就够了
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        // 导图是二维画布，触控板滚动不锁定方向
        scrollView.usesPredominantAxisScrolling = false
        scrollView.allowsMagnification = true
        scrollView.maxMagnification = 4
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.documentCursor = .openHand
        view = scrollView
    }

    func preparePreviewOfFile(at url: URL) async throws {
        // 读包和排版放到后台，大导图不会卡住预览窗口
        let preview = try await Task.detached(priority: .userInitiated) { try MapPreviewLoader.load(url) }.value
        let images = preview.images
        let canvas = MapExportView(layout: preview.layout, images: { images[$0] }, margin: Self.padding)
        self.canvas = canvas
        scrollView.backgroundColor = preview.layout.background
        scrollView.documentView = canvas
        // 预览窗口按导图大小打开（Quick Look 会限制在屏幕范围内）
        preferredContentSize = mapSize(canvas)
        zoomToFit()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let untouched = autoZoom.map { abs(scrollView.magnification - $0) < 0.0001 } ?? false
        if untouched {
            zoomToFit()
        } else if let fit = fitMagnification() {
            // 窗口变大后，最小比例跟着变大
            scrollView.minMagnification = min(1, fit)
            if scrollView.magnification < scrollView.minMagnification {
                scrollView.magnification = scrollView.minMagnification
            }
        }
    }

    /// 导图本身加上边距的大小（不含四周用来拖动的空白）。
    private func mapSize(_ canvas: MapExportView) -> CGSize {
        canvas.mapLayout.bounds.insetBy(dx: -Self.fitMargin, dy: -Self.fitMargin).size
    }

    /// 整张图正好放得下时的缩放比例；还没有布局时为 nil。
    private func fitMagnification() -> CGFloat? {
        guard let canvas else { return nil }
        let available = scrollView.bounds.size
        let map = mapSize(canvas)
        guard available.width > 1, available.height > 1, map.width > 0, map.height > 0 else { return nil }
        return min(available.width / map.width, available.height / map.height)
    }

    /// 缩放到放得下整张图（最大 100%，最小 readableZoom），以中心主题为准居中。
    /// 同时把最小比例设为整张图正好放得下（小导图就是 100%）：再小没有意义，缩过头了也不好找回来。
    private func zoomToFit() {
        guard let canvas else { return }
        if let fit = fitMagnification() {
            scrollView.minMagnification = min(1, fit)
            scrollView.magnification = min(1, max(Self.readableZoom, fit))
        }
        autoZoom = scrollView.magnification
        let layout = canvas.mapLayout
        if let root = layout.node(layout.rootID) {
            center(on: CGPoint(x: root.frame.midX + canvas.offset.x, y: root.frame.midY + canvas.offset.y))
        } else {
            center(on: CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY))
        }
    }

    /// 把画布上的点（视图坐标）移到可视区域中间，超出内容边缘的部分由 clip view 收回。
    private func center(on point: CGPoint) {
        let clip = scrollView.contentView
        let size = clip.bounds.size
        let proposed = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
        scrollView.reflectScrolledClipView(clip)
    }
}

/// 预览的滚动视图：按住拖动平移，⌘ + 滚轮缩放。
/// 放在滚动视图上而不是画布上：导图缩到比窗口小以后，鼠标在导图外面的空白处也能拖动、缩放。
final class PreviewScrollView: NSScrollView {
    private var panning: (start: CGPoint, origin: CGPoint)?

    // 内容区域的鼠标事件都交给滚动视图自己处理
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    // 按住拖动是平移导图，不是拖动预览窗口
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        panning = (event.locationInWindow, contentView.bounds.origin)
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pan = panning else { return }
        // 视图坐标会随滚动变化，所以用窗口坐标计算位移（窗口 y 向上，画布 y 向下）。
        let now = event.locationInWindow
        let origin = CGPoint(x: pan.origin.x - (now.x - pan.start.x) / magnification,
                             y: pan.origin.y + (now.y - pan.start.y) / magnification)
        contentView.scroll(to: contentView.constrainBoundsRect(CGRect(origin: origin, size: contentView.bounds.size)).origin)
        reflectScrolledClipView(contentView)
    }

    override func mouseUp(with event: NSEvent) {
        panning = nil
        NSCursor.openHand.set()
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command), let documentView else {
            super.scrollWheel(with: event)
            return
        }
        let dy = event.scrollingDeltaY
        guard dy != 0 else { return }
        // 鼠标滚轮每格固定缩放 10%（滚得快时系统给的滚动量很大，按滚动量算会一下缩过头）；触控板按滑动距离连续缩放
        let factor = event.hasPreciseScrollingDeltas ? pow(1.005, dy) : (dy > 0 ? 1.1 : 1 / 1.1)
        let newMag = max(minMagnification, min(maxMagnification, magnification * factor))
        setMagnification(newMag, centeredAt: documentView.convert(event.locationInWindow, from: nil))
    }
}
