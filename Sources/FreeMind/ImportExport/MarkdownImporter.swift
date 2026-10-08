import AppKit

/// 导入结果：导图 + 需要放进文档的资源文件。
struct ImportResult {
    var map: MindMap
    var resources: [UUID: ResourceFile] = [:]
    var title: String
}

/// Markdown → 导图。
///
/// 规则：
/// - 标题（`#`、Setext）按级别构成层级；
/// - 列表项（`-` `*` `+` `1.`）按缩进挂在最近的标题或上级列表项下；
/// - 其他文字作为最近一个主题的备注；代码块原样进备注；
/// - `[文字](链接)` 形式的整行标题 → 主题 + 超链接；`- [x]` → 完成进度标记；
/// - `![](相对路径)` 指向本地图片 → 主题图片；`📎 [名称](相对路径)` → 附件；
/// - 没有任何标题和列表时，按缩进把每一行当成一个主题。
enum MarkdownImporter {
    private final class Node {
        var title: String
        var level: Int
        var isHeading: Bool
        var noteLines: [String] = []
        var link: String?
        var markers: [MarkerID] = []
        var children: [Node] = []
        var image: (name: String, data: Data)?
        var attachments: [(name: String, data: Data)] = []

        init(title: String, level: Int, isHeading: Bool) {
            self.title = title
            self.level = level
            self.isHeading = isHeading
        }
    }

    static func parse(_ text: String, defaultTitle: String, baseURL: URL? = nil) -> ImportResult {
        var resources: [UUID: ResourceFile] = [:]
        let (roots, preamble) = parseNodes(text, baseURL: baseURL)
        var rootTopic: Topic
        // 只有一个顶层节点（无论是标题还是列表项）时，直接作为中心主题
        if roots.count == 1 {
            rootTopic = makeTopic(roots[0], resources: &resources)
            let pre = cleanNote(preamble)
            if !pre.isEmpty { rootTopic.note = rootTopic.note.isEmpty ? pre : pre + "\n\n" + rootTopic.note }
        } else {
            rootTopic = Topic(title: defaultTitle)
            rootTopic.children = roots.map { makeTopic($0, resources: &resources) }
            rootTopic.note = cleanNote(preamble)
        }
        let map = MindMap(root: rootTopic, structure: Preferences.shared.defaultStructure,
                          theme: Preferences.shared.defaultTheme)
        return ImportResult(map: map, resources: resources, title: rootTopic.title)
    }

    /// 粘贴用：返回顶层主题列表。
    static func parseFragment(_ text: String) -> [Topic] {
        var resources: [UUID: ResourceFile] = [:]
        let (roots, preamble) = parseNodes(text, baseURL: nil)
        var topics = roots.map { makeTopic($0, resources: &resources) }
        if topics.isEmpty {
            let pre = cleanNote(preamble)
            if !pre.isEmpty { topics = [Topic(title: pre)] }
        }
        return topics
    }

    // MARK: - 解析

    private static func parseNodes(_ text: String, baseURL: URL?) -> (roots: [Node], preamble: [String]) {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        // YAML front matter
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            lines.removeSubrange(0...end)
        }

        let hasStructure = lines.contains { isHeading($0) != nil || listItem($0) != nil }
            || lines.indices.dropFirst().contains { i in isSetextUnderline(lines[i]) != nil && isParagraphLine(lines[i - 1]) }
        if !hasStructure {
            return (parseIndentedOutline(lines), [])
        }

        var roots: [Node] = []
        var preamble: [String] = []
        var headingStack: [Node] = []
        var listStack: [(indent: Int, node: Node)] = []
        var current: Node?
        var inFence: String?
        var previousBlank = true

        func attach(_ node: Node, to parent: Node?) {
            if let parent { parent.children.append(node) } else { roots.append(node) }
        }

        func appendNote(_ line: String) {
            if let current { current.noteLines.append(line) } else { preamble.append(line) }
        }

        for (i, raw) in lines.enumerated() {
            let line = raw.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 列表项下的备注内容比列表标记多缩进 2 格
            let contentIndent = listStack.last.map { $0.indent + 2 }
            if let fence = inFence {
                appendNote(stripIndent(line, contentIndent))
                if trimmed.hasPrefix(fence) { inFence = nil }
                previousBlank = false
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence = String(trimmed.prefix(3))
                appendNote(stripIndent(line, contentIndent))
                previousBlank = false
                continue
            }
            if trimmed.isEmpty {
                appendNote("")
                previousBlank = true
                continue
            }

            // Setext 标题：上一行是段落文字，这一行是 === 或 ---
            if let level = isSetextUnderline(line), i > 0, isParagraphLine(lines[i - 1]), !previousBlank {
                let titleLine = lines[i - 1].trimmingCharacters(in: .whitespaces)
                // 撤回上一行已经记进备注的文字
                if let current, current.noteLines.last?.trimmingCharacters(in: .whitespaces) == titleLine {
                    current.noteLines.removeLast()
                } else if current == nil, preamble.last?.trimmingCharacters(in: .whitespaces) == titleLine {
                    preamble.removeLast()
                }
                let node = Node(title: titleLine, level: level, isHeading: true)
                applyInline(node)
                listStack.removeAll()
                while let top = headingStack.last, top.level >= level { headingStack.removeLast() }
                attach(node, to: headingStack.last)
                headingStack.append(node)
                current = node
                previousBlank = false
                continue
            }

            if let (level, title) = isHeading(line) {
                let node = Node(title: title, level: level, isHeading: true)
                applyInline(node)
                listStack.removeAll()
                while let top = headingStack.last, top.level >= level { headingStack.removeLast() }
                attach(node, to: headingStack.last)
                headingStack.append(node)
                current = node
                previousBlank = false
                continue
            }

            if let item = listItem(line) {
                let node = Node(title: item.content, level: item.indent, isHeading: false)
                if let checked = item.checked { node.markers = [MarkerID(checked ? "task-100" : "task-0")] }
                applyInline(node)
                while let top = listStack.last, top.indent >= item.indent { listStack.removeLast() }
                attach(node, to: listStack.last?.node ?? headingStack.last)
                listStack.append((item.indent, node))
                current = node
                previousBlank = false
                continue
            }

            // 普通段落
            let indent = line.prefix { $0 == " " }.count
            if let top = listStack.last, previousBlank, indent <= top.indent {
                // 列表之后空一行再出现不缩进的段落：列表结束，段落归属标题
                listStack.removeAll()
                current = headingStack.last
            }
            let content = stripIndent(line, listStack.last.map { $0.indent + 2 })
            if let current, let baseURL, handleResourceLine(content.trimmingCharacters(in: .whitespaces), node: current, baseURL: baseURL) {
                previousBlank = false
                continue
            }
            appendNote(unescapeNoteLine(content))
            previousBlank = false
        }
        return (roots, preamble)
    }

    /// 没有 Markdown 结构的纯文本：每行一个主题，按缩进确定层级。
    private static func parseIndentedOutline(_ lines: [String]) -> [Node] {
        var roots: [Node] = []
        var stack: [(indent: Int, node: Node)] = []
        for raw in lines {
            let line = raw.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let indent = line.prefix { $0 == " " }.count
            let node = Node(title: trimmed, level: indent, isHeading: false)
            applyInline(node)
            while let top = stack.last, top.indent >= indent { stack.removeLast() }
            if let parent = stack.last?.node { parent.children.append(node) } else { roots.append(node) }
            stack.append((indent, node))
        }
        return roots
    }

    // MARK: - 行识别

    private static func isHeading(_ line: String) -> (Int, String)? {
        let leading = line.prefix { $0 == " " }.count
        guard leading <= 3 else { return nil }
        let s = line.dropFirst(leading)
        let hashes = s.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = s.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " else { return nil }
        var title = rest.trimmingCharacters(in: .whitespaces)
        // 去掉闭合的 ###
        if let r = title.range(of: #"\s+#+$"#, options: .regularExpression) { title.removeSubrange(r) }
        if title.allSatisfy({ $0 == "#" }) { title = "" }
        return (hashes, title)
    }

    private static func isSetextUnderline(_ line: String) -> Int? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, line.prefix(while: { $0 == " " }).count <= 3 else { return nil }
        if t.allSatisfy({ $0 == "=" }) { return 1 }
        if t.count >= 2, t.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private static func isParagraphLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && isHeading(line) == nil && listItem(line) == nil && isSetextUnderline(line) == nil
            && !t.hasPrefix("```") && !t.hasPrefix("~~~") && !t.hasPrefix(">")
    }

    private static func listItem(_ line: String) -> (indent: Int, content: String, checked: Bool?)? {
        let expanded = line.replacingOccurrences(of: "\t", with: "    ")
        let indent = expanded.prefix { $0 == " " }.count
        let s = expanded.dropFirst(indent)
        var rest: Substring
        if let first = s.first, "-*+".contains(first) {
            rest = s.dropFirst()
            // 分隔线（--- / ***）不是列表
            if s.trimmingCharacters(in: .whitespaces).allSatisfy({ $0 == first }) && s.count >= 3 { return nil }
        } else {
            let digits = s.prefix { $0.isNumber }
            guard !digits.isEmpty, digits.count <= 9 else { return nil }
            let after = s.dropFirst(digits.count)
            guard let p = after.first, p == "." || p == ")" else { return nil }
            rest = after.dropFirst()
        }
        guard rest.isEmpty || rest.first == " " else { return nil }
        var content = rest.trimmingCharacters(in: .whitespaces)
        var checked: Bool?
        if content.hasPrefix("[ ] ") || content == "[ ]" {
            checked = false
            content = String(content.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        } else if content.lowercased().hasPrefix("[x] ") || content.lowercased() == "[x]" {
            checked = true
            content = String(content.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        }
        return (indent, content, checked)
    }

    private static func stripIndent(_ line: String, _ amount: Int?) -> String {
        guard let amount, amount > 0 else { return line }
        let leading = line.prefix { $0 == " " }.count
        return String(line.dropFirst(min(leading, amount)))
    }

    // MARK: - 行内处理

    private static func applyInline(_ node: Node) {
        var title = node.title
        // 整个标题就是一个链接：[文字](url)；含空格的路径写成 [文字](<路径>)
        if let m = title.firstMatch(of: #/^\[(.*)\]\(<([^>]*)>\)$/#) {
            title = String(m.1)
            node.link = String(m.2)
        } else if let m = title.firstMatch(of: #/^\[(.*)\]\((\S+?)(?:\s+"[^"]*")?\)$/#) {
            title = String(m.1)
            node.link = String(m.2)
        } else if let m = title.firstMatch(of: #/^<((?:https?|mailto):[^>]+)>$/#) {
            title = String(m.1)
            node.link = String(m.1)
        }
        node.title = cleanInline(title)
    }

    /// 还原导出时为备注行加的转义（`\- ` `\# ` `1\. ` 等）。
    static func unescapeNoteLine(_ line: String) -> String {
        let indent = line.prefix { $0 == " " }
        let rest = line.dropFirst(indent.count)
        if rest.hasPrefix("\\"), let next = rest.dropFirst().first, "#-+*=".contains(next) {
            return String(indent) + String(rest.dropFirst())
        }
        if let m = rest.firstMatch(of: #/^(\d+)\\([.)])/#) {
            return String(indent) + String(m.1) + String(m.2) + String(rest[m.range.upperBound...])
        }
        return line
    }

    /// 去掉粗体标记和转义符。
    static func cleanInline(_ s: String) -> String {
        var t = s
        for marker in ["**", "__"] {
            while let start = t.range(of: marker), let end = t.range(of: marker, range: start.upperBound..<t.endIndex) {
                t.removeSubrange(end)
                t.removeSubrange(start)
            }
        }
        t = t.replacing(#/\\([\\`*_{}\[\]()#+\-.!>|])/#) { String($0.1) }
        return t.trimmingCharacters(in: .whitespaces)
    }

    private static func handleResourceLine(_ line: String, node: Node, baseURL: URL) -> Bool {
        if let m = line.firstMatch(of: #/^!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)$/#) {
            guard node.image == nil, let url = resolveLocal(String(m.2), baseURL: baseURL),
                  let data = try? Data(contentsOf: url) else { return false }
            node.image = (url.lastPathComponent, data)
            return true
        }
        // 只认导出格式本身的附件行（📎 开头），普通链接行仍是备注文字
        if let m = line.firstMatch(of: #/^📎\s*\[([^\]]+)\]\(([^)\s]+)\)$/#) {
            guard let url = resolveLocal(String(m.2), baseURL: baseURL),
                  let data = try? Data(contentsOf: url) else { return false }
            node.attachments.append((url.lastPathComponent, data))
            return true
        }
        return false
    }

    /// 解析图片 / 附件的本地路径。出于安全考虑，只接受 Markdown 文件所在目录之内的相对路径：
    /// 绝对路径、`file://`、`../` 以及指向目录之外的符号链接一律忽略，避免把本机任意文件悄悄嵌进导图。
    private static func resolveLocal(_ path: String, baseURL: URL) -> URL? {
        let decoded = path.removingPercentEncoding ?? path
        guard !decoded.contains("://"), !decoded.hasPrefix("/"), !decoded.hasPrefix("~"),
              !decoded.split(separator: "/").contains("..") else { return nil }
        let base = baseURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let url = base.appendingPathComponent(decoded).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(base.path + "/"),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return nil }
        return url
    }

    private static func cleanNote(_ lines: [String]) -> String {
        var l = lines
        while l.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { l.removeFirst() }
        while l.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { l.removeLast() }
        // 合并连续空行
        var out: [String] = []
        for line in l {
            if line.trimmingCharacters(in: .whitespaces).isEmpty, out.last?.isEmpty == true { continue }
            out.append(line.trimmingCharacters(in: .whitespaces).isEmpty ? "" : line)
        }
        return out.joined(separator: "\n")
    }

    private static func makeTopic(_ node: Node, resources: inout [UUID: ResourceFile]) -> Topic {
        var topic = Topic(title: node.title)
        topic.note = cleanNote(node.noteLines)
        topic.link = node.link
        topic.markers = node.markers
        if let image = node.image, let ns = NSImage(data: image.data)?.size {
            let id = UUID()
            resources[id] = ResourceFile(name: image.name, data: image.data)
            var size = ns
            let longest = max(size.width, size.height, 1)
            if longest > 200 { size = CGSize(width: size.width * 200 / longest, height: size.height * 200 / longest) }
            topic.image = TopicImage(id: id, name: AttachmentStore.sanitize(image.name),
                                     width: Double(size.width.rounded()), height: Double(size.height.rounded()))
        }
        for file in node.attachments {
            let id = UUID()
            resources[id] = ResourceFile(name: file.name, data: file.data)
            topic.attachments.append(Attachment(id: id, name: AttachmentStore.sanitize(file.name), size: Int64(file.data.count)))
        }
        topic.children = node.children.map { makeTopic($0, resources: &resources) }
        return topic
    }
}
