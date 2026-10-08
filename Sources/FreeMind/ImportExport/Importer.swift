import AppKit

/// 导入入口：按扩展名分发到 Markdown / OPML / XMind。
enum Importer {
    static func importAll(at url: URL) throws -> [ImportResult] {
        let ext = url.pathExtension.lowercased()
        let title = url.deletingPathExtension().lastPathComponent
        switch ext {
        case "xmind":
            return try XMindImporter.importFile(at: url)
        case "opml":
            return [try OPMLImporter.parse(Data(contentsOf: url), defaultTitle: title)]
        default:
            let text = try readText(url)
            return [MarkdownImporter.parse(text, defaultTitle: title, baseURL: url)]
        }
    }

    static func importFile(at url: URL) throws -> ImportResult {
        guard let first = try importAll(at: url).first else { throw CocoaError(.fileReadCorruptFile) }
        return first
    }

    /// 读文本：优先 UTF-8，失败再让系统猜编码（兼容 GBK 等）。
    static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let s = String(data: data, encoding: .utf8) { return s }
        var converted: NSString?
        let encoding = NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &converted, usedLossyConversion: nil)
        if encoding != 0, let converted { return converted as String }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        if let s = String(data: data, encoding: gb18030) { return s }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}
