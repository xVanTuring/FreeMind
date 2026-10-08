import AppKit

/// 导入 XMind 文件（.xmind 是 zip 包）。支持新版（content.json）和 XMind 8（content.xml）。
/// 每个画布（sheet）导入为一张独立的导图。
enum XMindImporter {
    static func importFile(at url: URL) throws -> [ImportResult] {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreeMind-XMind-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", url.path, dir.path]
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw importError(L("The XMind file could not be unpacked."))
        }

        let json = dir.appendingPathComponent("content.json")
        let xml = dir.appendingPathComponent("content.xml")
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        if FileManager.default.fileExists(atPath: json.path) {
            return try parseJSON(Data(contentsOf: json), archive: dir, fallbackTitle: fallbackTitle)
        }
        if FileManager.default.fileExists(atPath: xml.path) {
            return try parseXML(Data(contentsOf: xml), archive: dir, fallbackTitle: fallbackTitle)
        }
        throw importError(L("This file does not look like an XMind workbook."))
    }

    /// 读取压缩包内的资源。路径必须解析到解压目录之内（拒绝 `../` 和指向外部的符号链接）。
    static func archiveFile(_ path: String, in archive: URL) -> Data? {
        let decoded = path.removingPercentEncoding ?? path
        let base = archive.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let url = archive.appendingPathComponent(decoded).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(base),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func importError(_ message: String) -> NSError {
        NSError(domain: "FreeMind", code: 20, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // MARK: - 新版 JSON

    private static func parseJSON(_ data: Data, archive: URL, fallbackTitle: String) throws -> [ImportResult] {
        guard let sheets = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw importError(L("This file does not look like an XMind workbook."))
        }
        var results: [ImportResult] = []
        for sheet in sheets {
            guard let rootDict = sheet["rootTopic"] as? [String: Any] else { continue }
            var resources: [UUID: ResourceFile] = [:]
            var idMap: [String: UUID] = [:]
            let root = topic(fromJSON: rootDict, archive: archive, resources: &resources, idMap: &idMap)
            var map = MindMap(root: root, structure: structure(from: rootDict["structureClass"] as? String),
                              theme: Preferences.shared.defaultTheme)
            map.root.collapsed = false
            for rel in (sheet["relationships"] as? [[String: Any]]) ?? [] {
                guard let a = (rel["end1Id"] as? String).flatMap({ idMap[$0] }),
                      let b = (rel["end2Id"] as? String).flatMap({ idMap[$0] }), a != b else { continue }
                map.relationships.append(Relationship(from: a, to: b, title: (rel["title"] as? String) ?? ""))
            }
            let title = (sheet["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle
            results.append(ImportResult(map: map, resources: resources, title: title))
        }
        guard !results.isEmpty else { throw importError(L("The XMind file contains no maps.")) }
        return results
    }

    private static func topic(fromJSON dict: [String: Any], archive: URL, resources: inout [UUID: ResourceFile],
                              idMap: inout [String: UUID]) -> Topic {
        var t = Topic(title: (dict["title"] as? String) ?? "")
        if let xmindID = dict["id"] as? String { idMap[xmindID] = t.id }
        if let notes = dict["notes"] as? [String: Any],
           let plain = notes["plain"] as? [String: Any], let content = plain["content"] as? String {
            t.note = content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let href = dict["href"] as? String {
            if href.hasPrefix("xap:") {
                let path = String(href.dropFirst(4))
                if let data = archiveFile(path, in: archive) {
                    let id = UUID()
                    let name = (dict["title"] as? String).flatMap { $0.contains(".") ? $0 : nil } ?? (path as NSString).lastPathComponent
                    resources[id] = ResourceFile(name: name, data: data)
                    t.attachments.append(Attachment(id: id, name: AttachmentStore.sanitize(name), size: Int64(data.count)))
                }
            } else if !href.hasPrefix("xmind:") {
                t.link = href
            }
        }
        if let labels = dict["labels"] as? [String] { t.labels = labels }
        if let markers = dict["markers"] as? [[String: Any]] {
            t.markers = convertMarkers(markers.compactMap { $0["markerId"] as? String })
        }
        if (dict["branch"] as? String) == "folded" { t.collapsed = true }
        if let image = dict["image"] as? [String: Any], let src = image["src"] as? String, src.hasPrefix("xap:") {
            let path = String(src.dropFirst(4))
            if let data = archiveFile(path, in: archive), let img = NSImage(data: data) {
                let id = UUID()
                let name = (path as NSString).lastPathComponent
                resources[id] = ResourceFile(name: name, data: data)
                var w = (image["width"] as? Double) ?? Double(img.size.width)
                var h = (image["height"] as? Double) ?? Double(img.size.height)
                let longest = max(w, h, 1)
                if longest > 300 { w = w * 300 / longest; h = h * 300 / longest }
                t.image = TopicImage(id: id, name: name, width: w.rounded(), height: h.rounded())
            }
        }
        if let children = dict["children"] as? [String: Any] {
            let attached = (children["attached"] as? [[String: Any]]) ?? []
            // 自由主题（detached）没有对应概念，挂到中心主题末尾
            let detached = (children["detached"] as? [[String: Any]]) ?? []
            t.children = (attached + detached).map { topic(fromJSON: $0, archive: archive, resources: &resources, idMap: &idMap) }
        }
        return t
    }

    // MARK: - XMind 8 XML

    private static func parseXML(_ data: Data, archive: URL, fallbackTitle: String) throws -> [ImportResult] {
        let doc = try XMLDocument(data: data, options: [])
        guard let root = doc.rootElement() else { throw importError(L("This file does not look like an XMind workbook.")) }
        var results: [ImportResult] = []
        for sheet in root.children?.compactMap({ $0 as? XMLElement }).filter({ $0.localName == "sheet" }) ?? [] {
            guard let topicElement = child(sheet, "topic") else { continue }
            var resources: [UUID: ResourceFile] = [:]
            let rootTopic = topic(fromXML: topicElement, archive: archive, resources: &resources)
            var map = MindMap(root: rootTopic,
                              structure: structure(from: topicElement.attribute(forName: "structure-class")?.stringValue),
                              theme: Preferences.shared.defaultTheme)
            map.root.collapsed = false
            let title = child(sheet, "title")?.stringValue ?? fallbackTitle
            results.append(ImportResult(map: map, resources: resources, title: title))
        }
        guard !results.isEmpty else { throw importError(L("The XMind file contains no maps.")) }
        return results
    }

    private static func child(_ e: XMLElement, _ name: String) -> XMLElement? {
        e.children?.compactMap { $0 as? XMLElement }.first { $0.localName == name }
    }

    private static func children(_ e: XMLElement, _ name: String) -> [XMLElement] {
        e.children?.compactMap { $0 as? XMLElement }.filter { $0.localName == name } ?? []
    }

    private static func topic(fromXML e: XMLElement, archive: URL, resources: inout [UUID: ResourceFile]) -> Topic {
        var t = Topic(title: child(e, "title")?.stringValue ?? "")
        if let notes = child(e, "notes"), let plain = child(notes, "plain") {
            t.note = (plain.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let href = e.attributes?.first(where: { $0.localName == "href" })?.stringValue {
            if href.hasPrefix("xap:") {
                let path = String(href.dropFirst(4))
                if let data = archiveFile(path, in: archive) {
                    let id = UUID()
                    let name = t.title.contains(".") ? t.title : (path as NSString).lastPathComponent
                    resources[id] = ResourceFile(name: name, data: data)
                    t.attachments.append(Attachment(id: id, name: AttachmentStore.sanitize(name), size: Int64(data.count)))
                }
            } else if !href.hasPrefix("xmind:") {
                t.link = href
            }
        }
        if let labels = child(e, "labels") {
            t.labels = children(labels, "label").compactMap { $0.stringValue }
        }
        if let refs = child(e, "marker-refs") {
            t.markers = convertMarkers(children(refs, "marker-ref").compactMap { $0.attribute(forName: "marker-id")?.stringValue })
        }
        if e.attribute(forName: "branch")?.stringValue == "folded" { t.collapsed = true }
        if let c = child(e, "children") {
            for topics in children(c, "topics") {
                t.children += children(topics, "topic").map { topic(fromXML: $0, archive: archive, resources: &resources) }
            }
        }
        return t
    }

    // MARK: - 映射

    static func structure(from xmindClass: String?) -> MapStructure {
        guard let c = xmindClass else { return .mindMap }
        if c.contains("logic.left") { return .logicLeft }
        if c.contains("logic") { return .logicRight }
        if c.contains("org-chart") { return .orgChart }
        if c.contains("tree") { return .tree }
        return .mindMap
    }

    static func convertMarkers(_ ids: [String]) -> [MarkerID] {
        var result: [MarkerID] = []
        for id in ids {
            var mapped: String?
            if id.hasPrefix("priority-"), let n = Int(id.dropFirst(9)) {
                mapped = "priority-\(min(max(n, 1), 6))"
            } else if id.hasPrefix("task-") {
                let table: [String: Int] = ["start": 0, "oct": 25, "quarter": 25, "3oct": 50, "half": 50,
                                            "5oct": 50, "3quar": 75, "7oct": 75, "done": 100]
                if let p = table[String(id.dropFirst(5))] { mapped = "task-\(p)" }
            } else if id.hasPrefix("flag-") || id.hasPrefix("star-") {
                let prefix = String(id.prefix(4))
                let color = String(id.dropFirst(5))
                let table: [String: String] = ["red": "red", "orange": "orange", "yellow": "yellow", "green": "green",
                                               "blue": "blue", "dark-blue": "blue", "purple": "purple", "gray": "gray",
                                               "black": "gray"]
                if let c = table[color] { mapped = "\(prefix)-\(c)" }
            } else if id.hasPrefix("symbol-") {
                let table: [String: String] = ["question": "question", "exclam": "important", "attention": "important",
                                               "wrong": "cross", "right": "check", "idea": "idea", "info": "idea",
                                               "heart": "heart", "thumbs-up": "like", "thumbs-down": "dislike",
                                               "pin": "pin", "time": "time", "money": "money"]
                if let k = table[String(id.dropFirst(7))] { mapped = "symbol-\(k)" }
            } else if id.hasPrefix("people-") {
                mapped = "symbol-person"
            } else if id == "other-question" {
                mapped = "symbol-question"
            }
            if let mapped {
                result = MarkerCatalog.toggle(MarkerID(mapped), in: result.filter { $0.rawValue != mapped })
            }
        }
        return result
    }
}
