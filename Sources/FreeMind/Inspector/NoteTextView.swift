import AppKit
import SwiftUI

/// 备注输入框。不用 SwiftUI 的 TextEditor：它的打字撤销会注册到文档的撤销栈，
/// 和编辑器的快照撤销混在一起（撤销可能作用到另一个主题的文字上）。
/// 这里关闭 NSTextView 自身的撤销，备注的撤销统一由 MapEditor 的合并撤销负责。
struct NoteTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.allowsUndo = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .textColor
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // 输入法组字过程中不能改写内容，否则会打断输入
        if textView.string != text, !textView.hasMarkedText() {
            let selection = textView.selectedRanges
            textView.string = text
            let length = (text as NSString).length
            textView.selectedRanges = selection.map { value in
                let r = value.rangeValue
                return NSValue(range: NSRange(location: min(r.location, length), length: min(r.length, max(0, length - r.location))))
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView

        init(_ parent: NoteTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            // 组字中的拼音不写回模型，等选字上屏后再写
            guard let textView = notification.object as? NSTextView, !textView.hasMarkedText() else { return }
            parent.text = textView.string
        }
    }
}
