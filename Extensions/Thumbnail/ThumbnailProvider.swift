import AppKit
import QuickLookThumbnailing

/// Finder 里 .fmind 文件的缩略图：显示导图本身。
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        do {
            let preview = try MapPreviewLoader.load(request.fileURL)
            let bounds = preview.layout.bounds.insetBy(dx: -30, dy: -30)
            let maximum = request.maximumSize
            let scale = min(maximum.width / max(bounds.width, 1), maximum.height / max(bounds.height, 1))
            let size = CGSize(width: max(1, (bounds.width * scale).rounded()), height: max(1, (bounds.height * scale).rounded()))
            let images = preview.images
            let image = ImageExporter.thumbnail(layout: preview.layout, images: { images[$0] }, size: size)
            handler(QLThumbnailReply(contextSize: size, currentContextDrawing: {
                image.draw(in: CGRect(origin: .zero, size: size))
                return true
            }), nil)
        } catch {
            handler(nil, error)
        }
    }
}
