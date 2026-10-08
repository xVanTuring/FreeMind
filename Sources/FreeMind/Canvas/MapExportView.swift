import AppKit

/// 把整张导图画出来的视图（打印、导出 PDF/PNG、Quick Look 预览用）。
final class MapExportView: NSView {
    let mapLayout: MapLayout
    let images: (UUID) -> NSImage?
    let margin: CGFloat
    var transparent = false

    init(layout: MapLayout, images: @escaping (UUID) -> NSImage?, margin: CGFloat = 40) {
        self.mapLayout = layout
        self.images = images
        self.margin = margin
        let size = CGSize(width: ceil(layout.bounds.width + margin * 2), height: ceil(layout.bounds.height + margin * 2))
        super.init(frame: CGRect(origin: .zero, size: size))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if !transparent {
            ctx.setFillColor(mapLayout.background.cgColor)
            ctx.fill(bounds)
        }
        ctx.saveGState()
        ctx.translateBy(x: margin - mapLayout.bounds.minX, y: margin - mapLayout.bounds.minY)
        MapRenderer(layout: mapLayout, images: images).draw(in: mapLayout.bounds.insetBy(dx: -margin, dy: -margin),
                                                            drawBackground: false)
        ctx.restoreGState()
    }
}

enum ImageExporter {
    static func pngData(layout: MapLayout, images: @escaping (UUID) -> NSImage?, scale: CGFloat = 2,
                        transparent: Bool = false) -> Data? {
        let view = MapExportView(layout: layout, images: images)
        view.transparent = transparent
        let size = view.bounds.size
        // 超大导图限制像素数，避免生成几百 MB 的位图
        let maxPixels: CGFloat = 16384
        let s = min(scale, maxPixels / max(size.width, 1), maxPixels / max(size.height, 1))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(size.width * s), pixelsHigh: Int(size.height * s),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    static func pdfData(layout: MapLayout, images: @escaping (UUID) -> NSImage?) -> Data {
        let view = MapExportView(layout: layout, images: images)
        return view.dataWithPDF(inside: view.bounds)
    }

    /// 生成缩略图（模板库预览、Finder 缩略图用）。
    static func thumbnail(layout: MapLayout, images: @escaping (UUID) -> NSImage? = { _ in nil },
                          size: CGSize) -> NSImage {
        let view = MapExportView(layout: layout, images: images, margin: 30)
        let full = view.bounds.size
        return NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(layout.background.cgColor)
            ctx.fill(rect)
            let scale = min(rect.width / full.width, rect.height / full.height, 1)
            ctx.translateBy(x: (rect.width - full.width * scale) / 2, y: (rect.height - full.height * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)
            view.draw(view.bounds)
            return true
        }
    }
}
