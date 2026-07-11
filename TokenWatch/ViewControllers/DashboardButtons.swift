import AppKit

final class DashboardNavigationButton: NSButton, DashboardAppearanceRefreshable {
    private let iconView = NSImageView()
    private let titleTextField = NSTextField(labelWithString: "")
    private let symbolName: String
    private var dashboardBackgroundColor: NSColor?

    init(
        title: String,
        symbolName: String,
        identifier: String,
        target: AnyObject?,
        action: Selector?
    ) {
        self.symbolName = symbolName
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        setAccessibilityIdentifier(identifier)
        setAccessibilityLabel(title)

        alignment = .left
        bezelStyle = .regularSquare
        isBordered = false
        font = .systemFont(ofSize: 13, weight: .medium)
        wantsLayer = true
        layer?.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false

        configureContent(title: title, symbolName: symbolName, identifier: identifier)
        setVisualTint(DashboardPalette.secondaryText)
    }

    required init?(coder: NSCoder) {
        fatalError("DashboardNavigationButton 必须用指定初始化方法构造")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshDashboardAppearance()
    }

    override func draw(_ dirtyRect: NSRect) {
        // 内容由子视图排版，避免 AppKit 默认按钮绘制吞掉设计稿里的内边距。
    }

    // 自绘 draw(_:) 不调用 super；显式提供 mask，让 AppKit 在独立绘制阶段保留系统 focus ring。
    override var focusRingMaskBounds: NSRect {
        bounds
    }

    override func drawFocusRingMask() {
        let cornerRadius = layer?.cornerRadius ?? 0
        NSBezierPath(
            roundedRect: bounds,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        ).fill()
    }

    func setVisualTint(_ color: NSColor) {
        iconView.contentTintColor = color
        titleTextField.textColor = color
    }

    func setDashboardBackgroundColor(_ color: NSColor) {
        dashboardBackgroundColor = color
        updateDashboardBackgroundColor()
    }

    func refreshDashboardAppearance() {
        updateDashboardBackgroundColor()
    }

    func updateTitle(_ title: String) {
        self.title = title
        setAccessibilityLabel(title)
        titleTextField.stringValue = title
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        iconView.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: title
        )?.withSymbolConfiguration(symbolConfiguration)
        iconView.image?.isTemplate = true
    }

    private func configureContent(title: String, symbolName: String, identifier: String) {
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        iconView.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: title
        )?.withSymbolConfiguration(symbolConfiguration)
        iconView.image?.isTemplate = true
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setAccessibilityIdentifier("\(identifier).icon")

        titleTextField.stringValue = title
        titleTextField.font = .systemFont(ofSize: 13, weight: .medium)
        titleTextField.alignment = .left
        titleTextField.lineBreakMode = .byTruncatingTail
        titleTextField.translatesAutoresizingMaskIntoConstraints = false
        titleTextField.setAccessibilityIdentifier("\(identifier).title")

        addSubview(iconView)
        addSubview(titleTextField)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            titleTextField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleTextField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleTextField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
    }

    private func updateDashboardBackgroundColor() {
        guard let dashboardBackgroundColor else { return }
        layer?.backgroundColor = DashboardLayerColor.cgColor(dashboardBackgroundColor, for: self)
    }
}

final class DashboardRangeButton: NSButton, DashboardAppearanceRefreshable {
    private var dashboardBackgroundColor: NSColor?
    private var dashboardBorderColor: NSColor?

    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
    }

    required init?(coder: NSCoder) {
        fatalError("DashboardRangeButton 必须用指定初始化方法构造")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshDashboardAppearance()
    }

    func setDashboardLayerColors(backgroundColor: NSColor, borderColor: NSColor) {
        dashboardBackgroundColor = backgroundColor
        dashboardBorderColor = borderColor
        updateDashboardLayerColors()
    }

    func refreshDashboardAppearance() {
        updateDashboardLayerColors()
    }

    private func updateDashboardLayerColors() {
        guard let dashboardBackgroundColor, let dashboardBorderColor else { return }
        layer?.backgroundColor = DashboardLayerColor.cgColor(dashboardBackgroundColor, for: self)
        layer?.borderColor = DashboardLayerColor.cgColor(dashboardBorderColor, for: self)
    }
}

final class DashboardSessionButton: NSButton, DashboardAppearanceRefreshable {
    enum ContentAlignment {
        case leading
        case center
    }

    private let titleTextField = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let contentAlignment: ContentAlignment
    private var dashboardBackgroundColor = NSColor.clear
    private var dashboardBorderColor = NSColor.clear
    private var dashboardTitleColor = DashboardPalette.primaryText

    init(
        title: String,
        target: AnyObject?,
        action: Selector?,
        contentAlignment: ContentAlignment,
        image: NSImage? = nil
    ) {
        self.contentAlignment = contentAlignment
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        self.image = image

        isBordered = false
        bezelStyle = .regularSquare
        wantsLayer = true
        layer?.masksToBounds = true

        titleTextField.stringValue = title
        titleTextField.lineBreakMode = .byTruncatingTail
        titleTextField.maximumNumberOfLines = 1
        titleTextField.alignment = contentAlignment == .center ? .center : .left
        titleTextField.translatesAutoresizingMaskIntoConstraints = false
        titleTextField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleTextField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleTextField.setAccessibilityIdentifier("DashboardSessionButton.title")

        iconView.image = image
        iconView.image?.isTemplate = true
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isHidden = image == nil
        iconView.setAccessibilityIdentifier("DashboardSessionButton.icon")

        addSubview(titleTextField)
        addSubview(iconView)
        activateContentConstraints(hasImage: image != nil)
    }

    required init?(coder: NSCoder) {
        fatalError("DashboardSessionButton 必须用指定初始化方法构造")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshDashboardAppearance()
    }

    override func draw(_ dirtyRect: NSRect) {
        // 会话页按钮由 layer 和子视图绘制，避免 NSButtonCell 在外观切换后保留系统深色样式。
    }

    // 自绘 draw(_:) 不调用 super；显式提供 mask，让 AppKit 在独立绘制阶段保留系统 focus ring。
    override var focusRingMaskBounds: NSRect {
        bounds
    }

    override func drawFocusRingMask() {
        let cornerRadius = layer?.cornerRadius ?? 0
        NSBezierPath(
            roundedRect: bounds,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        ).fill()
    }

    func setDashboardTitle(_ title: String) {
        self.title = title
        titleTextField.stringValue = title
    }

    func setDashboardStyle(
        backgroundColor: NSColor,
        borderColor: NSColor,
        borderWidth: CGFloat,
        cornerRadius: CGFloat,
        titleColor: NSColor,
        font: NSFont
    ) {
        dashboardBackgroundColor = backgroundColor
        dashboardBorderColor = borderColor
        dashboardTitleColor = titleColor
        titleTextField.font = font
        layer?.borderWidth = borderWidth
        layer?.cornerRadius = cornerRadius
        contentTintColor = titleColor
        refreshDashboardAppearance()
    }

    func refreshDashboardAppearance() {
        layer?.backgroundColor = DashboardLayerColor.cgColor(dashboardBackgroundColor, for: self)
        layer?.borderColor = DashboardLayerColor.cgColor(dashboardBorderColor, for: self)
        let resolvedTitleColor = DashboardLayerColor.nsColor(dashboardTitleColor, for: self)
        titleTextField.textColor = resolvedTitleColor
        iconView.contentTintColor = resolvedTitleColor
        contentTintColor = resolvedTitleColor
    }

    private func activateContentConstraints(hasImage: Bool) {
        switch contentAlignment {
        case .center:
            NSLayoutConstraint.activate([
                titleTextField.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
                titleTextField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
                titleTextField.centerXAnchor.constraint(equalTo: centerXAnchor),
                titleTextField.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        case .leading:
            if hasImage {
                NSLayoutConstraint.activate([
                    titleTextField.leadingAnchor.constraint(equalTo: leadingAnchor),
                    titleTextField.centerYAnchor.constraint(equalTo: centerYAnchor),
                    iconView.leadingAnchor.constraint(equalTo: titleTextField.trailingAnchor, constant: 6),
                    iconView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
                    iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                    iconView.widthAnchor.constraint(equalToConstant: 13),
                    iconView.heightAnchor.constraint(equalToConstant: 13),
                ])
            } else {
                NSLayoutConstraint.activate([
                    titleTextField.leadingAnchor.constraint(equalTo: leadingAnchor),
                    titleTextField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
                    titleTextField.centerYAnchor.constraint(equalTo: centerYAnchor),
                ])
            }
        }
    }
}
