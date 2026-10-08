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
            throw parser.parserError ?? CocoaError(.fileReadCorruptFile)
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
            var t = Topic(title: attributes["text"] ?? attributes["title"] ?? "")
            t.note = attributes["_note"] ?? ""
            if let url = attributes["url"] ?? attributes["htmlUrl"] ?? attributes["xmlUrl"], !url.isEmpty { t.link = url }
            t.collapsed = attributes["_collapsed"] == "true"
            stack.append(t)
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTitle { headTitle += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name.lowercased() {
        case "title": inTitle = false
        case "outline":
            guard let t = stack.popLast() else { return }
            if stack.isEmpty { roots.append(t) } else { stack[stack.count - 1].children.append(t) }
        default: break
        }
    }
}
