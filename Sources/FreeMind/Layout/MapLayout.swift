import AppKit

/// 分支相对父主题的生长方向。
enum BranchSide: Equatable {
    case root, right, left, down, tree

    var isHorizontal: Bool { self == .right || self == .left }
}

enum ConnectorOrientation {
    case horizontal, vertical, tree
}

struct NodeLayout {
    let id: UUID
    var frame: CGRect
    let level: Int
    /// 自身所在的一侧（根主题为 .root）。
    let side: BranchSide
    /// 子主题向哪个方向生长。
    let childSide: BranchSide
    let style: ResolvedStyle
    let content: TopicContent
    let parentID: UUID?
    let childIDs: [UUID]
    /// 直接子主题数量（含折叠隐藏的）。
    let childCount: Int
    let collapsed: Bool
    /// 折叠后隐藏的后代数量。
    let hiddenCount: Int
    let hasBoundary: Bool
    /// 折叠按钮 / 添加按钮的中心位置。
    var foldCenter: CGPoint
    /// 整棵（可见）子树的包围框。
    var subtreeBounds: CGRect
    let imageID: UUID?
    let link: String?
}

struct Connector {
    let parentID: UUID
    let childID: UUID
    var from: CGPoint
    var to: CGPoint
    let orientation: ConnectorOrientation
    /// 折线共用主干的位置：水平布局是 x，竖直布局是 y，树状图是竖线 x。
    var spine: CGFloat
    let color: NSColor
    let width: CGFloat
    /// 连线朝向（+1 向右/向下，-1 向左）。
    let direction: CGFloat
}

/// 联系线的几何：三次贝塞尔曲线 p0 → p3，控制点 c1 / c2。
struct RelationshipLayout {
    let id: UUID
    let from: UUID
    let to: UUID
    var p0: CGPoint
    var c1: CGPoint
    var c2: CGPoint
    var p3: CGPoint
    let color: NSColor
    let dashed: Bool
    let arrowStart: Bool
    let arrowEnd: Bool
    let title: String
    var labelRect: CGRect?
    /// 主题中心（拖动控制点时换算偏移用）。
    let fromCenter: CGPoint
    let toCenter: CGPoint

    static let labelFont = NSFont.systemFont(ofSize: 12, weight: .medium)

    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p3.x,
                       y: a * p0.y + b * c1.y + c * c2.y + d * p3.y)
    }

    var bounds: CGRect {
        var r = CGRect(x: min(p0.x, c1.x, c2.x, p3.x), y: min(p0.y, c1.y, c2.y, p3.y), width: 0, height: 0)
        r.size = CGSize(width: max(p0.x, c1.x, c2.x, p3.x) - r.minX, height: max(p0.y, c1.y, c2.y, p3.y) - r.minY)
        if let labelRect { r = r.union(labelRect) }
        return r.insetBy(dx: -8, dy: -8)
    }

    /// 点到曲线的近似最短距离（采样）。
    func distance(to p: CGPoint) -> CGFloat {
        var best = CGFloat.greatestFiniteMagnitude
        for i in 0...48 {
            let q = point(at: CGFloat(i) / 48)
            best = min(best, hypot(q.x - p.x, q.y - p.y))
        }
        return best
    }
}

/// 一次完整布局的结果。坐标以根主题中心为原点。
struct MapLayout {
    var nodes: [UUID: NodeLayout] = [:]
    /// 绘制顺序（深度优先）。
    var order: [UUID] = []
    var connectors: [Connector] = []
    var relationships: [RelationshipLayout] = []
    var bounds: CGRect = .zero
    var rootID: UUID?
    var lineStyle: LineStyle = .curve
    var structure: MapStructure = .mindMap
    var background: NSColor = .white
    var isDarkBackground = false

    static let foldRadius: CGFloat = 8

    func node(_ id: UUID?) -> NodeLayout? {
        guard let id else { return nil }
        return nodes[id]
    }

    /// 命中测试：返回点所在的主题（后绘制的优先）。
    func topic(at point: CGPoint, slop: CGFloat = 2) -> UUID? {
        for id in order.reversed() {
            if let n = nodes[id], n.frame.insetBy(dx: -slop, dy: -slop).contains(point) { return id }
        }
        return nil
    }

    func relationship(_ id: UUID?) -> RelationshipLayout? {
        guard let id else { return nil }
        return relationships.first { $0.id == id }
    }

    /// 命中测试：点在联系线（或其标签）附近。
    func relationship(at p: CGPoint, tolerance: CGFloat = 6) -> UUID? {
        for r in relationships.reversed() {
            if let label = r.labelRect, label.insetBy(dx: -2, dy: -2).contains(p) { return r.id }
            guard r.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p) else { continue }
            if r.distance(to: p) <= tolerance { return r.id }
        }
        return nil
    }

    func foldRect(for node: NodeLayout) -> CGRect {
        let r = MapLayout.foldRadius
        var width = r * 2
        if node.collapsed {
            let text = "\(node.hiddenCount)" as NSString
            let w = text.size(withAttributes: [.font: MapLayout.foldFont]).width
            width = max(r * 2, ceil(w) + 10)
        }
        var center = node.foldCenter
        // 折叠徽标变宽时，向外侧延展，避免压住主题。
        switch node.childSide {
        case .right: center.x += (width - r * 2) / 2
        case .left: center.x -= (width - r * 2) / 2
        default: break
        }
        return CGRect(x: center.x - width / 2, y: center.y - r, width: width, height: r * 2)
    }

    static let foldFont = NSFont.systemFont(ofSize: 10, weight: .bold)

    /// 视觉上的上下左右邻居，用于方向键导航。
    func neighbor(of id: UUID, direction: NavigationDirection, preferredChild: UUID? = nil) -> UUID? {
        guard let node = nodes[id] else { return nil }

        // 先按树关系导航：朝子主题方向 → 子主题；朝父主题方向 → 父主题。
        let towardChildren: Bool
        let towardParent: Bool
        switch (node.childSide, direction) {
        case (.right, .right), (.left, .left), (.down, .down), (.tree, .right): towardChildren = true
        // 组织结构图里竖排叶子的父主题：向下进入子主题
        case (.tree, .down) where node.side == .down: towardChildren = true
        default: towardChildren = false
        }
        switch (node.side, direction) {
        case (.right, .left), (.left, .right), (.down, .up), (.tree, .left): towardParent = true
        default: towardParent = false
        }

        if node.side == .root && structure == .mindMap && (direction == .left || direction == .right) {
            // 根主题左右两侧都有分支：找该侧离根最近的子主题。
            let candidates = node.childIDs.compactMap { nodes[$0] }.filter { direction == .right ? $0.side == .right : $0.side == .left }
            return candidates.min { abs($0.frame.midY - node.frame.midY) < abs($1.frame.midY - node.frame.midY) }?.id
        }
        if towardChildren {
            let visible = node.childIDs.compactMap { nodes[$0] }
            guard !visible.isEmpty else { return nil }
            if let preferredChild, visible.contains(where: { $0.id == preferredChild }) { return preferredChild }
            if node.childSide == .down {
                return visible.min { abs($0.frame.midX - node.frame.midX) < abs($1.frame.midX - node.frame.midX) }?.id
            }
            if node.childSide == .tree { return visible.first?.id }
            return visible.min { abs($0.frame.midY - node.frame.midY) < abs($1.frame.midY - node.frame.midY) }?.id
        }
        if towardParent { return node.parentID }

        // 同级方向：优先兄弟主题，其次空间上最近的主题。
        if let parentID = node.parentID, let parent = nodes[parentID] {
            let siblings = parent.childIDs.compactMap { nodes[$0] }.filter { $0.side == node.side }
            let candidates: [NodeLayout]
            switch direction {
            case .up: candidates = siblings.filter { $0.frame.midY < node.frame.midY - 1 }
            case .down: candidates = siblings.filter { $0.frame.midY > node.frame.midY + 1 }
            case .left: candidates = siblings.filter { $0.frame.midX < node.frame.midX - 1 }
            case .right: candidates = siblings.filter { $0.frame.midX > node.frame.midX + 1 }
            }
            let best = candidates.min { distance(node, $0, direction) < distance(node, $1, direction) }
            if let best { return best.id }
        }
        return spatialNeighbor(of: node, direction: direction)
    }

    private func distance(_ a: NodeLayout, _ b: NodeLayout, _ direction: NavigationDirection) -> CGFloat {
        let dx = b.frame.midX - a.frame.midX, dy = b.frame.midY - a.frame.midY
        switch direction {
        case .up, .down: return abs(dy) + abs(dx) * 3
        case .left, .right: return abs(dx) + abs(dy) * 3
        }
    }

    private func spatialNeighbor(of node: NodeLayout, direction: NavigationDirection) -> UUID? {
        var best: (UUID, CGFloat)?
        for other in nodes.values where other.id != node.id {
            let dx = other.frame.midX - node.frame.midX, dy = other.frame.midY - node.frame.midY
            let ok: Bool
            switch direction {
            case .up: ok = other.frame.maxY <= node.frame.minY + 2
            case .down: ok = other.frame.minY >= node.frame.maxY - 2
            case .left: ok = other.frame.maxX <= node.frame.minX + 2
            case .right: ok = other.frame.minX >= node.frame.maxX - 2
            }
            guard ok else { continue }
            let score: CGFloat
            switch direction {
            case .up, .down: score = abs(dy) + abs(dx) * 2.5
            case .left, .right: score = abs(dx) + abs(dy) * 2.5
            }
            if best == nil || score < best!.1 { best = (other.id, score) }
        }
        return best?.0
    }
}

enum NavigationDirection {
    case up, down, left, right
}
