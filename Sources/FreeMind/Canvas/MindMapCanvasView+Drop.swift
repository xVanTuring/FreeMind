import AppKit
import UniformTypeIdentifiers

/// 从 Finder / 浏览器拖进画布：
/// - 文件拖到主题上 → 作为附件（按住 ⌥ 拖一张图片 → 设为主题图片）
/// - 文件拖到空白处 → 每个文件新建一个子主题（挂在选中主题或中心主题下）
/// - 文字 → 按 Markdown / 缩进解析成主题
/// - 图片数据 → 主题图片
extension MindMapCanvasView {
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDropHighlight(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDropHighlight(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropHighlight = nil
        needsDisplay = true
    }

    private func updateDropHighlight(_ sender: NSDraggingInfo) -> NSDragOperation {
        let p = layoutPoint(convert(sender.draggingLocation, from: nil))
        let target = mapLayout.topic(at: p, slop: 6)
        if target != dropHighlight {
            dropHighlight = target
            needsDisplay = true
        }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let target = dropHighlight
        dropHighlight = nil
        needsDisplay = true
        window?.makeFirstResponder(self)

        do {
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
                try dropFiles(urls, on: target, imageMode: NSEvent.modifierFlags.contains(.option))
                return true
            }
            if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff), let image = NSImage(data: data), let png = image.pngData {
                let id = target ?? editor.primaryID ?? editor.rootID
                editor.setImage(data: png, name: L("Image") + ".png", for: id)
                return true
            }
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let url = urls.first, !url.isFileURL {
                // 网页链接：新建一个带超链接的子主题
                let parent = target ?? editor.primaryID ?? editor.rootID
                var topic = Topic(title: pb.string(forType: .string).flatMap { $0 == url.absoluteString ? nil : $0 } ?? url.host ?? url.absoluteString)
                topic.link = url.absoluteString
                editor.insertTopics([topic], into: parent, actionName: L("Add Link"))
                return true
            }
            if let string = pb.string(forType: .string) {
                let topics = MarkdownImporter.parseFragment(string)
                guard !topics.isEmpty else { return false }
                editor.insertTopics(topics, into: target ?? editor.primaryID ?? editor.rootID, actionName: L("Add Topics"))
                return true
            }
        } catch {
            presentErrorSheet(error)
        }
        return false
    }

    private func dropFiles(_ urls: [URL], on target: UUID?, imageMode: Bool) throws {
        if let target {
            if imageMode, urls.count == 1, let type = UTType(filenameExtension: urls[0].pathExtension), type.conforms(to: .image) {
                try editor.setImage(fileAt: urls[0], for: target)
            } else {
                try editor.addAttachments(urls, to: target)
            }
            return
        }
        // 拖到空白处：每个文件一个新主题
        guard let store = editor.attachments else { return }
        let parent = editor.primaryID ?? editor.rootID
        var topics: [Topic] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let attachment = try store.add(fileAt: url)
            var topic = Topic(title: url.deletingPathExtension().lastPathComponent)
            topic.attachments = [attachment]
            topics.append(topic)
        }
        editor.insertTopics(topics, into: parent, actionName: L("Add Attachments"))
    }
}
