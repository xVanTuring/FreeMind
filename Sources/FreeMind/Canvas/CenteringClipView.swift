import AppKit

/// 内容比可视区域小时居中显示的 clip view（画布和 Quick Look 预览共用）。
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let docFrame = documentView.frame
        if rect.width > docFrame.width {
            rect.origin.x = docFrame.midX - rect.width / 2
        }
        if rect.height > docFrame.height {
            rect.origin.y = docFrame.midY - rect.height / 2
        }
        return rect
    }
}
