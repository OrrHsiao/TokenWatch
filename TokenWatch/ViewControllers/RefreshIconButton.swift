import AppKit

/// 图标型刷新按钮,提供与状态栏弹窗一致的 ghost hover 样式。
final class RefreshIconButton: NSButton {
    private var hoverTrackingArea: NSTrackingArea?
    private var isPointerInside = false

    var debugCornerRadius: CGFloat { layer?.cornerRadius ?? 0 }
    var debugHasBackground: Bool { layer?.backgroundColor != nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("RefreshIconButton 不支持 storyboard 初始化")
    }

    override var isHighlighted: Bool {
        didSet { updateChrome() }
    }

    override var isEnabled: Bool {
        didSet { updateChrome() }
    }

    /// 不使用系统为无边框按钮附加的对齐内边距。
    ///
    /// 系统按文字基线给无边框图片按钮加上下不对称的内边距（各 macOS 版本数值不同），
    /// 尺寸与居中约束只作用在内边距内侧，frame 会被撑成竖长条：自绘的 hover 背景不再是方形，
    /// 图标也与同行标题错开。本按钮的背景与图标都按 bounds 自绘，对齐矩形应与 frame 一致。
    override var alignmentRectInsets: NSEdgeInsets {
        NSEdgeInsetsZero
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isPointerInside = true
        updateChrome()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isPointerInside = false
        updateChrome()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateChrome()
    }

    func debugSetHovering(_ isHovering: Bool) {
        isPointerInside = isHovering
        updateChrome()
    }

    private func setupChrome() {
        wantsLayer = true
        focusRingType = .none
        updateChrome()
    }

    private func updateChrome() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.cornerRadius = 6
            layer?.masksToBounds = true

            guard isEnabled else {
                layer?.backgroundColor = nil
                return
            }

            let backgroundColor: NSColor?
            if isHighlighted {
                backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18)
            } else if isPointerInside {
                backgroundColor = NSColor.quaternaryLabelColor
            } else {
                backgroundColor = nil
            }
            layer?.backgroundColor = backgroundColor?.cgColor
        }
    }
}
