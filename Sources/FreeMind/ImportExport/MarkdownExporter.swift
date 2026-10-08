import Foundation

struct MarkdownExportOptions: Equatable {
    /// 用标题（# ~ ######）表示的层数，中心主题算第 1 层；更深的层级用嵌套列表。
    var headingLevels: Int = 3
    var includeNotes = true
    var includeLinks = true
    var includeLabels = false
    /// 进度标记导出为 GFM 任务列表（- [x] / - [ ]），仅对列表项生效。
    var includeTaskCheckboxes = true
    /// 附件 / 图片所在的相对目录（如 `导图名.assets`）。nil 表示不导出附件引用。
    var assetsFolder: String?
}

/// 导图 → Markdown。
enum MarkdownExporter {
    struct Result {
        var text: String
        /// 资源 id → 相对路径（调用方据此把文件写到磁盘）。
        var assets: [UUID: String]
    }

    static func export(_ map: MindMap, options: MarkdownExportOptions = MarkdownExportOptions()) -> Result {
        var lines: [String] = []
        let assets = assetPaths(for: map.root, folder: options.assetsFolder)
        render(map.root, depth: 0, options: options, assets: assets, into: &lines)
        // 合并多余空行
        var output: [String] = []
        for line in lines {
            if line.isEmpty, output.last?.isEmpty ?? true { continue }
            output.append(line)
        }
        while output.last?.isEmpty == true { output.removeLast() }
        return Result(text: output.joined(separator: "\n") + "\n", assets: assets)
    }

    /// 剪贴板用：把若干主题导出成无序列表。
    static func outline(_ topics: [Topic]) -> String {
        var lines: [String] = []
        var options = MarkdownExportOptions()
        options.headingLevels = 0
        options.includeNotes = false
        for t in topics { render(t, depth: 0, options: options, assets: [:], into: &lines) }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    // MARK: - 渲染

    private static func render(_ topic: Topic, depth: Int, options: MarkdownExportOptions,
                               assets: [UUID: String], into lines: inout [String]) {
        let isHeading = depth < options.headingLevels
        var text = inlineTitle(topic, options: options, heading: isHeading)
        if options.includeLabels, !topic.labels.isEmpty {
            text += " " + topic.labels.map { "`\($0)`" }.joined(separator: " ")
        }

        let extraIndent: String
        if isHeading {
            lines.append("")
            lines.append(String(repeating: "#", count: min(depth + 1, 6)) + " " + text)
            lines.append("")
            extraIndent = ""
        } else {
            let level = depth - options.headingLevels
            let indent = String(repeating: "  ", count: level)
            var bullet = "- "
            if options.includeTaskCheckboxes, let progress = topic.markers.first(where: { $0.group == .task }) {
                bullet += progress.suffix == "100" ? "[x] " : "[ ] "
            }
            lines.append(indent + bullet + text)
            extraIndent = indent + "  "
        }

        var body: [String] = []
        if let image = topic.image, let path = assets[image.id] {
            body.append("![\(escapeLinkText(image.name))](\(encodePath(path)))")
        }
        if options.includeNotes, topic.hasNote {
            if !body.isEmpty { body.append("") }
            body.append(contentsOf: escapeNoteLines(topic.note.trimmingCharacters(in: .newlines).components(separatedBy: "\n")))
        }
        let attachmentLinks = topic.attachments.compactMap { a -> String? in
            guard let path = assets[a.id] else { return nil }
            return "📎 [\(escapeLinkText(a.name))](\(encodePath(path)))"
        }
        if !attachmentLinks.isEmpty {
            if !body.isEmpty { body.append("") }
            // 每个附件单独成段，避免被合并成一行
            for (i, link) in attachmentLinks.enumerated() {
                if i > 0 { body.append("") }
                body.append(link)
            }
        }
        if !body.isEmpty {
            if isHeading {
                lines.append(contentsOf: body)
                lines.append("")
            } else {
                lines.append("")
                lines.append(contentsOf: body.map { $0.isEmpty ? "" : extraIndent + $0 })
                lines.append("")
            }
        }

        for child in topic.children {
            render(child, depth: depth + 1, options: options, assets: assets, into: &lines)
        }
        if !isHeading, depth == options.headingLevels { lines.append("") }
    }

    private static func inlineTitle(_ topic: Topic, options: MarkdownExportOptions, heading: Bool) -> String {
        let flat = topic.title.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        var title = escape(flat.isEmpty ? " " : flat, atLineStart: true)
        if options.includeLinks, let link = topic.link, !link.isEmpty {
            // 含空格的链接（多为文件路径）用 <…> 包起来，保持原样
            let target = link.contains(" ") ? "<\(link)>" : link
            title = "[\(escapeLinkText(flat))](\(target))"
        }
        return title
    }

    /// 备注里会被误解析成标题、列表、Setext 下划线的行加反斜杠转义（代码块内不动），导入时再去掉。
    static func escapeNoteLines(_ lines: [String]) -> [String] {
        var inFence = false
        return lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                return line
            }
            guard !inFence, let first = trimmed.first else { return line }
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            let needsEscape: Bool
            if first == "#" {
                needsEscape = true
            } else if "-+*".contains(first), trimmed.count == 1 || trimmed.dropFirst().first == " " {
                needsEscape = true
            } else if trimmed.allSatisfy({ $0 == "=" }) || (trimmed.count >= 2 && trimmed.allSatisfy({ $0 == "-" })) {
                needsEscape = true
            } else if first.isNumber {
                // 有序列表：1. / 1)
                let escaped = escape(trimmed, atLineStart: true)
                return escaped == trimmed ? line : indent + escaped
            } else {
                needsEscape = false
            }
            return needsEscape ? indent + "\\" + trimmed : line
        }
    }

    /// 转义行首会被误解析成标题/列表/引用的字符。
    static func escape(_ s: String, atLineStart: Bool) -> String {
        guard atLineStart, let first = s.first else { return s }
        if "#>-+*[".contains(first) { return "\\" + s }
        // 1. 2) 这样的有序列表开头
        if let m = s.range(of: #"^\d+[.)]"#, options: .regularExpression) {
            let punct = s.index(before: m.upperBound)
            let rest = s[m.upperBound...]
            if rest.isEmpty || rest.first == " " {
                return String(s[..<punct]) + "\\" + String(s[punct...])
            }
        }
        return s
    }

    private static func escapeLinkText(_ s: String) -> String {
        s.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }

    private static func encodePath(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    }

    /// 为每个资源分配一个不冲突的相对路径。
    static func assetPaths(for root: Topic, folder: String?) -> [UUID: String] {
        guard let folder else { return [:] }
        var result: [UUID: String] = [:]
        var used = Set<String>()
        func assign(_ id: UUID, _ name: String) {
            guard result[id] == nil else { return }
            var candidate = AttachmentStore.sanitize(name)
            let base = (candidate as NSString).deletingPathExtension
            let ext = (candidate as NSString).pathExtension
            var n = 2
            while used.contains(candidate.lowercased()) {
                candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
                n += 1
            }
            used.insert(candidate.lowercased())
            result[id] = folder + "/" + candidate
        }
        root.forEach { t in
            if let image = t.image { assign(image.id, image.name) }
            for a in t.attachments { assign(a.id, a.name) }
        }
        return result
    }
}
