import AppKit

/// 导图画布：绘制、选中、行内编辑、拖动主题、拖入文件。放在 NSScrollView 里，缩放由滚动视图负责。
final class MindMapCanvasView: NSView {
    let editor: MapEditor
    var images: (UUID) -> NSImage? = { _ in nil }

    /// 画布四周留白（布局坐标）。
    static let padding: CGFloat = 640

    /// 布局坐标 → 视图坐标的偏移：view = layout + offset。
    private(set) var offset: CGPoint = .zero
    let textEditor = TopicTextEditor()

    var hovered: UUID?
    var hoveredControl: UUID?
    var dropHighlight: UUID?

    // 拖动主题
    struct DropTarget: Equatable {
        enum Kind: Equatable { case child, before, after }
        var kind: Kind
        /// 参照主题（child 时是新父主题；before/after 时是相邻的兄弟）。
        var reference: UUID
        var parentID: UUID
        var index: Int?
    }

    struct TopicDrag {
        var ids: [UUID]
        var primary: UUID
        var startPoint: CGPoint
        var grabOffset: CGPoint
        var current: CGPoint
        var started = false
        var target: DropTarget?
    }

    var pendingDrag: TopicDrag?
    /// 正在创建联系线：起点主题 + 鼠标位置（布局坐标）。
    var relationshipSource: UUID?
    var relationshipCursor: CGPoint = .zero
    /// 正在拖动联系线的控制柄（which = 1 / 2），session 用于把一次拖动合并成一步撤销。
    var controlDrag: (id: UUID, which: Int, session: String)?
    /// 悬停提示 tag → 对应的主题和图标。
    var toolTipTargets: [NSView.ToolTipTag: (UUID, Indicator)] = [:]
    var marquee: (start: CGPoint, current: CGPoint, base: [UUID])?
    var panning: (start: CGPoint, origin: CGPoint)?
    /// 鼠标按下时点中的是已选中的主题（多选时，松开鼠标才收缩为单选）。
    var clickedSelected: UUID?

    init(editor: MapEditor) {
        self.editor = editor
        super.init(frame: CGRect(x: 0, y: 0, width: 2000, height: 2000))
        editor.delegate = self
        textEditor.onTextChange = { [weak self] text in self?.editor.editingTextDidChange(text) }
        textEditor.onFinish = { [weak self] commit in self?.editor.endEditing(commit: commit) }
        textEditor.onCommand = { [weak self] selector in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
            NSApp.sendAction(selector, to: self, from: nil)
        }
        registerForDraggedTypes([.fileURL, .png, .tiff, .string, .URL])
        updateFrame(anchor: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var mapLayout: MapLayout { editor.layout }

    // MARK: - 坐标

    func viewPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + offset.x, y: p.y + offset.y) }
    func layoutPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - offset.x, y: p.y - offset.y) }
    func viewRect(_ r: CGRect) -> CGRect { r.offsetBy(dx: offset.x, dy: offset.y) }

    func layoutPoint(for event: NSEvent) -> CGPoint {
        layoutPoint(convert(event.locationInWindow, from: nil))
    }

    /// 布局变化后调整画布尺寸；anchor=true 时保持内容在屏幕上的位置不动。
    func updateFrame(anchor: Bool) {
        let bounds = mapLayout.bounds.isEmpty ? CGRect(x: -100, y: -50, width: 200, height: 100) : mapLayout.bounds
        let canvasRect = bounds.insetBy(dx: -Self.padding, dy: -Self.padding).integral
        let newOffset = CGPoint(x: -canvasRect.minX, y: -canvasRect.minY)
        let delta = CGPoint(x: newOffset.x - offset.x, y: newOffset.y - offset.y)
        offset = newOffset
        if frame.size != canvasRect.size { setFrameSize(canvasRect.size) }
        if anchor, delta != .zero, let clip = enclosingScrollView?.contentView {
            var origin = clip.bounds.origin
            origin.x += delta.x
            origin.y += delta.y
            clip.setBoundsOrigin(origin)
            enclosingScrollView?.reflectScrolledClipView(clip)
        }
        positionTextEditor()
        needsDisplay = true
    }

    /// 把布局坐标里的点滚动到可视区域中心。
    func center(onLayoutPoint p: CGPoint) {
        guard let clip = enclosingScrollView?.contentView else { return }
        let v = viewPoint(p)
        let size = clip.bounds.size
        clip.setBoundsOrigin(CGPoint(x: v.x - size.width / 2, y: v.y - size.height / 2))
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    /// 可视区域中心（布局坐标）。
    var visibleCenter: CGPoint {
        let r = visibleRect
        return layoutPoint(CGPoint(x: r.midX, y: r.midY))
    }

    /// 确保主题完整可见（带一点边距）。
    func scrollTopicVisible(_ id: UUID) {
        guard let node = mapLayout.nodes[id] else { return }
        let r = viewRect(node.frame).insetBy(dx: -48, dy: -36)
        let visible = visibleRect
        if visible.contains(r) { return }
        var origin = visible.origin
        if r.width > visible.width || r.minX < visible.minX { origin.x = r.minX } else if r.maxX > visible.maxX { origin.x = r.maxX - visible.width }
        if r.height > visible.height || r.minY < visible.minY { origin.y = r.minY } else if r.maxY > visible.maxY { origin.y = r.maxY - visible.height }
        guard let clip = enclosingScrollView?.contentView else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            clip.animator().setBoundsOrigin(origin)
        }
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    // MARK: - 绘制

    var renderState: RenderState {
        var state = RenderState()
        state.selection = Set(editor.selection)
        state.hovered = hovered
        state.editing = editor.editingID
        if !editor.findQuery.isEmpty {
            state.highlighted = Set(editor.findResults)
            state.currentMatch = editor.currentFindMatch
        }
        var fold = Set<UUID>()
        if let hovered { fold.insert(hovered) }
        if let hoveredControl { fold.insert(hoveredControl) }
        if let primary = editor.primaryID { fold.insert(primary) }
        state.showFoldButtonsFor = fold
        if let drag = pendingDrag, drag.started { state.dragSources = Set(drag.ids) }
        state.selectedRelationship = editor.selectedRelationship
        state.accent = .controlAccentColor
        return state
    }

    /// 创建联系线时，从起点主题到鼠标的预览虚线。
    private func drawRelationshipPreview(_ ctx: CGContext) {
        guard let source = relationshipSource, let node = mapLayout.nodes[source] else { return }
        let accent = NSColor.controlAccentColor
        let start = CGPoint(x: node.frame.midX, y: node.frame.midY)
        var end = relationshipCursor
        if let target = mapLayout.topic(at: relationshipCursor), target != source, let t = mapLayout.nodes[target] {
            end = CGPoint(x: t.frame.midX, y: t.frame.midY)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: t.frame.insetBy(dx: -5, dy: -5), cornerWidth: 8, cornerHeight: 8, transform: nil))
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(2)
            ctx.strokePath()
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()
        ctx.restoreGState()
    }

    func beginRelationship(from source: UUID) {
        relationshipSource = source
        if let node = mapLayout.nodes[source] { relationshipCursor = CGPoint(x: node.frame.midX + 80, y: node.frame.midY - 60) }
        NSCursor.crosshair.set()
        needsDisplay = true
    }

    func cancelRelationship() {
        guard relationshipSource != nil else { return }
        relationshipSource = nil
        hovered = nil
        NSCursor.arrow.set()
        needsDisplay = true
    }

    /// 选中的联系线的控制柄命中测试。
    private func controlHandleHit(at p: CGPoint) -> Int? {
        guard let r = mapLayout.relationship(editor.selectedRelationship) else { return nil }
        if hypot(p.x - r.c1.x, p.y - r.c1.y) <= 8 { return 1 }
        if hypot(p.x - r.c2.x, p.y - r.c2.y) <= 8 { return 2 }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(mapLayout.background.cgColor)
        ctx.fill(dirtyRect)
        ctx.saveGState()
        ctx.translateBy(x: offset.x, y: offset.y)
        let layoutRect = dirtyRect.offsetBy(dx: -offset.x, dy: -offset.y)
        let renderer = MapRenderer(layout: mapLayout, images: images)
        renderer.draw(in: layoutRect, state: renderState, drawBackground: false)
        drawAddButton(ctx)
        drawDropHighlight(ctx)
        drawDragFeedback(ctx, renderer: renderer)
        drawRelationshipPreview(ctx)
        drawMarquee(ctx)
        ctx.restoreGState()
    }

    /// 选中的无子主题主题旁边显示一个“+”按钮，点一下添加子主题。
    var addButtonTarget: UUID? {
        guard !editor.isEditing, editor.selection.count == 1, let id = editor.primaryID,
              let node = mapLayout.nodes[id], node.childCount == 0, pendingDrag?.started != true else { return nil }
        return id
    }

    func addButtonRect(for node: NodeLayout) -> CGRect {
        let r = MapLayout.foldRadius
        return CGRect(x: node.foldCenter.x - r, y: node.foldCenter.y - r, width: r * 2, height: r * 2)
    }

    private func drawAddButton(_ ctx: CGContext) {
        guard let id = addButtonTarget, let node = mapLayout.nodes[id] else { return }
        let rect = addButtonRect(for: node)
        let color = NSColor.controlAccentColor
        let hot = hoveredControl == id
        ctx.saveGState()
        ctx.setFillColor((hot ? color : mapLayout.background).cgColor)
        ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: rect.insetBy(dx: 0.75, dy: 0.75))
        ctx.setStrokeColor((hot ? NSColor.white : color).cgColor)
        ctx.setLineWidth(1.6)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: rect.midX - 4, y: rect.midY))
        ctx.addLine(to: CGPoint(x: rect.midX + 4, y: rect.midY))
        ctx.move(to: CGPoint(x: rect.midX, y: rect.midY - 4))
        ctx.addLine(to: CGPoint(x: rect.midX, y: rect.midY + 4))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawDropHighlight(_ ctx: CGContext) {
        guard let id = dropHighlight, let node = mapLayout.nodes[id] else { return }
        ctx.saveGState()
        let r = node.frame.insetBy(dx: -6, dy: -6)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor)
        ctx.fillPath()
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: [5, 3])
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawDragFeedback(_ ctx: CGContext, renderer: MapRenderer) {
        guard let drag = pendingDrag, drag.started, let node = mapLayout.nodes[drag.primary] else { return }
        let accent = NSColor.controlAccentColor
        if let target = drag.target, let ref = mapLayout.nodes[target.reference] {
            ctx.saveGState()
            ctx.setStrokeColor(accent.cgColor)
            ctx.setFillColor(accent.cgColor)
            switch target.kind {
            case .child:
                let r = ref.frame.insetBy(dx: -5, dy: -5)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: 8, cornerHeight: 8, transform: nil))
                ctx.setLineWidth(2)
                ctx.setLineDash(phase: 0, lengths: [5, 3])
                ctx.strokePath()
                ctx.setLineDash(phase: 0, lengths: [])
                ctx.setLineWidth(1.5)
                ctx.move(to: ref.foldCenter)
                let ghostLeft = CGPoint(x: drag.current.x - drag.grabOffset.x, y: drag.current.y - drag.grabOffset.y + node.frame.height / 2)
                ctx.addLine(to: ghostLeft)
                ctx.strokePath()
            case .before, .after:
                let f = ref.frame
                let vertical = ref.side == .down
                var before = target.kind == .before
                if ref.side == .left && editor.map.structure == .mindMap && ref.level == 1 { before.toggle() }
                let bar: CGRect
                if vertical {
                    let x = before ? f.minX - 8 : f.maxX + 5
                    bar = CGRect(x: x, y: f.minY, width: 3, height: f.height)
                } else {
                    let y = before ? f.minY - 7 : f.maxY + 4
                    bar = CGRect(x: f.minX, y: y, width: max(f.width, 40), height: 3)
                }
                ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
                ctx.fillPath()
            }
            ctx.restoreGState()
        }
        let origin = CGPoint(x: drag.current.x - drag.grabOffset.x, y: drag.current.y - drag.grabOffset.y)
        renderer.drawGhost(node, at: origin)
        if drag.ids.count > 1 {
            let badge = CGRect(x: origin.x + node.frame.width - 8, y: origin.y - 10, width: 20, height: 20)
            ctx.setFillColor(accent.cgColor)
            ctx.fillEllipse(in: badge)
            let s = NSAttributedString(string: "\(drag.ids.count)", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: NSColor.white,
            ])
            let size = s.size()
            s.draw(at: CGPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2))
        }
    }

    private func drawMarquee(_ ctx: CGContext) {
        guard let m = marquee else { return }
        let r = CGRect(x: min(m.start.x, m.current.x), y: min(m.start.y, m.current.y),
                       width: abs(m.current.x - m.start.x), height: abs(m.current.y - m.start.y))
        ctx.saveGState()
        ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor)
        ctx.fill(r)
        ctx.setStrokeColor(NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(r.insetBy(dx: 0.5, dy: 0.5))
        ctx.restoreGState()
    }

    // MARK: - 行内编辑

    func positionTextEditor() {
        guard let id = editor.editingID, let node = mapLayout.nodes[id], textEditor.superview === self else { return }
        let r = viewRect(node.content.textRect.offsetBy(dx: node.frame.minX, dy: node.frame.minY))
        textEditor.frame = CGRect(x: r.minX - 2, y: r.minY, width: r.width + 4, height: max(r.height, 10))
    }

    // MARK: - 悬停

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = layoutPoint(for: event)
        if relationshipSource != nil {
            relationshipCursor = p
            NSCursor.crosshair.set()
            needsDisplay = true
            return
        }
        let control = controlHit(at: p)
        let topic = control == nil ? mapLayout.topic(at: p) : nil
        let newHover = topic ?? control?.id
        let newControl = control?.id
        if newHover != hovered || newControl != hoveredControl {
            invalidate(hovered)
            invalidate(hoveredControl)
            hovered = newHover
            hoveredControl = newControl
            invalidate(hovered)
            invalidate(hoveredControl)
        }
        if control != nil || indicatorHit(at: p) != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        invalidate(hovered)
        invalidate(hoveredControl)
        hovered = nil
        hoveredControl = nil
        NSCursor.arrow.set()
    }

    /// 只重绘一个主题（以及它的折叠按钮）所在区域。
    func invalidate(_ id: UUID?) {
        guard let id, let node = mapLayout.nodes[id] else { return }
        var r = node.frame.insetBy(dx: -8, dy: -8)
        r = r.union(mapLayout.foldRect(for: node).insetBy(dx: -4, dy: -4))
        setNeedsDisplay(viewRect(r))
    }

    // MARK: - 命中测试

    enum ControlHit {
        case fold(UUID)
        case add(UUID)

        var id: UUID {
            switch self {
            case .fold(let id), .add(let id): return id
            }
        }
    }

    func controlHit(at p: CGPoint) -> ControlHit? {
        if let id = addButtonTarget, let node = mapLayout.nodes[id], addButtonRect(for: node).insetBy(dx: -3, dy: -3).contains(p) {
            return .add(id)
        }
        for id in mapLayout.order.reversed() {
            guard let node = mapLayout.nodes[id], node.childCount > 0 else { continue }
            if node.level == 0 && mapLayout.structure == .mindMap { continue }
            // 展开状态的折叠按钮只在悬停/选中时画出来，但点击区域始终有效（鼠标移过去就会显示）。
            if mapLayout.foldRect(for: node).insetBy(dx: -3, dy: -3).contains(p) { return .fold(id) }
        }
        return nil
    }

    func indicatorHit(at p: CGPoint) -> (UUID, Indicator, CGRect)? {
        guard let id = mapLayout.topic(at: p), let node = mapLayout.nodes[id] else { return nil }
        for (indicator, rect) in node.content.indicatorRects {
            let r = rect.offsetBy(dx: node.frame.minX, dy: node.frame.minY).insetBy(dx: -2, dy: -2)
            if r.contains(p) { return (id, indicator, r) }
        }
        return nil
    }

    // MARK: - 鼠标

    override func mouseDown(with event: NSEvent) {
        // 抢回焦点：正在行内编辑时会因此提交编辑
        window?.makeFirstResponder(self)
        let p = layoutPoint(for: event)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let extend = flags.contains(.shift) || flags.contains(.command)
        clickedSelected = nil

        // 创建联系线：点目标主题完成，点其他地方取消
        if let source = relationshipSource {
            cancelRelationship()
            if let target = mapLayout.topic(at: p), target != source {
                editor.addRelationship(from: source, to: target)
            }
            return
        }

        // 拖动选中联系线的控制柄
        if let which = controlHandleHit(at: p), let id = editor.selectedRelationship {
            controlDrag = (id, which, UUID().uuidString)
            return
        }

        if let control = controlHit(at: p) {
            switch control {
            case .fold(let id): editor.toggleFold([id])
            case .add(let id): editor.addChild(to: id)
            }
            return
        }

        if let (id, indicator, rect) = indicatorHit(at: p) {
            editor.select(id)
            handleIndicatorClick(indicator, topic: id, rect: viewRect(rect))
            return
        }

        if let id = mapLayout.topic(at: p) {
            if event.clickCount >= 2 {
                editor.beginEditing(id, selectAll: false)
                return
            }
            if extend {
                editor.select(id, extend: true)
            } else if editor.selection.contains(id) {
                clickedSelected = id
                // 保持多选，便于整体拖动；松开时再收缩为单选
                var s = editor.selection
                s.removeAll { $0 == id }
                s.append(id)
                editor.setSelection(s)
            } else {
                editor.select(id)
            }
            guard let node = mapLayout.nodes[id] else { return }
            let ids = editor.selection.contains(id) ? editor.selection : [id]
            pendingDrag = TopicDrag(ids: ids.filter { $0 != editor.rootID }, primary: id, startPoint: p,
                                    grabOffset: CGPoint(x: p.x - node.frame.minX, y: p.y - node.frame.minY),
                                    current: p)
            return
        }

        // 联系线
        if let rel = mapLayout.relationship(at: p) {
            editor.selectRelationship(rel)
            if event.clickCount >= 2 { showRelationshipLabelPopover(for: rel) }
            return
        }

        // 空白处
        if event.clickCount >= 2 {
            NSApp.sendAction(#selector(MapViewController.zoomToFit(_:)), to: nil, from: self)
            return
        }
        if flags.contains(.option) {
            panning = (event.locationInWindow, enclosingScrollView?.contentView.bounds.origin ?? .zero)
            NSCursor.closedHand.set()
            return
        }
        marquee = (p, p, extend ? editor.selection : [])
        if !extend { editor.select(nil) }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = layoutPoint(for: event)
        if let pan = panning, let clip = enclosingScrollView?.contentView {
            // 视图坐标会随滚动变化，所以用窗口坐标计算位移（窗口 y 向上，画布 y 向下）。
            let now = event.locationInWindow
            let mag = enclosingScrollView?.magnification ?? 1
            let dx = (now.x - pan.start.x) / mag, dy = (now.y - pan.start.y) / mag
            clip.setBoundsOrigin(CGPoint(x: pan.origin.x - dx, y: pan.origin.y + dy))
            enclosingScrollView?.reflectScrolledClipView(clip)
            return
        }
        if let drag = controlDrag, let r = mapLayout.relationship(drag.id) {
            // 控制点存成相对主题中心的偏移，主题移动后弧度保持
            let base = drag.which == 1 ? r.fromCenter : r.toCenter
            let offset = Relationship.Offset(dx: Double(p.x - base.x), dy: Double(p.y - base.y))
            editor.updateRelationship(drag.id, actionName: L("Reshape Relationship"), coalesce: drag.session) { rel in
                if drag.which == 1 {
                    rel.control1 = offset
                    if rel.control2 == nil { rel.control2 = Relationship.Offset(dx: Double(r.c2.x - r.toCenter.x), dy: Double(r.c2.y - r.toCenter.y)) }
                } else {
                    rel.control2 = offset
                    if rel.control1 == nil { rel.control1 = Relationship.Offset(dx: Double(r.c1.x - r.fromCenter.x), dy: Double(r.c1.y - r.fromCenter.y)) }
                }
            }
            autoscroll(with: event)
            return
        }
        if var drag = pendingDrag {
            if !drag.started {
                let d = hypot(p.x - drag.startPoint.x, p.y - drag.startPoint.y)
                guard d > 4, !drag.ids.isEmpty else { return }
                drag.started = true
            }
            drag.current = p
            drag.target = dropTarget(at: p, dragging: drag.ids)
            pendingDrag = drag
            autoscroll(with: event)
            needsDisplay = true
            return
        }
        if var m = marquee {
            m.current = p
            marquee = m
            let r = CGRect(x: min(m.start.x, p.x), y: min(m.start.y, p.y), width: abs(p.x - m.start.x), height: abs(p.y - m.start.y))
            var ids = m.base
            for id in mapLayout.order where mapLayout.nodes[id]!.frame.intersects(r) && !ids.contains(id) { ids.append(id) }
            editor.setSelection(ids)
            autoscroll(with: event)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            pendingDrag = nil
            marquee = nil
            clickedSelected = nil
            controlDrag = nil
            needsDisplay = true
        }
        if panning != nil {
            panning = nil
            NSCursor.arrow.set()
            return
        }
        if let drag = pendingDrag {
            if drag.started {
                if let target = drag.target {
                    let copy = event.modifierFlags.contains(.option)
                    editor.move(drag.ids, to: target.parentID, at: target.index, copy: copy)
                }
            } else if let clicked = clickedSelected, editor.selection.count > 1 {
                editor.select(clicked)
            }
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        panning = (event.locationInWindow, enclosingScrollView?.contentView.bounds.origin ?? .zero)
        NSCursor.closedHand.set()
    }

    override func otherMouseDragged(with event: NSEvent) { mouseDragged(with: event) }

    override func otherMouseUp(with event: NSEvent) {
        panning = nil
        NSCursor.arrow.set()
    }

    override func scrollWheel(with event: NSEvent) {
        // ⌘ + 滚轮缩放（与 XMind 一致）
        if event.modifierFlags.contains(.command), let scrollView = enclosingScrollView {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
            let newMag = max(scrollView.minMagnification, min(scrollView.maxMagnification, scrollView.magnification * (1 + delta)))
            let p = convert(event.locationInWindow, from: nil)
            scrollView.setMagnification(newMag, centeredAt: p)
            editor.zoom = scrollView.magnification
            return
        }
        super.scrollWheel(with: event)
    }

    // MARK: - 拖放目标

    func dropTarget(at p: CGPoint, dragging ids: [UUID]) -> DropTarget? {
        let map = editor.map
        let excluded: (UUID) -> Bool = { id in ids.contains { map.isAncestor($0, of: id) } }

        if let hit = mapLayout.topic(at: p, slop: 4), !excluded(hit), let node = mapLayout.nodes[hit] {
            if node.level == 0 {
                return DropTarget(kind: .child, reference: hit, parentID: hit, index: nil)
            }
            let rel: CGFloat = node.side == .down
                ? (p.x - node.frame.minX) / max(node.frame.width, 1)
                : (p.y - node.frame.minY) / max(node.frame.height, 1)
            if rel > 0.28 && rel < 0.72 {
                return DropTarget(kind: .child, reference: hit, parentID: hit, index: nil)
            }
            guard let parentID = node.parentID, let path = map.path(of: hit), let index = path.last else { return nil }
            var before = rel <= 0.28
            let kind: DropTarget.Kind = before ? .before : .after
            // 思维导图左侧分支视觉顺序与数组顺序相反
            if node.side == .left && map.structure == .mindMap && node.level == 1 { before.toggle() }
            return DropTarget(kind: kind, reference: hit, parentID: parentID, index: before ? index : index + 1)
        }

        // 没有直接落在主题上：找附近的主题，成为它的子主题。
        var best: (NodeLayout, CGFloat)?
        for node in mapLayout.nodes.values where !excluded(node.id) {
            let f = node.frame
            let dx = max(f.minX - p.x, 0, p.x - f.maxX)
            let dy = max(f.minY - p.y, 0, p.y - f.maxY)
            let d = hypot(dx, dy)
            if d < 70, best == nil || d < best!.1 { best = (node, d) }
        }
        guard let (node, _) = best else { return nil }
        // 按位置算出插入到哪两个子主题之间
        let children = node.childIDs.compactMap { mapLayout.nodes[$0] }
        var index: Int?
        if !children.isEmpty, let topic = map.topic(node.id) {
            let ordered = topic.children.map(\.id)
            let vertical = node.childSide == .down
            let after = children.filter { vertical ? $0.frame.midX < p.x : $0.frame.midY < p.y }
            if let last = after.max(by: { vertical ? $0.frame.midX < $1.frame.midX : $0.frame.midY < $1.frame.midY }),
               let i = ordered.firstIndex(of: last.id) {
                index = i + 1
            } else {
                index = 0
            }
            if node.level == 0 && map.structure == .mindMap { index = nil }
        }
        return DropTarget(kind: .child, reference: node.id, parentID: node.id, index: index)
    }

    // MARK: - 键盘

    /// 校验通过才执行（与菜单项的启用状态保持一致）。
    private func performIfValid(_ selector: Selector) {
        let probe = NSMenuItem(title: "", action: selector, keyEquivalent: "")
        if validateMenuItem(probe) {
            NSApp.sendAction(selector, to: self, from: self)
        } else {
            NSSound.beep()
        }
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let shift = flags.contains(.shift)
        // 这些键在菜单里也有快捷键，但 Tab 等会被窗口的键盘焦点切换抢走，所以在这里直接处理。
        if let special = event.specialKey {
            switch (special, flags) {
            case (.tab, []): performIfValid(#selector(insertSubtopic(_:))); return
            case (.backTab, _), (.tab, [.shift]): performIfValid(#selector(promoteTopic(_:))); return
            case (.carriageReturn, []), (.enter, []): performIfValid(#selector(insertTopic(_:))); return
            case (.carriageReturn, [.shift]), (.enter, [.shift]): performIfValid(#selector(insertTopicBefore(_:))); return
            case (.carriageReturn, [.command]), (.enter, [.command]): performIfValid(#selector(insertParentTopic(_:))); return
            case (.delete, []), (.deleteForward, []): performIfValid(#selector(delete(_:))); return
            case (.delete, [.option]), (.deleteForward, [.option]): performIfValid(#selector(deleteTopicOnly(_:))); return
            default: break
            }
        }
        if event.keyCode == 49, flags.isEmpty { // 空格
            performIfValid(#selector(editTopic(_:)))
            return
        }
        if let special = event.specialKey {
            switch special {
            case .upArrow where !flags.contains(.option) && !flags.contains(.command): editor.navigate(.up, extend: shift); return
            case .downArrow where !flags.contains(.option) && !flags.contains(.command): editor.navigate(.down, extend: shift); return
            case .leftArrow where !flags.contains(.option) && !flags.contains(.command): editor.navigate(.left, extend: shift); return
            case .rightArrow where !flags.contains(.option) && !flags.contains(.command): editor.navigate(.right, extend: shift); return
            case .home:
                editor.select(editor.rootID)
                scrollTopicVisible(editor.rootID)
                return
            case .f2:
                editor.beginEditing(selectAll: false)
                return
            default: break
            }
        }
        if event.keyCode == 53 { // Esc
            if relationshipSource != nil {
                cancelRelationship()
            } else if pendingDrag != nil {
                pendingDrag = nil
                needsDisplay = true
            } else {
                editor.select(nil)
            }
            return
        }
        // 直接打字：开始编辑并替换标题（支持输入法）
        if flags.subtracting(.shift).isEmpty, let chars = event.characters, let scalar = chars.unicodeScalars.first,
           !CharacterSet.controlCharacters.contains(scalar), event.specialKey == nil,
           editor.primaryID != nil, editor.selection.count == 1 {
            editor.beginEditing(selectAll: true)
            if textEditor.window != nil {
                textEditor.inputContext?.activate()
                textEditor.keyDown(with: event)
            }
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - MapEditorDelegate

extension MindMapCanvasView: MapEditorDelegate {
    func editorLayoutDidChange(_ editor: MapEditor) {
        updateFrame(anchor: true)
        if let scrollView = enclosingScrollView, scrollView.backgroundColor != mapLayout.background {
            scrollView.backgroundColor = mapLayout.background
        }
        rebuildToolTips()
    }

    func editorSelectionDidChange(_ editor: MapEditor) {
        needsDisplay = true
    }

    func editor(_ editor: MapEditor, beginEditing id: UUID, selectAll: Bool) {
        guard let node = mapLayout.nodes[id], let topic = editor.map.topic(id) else { return }
        textEditor.configure(text: topic.title, font: node.style.font, color: node.style.text, alignment: node.style.alignment)
        textEditor.isHidden = false
        if textEditor.superview !== self { addSubview(textEditor) }
        positionTextEditor()
        scrollTopicVisible(id)
        window?.makeFirstResponder(textEditor)
        if selectAll {
            textEditor.selectAll(nil)
        } else {
            textEditor.setSelectedRange(NSRange(location: (textEditor.string as NSString).length, length: 0))
        }
        needsDisplay = true
    }

    func editorEndEditing(_ editor: MapEditor) {
        if textEditor.isResigning {
            // 焦点正在转到别的控件（例如检查器里的输入框）：先隐藏，下一轮再移除，不抢焦点
            textEditor.isHidden = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.editor.editingID == nil else { return }
                self.textEditor.removeFromSuperview()
                self.textEditor.isHidden = false
            }
        } else {
            let hadFocus = window?.firstResponder === textEditor
            textEditor.removeFromSuperview()
            if hadFocus { window?.makeFirstResponder(self) }
        }
        needsDisplay = true
    }

    func editor(_ editor: MapEditor, reveal id: UUID) {
        scrollTopicVisible(id)
        needsDisplay = true
    }
}

// MARK: - 悬停提示

extension MindMapCanvasView: NSViewToolTipOwner {
    /// 备注 / 链接 / 附件图标的悬停提示：备注显示内容，链接显示地址，附件显示文件名。
    func rebuildToolTips() {
        removeAllToolTips()
        toolTipTargets.removeAll()
        for node in mapLayout.nodes.values {
            for (indicator, rect) in node.content.indicatorRects {
                let r = viewRect(rect.offsetBy(dx: node.frame.minX, dy: node.frame.minY))
                let tag = addToolTip(r, owner: self, userData: nil)
                toolTipTargets[tag] = (node.id, indicator)
            }
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let (id, indicator) = toolTipTargets[tag], let topic = editor.map.topic(id) else { return "" }
        switch indicator {
        case .note:
            let note = topic.note.trimmingCharacters(in: .whitespacesAndNewlines)
            return note.count > 600 ? String(note.prefix(600)) + "…" : note
        case .link:
            return (topic.link ?? "") + "\n" + L("Click to open · ⌥-click to edit")
        case .attachments:
            return topic.attachments.map(\.name).joined(separator: "\n")
        }
    }
}
