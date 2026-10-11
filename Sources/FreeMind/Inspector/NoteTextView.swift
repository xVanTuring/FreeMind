import AppKit
import MarkdownEngine
import MarkdownEngineCodeBlocks
import MarkdownEngineLatex
import SwiftUI

/// 备注输入框：所见即所得的 Markdown 编辑器（swift-markdown-engine，同 Perch / UniReader）。
/// 支持标题、粗斜体、列表、引用、链接、`==高亮==`、`~~删除线~~`、带语言的代码块高亮、`$…$` / `$$…$$` 公式。
///
/// 备注仍以 Markdown 源文本存进 `Topic.note`。撤销：引擎按 `documentId` 各管一套撤销栈
/// （不会混进文档的快照撤销栈），所以 `documentId` 必须每个主题唯一。
struct NoteTextView: View {
    @Binding var text: String
    /// 引擎按它隔离撤销栈和编辑状态，传主题 id。
    let documentId: String
    /// 出现后把光标放进输入框（备注弹窗用）。检查器里不要用：切换选中主题就会抢走画布的键盘焦点。
    var focusOnAppear = false

    /// 高亮 / 公式桥接对象内部有缓存和观察者（HighlighterSwift 走 JavaScriptCore），必须全局只建一个。
    private static let sharedHighlighter = HighlighterSwiftBridge()
    private static let sharedLatex = SwiftMathBridge()

    private static let configuration: MarkdownEditorConfiguration = {
        var c = MarkdownEditorConfiguration.default
        c.services = MarkdownEditorServices(syntaxHighlighter: sharedHighlighter, latex: sharedLatex)
        // 备注框很窄：列表每级缩进和标题字号都按小框收紧（引擎默认是给整页文档定的）
        c.lists.indentPerLevel = 16
        c.headings.fontMultipliers = [1.4, 1.25, 1.12, 1.05, 1.0, 1.0]
        c.headings.topSpacingEm = [0.3, 0.25, 0.2, 0.15, 0.1, 0.1]
        c.overscroll = OverscrollPolicy(percent: 0, maxPoints: 8, minPoints: 8)
        c.scrollers = .vertical
        c.textInsets = TextInsets(horizontal: 2, vertical: 4)
        // 写的是 Markdown / LaTeX 源码，引号不能被换成弯引号
        c.spellChecking.automaticQuoteSubstitution = false
        // 0.10.0 起删除线和高亮不再是核心语法，要注册才生效
        c.extensions = [StrikethroughExtension(), HighlightExtension()]
        return c
    }()

    /// 用来拿到这个编辑器所在的窗口（弹窗和检查器都是）。
    @State private var anchor = AnchorBox()

    var body: some View {
        NativeTextViewWrapper(
            text: $text,
            configuration: Self.configuration,
            fontSize: NSFont.systemFontSize,
            documentId: documentId,
            isEditable: true)
            .background(WindowAnchor(box: anchor))
            // 出现时、切换到另一个主题时各做一次
            .task(id: documentId) { await refreshRendering() }
    }

    /// 引擎在创建时视口还是 0 宽，初次排版缓存的文本片段只有一行高，之后宽度变了它也不会让缓存失效，
    /// 表现为只显示第一行、点一下输入框才出全文（实测：排版数据是对的，只让整篇排版失效一次就能修好）。
    /// 视图挂到窗口之后才能拿到文本视图，所以要等；第一次不等，之后每 16ms 重试，最多约 1 秒，尽量减少闪烁。
    @MainActor private func refreshRendering() async {
        for attempt in 0..<60 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 16_000_000) } else { await Task.yield() }
            guard let window = anchor.view?.window, window.isVisible,
                  let root = window.contentView, let tv = Self.firstEditableTextView(in: root) else { continue }
            if let tlm = tv.textLayoutManager { tlm.invalidateLayout(for: tlm.documentRange) }
            if focusOnAppear {
                window.makeKey()
                window.makeFirstResponder(tv)
            }
            return
        }
    }

    private static func firstEditableTextView(in view: NSView) -> NSTextView? {
        if let tv = view as? NSTextView, tv.isEditable { return tv }
        for sub in view.subviews {
            if let hit = firstEditableTextView(in: sub) { return hit }
        }
        return nil
    }
}

/// 持有一个视图的弱引用。
final class AnchorBox {
    weak var view: NSView?
}

private struct WindowAnchor: NSViewRepresentable {
    let box: AnchorBox
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        box.view = v
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { box.view = nsView }
}
