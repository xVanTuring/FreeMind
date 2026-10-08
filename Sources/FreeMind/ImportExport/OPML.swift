import Foundation

/// OPML 大纲格式（OmniOutliner、幕布、Workflowy 等大纲软件通用）。
enum OPMLExporter {
    static func export(_ map: MindMap) -> String {
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>\(escape(map.root.title))</title>
          </head>
          <body>

        """
        func write(_ t: Topic, indent: Int) {
            let pad = String(repeating: "  ", count: indent)
            var attrs = "text=\"\(escape(t.title))\""
            if t.hasNote { attrs += " _note=\"\(escape(t.note))\"" }
            if let link = t.link, !link.isEmpty { attrs += " type=\"link\" url=\"\(escape(link))\"" }
            if t.collapsed { attrs += " _collapsed=\"true\"" }
            if t.children.isEmpty {
                out += "\(pad)<outline \(attrs)/>\n"
            } else {
                out += "\(pad)<outline \(attrs)>\n"
                t.children.forEach { write($0, indent: indent + 1) }
                out += "\(pad)</outline>\n"
            }
        }
        write(map.root, indent: 2)
        out += "  </body>\n</opml>\n"
        return out
    }

    /// 属性值转义。换行、制表符、回车写成字符引用（否则 XML 解析时会被规范化成空格），
    /// XML 1.0 不允许的控制字符直接去掉，保证导出的文件一定能解析。
    static func escape(_ s: String) -> String {
        var r = ""
        r.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": r += "&amp;"
            case "<": r += "&lt;"
            case ">": r += "&gt;"
            case "\"": r += "&quot;"
            case "\n": r += "&#10;"
            case "\r": r += "&#13;"
            case "\t": r += "&#9;"
            default:
                let v = scalar.value
                if v < 0x20 || v == 0xFFFE || v == 0xFFFF { continue }
                r.unicodeScalars.append(scalar)
            }
        }
        return r
    }
}

final class OPMLImporter: NSObject, XMLParserDelegate {
    private var stack: [Topic] = []
    private var roots: [Topic] = []
    private var headTitle = ""
    private var inTitle = false

    static func parse(_ data: Data, defaultTitle: String) throws -> ImportResult {
        let importer = OPMLImporter()
        let parser = XMLParser(data: data)
        parser.delegate = importer
        guard parser.parse() else {
            var info: [String: Any] = [
                NSLocalizedDescriptionKey: L("This OPML file is damaged and could not be read."),
                NSLocalizedRecoverySuggestionErrorKey: LF("The problem is near line %d.", parser.lineNumber),
            ]
            if let underlying = parser.parserError { info[NSUnderlyingErrorKey] = underlying }
            throw NSError(domain: "FreeMind", code: 21, userInfo: info)
        }
        let root: Topic
        if importer.roots.count == 1 {
            root = importer.roots[0]
        } else {
            let title = importer.headTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            root = Topic(title: title.isEmpty ? defaultTitle : title, children: importer.roots)
        }
        let map = MindMap(root: root, structure: Preferences.shared.defaultStructure, theme: Preferences.shared.defaultTheme)
        return ImportResult(map: map, title: root.title)
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch name.lowercased() {
        case "title": inTitle = stack.isEmpty
        case "outline":
            let (title, bold) = Self.cleanTitle(attributes["text"] ?? attributes["title"] ?? "")
            var t = Topic(title: title)
            if bold { t.style.bold = true }
            t.note = (attributes["_note"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = attributes["url"] ?? attributes["htmlUrl"] ?? attributes["xmlUrl"], !url.isEmpty { t.link = url }
            t.collapsed = attributes["_collapsed"] == "true"
            // Workflowy 用 _complete 标记已完成的条目
            if attributes["_complete"] == "true" { t.markers = [MarkerID("task-100")] }
            stack.append(t)
        default: break
        }
    }

    /// 其他大纲软件会把格式写进文字：Workflowy 用 HTML 标签（`<b>粗体</b>`），Logseq 用 Markdown（`**粗体**`）。
    /// 去掉常见的格式标签和首尾空白；整行都是粗体时改为主题的粗体样式。
    static func cleanTitle(_ raw: String) -> (title: String, bold: Bool) {
        var text = formattingTags.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for mark in ["**", "__"] where text.count > mark.count * 2 && text.hasPrefix(mark) && text.hasSuffix(mark) {
            let inner = String(text.dropFirst(mark.count).dropLast(mark.count))
            if !inner.contains(mark) { return (inner.trimmingCharacters(in: .whitespaces), true) }
        }
        return (text, false)
    }

    private static let formattingTags = try! NSRegularExpression(
        pattern: "</?(b|i|u|s|em|strong|span|mark|code|strike|del|a|br)\\b[^>]*>", options: [.caseInsensitive])

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTitle { headTitle += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name.lowercased() {
        case "title": inTitle = false
        case "outline":
            guard let t = stack.popLast() else { return }
            // 什么都没有的空条目（Logseq 页面开头常有一个只含换行的块）不导入
            if t.title.isEmpty, t.children.isEmpty, t.note.isEmpty, t.link == nil, t.markers.isEmpty { return }
            if stack.isEmpty { roots.append(t) } else { stack[stack.count - 1].children.append(t) }
        default: break
        }
    }
}
