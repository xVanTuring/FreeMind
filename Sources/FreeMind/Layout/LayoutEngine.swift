import AppKit

/// 把 MindMap 排成 MapLayout。每次修改后整体重排（O(n)，文字测量有缓存）。
struct LayoutEngine {
    let map: MindMap
    let measurer: TopicMeasurer
    /// 正在编辑的主题使用输入框里的实时文字排版。
    var titleOverride: (id: UUID, title: String)?

    private final class PNode {
        let id: UUID
        let level: Int
        let style: ResolvedStyle
        let content: TopicContent
        var children: [PNode] = []
        let childCount: Int
        let collapsed: Bool
        let hiddenCount: Int
        let boundary: Bool
        let imageID: UUID?
        let link: String?
        weak var parent: PNode?
        var frame: CGRect = .zero
        var side: BranchSide = .root
        var childSide: BranchSide = .right
        /// 组织结构图里，子主题全是叶子时竖向堆叠在下方（避免整张图横向拉得太宽）。
        var stacked = false
        /// 子树在堆叠方向上占用的长度（水平布局为高度，组织结构图为宽度）。
        var extent: CGFloat = 0

        init(id: UUID, level: Int, style: ResolvedStyle, content: TopicContent, childCount: Int,
             collapsed: Bool, hiddenCount: Int, boundary: Bool, imageID: UUID?, link: String?) {
            self.id = id
            self.level = level
            self.style = style
            self.content = content
            self.childCount = childCount
            self.collapsed = collapsed
            self.hiddenCount = hiddenCount
            self.boundary = boundary
            self.imageID = imageID
            self.link = link
            self.frame.size = content.size
        }
    }

    // MARK: 间距

    private var factor: CGFloat { CGFloat(map.spacing.factor) }
    private let boundaryPad: CGFloat = 10

    /// 父主题到子主题的水平间隔。
    private func hGap(fromLevel level: Int) -> CGFloat {
        (level == 0 ? 56 : level == 1 ? 38 : 30) * factor
    }

    /// 同级主题之间的竖直间隔。
    private func vGap(childLevel level: Int) -> CGFloat {
        (level <= 1 ? 22 : 10) * factor
    }

    private func orgVGap(fromLevel level: Int) -> CGFloat { (level == 0 ? 48 : 34) * factor }
    private func orgHGap(childLevel level: Int) -> CGFloat { (level <= 1 ? 26 : 14) * factor }
    private var treeIndent: CGFloat { 30 * factor }
    private var treeVGap: CGFloat { 10 * factor }
    private var treeSpineInset: CGFloat { 14 }

    // MARK: 入口

    func run() -> MapLayout {
        let theme = map.theme
        let root = prepare(map.root, level: 0, branch: theme.centralBranchColor, branchIndex: 0)

        switch map.structure {
        case .mindMap: placeMindMap(root)
        case .logicRight: placeLogic(root, dir: 1)
        case .logicLeft: placeLogic(root, dir: -1)
        case .orgChart: placeOrg(root)
        case .tree: placeTree(root)
        }

        var layout = MapLayout()
        layout.rootID = root.id
        layout.lineStyle = map.effectiveLineStyle
        layout.structure = map.structure
        layout.background = theme.backgroundColor
        layout.isDarkBackground = theme.isDark
        collect(root, into: &layout)
        computeSubtreeBounds(root, layout: &layout)
        layoutRelationships(into: &layout)

        var bounds = CGRect.null
        for node in layout.nodes.values {
            bounds = bounds.union(node.frame)
            if node.childCount > 0 { bounds = bounds.union(layout.foldRect(for: node)) }
            if node.hasBoundary { bounds = bounds.union(node.subtreeBounds.insetBy(dx: -boundaryPad, dy: -boundaryPad)) }
        }
        for r in layout.relationships { bounds = bounds.union(r.bounds) }
        layout.bounds = bounds.isNull ? .zero : bounds
        return layout
    }

    // MARK: 联系线

    /// 联系线默认颜色（与主题背景形成对比的紫色）。
    static func defaultRelationshipColor(dark: Bool) -> NSColor {
        NSColor(hex: dark ? "#C4B5FD" : "#7C5CDB") ?? .systemPurple
    }

    private func layoutRelationships(into layout: inout MapLayout) {
        guard !map.relationships.isEmpty else { return }
        // 端点被折叠隐藏时，连到最近的可见祖先
        var parent: [UUID: UUID] = [:]
        func walk(_ t: Topic) {
            for c in t.children {
                parent[c.id] = t.id
                walk(c)
            }
        }
        walk(map.root)
        func visibleNode(_ id: UUID) -> NodeLayout? {
            var current: UUID? = id
            while let c = current {
                if let n = layout.nodes[c] { return n }
                current = parent[c]
            }
            return nil
        }

        let theme = map.theme
        let defaultColor = Self.defaultRelationshipColor(dark: theme.isDark)
        for rel in map.relationships {
            guard let a = visibleNode(rel.from), let b = visibleNode(rel.to), a.id != b.id else { continue }
            let ca = CGPoint(x: a.frame.midX, y: a.frame.midY)
            let cb = CGPoint(x: b.frame.midX, y: b.frame.midY)
            let dx = cb.x - ca.x, dy = cb.y - ca.y
            let length = max(hypot(dx, dy), 1)
            var nx = -dy / length, ny = dx / length
            let bulge = min(length * 0.3, 140)
            var labelSize = CGSize.zero
            if !rel.title.isEmpty {
                let attributed = NSAttributedString(string: rel.title, attributes: [.font: RelationshipLayout.labelFont])
                labelSize = measurer.measureText(attributed, font: RelationshipLayout.labelFont, maxWidth: 200)
                labelSize.width += 12
                labelSize.height += 6
            }
            if rel.control1 == nil || rel.control2 == nil {
                // 自动弧度：两侧都试一下，选压到主题更少的一侧；一样多时朝远离中心主题的方向
                func controls(_ sign: CGFloat) -> (CGPoint, CGPoint) {
                    (CGPoint(x: ca.x + dx * 0.3 + sign * nx * bulge, y: ca.y + dy * 0.3 + sign * ny * bulge),
                     CGPoint(x: ca.x + dx * 0.7 + sign * nx * bulge, y: ca.y + dy * 0.7 + sign * ny * bulge))
                }
                func collisions(_ sign: CGFloat) -> Int {
                    let (k1, k2) = controls(sign)
                    let probe = RelationshipLayout(id: rel.id, from: a.id, to: b.id, p0: ca, c1: k1, c2: k2, p3: cb,
                                                   color: .clear, dashed: false, arrowStart: false, arrowEnd: false,
                                                   title: "", labelRect: nil, fromCenter: ca, toCenter: cb)
                    // 压到中心主题代价最高，其次是分支主题
                    var hits = 0
                    for i in 1..<20 {
                        let q = probe.point(at: CGFloat(i) / 20)
                        for node in layout.nodes.values where node.id != a.id && node.id != b.id {
                            if node.frame.insetBy(dx: -6, dy: -6).contains(q) {
                                hits += node.level == 0 ? 6 : (node.level == 1 ? 2 : 1)
                                break
                            }
                        }
                    }
                    if labelSize != .zero {
                        let mid = probe.point(at: 0.5)
                        let label = CGRect(x: mid.x - labelSize.width / 2, y: mid.y - labelSize.height / 2,
                                           width: labelSize.width, height: labelSize.height)
                        for node in layout.nodes.values where node.frame.insetBy(dx: -4, dy: -4).intersects(label) {
                            hits += 4
                        }
                    }
                    return hits
                }
                let plus = collisions(1), minus = collisions(-1)
                let mid = CGPoint(x: (ca.x + cb.x) / 2, y: (ca.y + cb.y) / 2)
                let outward: CGFloat = (nx * mid.x + ny * mid.y) >= 0 ? 1 : -1
                let sign: CGFloat = plus == minus ? outward : (plus < minus ? 1 : -1)
                nx *= sign
                ny *= sign
            }
            let c1 = rel.control1.map { CGPoint(x: ca.x + $0.dx, y: ca.y + $0.dy) }
                ?? CGPoint(x: ca.x + dx * 0.3 + nx * bulge, y: ca.y + dy * 0.3 + ny * bulge)
            let c2 = rel.control2.map { CGPoint(x: cb.x + $0.dx, y: cb.y + $0.dy) }
                ?? CGPoint(x: ca.x + dx * 0.7 + nx * bulge, y: ca.y + dy * 0.7 + ny * bulge)
            let p0 = Self.boundaryPoint(a.frame.insetBy(dx: -3, dy: -3), toward: c1)
            let p3 = Self.boundaryPoint(b.frame.insetBy(dx: -3, dy: -3), toward: c2)
            let color = rel.color?.resolve(branch: defaultColor, background: theme.backgroundColor) ?? defaultColor
            var r = RelationshipLayout(id: rel.id, from: rel.from, to: rel.to, p0: p0, c1: c1, c2: c2, p3: p3,
                                       color: color, dashed: rel.dashed, arrowStart: rel.arrowStart, arrowEnd: rel.arrowEnd,
                                       title: rel.title, labelRect: nil, fromCenter: ca, toCenter: cb)
            if labelSize != .zero {
                let mid = r.point(at: 0.5)
                r.labelRect = CGRect(x: mid.x - labelSize.width / 2, y: mid.y - labelSize.height / 2,
                                     width: labelSize.width, height: labelSize.height)
            }
            layout.relationships.append(r)
        }
    }

    /// 从矩形中心射向 target 的射线与矩形边框的交点。
    static func boundaryPoint(_ rect: CGRect, toward target: CGPoint) -> CGPoint {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let dx = target.x - c.x, dy = target.y - c.y
        guard abs(dx) > 0.001 || abs(dy) > 0.001 else { return c }
        let tx = abs(dx) < 0.001 ? CGFloat.infinity : (rect.width / 2) / abs(dx)
        let ty = abs(dy) < 0.001 ? CGFloat.infinity : (rect.height / 2) / abs(dy)
        let t = min(tx, ty, 1)
        return CGPoint(x: c.x + dx * t, y: c.y + dy * t)
    }

    // MARK: 准备（样式 + 尺寸）

    private func prepare(_ topic: Topic, level: Int, branch: NSColor, branchIndex: Int) -> PNode {
        let theme = map.theme
        var branchColor = branch
        if level == 1 { branchColor = theme.branchColor(at: branchIndex) }
        if let override = topic.style.branchColor,
           let color = override.resolve(branch: branchColor, background: theme.backgroundColor) {
            branchColor = color
        }
        let style = ResolvedStyle.resolve(topic: topic, level: level, branchColor: branchColor, theme: theme)
        var title = topic.title
        if let titleOverride, titleOverride.id == topic.id { title = titleOverride.title }
        let content = measurer.content(for: topic, title: title, style: style, level: level, maxWidth: map.topicMaxWidth)
        let collapsed = topic.collapsed && level > 0 && !topic.children.isEmpty
        let node = PNode(id: topic.id, level: level, style: style, content: content,
                         childCount: topic.children.count, collapsed: collapsed,
                         hiddenCount: collapsed ? topic.subtreeCount - 1 : 0,
                         boundary: topic.style.boundary ?? false, imageID: topic.image?.id, link: topic.link)
        if !collapsed {
            for (i, child) in topic.children.enumerated() {
                let c = prepare(child, level: level + 1, branch: branchColor, branchIndex: i)
                c.parent = node
                node.children.append(c)
            }
        }
        return node
    }

    // MARK: 水平布局（思维导图 / 逻辑图）

    private func measureHorizontal(_ n: PNode) {
        let pad = n.boundary ? boundaryPad * 2 : 0
        guard !n.children.isEmpty else { n.extent = n.frame.height + pad; return }
        n.children.forEach(measureHorizontal)
        let gap = vGap(childLevel: n.level + 1)
        let sum = n.children.reduce(0) { $0 + $1.extent } + gap * CGFloat(n.children.count - 1)
        n.extent = max(n.frame.height, sum) + pad
    }

    /// edgeX：主题靠近父主题那一侧的 x；top：子树块的上边缘。
    private func placeHorizontal(_ n: PNode, dir: CGFloat, edgeX: CGFloat, top: CGFloat) {
        let pad = n.boundary ? boundaryPad : 0
        let inner = n.extent - pad * 2
        let centerY = top + pad + inner / 2
        let w = n.frame.width, h = n.frame.height
        n.frame = CGRect(x: dir > 0 ? edgeX : edgeX - w, y: centerY - h / 2, width: w, height: h)
        n.side = dir > 0 ? .right : .left
        n.childSide = n.side
        layoutChildrenHorizontal(n, dir: dir, centerY: centerY)
    }

    private func layoutChildrenHorizontal(_ n: PNode, dir: CGFloat, centerY: CGFloat) {
        guard !n.children.isEmpty else { return }
        let gap = vGap(childLevel: n.level + 1)
        let sum = n.children.reduce(0) { $0 + $1.extent } + gap * CGFloat(n.children.count - 1)
        let childEdge = dir > 0 ? n.frame.maxX + hGap(fromLevel: n.level) : n.frame.minX - hGap(fromLevel: n.level)
        var y = centerY - sum / 2
        for c in n.children {
            placeHorizontal(c, dir: dir, edgeX: childEdge, top: y)
            y += c.extent + gap
        }
    }

    private func placeRootCentered(_ root: PNode) {
        root.frame = CGRect(x: -root.frame.width / 2, y: -root.frame.height / 2,
                            width: root.frame.width, height: root.frame.height)
        root.side = .root
    }

    private func placeLogic(_ root: PNode, dir: CGFloat) {
        placeRootCentered(root)
        root.childSide = dir > 0 ? .right : .left
        root.children.forEach(measureHorizontal)
        layoutChildrenHorizontal(root, dir: dir, centerY: 0)
    }

    private func placeMindMap(_ root: PNode) {
        placeRootCentered(root)
        root.childSide = .right
        root.children.forEach(measureHorizontal)
        let count = root.children.count
        let rightCount = (count + 1) / 2
        let right = Array(root.children.prefix(rightCount))
        // 顺时针：右侧从上到下，左侧从下到上。
        let left = Array(root.children.suffix(from: rightCount).reversed())
        let gap = vGap(childLevel: 1)

        func stack(_ list: [PNode], dir: CGFloat) {
            guard !list.isEmpty else { return }
            let sum = list.reduce(0) { $0 + $1.extent } + gap * CGFloat(list.count - 1)
            let edge = dir > 0 ? root.frame.maxX + hGap(fromLevel: 0) : root.frame.minX - hGap(fromLevel: 0)
            var y = -sum / 2
            for c in list {
                placeHorizontal(c, dir: dir, edgeX: edge, top: y)
                y += c.extent + gap
            }
        }
        stack(right, dir: 1)
        stack(left, dir: -1)
    }

    // MARK: 组织结构图（向下）

    private var orgStackIndent: CGFloat { 26 }

    private func measureOrg(_ n: PNode) {
        let pad = n.boundary ? boundaryPad * 2 : 0
        guard !n.children.isEmpty else { n.extent = n.frame.width + pad; return }
        n.children.forEach(measureOrg)
        if n.level >= 1 && n.children.allSatisfy({ $0.children.isEmpty }) {
            n.stacked = true
            let widest = n.children.map(\.frame.width).max() ?? 0
            n.extent = max(n.frame.width, orgStackIndent + widest) + pad
            return
        }
        let gap = orgHGap(childLevel: n.level + 1)
        let sum = n.children.reduce(0) { $0 + $1.extent } + gap * CGFloat(n.children.count - 1)
        n.extent = max(n.frame.width, sum) + pad
    }

    private func placeOrgNode(_ n: PNode, left: CGFloat, top: CGFloat) {
        let pad = n.boundary ? boundaryPad : 0
        let inner = n.extent - pad * 2
        n.side = .down
        if n.stacked {
            // 主题靠左，叶子子主题依次竖排在下方，用树状连线连接
            n.frame.origin = CGPoint(x: left + pad, y: top + pad)
            n.childSide = .tree
            var y = n.frame.maxY + treeVGap * 1.4
            for c in n.children {
                c.frame.origin = CGPoint(x: n.frame.minX + orgStackIndent, y: y)
                c.side = .tree
                c.childSide = .right
                y = c.frame.maxY + treeVGap
            }
            return
        }
        let centerX = left + pad + inner / 2
        n.frame = CGRect(x: centerX - n.frame.width / 2, y: top + pad, width: n.frame.width, height: n.frame.height)
        n.childSide = .down
        layoutChildrenOrg(n, centerX: centerX)
    }

    private func layoutChildrenOrg(_ n: PNode, centerX: CGFloat) {
        guard !n.children.isEmpty else { return }
        let gap = orgHGap(childLevel: n.level + 1)
        let sum = n.children.reduce(0) { $0 + $1.extent } + gap * CGFloat(n.children.count - 1)
        var x = centerX - sum / 2
        let top = n.frame.maxY + orgVGap(fromLevel: n.level)
        for c in n.children {
            placeOrgNode(c, left: x, top: top)
            x += c.extent + gap
        }
    }

    private func placeOrg(_ root: PNode) {
        placeRootCentered(root)
        root.childSide = .down
        root.children.forEach(measureOrg)
        layoutChildrenOrg(root, centerX: 0)
    }

    // MARK: 树状图（缩进）

    private func placeTree(_ root: PNode) {
        placeRootCentered(root)
        root.childSide = .tree
        var y = root.frame.maxY + treeVGap * 1.6
        for c in root.children {
            y = placeTreeNode(c, x: root.frame.minX + treeIndent, top: y) + treeVGap
        }
    }

    /// 返回子树底部 y。
    private func placeTreeNode(_ n: PNode, x: CGFloat, top: CGFloat) -> CGFloat {
        n.frame = CGRect(x: x, y: top, width: n.frame.width, height: n.frame.height)
        n.side = .tree
        n.childSide = .tree
        var y = n.frame.maxY + treeVGap
        var bottom = n.frame.maxY
        for c in n.children {
            bottom = placeTreeNode(c, x: x + treeIndent, top: y)
            y = bottom + treeVGap
        }
        return bottom
    }

    // MARK: 输出

    private func anchorY(_ n: PNode) -> CGFloat {
        n.style.shape == .underline ? n.frame.maxY - n.style.underlineWidth / 2 : n.frame.midY
    }

    /// 主题出发去连接子主题的锚点。
    private func outAnchor(_ n: PNode, toward side: BranchSide) -> CGPoint {
        switch side {
        case .right:
            return CGPoint(x: n.frame.maxX, y: n.level == 0 ? n.frame.midY : anchorY(n))
        case .left:
            return CGPoint(x: n.frame.minX, y: n.level == 0 ? n.frame.midY : anchorY(n))
        case .down:
            return CGPoint(x: n.frame.midX, y: n.frame.maxY)
        case .tree:
            return CGPoint(x: n.frame.minX + min(treeSpineInset, n.frame.width / 2), y: n.frame.maxY)
        case .root:
            return CGPoint(x: n.frame.midX, y: n.frame.midY)
        }
    }

    /// 子主题接入连线的锚点。
    private func inAnchor(_ n: PNode) -> CGPoint {
        switch n.side {
        case .right: return CGPoint(x: n.frame.minX, y: anchorY(n))
        case .left: return CGPoint(x: n.frame.maxX, y: anchorY(n))
        case .down: return CGPoint(x: n.frame.midX, y: n.frame.minY)
        case .tree: return CGPoint(x: n.frame.minX, y: anchorY(n))
        case .root: return CGPoint(x: n.frame.midX, y: n.frame.midY)
        }
    }

    private func foldCenter(_ n: PNode) -> CGPoint {
        let r = MapLayout.foldRadius
        if n.stacked {
            return CGPoint(x: outAnchor(n, toward: .tree).x, y: n.frame.maxY + r + 1)
        }
        switch n.childSide {
        case .right:
            let a = outAnchor(n, toward: .right)
            return CGPoint(x: a.x + r + 3, y: a.y)
        case .left:
            let a = outAnchor(n, toward: .left)
            return CGPoint(x: a.x - r - 3, y: a.y)
        case .down:
            return CGPoint(x: n.frame.midX, y: n.frame.maxY + r + 3)
        case .tree:
            return CGPoint(x: n.frame.minX - r - 4, y: n.frame.midY)
        case .root:
            return CGPoint(x: n.frame.maxX + r + 3, y: n.frame.midY)
        }
    }

    private func collect(_ n: PNode, into layout: inout MapLayout) {
        let node = NodeLayout(
            id: n.id, frame: n.frame, level: n.level, side: n.side, childSide: n.childSide,
            style: n.style, content: n.content, parentID: n.parent?.id, childIDs: n.children.map(\.id),
            childCount: n.childCount, collapsed: n.collapsed, hiddenCount: n.hiddenCount,
            hasBoundary: n.boundary, foldCenter: foldCenter(n), subtreeBounds: n.frame,
            imageID: n.imageID, link: n.link)
        layout.nodes[n.id] = node
        layout.order.append(n.id)

        let theme = map.theme
        for c in n.children {
            let from = outAnchor(n, toward: c.side == .root ? n.childSide : c.side)
            let to = inAnchor(c)
            let orientation: ConnectorOrientation
            let spine: CGFloat
            let direction: CGFloat
            switch c.side {
            case .down:
                orientation = .vertical
                spine = from.y + orgVGap(fromLevel: n.level) / 2
                direction = 1
            case .tree:
                orientation = .tree
                spine = from.x
                direction = 1
            case .left:
                orientation = .horizontal
                spine = from.x - hGap(fromLevel: n.level) / 2
                direction = -1
            default:
                orientation = .horizontal
                spine = from.x + hGap(fromLevel: n.level) / 2
                direction = 1
            }
            let color = theme.linePaint.resolve(branch: c.style.branchColor, background: theme.backgroundColor)
                ?? c.style.branchColor
            let width = CGFloat(c.level == 1 ? theme.mainLineWidth : theme.lineWidth)
            layout.connectors.append(Connector(parentID: n.id, childID: c.id, from: from, to: to,
                                               orientation: orientation, spine: spine, color: color,
                                               width: width, direction: direction))
            collect(c, into: &layout)
        }
    }

    @discardableResult
    private func computeSubtreeBounds(_ n: PNode, layout: inout MapLayout) -> CGRect {
        var rect = n.frame
        for c in n.children { rect = rect.union(computeSubtreeBounds(c, layout: &layout)) }
        layout.nodes[n.id]?.subtreeBounds = rect
        return rect
    }
}
