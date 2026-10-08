import Foundation
import UniformTypeIdentifiers

enum DocumentTypes {
    static let map = "tech.xvanturing.freemind.map"
    static let markdown = "net.daringfireball.markdown"
    static let opml = "org.opml.opml"
    static let xmind = "tech.xvanturing.freemind.xmind-import"

    static let fileExtension = "fmind"

    static var mapUTType: UTType { UTType(exportedAs: map, conformingTo: .package) }

    /// 可以导入（转换成新导图）的扩展名。
    static let importableExtensions = ["md", "markdown", "mdown", "txt", "opml", "xmind"]
}

/// 打开时恢复的视图状态（缩放、可视中心、选中项）。
struct ViewState: Codable, Equatable {
    var zoom: Double
    /// 可视区域中心，布局坐标（根主题中心为原点）。
    var centerX: Double
    var centerY: Double
    var selection: [UUID]
}

/// `content.json` 的顶层结构。
struct DocumentContent: Codable {
    static let currentVersion = 1

    var format: String
    var version: Int
    var generator: String?
    var map: MindMap
    var view: ViewState?

    init(map: MindMap, view: ViewState?) {
        self.format = "freemind"
        self.version = Self.currentVersion
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        self.generator = "FreeMind \(appVersion)"
        self.map = map
        self.view = view
    }

    static let contentFileName = "content.json"

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> DocumentContent {
        let content = try JSONDecoder().decode(DocumentContent.self, from: data)
        guard content.format == "freemind" else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if content.version > currentVersion {
            throw NSError(domain: "FreeMind", code: 2, userInfo: [
                NSLocalizedDescriptionKey: L("This map was created by a newer version of FreeMind."),
                NSLocalizedRecoverySuggestionErrorKey: L("Please update FreeMind to open it."),
            ])
        }
        return content
    }
}

/// 导入、粘贴、模板里携带的资源文件（附件 / 图片）。
struct ResourceFile: Codable, Equatable {
    var name: String
    var data: Data
}
