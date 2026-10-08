import AppKit
import UniformTypeIdentifiers

/// 复制 / 粘贴。剪贴板同时写入：
/// - 自有类型（完整主题树 + 附件数据，可以跨文档粘贴）
/// - 纯文本（Markdown 列表，粘贴到其他应用时可读）
extension MapEditor {
    static let topicsPasteboardType = NSPasteboard.PasteboardType("tech.xvanturing.freemind.topics")

    /// 跨文档共享的“复制样式”。
    static var styleClipboard: TopicStyle?

    private struct ClipboardPayload: Codable {
        var topics: [Topic]
        var resources: [String: ResourceFile]
    }

    func copySelection(to pasteboard: NSPasteboard) {
        let ids = map.topmost(selection)
        let topics = ids.compactMap { map.topic($0) }
        guard !topics.isEmpty else { return }
        var resources: [String: ResourceFile] = [:]
        var total = 0
        if let store = attachments {
            for id in topics.reduce(into: Set<UUID>(), { $0.formUnion($1.resourceIDs()) }) {
                guard let data = store.data(for: id), let name = store.fileName(for: id) else { continue }
                // 剪贴板总量上限 512MB。超出的附件不放进剪贴板：同一文档内粘贴不受影响（资源还在），
                // 粘贴到其他文档时会去掉这些引用并提示。
                guard total + data.count <= 512 * 1024 * 1024 else { continue }
                total += data.count
                resources[id.uuidString] = ResourceFile(name: name, data: data)
            }
        }
        pasteboard.clearContents()
        if let data = try? JSONEncoder().encode(ClipboardPayload(topics: topics, resources: resources)) {
            pasteboard.setData(data, forType: Self.topicsPasteboardType)
        }
        pasteboard.setString(MarkdownExporter.outline(topics), forType: .string)
    }

    func canPaste(from pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        return types.contains(Self.topicsPasteboardType) || types.contains(.string) || types.contains(.fileURL)
            || types.contains(.png) || types.contains(.tiff)
    }

    /// 粘贴到当前选中的主题下。
    func paste(from pasteboard: NSPasteboard) throws {
        let target = primaryID ?? rootID
        let types = pasteboard.types ?? []

        if types.contains(Self.topicsPasteboardType), let data = pasteboard.data(forType: Self.topicsPasteboardType),
           let payload = try? JSONDecoder().decode(ClipboardPayload.self, from: data) {
            var missing = Set<UUID>()
            if let store = attachments {
                for (key, file) in payload.resources {
                    if let id = UUID(uuidString: key), !store.contains(id) { store.add(data: file.data, name: file.name, id: id) }
                }
                for t in payload.topics { missing.formUnion(t.resourceIDs().filter { !store.contains($0) }) }
            }
            var topics = payload.topics.map { $0.withFreshIDs() }
            if !missing.isEmpty {
                // 去掉找不到文件的附件 / 图片引用，避免留下打不开的坏链接
                for i in topics.indices {
                    topics[i].mutateAll { t in
                        t.attachments.removeAll { missing.contains($0.id) }
                        if let image = t.image, missing.contains(image.id) { t.image = nil }
                    }
                }
            }
            insertTopics(topics, into: target, actionName: L("Paste"))
            if !missing.isEmpty {
                throw NSError(domain: "FreeMind", code: 30, userInfo: [
                    NSLocalizedDescriptionKey: L("Some attachments were too large to copy and were left out."),
                    NSLocalizedRecoverySuggestionErrorKey: L("Attach those files to the pasted topics again."),
                ])
            }
            return
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            try addAttachments(urls, to: target)
            return
        }

        if types.contains(.png) || types.contains(.tiff), !types.contains(.string),
           let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
           let image = NSImage(data: data), let png = image.pngData {
            let name = L("Pasted Image") + ".png"
            if map.topic(target)?.image == nil {
                setImage(data: png, name: name, for: target)
            } else {
                // 已经有图片：新建一个子主题放图片
                let topic = Topic(title: L("Image"))
                insertTopics([topic], into: target, actionName: L("Paste"))
                setImage(data: png, name: name, for: topic.id)
            }
            return
        }

        if let string = pasteboard.string(forType: .string) {
            let topics = MarkdownImporter.parseFragment(string)
            guard !topics.isEmpty else { return }
            insertTopics(topics, into: target, actionName: L("Paste"))
        }
    }

    /// 复制一份选中主题，放在原主题后面（⌘D）。
    func duplicateSelection() {
        let ids = map.topmost(selection).filter { $0 != rootID }
        guard !ids.isEmpty else { return }
        var newIDs: [UUID] = []
        perform(L("Duplicate"), select: nil) { m in
            for id in ids {
                guard let topic = m.topic(id), let parent = m.parentID(of: id), let index = m.path(of: id)?.last else { continue }
                let copy = topic.withFreshIDs()
                newIDs.append(copy.id)
                m.insert(copy, into: parent, at: index + 1)
            }
        }
        setSelection(newIDs)
        if let last = newIDs.last { delegate?.editor(self, reveal: last) }
    }
}

extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
