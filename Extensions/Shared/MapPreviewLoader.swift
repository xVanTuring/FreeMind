import AppKit

/// Quick Look 预览 / 缩略图共用：直接从 .fmind 包里读出导图并排版。
/// 扩展运行在沙盒里，只读传进来的包，不经过 NSDocument。
enum MapPreviewLoader {
    struct Preview {
        let layout: MapLayout
        let images: [UUID: NSImage]
    }

    static func load(_ packageURL: URL) throws -> Preview {
        let data = try Data(contentsOf: packageURL.appendingPathComponent(DocumentContent.contentFileName))
        let content = try DocumentContent.decode(data)
        let attachments = packageURL.appendingPathComponent(AttachmentDirectory.name)
        var images: [UUID: NSImage] = [:]
        content.map.root.forEach { topic in
            guard let image = topic.image else { return }
            let dir = attachments.appendingPathComponent(image.id.uuidString)
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                                       options: [.skipsHiddenFiles])) ?? []
            if let file = files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first,
               let ns = NSImage(contentsOf: file) {
                images[image.id] = ns
            }
        }
        let layout = LayoutEngine(map: content.map, measurer: TopicMeasurer()).run()
        return Preview(layout: layout, images: images)
    }
}

/// 与 AttachmentStore.directoryName 保持一致（扩展不编译 AttachmentStore）。
enum AttachmentDirectory {
    static let name = "attachments"
}
