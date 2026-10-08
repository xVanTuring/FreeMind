import AppKit
import QuickLookUI
import UniformTypeIdentifiers

/// Finder 里按空格预览 .fmind：把整张导图渲染成矢量 PDF。
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let preview = try MapPreviewLoader.load(request.fileURL)
        let (data, size) = await MainActor.run { () -> (Data, CGSize) in
            let images = preview.images
            let view = MapExportView(layout: preview.layout, images: { images[$0] })
            return (view.dataWithPDF(inside: view.bounds), view.bounds.size)
        }
        return QLPreviewReply(dataOfContentType: .pdf, contentSize: size) { _ in data }
    }
}
