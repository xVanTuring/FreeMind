import AppKit

/// 画布右下角的缩略图：整张导图的缩影 + 当前可视范围框，点击 / 拖动可快速定位。
final class MinimapView: NSView {
    static let size = CGSize(width: 200, height: 140)
    private static let inset: CGFloat = 8

    private weak var canvas: MindMapCanvasView?
    private var cache: NSImage?
    private var cacheWorld: CGRect = .zero
    /// 拖动视口框时，按下位置相对视口中心的偏移（布局坐标）。
    private var grabOffset: CGPoint = .zero

    init(canvas: MindMapCanvasView) {
        self.canvas = canvas
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        toolTip = L("Minimap")
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// 导图内容变了（布局、主题），下次绘制重建缩影。
    func invalidate() {
        cache = nil
        needsDisplay = true
    }

    // MARK: 坐标

    /// 视口在布局坐标里的范围。
    private var viewport: CGRect {
        guard let canvas else { return .zero }
        let r = canvas.visibleRect
        let origin = canvas.layoutPoint(r.origin)
        return CGRect(origin: origin, size: r.size)
    }

    /// 缩略图覆盖的布局范围：整张导图，视口拖到外面时也要包含视口。
    private var world: CGRect {
        guard let canvas else { return .zero }
        let content = canvas.mapLayout.bounds.insetBy(dx: -40, dy: -40)
        return content.union(viewport)
    }

    private func transform(for world: CGRect) -> (scale: CGFloat, origin: CGPoint) {
        let avail = CGSize(width: bounds.width - Self.inset * 2, height: bounds.height - Self.inset * 2)
        let scale = min(avail.width / max(world.width, 1), avail.height / max(world.height, 1))
        let origin = CGPoint(x: (bounds.width - world.width * scale) / 2 - world.minX * scale,
                             y: (bounds.height - world.height * scale) / 2 - world.minY * scale)
        return (scale, origin)
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let canvas, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let layout = canvas.mapLayout
        let world = self.world
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)

        ctx.saveGState()
        shape.addClip()
        ctx.setFillColor(layout.background.withAlphaComponent(0.94).cgColor)
        ctx.fill(bounds)
        if cache == nil || cacheWorld != world { cache = renderContent(layout, world: world) }
        cache?.draw(in: bounds)

        // 视口框
        let (scale, origin) = transform(for: world)
        let vp = viewport
        let box = CGRect(x: vp.minX * scale + origin.x, y: vp.minY * scale + origin.y,
                         width: vp.width * scale, height: vp.height * scale)
        let accent = NSColor.controlAccentColor
        ctx.setFillColor(accent.withAlphaComponent(0.14).cgColor)
        ctx.fill(box)
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(box.insetBy(dx: 0.75, dy: 0.75))
        ctx.restoreGState()

        let edge = layout.isDarkBackground ? NSColor.white.withAlphaComponent(0.25) : NSColor.black.withAlphaComponent(0.25)
        edge.setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }

    /// 把整张导图画成简化的色块和连线（不画文字），缓存成图片，滚动时只重画视口框。
    /// backingScale 默认取窗口的（测试里指定）。
    func renderContent(_ layout: MapLayout, world: CGRect, backingScale: CGFloat? = nil) -> NSImage {
        cacheWorld = world
        let scale = backingScale ?? window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixels = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return NSImage(size: bounds.size) }
        // 必须先设好点尺寸再建上下文：上下文按 rep.size 把坐标换算成像素，建好之后再改 size 不起作用，
        // 坐标会变成像素，Retina 屏上缩影只有一半大而且偏到左下角
        rep.size = bounds.size
        guard let gc = NSGraphicsContext(bitmapImageRep: rep) else { return NSImage(size: bounds.size) }
        let (s, o) = transform(for: world)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        let ctx = gc.cgContext
        // 位图坐标 y 向上，翻成和视图一致的 y 向下
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)

        ctx.setLineCap(.round)
        for c in layout.connectors {
            ctx.setStrokeColor(c.color.withAlphaComponent(0.7).cgColor)
            ctx.setLineWidth(max(0.6, min(c.width * s, 1.5)))
            ctx.move(to: CGPoint(x: c.from.x * s + o.x, y: c.from.y * s + o.y))
            ctx.addLine(to: CGPoint(x: c.to.x * s + o.x, y: c.to.y * s + o.y))
            ctx.strokePath()
        }
        for id in layout.order {
            guard let n = layout.nodes[id] else { continue }
            let color = n.style.fill ?? n.style.border ?? n.style.branchColor
            var r = CGRect(x: n.frame.minX * s + o.x, y: n.frame.minY * s + o.y,
                           width: n.frame.width * s, height: n.frame.height * s)
            // 小导图放大后色块不要太大，大导图缩小后也要看得见
            r.size.width = max(r.width, 1.5)
            r.size.height = max(r.height, 1.5)
            ctx.setFillColor((n.style.fill == nil ? color.withAlphaComponent(0.65) : color).cgColor)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(2, r.height / 2), cornerHeight: min(2, r.height / 2), transform: nil))
            ctx.fillPath()
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: 交互

    override func mouseDown(with event: NSEvent) {
        let p = layoutPoint(for: event)
        let vp = viewport
        if vp.contains(p) {
            grabOffset = CGPoint(x: p.x - vp.midX, y: p.y - vp.midY)
        } else {
            grabOffset = .zero
            scroll(to: p)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        scroll(to: layoutPoint(for: event))
    }

    private func layoutPoint(for event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        let (scale, origin) = transform(for: world)
        return CGPoint(x: (local.x - origin.x) / scale, y: (local.y - origin.y) / scale)
    }

    private func scroll(to p: CGPoint) {
        guard let canvas else { return }
        // 拖动期间 world 会随视口变化，限制在导图范围内，避免越拖越远
        let bounds = canvas.mapLayout.bounds
        let target = CGPoint(x: min(max(p.x - grabOffset.x, bounds.minX), bounds.maxX),
                             y: min(max(p.y - grabOffset.y, bounds.minY), bounds.maxY))
        canvas.center(onLayoutPoint: target)
        needsDisplay = true
    }

    /// 在缩略图上滚动时交给画布处理。
    override func scrollWheel(with event: NSEvent) {
        canvas?.scrollWheel(with: event)
    }
}
