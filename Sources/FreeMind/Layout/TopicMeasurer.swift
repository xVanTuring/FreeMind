import AppKit

/// 主题右侧的小图标（备注、链接、附件）。
enum Indicator: Equatable {
    case note
    case link
    case attachments(Int)

    var symbolName: String {
        switch self {
        case .note: return "note.text"
        case .link: return "link"
        case .attachments: return "paperclip"
        }
    }
}

/// 主题内部各元素的排布，坐标相对主题框左上角。
struct TopicContent {
    var size: CGSize
    var imageRect: CGRect?
    var markerRects: [(id: MarkerID, rect: CGRect)]
    var textRect: CGRect
    var indicatorRects: [(indicator: Indicator, rect: CGRect)]
    var labelRects: [(text: String, rect: CGRect)]
    var title: NSAttributedString
    var labelFont: NSFont
    var iconSize: CGFloat
}

/// 计算主题尺寸和内部排布。文字测量结果带缓存，避免每次重排都重新测量。
final class TopicMeasurer {
    private var textCache: [String: CGSize] = [:]

    static let minTextWidth: CGFloat = 12

    func textAttributes(style: ResolvedStyle) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = style.alignment
        paragraph.lineBreakMode = .byWordWrapping
        return [.font: style.font, .foregroundColor: style.text, .paragraphStyle: paragraph]
    }

    func measureText(_ string: NSAttributedString, font: NSFont, maxWidth: CGFloat) -> CGSize {
        let key = "\(font.fontName)|\(font.pointSize)|\(maxWidth)|\(string.string)"
        if let cached = textCache[key] { return cached }
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        var size: CGSize
        if string.length == 0 {
            size = CGSize(width: 0, height: lineHeight)
        } else {
            let rect = string.boundingRect(with: CGSize(width: maxWidth, height: 100_000),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading])
            // 末尾是换行时 boundingRect 不计入最后一个空行，这里补上，保证编辑时光标有位置。
            var height = ceil(rect.height)
            if string.string.hasSuffix("\n") { height += lineHeight }
            size = CGSize(width: ceil(rect.width) + 2, height: max(height, lineHeight))
        }
        if textCache.count > 8000 { textCache.removeAll(keepingCapacity: true) }
        textCache[key] = size
        return size
    }

    func content(for topic: Topic, title: String, style: ResolvedStyle, level: Int, maxWidth: Double) -> TopicContent {
        let font = style.font
        let iconSize = min(max((font.pointSize * 1.15).rounded(), 14), 30)
        let indicatorSize = (iconSize * 0.82).rounded()
        let gap: CGFloat = 4

        // 标记（左侧）
        let markers = topic.markers
        let markersWidth = markers.isEmpty ? 0 : CGFloat(markers.count) * iconSize + CGFloat(markers.count - 1) * 3 + 6

        // 指示图标（右侧）
        var indicators: [Indicator] = []
        if topic.hasNote { indicators.append(.note) }
        if topic.hasLink { indicators.append(.link) }
        if !topic.attachments.isEmpty { indicators.append(.attachments(topic.attachments.count)) }
        let countFont = NSFont.systemFont(ofSize: indicatorSize * 0.72, weight: .semibold)
        let indicatorWidths: [CGFloat] = indicators.map { indicator in
            if case .attachments(let n) = indicator, n > 1 {
                let w = ("\(n)" as NSString).size(withAttributes: [.font: countFont]).width
                return indicatorSize + ceil(w) + 1
            }
            return indicatorSize
        }
        let indicatorsWidth = indicators.isEmpty ? 0 : indicatorWidths.reduce(0, +) + CGFloat(indicators.count - 1) * 3 + 6

        // 文字
        let maxW = CGFloat(level == 0 ? maxWidth * 1.3 : maxWidth)
        let textMax = max(maxW - markersWidth - indicatorsWidth, 60)
        let attributed = NSAttributedString(string: title, attributes: textAttributes(style: style))
        var textSize = measureText(attributed, font: font, maxWidth: textMax)
        textSize.width = max(textSize.width, Self.minTextWidth)

        let rowHeight = max(textSize.height, (markers.isEmpty && indicators.isEmpty) ? 0 : iconSize)
        let rowWidth = markersWidth + textSize.width + indicatorsWidth

        // 标签（下方小胶囊）
        let labelFont = NSFont.systemFont(ofSize: max(10, (font.pointSize * 0.72).rounded()), weight: .medium)
        let labelHeight = ceil(labelFont.ascender - labelFont.descender) + 4
        var labelWidths: [CGFloat] = []
        for label in topic.labels {
            let w = (label as NSString).size(withAttributes: [.font: labelFont]).width
            labelWidths.append(ceil(w) + 12)
        }
        let labelsWidth = labelWidths.isEmpty ? 0 : labelWidths.reduce(0, +) + CGFloat(labelWidths.count - 1) * 4

        // 图片（上方）
        var imageSize = CGSize.zero
        if let image = topic.image {
            imageSize = CGSize(width: max(16, image.width), height: max(16, image.height))
        }

        let contentWidth = max(rowWidth, labelsWidth, imageSize.width)
        var contentHeight = rowHeight
        if imageSize.height > 0 { contentHeight += imageSize.height + 6 }
        if !labelWidths.isEmpty { contentHeight += labelHeight + gap + 2 }

        // 外框尺寸
        var frameSize: CGSize
        switch style.shape {
        case .ellipse:
            frameSize = CGSize(width: contentWidth * 1.2 + style.padH * 2, height: contentHeight * 1.4 + style.padV * 2)
        case .diamond:
            frameSize = CGSize(width: contentWidth * 2 + style.padH, height: contentHeight * 2 + style.padV)
        case .capsule:
            frameSize = CGSize(width: contentWidth + style.padH * 2 + contentHeight * 0.3, height: contentHeight + style.padV * 2)
        case .underline:
            frameSize = CGSize(width: contentWidth + style.padH * 2, height: contentHeight + style.padV * 2 + style.underlineWidth)
        default:
            frameSize = CGSize(width: contentWidth + style.padH * 2, height: contentHeight + style.padV * 2)
        }
        frameSize.width = ceil(max(frameSize.width, level == 0 ? 80 : 28))
        frameSize.height = ceil(frameSize.height)

        // 内容在框里居中（下划线/无边框靠左）
        let originX: CGFloat = style.shape.isBoxed ? (frameSize.width - contentWidth) / 2 : style.padH
        let contentHeightWithoutUnderline = frameSize.height - (style.shape == .underline ? style.underlineWidth : 0)
        var y: CGFloat = (contentHeightWithoutUnderline - contentHeight) / 2

        var imageRect: CGRect?
        if imageSize.height > 0 {
            imageRect = CGRect(x: originX + (contentWidth - imageSize.width) / 2, y: y,
                               width: imageSize.width, height: imageSize.height)
            y += imageSize.height + 6
        }

        let rowX = originX + (style.shape.isBoxed ? (contentWidth - rowWidth) / 2 : 0)
        var x = rowX
        var markerRects: [(MarkerID, CGRect)] = []
        for marker in markers {
            markerRects.append((marker, CGRect(x: x, y: y + (rowHeight - iconSize) / 2, width: iconSize, height: iconSize)))
            x += iconSize + 3
        }
        if !markers.isEmpty { x += 3 }
        let textRect = CGRect(x: x, y: y + (rowHeight - textSize.height) / 2, width: textSize.width, height: textSize.height)
        x += textSize.width + (indicators.isEmpty ? 0 : 6)
        var indicatorRects: [(Indicator, CGRect)] = []
        for (i, indicator) in indicators.enumerated() {
            let w = indicatorWidths[i]
            indicatorRects.append((indicator, CGRect(x: x, y: y + (rowHeight - indicatorSize) / 2, width: w, height: indicatorSize)))
            x += w + 3
        }
        y += rowHeight

        var labelRects: [(String, CGRect)] = []
        if !labelWidths.isEmpty {
            y += gap + 2
            var lx = originX + (style.shape.isBoxed ? (contentWidth - labelsWidth) / 2 : 0)
            for (i, label) in topic.labels.enumerated() {
                labelRects.append((label, CGRect(x: lx, y: y, width: labelWidths[i], height: labelHeight)))
                lx += labelWidths[i] + 4
            }
        }

        return TopicContent(size: frameSize, imageRect: imageRect, markerRects: markerRects, textRect: textRect,
                            indicatorRects: indicatorRects, labelRects: labelRects, title: attributed,
                            labelFont: labelFont, iconSize: iconSize)
    }
}
