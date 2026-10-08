import AppKit

/// 行内编辑主题标题的输入框。放在画布上主题文字的位置，跟随画布一起缩放。
final class TopicTextEditor: NSTextView {
    var onTextChange: ((String) -> Void)?
    /// commit=true 写回；false 放弃修改。
    var onFinish: ((_ commit: Bool) -> Void)?
    /// 编辑中按 Tab / Return 等快捷键时，先结束编辑再交给画布执行对应命令。
    var onCommand: ((Selector) -> Void)?

    private var finishing = false

    init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 1000, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isVerticallyResizable = false
        isHorizontallyResizable = false
        drawsBackground = false
        textContainerInset = .zero
        focusRingType = .none
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isContinuousSpellCheckingEnabled = false
        usesFindBar = false
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(text: String, font: NSFont, color: NSColor, alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        typingAttributes = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        string = text
        textStorage?.setAttributes(typingAttributes, range: NSRange(location: 0, length: (string as NSString).length))
        insertionPointColor = color
        finishing = false
        resetUndo()
    }

    override func didChangeText() {
        super.didChangeText()
        onTextChange?(string)
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(insertNewline(_:)):
            // Return：完成编辑；⇧/⌥ + Return：换行
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            if flags.contains(.shift) || flags.contains(.option) {
                insertNewlineIgnoringFieldEditor(nil)
            } else {
                finish(commit: true)
            }
        case #selector(insertLineBreak(_:)), #selector(insertNewlineIgnoringFieldEditor(_:)):
            insertNewlineIgnoringFieldEditor(nil)
        case #selector(insertTab(_:)):
            finish(commit: true)
            onCommand?(#selector(MindMapCanvasView.insertSubtopic(_:)))
        case #selector(insertBacktab(_:)):
            finish(commit: true)
        case #selector(cancelOperation(_:)):
            finish(commit: false)
        default:
            super.doCommand(by: selector)
        }
    }

    /// 正在因为焦点转移而退出编辑（此时不能再切换第一响应者，也不能立即移除视图）。
    private(set) var isResigning = false

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok, !finishing {
            isResigning = true
            finish(commit: true)
            isResigning = false
        }
        return ok
    }

    func finish(commit: Bool) {
        guard !finishing else { return }
        finishing = true
        onFinish?(commit)
    }

    /// 输入框使用独立的撤销栈，避免打字的撤销步骤混进文档的撤销栈。
    private let localUndoManager = UndoManager()

    override var undoManager: UndoManager? { localUndoManager }

    func resetUndo() { localUndoManager.removeAllActions() }
}
