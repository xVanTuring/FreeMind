import AppKit

/// 绘制时的交互状态（导出图片时全部为空）。
struct RenderState {
    var selection: Set<UUID> = []
    var hovered: UUID?
    var editing: UUID?
    var highlighted: Set<UUID> = []
    var currentMatch: UUID?
    var showFoldButtonsFor: Set<UUID> = []
    var dragSources: Set<UUID> = []
    var selectedRelationship: UUID?
    var accent: NSColor = .controlAccentColor
}

/// 把 MapLayout 画到当前的 NSGraphicsContext（要求坐标系是翻转的，y 向下）。
/// 画布、导出 PNG/PDF、打印、模板缩略图都共用这一份绘制代码。
struct MapRenderer {
    let layout: MapLayout
    var images: (UUID) -> NSImage? = { _ in nil }

    func draw(in rect: CGRect, state: RenderState = RenderState(), drawBackground: Bool = true) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if drawBackground {
            ctx.setFillColor(layout.background.cgColor)
            ctx.fill(rect)
        }
        drawBoundaries(ctx, in: rect)
        drawConnectors(ctx, in: rect, state: state)
        for id in layout.order {
            guard let node = layout.nodes[id] else { continue }
            let visible = node.frame.insetBy(dx: -8, dy: -8)
            if visible.intersects(rect) {
                drawTopic(node, ctx: ctx, state: state)
            }
            if node.childCount > 0, node.level > 0 || layout.structure != .mindMap {
                if node.collapsed || state.showFoldButtonsFor.contains(id) {
                    drawFoldButton(node, ctx: ctx, state: state)
                }
            }
        }
        drawRelationships(ctx, in: rect, state: state)
    }

    // MARK: 联系线

    /// 先画所有的线，再画所有的标签，最后画选中线的控制柄：标签不会被后画的线压住。
    private func drawRelationships(_ ctx: CGContext, in rect: CGRect, state: RenderState) {
        let visible = layout.relationships.filter { $0.bounds.intersects(rect) }
        for r in visible { drawRelationshipLine(r, ctx: ctx, state: state) }
        for r in visible { drawRelationshipLabel(r, ctx: ctx) }
        if let r = visible.first(where: { $0.id == state.selectedRelationship }) { drawControlHandles(r, ctx: ctx, state: state) }
    }

    private func drawRelationshipLine(_ r: RelationshipLayout, ctx: CGContext, state: RenderState) {
        let path = CGMutablePath()
        path.move(to: r.p0)
        path.addCurve(to: r.p3, control1: r.c1, control2: r.c2)
        ctx.saveGState()
        ctx.setLineCap(.round)
        if state.selectedRelationship == r.id {
            ctx.addPath(path)
            ctx.setStrokeColor(state.accent.withAlphaComponent(0.3).cgColor)
            ctx.setLineWidth(8)
            ctx.strokePath()
        }
        ctx.addPath(path)
        ctx.setStrokeColor(r.color.cgColor)
        ctx.setLineWidth(2)
        if r.dashed { ctx.setLineDash(phase: 0, lengths: [7, 5]) }
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setFillColor(r.color.cgColor)
        if r.arrowEnd { drawArrow(ctx, tip: r.p3, from: r.c2 == r.p3 ? r.p0 : r.c2) }
        if r.arrowStart { drawArrow(ctx, tip: r.p0, from: r.c1 == r.p0 ? r.p3 : r.c1) }
        ctx.restoreGState()
    }

    private func drawRelationshipLabel(_ r: RelationshipLayout, ctx: CGContext) {
        guard let label = r.labelRect else { return }
        ctx.saveGState()
        let bg = CGPath(roundedRect: label, cornerWidth: label.height / 2, cornerHeight: label.height / 2, transform: nil)
        ctx.addPath(bg)
        ctx.setFillColor(layout.background.cgColor)
        ctx.fillPath()
        ctx.addPath(bg)
        ctx.setStrokeColor(r.color.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = NSAttributedString(string: r.title, attributes: [
            .font: RelationshipLayout.labelFont, .foregroundColor: r.color, .paragraphStyle: paragraph,
        ])
        text.draw(with: label.insetBy(dx: 6, dy: 3), options: [.usesLineFragmentOrigin, .usesFontLeading])
        ctx.restoreGState()
    }

    private func drawControlHandles(_ r: RelationshipLayout, ctx: CGContext, state: RenderState) {
        ctx.saveGState()
        ctx.setStrokeColor(state.accent.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: r.p0)
        ctx.addLine(to: r.c1)
        ctx.move(to: r.p3)
        ctx.addLine(to: r.c2)
        ctx.strokePath()
        for c in [r.c1, r.c2] {
            let handle = CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: handle)
            ctx.setStrokeColor(state.accent.cgColor)
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: handle)
        }
        ctx.restoreGState()
    }

    private func drawArrow(_ ctx: CGContext, tip: CGPoint, from: CGPoint) {
        let angle = atan2(tip.y - from.y, tip.x - from.x)
        let length: CGFloat = 12, spread: CGFloat = .pi / 7
        ctx.move(to: tip)
        ctx.addLine(to: CGPoint(x: tip.x - length * cos(angle - spread), y: tip.y - length * sin(angle - spread)))
        ctx.addLine(to: CGPoint(x: tip.x - length * cos(angle + spread), y: tip.y - length * sin(angle + spread)))
        ctx.closePath()
        ctx.fillPath()
    }

    /// 拖动主题时跟随鼠标的半透明预览。
    func drawGhost(_ node: NodeLayout, at origin: CGPoint) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        var moved = node
        moved.frame.origin = origin
        ctx.saveGState()
        ctx.setAlpha(0.75)
        drawTopic(moved, ctx: ctx, state: RenderState())
        ctx.restoreGState()
    }

    // MARK: 外框

    private func drawBoundaries(_ ctx: CGContext, in rect: CGRect) {
        for id in layout.order {
            guard let node = layout.nodes[id], node.hasBoundary else { continue }
            let box = node.subtreeBounds.insetBy(dx: -8, dy: -8)
            guard box.intersects(rect) else { continue }
            let path = CGPath(roundedRect: box, cornerWidth: 12, cornerHeight: 12, transform: nil)
            let color = node.style.branchColor
            ctx.saveGState()
            ctx.addPath(path)
            ctx.setFillColor(color.withAlphaComponent(layout.isDarkBackground ? 0.12 : 0.07).cgColor)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor(color.withAlphaComponent(0.7).cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    // MARK: 连线

    private func drawConnectors(_ ctx: CGContext, in rect: CGRect, state: RenderState) {
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for c in layout.connectors {
            let box = CGRect(x: min(c.from.x, c.to.x), y: min(c.from.y, c.to.y),
                             width: abs(c.to.x - c.from.x), height: abs(c.to.y - c.from.y)).insetBy(dx: -4, dy: -4)
            guard box.intersects(rect) else { continue }
            let path = connectorPath(c)
            ctx.addPath(path)
            var color = c.color
            if state.dragSources.contains(c.childID) { color = color.withAlphaComponent(0.3) }
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(c.width)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    func connectorPath(_ c: Connector) -> CGPath {
        let path = CGMutablePath()
        let p0 = c.from, p1 = c.to
        path.move(to: p0)
        switch c.orientation {
        case .horizontal:
            switch layout.lineStyle {
            case .curve:
                let mx = p0.x + (p1.x - p0.x) * 0.5
                path.addCurve(to: p1, control1: CGPoint(x: mx, y: p0.y), control2: CGPoint(x: mx, y: p1.y))
            case .straight:
                path.addLine(to: p1)
            case .elbow:
                path.addLine(to: CGPoint(x: c.spine, y: p0.y))
                path.addLine(to: CGPoint(x: c.spine, y: p1.y))
                path.addLine(to: p1)
            case .roundedElbow:
                let r = min(10, abs(p1.y - p0.y) / 2, abs(p1.x - c.spine))
                path.addLine(to: CGPoint(x: c.spine, y: p0.y))
                if r < 0.5 {
                    path.addLine(to: CGPoint(x: c.spine, y: p1.y))
                } else {
                    let sy: CGFloat = p1.y > p0.y ? 1 : -1
                    path.addLine(to: CGPoint(x: c.spine, y: p1.y - sy * r))
                    path.addQuadCurve(to: CGPoint(x: c.spine + c.direction * r, y: p1.y),
                                      control: CGPoint(x: c.spine, y: p1.y))
                }
                path.addLine(to: p1)
            }
        case .vertical:
            switch layout.lineStyle {
            case .curve:
                let my = p0.y + (p1.y - p0.y) * 0.5
                path.addCurve(to: p1, control1: CGPoint(x: p0.x, y: my), control2: CGPoint(x: p1.x, y: my))
            case .straight:
                path.addLine(to: p1)
            case .elbow:
                path.addLine(to: CGPoint(x: p0.x, y: c.spine))
                path.addLine(to: CGPoint(x: p1.x, y: c.spine))
                path.addLine(to: p1)
            case .roundedElbow:
                let r = min(10, abs(p1.x - p0.x) / 2, abs(p1.y - c.spine))
                path.addLine(to: CGPoint(x: p0.x, y: c.spine))
                if r < 0.5 {
                    path.addLine(to: CGPoint(x: p1.x, y: c.spine))
                } else {
                    let sx: CGFloat = p1.x > p0.x ? 1 : -1
                    path.addLine(to: CGPoint(x: p1.x - sx * r, y: c.spine))
                    path.addQuadCurve(to: CGPoint(x: p1.x, y: c.spine + r), control: CGPoint(x: p1.x, y: c.spine))
                }
                path.addLine(to: p1)
            }
        case .tree:
            // 树状图：从父主题左下竖直向下，再水平接入子主题。
            let r: CGFloat = (layout.lineStyle == .elbow || layout.lineStyle == .straight) ? 0 : min(8, abs(p1.y - p0.y))
            if r < 0.5 {
                path.addLine(to: CGPoint(x: p0.x, y: p1.y))
            } else {
                path.addLine(to: CGPoint(x: p0.x, y: p1.y - r))
                path.addQuadCurve(to: CGPoint(x: p0.x + r, y: p1.y), control: CGPoint(x: p0.x, y: p1.y))
            }
            path.addLine(to: p1)
        }
        return path
    }

    // MARK: 主题

    func shapePath(_ shape: TopicShape, in frame: CGRect, radius: CGFloat) -> CGPath {
        switch shape {
        case .roundedRect:
            let r = min(radius, frame.height / 2, frame.width / 2)
            return CGPath(roundedRect: frame, cornerWidth: r, cornerHeight: r, transform: nil)
        case .rect:
            let r = min(radius, 3)
            return r > 0 ? CGPath(roundedRect: frame, cornerWidth: r, cornerHeight: r, transform: nil) : CGPath(rect: frame, transform: nil)
        case .capsule:
            let r = min(frame.height / 2, frame.width / 2)
            return CGPath(roundedRect: frame, cornerWidth: r, cornerHeight: r, transform: nil)
        case .ellipse:
            return CGPath(ellipseIn: frame, transform: nil)
        case .diamond:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: frame.midX, y: frame.minY))
            p.addLine(to: CGPoint(x: frame.maxX, y: frame.midY))
            p.addLine(to: CGPoint(x: frame.midX, y: frame.maxY))
            p.addLine(to: CGPoint(x: frame.minX, y: frame.midY))
            p.closeSubpath()
            return p
        case .underline, .plain:
            return CGPath(roundedRect: frame, cornerWidth: 6, cornerHeight: 6, transform: nil)
        }
    }

    private func drawTopic(_ node: NodeLayout, ctx: CGContext, state: RenderState) {
        let style = node.style
        let frame = node.frame
        let dragging = state.dragSources.contains(node.id)
        ctx.saveGState()
        if dragging { ctx.setAlpha(0.35) }

        let path = shapePath(style.shape, in: frame, radius: style.radius)

        // 搜索高亮底色
        if state.highlighted.contains(node.id) {
            let hl = (state.currentMatch == node.id) ? NSColor.systemYellow : NSColor.systemYellow.withAlphaComponent(0.45)
            ctx.addPath(CGPath(roundedRect: frame.insetBy(dx: -5, dy: -5), cornerWidth: 8, cornerHeight: 8, transform: nil))
            ctx.setFillColor(hl.cgColor)
            ctx.fillPath()
        }

        if let fill = style.fill {
            ctx.addPath(path)
            ctx.setFillColor(fill.cgColor)
            ctx.fillPath()
        }
        if style.shape.isBoxed, let border = style.border, style.borderWidth > 0 {
            let inset = style.borderWidth / 2
            let borderPath = shapePath(style.shape, in: frame.insetBy(dx: inset, dy: inset), radius: max(style.radius - inset, 0))
            ctx.addPath(borderPath)
            ctx.setStrokeColor(border.cgColor)
            ctx.setLineWidth(style.borderWidth)
            ctx.strokePath()
        }
        if style.shape == .underline {
            let color = style.border ?? style.branchColor
            let y = frame.maxY - style.underlineWidth / 2
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(style.underlineWidth)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: frame.minX, y: y))
            ctx.addLine(to: CGPoint(x: frame.maxX, y: y))
            ctx.strokePath()
        }

        drawContent(node, ctx: ctx, hideTitle: state.editing == node.id)
        ctx.restoreGState()

        // 选中 / 悬停描边
        let selected = state.selection.contains(node.id)
        if selected || state.hovered == node.id {
            let ring = frame.insetBy(dx: -4, dy: -4)
            let ringPath: CGPath
            switch style.shape {
            case .ellipse: ringPath = CGPath(ellipseIn: ring, transform: nil)
            case .diamond: ringPath = shapePath(.diamond, in: ring.insetBy(dx: -4, dy: -3), radius: 0)
            case .capsule: ringPath = shapePath(.capsule, in: ring, radius: 0)
            default:
                let r = style.shape.isBoxed ? min(style.radius + 4, ring.height / 2) : 6
                ringPath = CGPath(roundedRect: ring, cornerWidth: r, cornerHeight: r, transform: nil)
            }
            ctx.saveGState()
            ctx.addPath(ringPath)
            ctx.setStrokeColor((selected ? state.accent : state.accent.withAlphaComponent(0.45)).cgColor)
            ctx.setLineWidth(selected ? 2.5 : 1.5)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    private func drawContent(_ node: NodeLayout, ctx: CGContext, hideTitle: Bool) {
        let origin = node.frame.origin
        let content = node.content

        if let imageRect = content.imageRect {
            let r = imageRect.offsetBy(dx: origin.x, dy: origin.y)
            if let id = node.imageID, let image = images(id) {
                ctx.saveGState()
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: 4, cornerHeight: 4, transform: nil))
                ctx.clip()
                image.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                ctx.restoreGState()
            } else {
                ctx.setFillColor(NSColor.gray.withAlphaComponent(0.2).cgColor)
                ctx.fill(r)
            }
        }

        for (marker, rect) in content.markerRects {
            MarkerRenderer.draw(marker, in: rect.offsetBy(dx: origin.x, dy: origin.y))
        }

        if !hideTitle {
            let textRect = content.textRect.offsetBy(dx: origin.x, dy: origin.y)
            content.title.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }

        let iconColor = node.style.text.withAlphaComponent(0.65)
        for (indicator, rect) in content.indicatorRects {
            let r = rect.offsetBy(dx: origin.x, dy: origin.y)
            let iconRect = CGRect(x: r.minX, y: r.minY, width: r.height, height: r.height)
            SymbolImages.draw(indicator.symbolName, in: iconRect, color: iconColor)
            if case .attachments(let n) = indicator, n > 1 {
                let font = NSFont.systemFont(ofSize: r.height * 0.72, weight: .semibold)
                let s = NSAttributedString(string: "\(n)", attributes: [.font: font, .foregroundColor: iconColor])
                s.draw(at: CGPoint(x: iconRect.maxX + 1, y: r.midY - s.size().height / 2))
            }
        }

        for (label, rect) in content.labelRects {
            let r = rect.offsetBy(dx: origin.x, dy: origin.y)
            let base = node.style.branchColor
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil))
            ctx.setFillColor(base.withAlphaComponent(layout.isDarkBackground ? 0.35 : 0.16).cgColor)
            ctx.fillPath()
            let textColor = layout.isDarkBackground ? NSColor.white.withAlphaComponent(0.9) : base.mixed(with: .black, fraction: 0.35)
            let s = NSAttributedString(string: label, attributes: [.font: content.labelFont, .foregroundColor: textColor])
            let size = s.size()
            s.draw(at: CGPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2))
        }
    }

    // MARK: 折叠按钮

    private func drawFoldButton(_ node: NodeLayout, ctx: CGContext, state: RenderState) {
        let rect = layout.foldRect(for: node)
        let color = node.style.branchColor
        ctx.saveGState()
        let path = CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor((node.collapsed ? color : layout.background).cgColor)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokePath()
        if node.collapsed {
            let s = NSAttributedString(string: "\(node.hiddenCount)",
                                       attributes: [.font: MapLayout.foldFont, .foregroundColor: color.contrastingTextColor])
            let size = s.size()
            s.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        } else {
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(1.6)
            ctx.move(to: CGPoint(x: rect.midX - 4, y: rect.midY))
            ctx.addLine(to: CGPoint(x: rect.midX + 4, y: rect.midY))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}

/// SF Symbol 着色后绘制，带缓存。
enum SymbolImages {
    private static var cache: [String: NSImage] = [:]

    /// twoTone：圆形底的符号（checkmark.circle.fill 等）里面的图形画成白色，否则会和底色糊成一片。
    static func image(_ name: String, color: NSColor, pointSize: CGFloat, twoTone: Bool = false) -> NSImage? {
        let key = "\(name)|\(color.hexString)|\(Int(pointSize))|\(twoTone)"
        if let cached = cache[key] { return cached }
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let colors: [NSColor] = twoTone ? [.white, color] : [color]
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: colors))
        let image = base.withSymbolConfiguration(config)
        cache[key] = image
        return image
    }

    static func draw(_ name: String, in rect: CGRect, color: NSColor, twoTone: Bool = false) {
        guard let image = image(name, color: color, pointSize: rect.height, twoTone: twoTone) else { return }
        // 保持符号原始宽高比，居中放入 rect。
        let size = image.size
        let scale = min(rect.width / max(size.width, 1), rect.height / max(size.height, 1))
        let w = size.width * scale, h = size.height * scale
        let target = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

/// 标记图标绘制。
enum MarkerRenderer {
    static func draw(_ marker: MarkerID, in rect: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        switch marker.group {
        case .priority:
            let n = Int(marker.suffix) ?? 1
            let colors = ["#E5484D", "#F76B15", "#E9A800", "#30A46C", "#0090FF", "#8E4EC6"]
            let color = NSColor(hex: colors[max(0, min(colors.count - 1, n - 1))]) ?? .systemRed
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: rect.insetBy(dx: 0.5, dy: 0.5))
            let font = NSFont.systemFont(ofSize: rect.height * 0.62, weight: .bold)
            let s = NSAttributedString(string: "\(n)", attributes: [.font: font, .foregroundColor: NSColor.white])
            let size = s.size()
            s.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        case .task:
            let p = CGFloat(Int(marker.suffix) ?? 0) / 100
            let green = NSColor(hex: "#30A46C")!
            let circle = rect.insetBy(dx: 1, dy: 1)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: circle)
            if p >= 1 {
                ctx.setFillColor(green.cgColor)
                ctx.fillEllipse(in: circle)
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(max(1.5, rect.height * 0.11))
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                ctx.move(to: CGPoint(x: circle.minX + circle.width * 0.27, y: circle.midY + circle.height * 0.02))
                ctx.addLine(to: CGPoint(x: circle.minX + circle.width * 0.44, y: circle.midY + circle.height * 0.2))
                ctx.addLine(to: CGPoint(x: circle.minX + circle.width * 0.74, y: circle.midY - circle.height * 0.18))
                ctx.strokePath()
            } else {
                if p > 0 {
                    let c = CGPoint(x: circle.midX, y: circle.midY)
                    ctx.move(to: c)
                    // 翻转坐标系下，从 12 点方向顺时针画扇形。
                    ctx.addArc(center: c, radius: circle.width / 2 - 1.5, startAngle: -.pi / 2,
                               endAngle: -.pi / 2 + .pi * 2 * p, clockwise: false)
                    ctx.closePath()
                    ctx.setFillColor(green.cgColor)
                    ctx.fillPath()
                }
                ctx.setStrokeColor(green.cgColor)
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: circle.insetBy(dx: 0.75, dy: 0.75))
            }
        case .flag:
            let color = NSColor(hex: MarkerColorName(rawValue: marker.suffix)?.hex ?? "#E5484D") ?? .systemRed
            SymbolImages.draw("flag.fill", in: rect.insetBy(dx: 1, dy: 1), color: color)
        case .star:
            let color = NSColor(hex: MarkerColorName(rawValue: marker.suffix)?.hex ?? "#E9A800") ?? .systemYellow
            SymbolImages.draw("star.fill", in: rect.insetBy(dx: 0.5, dy: 0.5), color: color)
        case .symbol:
            if let def = MarkerCatalog.symbol(for: marker) {
                let twoTone = def.symbol.hasSuffix("circle.fill")
                SymbolImages.draw(def.symbol, in: rect, color: NSColor(hex: def.colorHex) ?? .systemBlue, twoTone: twoTone)
            }
        case nil:
            break
        }
    }

    /// 生成一张标记小图（菜单、检查器里用）。
    static func image(for marker: MarkerID, size: CGFloat = 18) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            draw(marker, in: rect)
            return true
        }
    }
}
