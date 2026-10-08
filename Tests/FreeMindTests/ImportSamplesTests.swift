import XCTest
@testable import FreeMind

/// 用真实软件生成的样例文件（XMind、OPML、Markdown）检查导入结果，输出一份统计报告供人工对照。
/// 只有设置了环境变量 FREEMIND_IMPORT_SAMPLES（样例目录）才会运行，报告写到该目录下的 import-report.txt。
final class ImportSamplesTests: XCTestCase {
    func testImportSamples() throws {
        guard let path = ProcessInfo.processInfo.environment["FREEMIND_IMPORT_SAMPLES"], !path.isEmpty else {
            throw XCTSkip("FREEMIND_IMPORT_SAMPLES not set")
        }
        let dir = URL(fileURLWithPath: path)
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { DocumentTypes.importableExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var report: [String] = []
        for file in files {
            report.append(file.lastPathComponent)
            do {
                for result in try Importer.importAll(at: file) {
                    report.append(contentsOf: Self.describe(result))
                }
            } catch {
                report.append("  ERROR: \(error.localizedDescription)")
            }
        }
        try report.joined(separator: "\n").write(to: dir.appendingPathComponent("import-report.txt"), atomically: true, encoding: .utf8)
    }

    private static func describe(_ result: ImportResult) -> [String] {
        let map = result.map
        var counts: [String: Int] = [:]
        var markers: [String: Int] = [:]
        var maxDepth = 0
        func walk(_ t: Topic, _ depth: Int) {
            counts["topics", default: 0] += 1
            maxDepth = max(maxDepth, depth)
            if !t.note.isEmpty { counts["notes", default: 0] += 1 }
            if t.link != nil { counts["links", default: 0] += 1 }
            if !t.labels.isEmpty { counts["labeled", default: 0] += 1 }
            if t.collapsed { counts["folded", default: 0] += 1 }
            if t.image != nil { counts["images", default: 0] += 1 }
            if t.style.boundary == true { counts["boundaries", default: 0] += 1 }
            counts["attachments", default: 0] += t.attachments.count
            for m in t.markers { markers[m.rawValue, default: 0] += 1 }
            for c in t.children { walk(c, depth + 1) }
        }
        walk(map.root, 0)
        counts["maxDepth"] = maxDepth
        var lines = [
            "  map \(result.title.debugDescription) structure=\(map.structure.rawValue) relationships=\(map.relationships.count) resources=\(result.resources.count)",
            "    " + counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "),
            "    markers: " + markers.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: ", "),
            "    root: \(map.root.title.debugDescription) → " + map.root.children.prefix(8).map { $0.title.debugDescription }.joined(separator: ", "),
        ]
        // 资源完整性：每个引用的附件 / 图片都要有数据
        let referenced = map.root.resourceIDs()
        let missing = referenced.subtracting(result.resources.keys)
        if !missing.isEmpty { lines.append("    MISSING RESOURCES: \(missing.count)") }
        return lines
    }
}
