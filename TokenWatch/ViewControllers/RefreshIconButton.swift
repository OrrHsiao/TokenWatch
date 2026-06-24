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
