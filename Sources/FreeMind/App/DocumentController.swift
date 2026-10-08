import AppKit

/// 自定义文档控制器：新建时弹出模板库，打开 Markdown / OPML / XMind 时转为导入。
final class DocumentController: NSDocumentController {
    static var sharedController: DocumentController { NSDocumentController.shared as! DocumentController }

    override func newDocument(_ sender: Any?) {
        if Preferences.shared.showTemplateGalleryOnNew {
            TemplateGalleryController.show()
        } else {
            createBlankDocument()
        }
    }

    /// 直接新建空白导图（不经过模板库）。
    func createBlankDocument() {
        var map = MindMap.blank(structure: Preferences.shared.defaultStructure, theme: Preferences.shared.defaultTheme)
        map.spacing = Preferences.shared.defaultSpacing
        openUntitled(map: map, resources: [:], displayName: nil, markEdited: false)
    }

    @discardableResult
    func openUntitled(map: MindMap, resources: [UUID: ResourceFile], displayName: String?, markEdited: Bool) -> MindMapDocument? {
        do {
            guard let doc = try makeUntitledDocument(ofType: DocumentTypes.map) as? MindMapDocument else { return nil }
            doc.setInitialContent(map, resources: resources)
            if let displayName, !displayName.isEmpty { doc.displayName = displayName }
            addDocument(doc)
            doc.makeWindowControllers()
            doc.showWindows()
            if markEdited { doc.updateChangeCount(.changeDone) }
            return doc
        } catch {
            presentError(error)
            return nil
        }
    }

    override func openDocument(withContentsOf url: URL, display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void) {
        let ext = url.pathExtension.lowercased()
        guard DocumentTypes.importableExtensions.contains(ext) else {
            super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
            return
        }
        importFile(at: url, completion: { doc, error in completionHandler(doc, false, error) })
    }

    /// 导入外部文件，生成一个或多个未命名导图。
    func importFile(at url: URL, completion: ((NSDocument?, Error?) -> Void)? = nil) {
        do {
            let results = try Importer.importAll(at: url)
            var first: NSDocument?
            for result in results {
                let name = results.count > 1 ? result.title : url.deletingPathExtension().lastPathComponent
                let doc = openUntitled(map: result.map, resources: result.resources, displayName: name, markEdited: true)
                if first == nil { first = doc }
            }
            completion?(first, nil)
        } catch {
            presentError(error)
            completion?(nil, error)
        }
    }
}
