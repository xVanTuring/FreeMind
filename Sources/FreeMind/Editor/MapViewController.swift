import AppKit
import SwiftUI

/// 内容比可视区域小时居中显示的 clip view。
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

/// 导图编辑区：查找栏 + 可缩放画布 + 状态栏。
final class MapViewController: NSViewController {
    let editor: MapEditor
    let canvas: MindMapCanvasView
    let scrollView = NSScrollView()
    private var findBar: NSView!
    private var findBarHeight: NSLayoutConstraint!
    private var didInitialPosition = false
    private var pendingViewState: ViewState?

    init(editor: MapEditor, images: @escaping (UUID) -> NSImage?) {
        self.editor = editor
        canvas = MindMapCanvasView(editor: editor)
        canvas.images = images
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()

        scrollView.contentView = CenteringClipView()
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        // 默认会把触控板滚动锁定在起手时的主方向（只能水平或垂直）；导图是二维画布，要能斜着任意拖
        scrollView.usesPredominantAxisScrolling = false
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 4
        scrollView.drawsBackground = true
        scrollView.backgroundColor = editor.layout.background
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let find = NSHostingView(rootView: FindBarView(editor: editor, close: { [weak self] in self?.hideFindBar() }))
        find.translatesAutoresizingMaskIntoConstraints = false
        find.isHidden = true
        findBar = find

        let status = NSHostingView(rootView: StatusBarView(editor: editor, zoomAction: { [weak self] zoom in self?.setZoom(zoom) }))
        status.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(scrollView)
        root.addSubview(find)
        root.addSubview(status)
        findBarHeight = find.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            find.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            find.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            find.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            findBarHeight,
            scrollView.topAnchor.constraint(equalTo: find.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: status.topAnchor),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            status.heightAnchor.constraint(equalToConstant: 26),
        ])
        view = root

        NotificationCenter.default.addObserver(self, selector: #selector(magnificationChanged),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func restore(_ state: ViewState?) {
        pendingViewState = state
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard !didInitialPosition, scrollView.contentView.bounds.width > 0 else { return }
        didInitialPosition = true
        canvas.updateFrame(anchor: false)
        if let state = pendingViewState, Preferences.shared.restoreViewState {
            scrollView.magnification = max(scrollView.minMagnification, min(scrollView.maxMagnification, CGFloat(state.zoom)))
            canvas.center(onLayoutPoint: CGPoint(x: state.centerX, y: state.centerY))
            editor.setSelection(state.selection)
        } else {
            fitIfNeeded()
        }
        editor.zoom = scrollView.magnification
    }

    /// 首次打开：导图比窗口大就缩小到能看见全貌（但不小于 50%），否则 100% 居中。
    private func fitIfNeeded() {
        let bounds = editor.layout.bounds.insetBy(dx: -40, dy: -40)
        let visible = scrollView.contentView.bounds.size
        let scale = min(visible.width / max(bounds.width, 1), visible.height / max(bounds.height, 1))
        scrollView.magnification = max(0.5, min(1, scale))
        canvas.center(onLayoutPoint: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    func currentViewState() -> ViewState {
        let c = canvas.visibleCenter
        return ViewState(zoom: Double(scrollView.magnification), centerX: Double(c.x), centerY: Double(c.y),
                         selection: editor.selection)
    }

    // MARK: 缩放

    @objc private func magnificationChanged() {
        editor.zoom = scrollView.magnification
    }

    func setZoom(_ zoom: CGFloat) {
        let center = CGPoint(x: canvas.visibleRect.midX, y: canvas.visibleRect.midY)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            scrollView.animator().setMagnification(max(scrollView.minMagnification, min(scrollView.maxMagnification, zoom)),
                                                   centeredAt: center)
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.editor.zoom = self.scrollView.magnification
        }
        editor.zoom = zoom
    }

    @objc func zoomIn(_ sender: Any?) { setZoom(nextZoom(up: true)) }
    @objc func zoomOut(_ sender: Any?) { setZoom(nextZoom(up: false)) }
    @objc func actualSize(_ sender: Any?) { setZoom(1) }

    @objc func zoomToFit(_ sender: Any?) {
        let bounds = canvas.viewRect(editor.layout.bounds.insetBy(dx: -30, dy: -30))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            scrollView.animator().magnify(toFit: bounds)
        } completionHandler: { [weak self] in
            guard let self else { return }
            if self.scrollView.magnification > 1 { self.scrollView.magnification = 1 }
            self.canvas.center(onLayoutPoint: CGPoint(x: self.editor.layout.bounds.midX, y: self.editor.layout.bounds.midY))
            self.editor.zoom = self.scrollView.magnification
        }
    }

    @objc func centerMap(_ sender: Any?) {
        guard let root = editor.layout.node(editor.rootID) else { return }
        canvas.center(onLayoutPoint: CGPoint(x: root.frame.midX, y: root.frame.midY))
    }

    private static let zoomSteps: [CGFloat] = [0.1, 0.25, 0.33, 0.5, 0.67, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4]

    private func nextZoom(up: Bool) -> CGFloat {
        let current = scrollView.magnification
        if up { return Self.zoomSteps.first { $0 > current + 0.01 } ?? 4 }
        return Self.zoomSteps.last { $0 < current - 0.01 } ?? 0.1
    }

    // MARK: 查找

    @objc func showFindBar(_ sender: Any?) {
        findBar.isHidden = false
        findBarHeight.constant = 40
        // 让 SwiftUI 的输入框获得焦点
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .freeMindFocusFind, object: self.editor)
        }
    }

    func hideFindBar() {
        findBar.isHidden = true
        findBarHeight.constant = 0
        editor.findQuery = ""
        view.window?.makeFirstResponder(canvas)
        canvas.needsDisplay = true
    }

    @objc func findNextMatch(_ sender: Any?) {
        if findBar.isHidden { showFindBar(sender); return }
        editor.findNext()
        canvas.needsDisplay = true
    }

    @objc func findPreviousMatch(_ sender: Any?) {
        if findBar.isHidden { showFindBar(sender); return }
        editor.findNext(backwards: true)
        canvas.needsDisplay = true
    }

    @objc func useSelectionForFind(_ sender: Any?) {
        guard let title = editor.selectedTopic?.title else { return }
        editor.findQuery = title
        showFindBar(sender)
    }
}

extension Notification.Name {
    static let freeMindFocusFind = Notification.Name("FreeMindFocusFind")
}
