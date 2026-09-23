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

final class DashboardDataSourceRowButton: NSButton, DashboardAppearanceRefreshable {
    let providerID: ProviderID
    let isAuthorized: Bool
    private let dotView: DashboardDotView
    private let titleLabel = NSTextField(labelWithString: "")
    private let metricLabel = NSTextField(labelWithString: "")
    private var trackingAreaRef: NSTrackingArea?
    private var isHovered: Bool = false
    private(set) var isSelectedSource: Bool = false

    init(
        providerID: ProviderID,
        title: String,
        isAuthorized: Bool,
        metricText: String = "",
        statusText: String,
        target: AnyObject?,
        action: Selector?
    ) {
        self.providerID = providerID
        self.isAuthorized = isAuthorized
        self.dotView = DashboardDotView(
            color: isAuthorized ? DashboardPalette.green : DashboardPalette.statusInactive,
            accessibilityIdentifier: "DashboardDataSourceStatus.\(providerID.rawValue)",
            accessibilityValue: statusText
        )
        super.init(frame: .zero)
        self.target = target
        self.action = action
        self.title = ""
        self.toolTip = statusText
        self.identifier = NSUserInterfaceItemIdentifier("DashboardDataSourceRow.\(providerID.rawValue)")
        setAccessibilityIdentifier("DashboardDataSourceRow.\(providerID.rawValue)")
        setAccessibilityLabel(title)
        setAccessibilityValue(statusText)

        isBordered = false
        bezelStyle = .regularSquare
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false

        setupContent(title: title, metricText: metricText, statusText: statusText)
        updateAppearanceColors()
    }

    required init?(coder: NSCoder) {
        fatalError("DashboardDataSourceRowButton 必须用指定初始化方法构造")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateAppearanceColors()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateAppearanceColors()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if action != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func draw(_ dirtyRect: NSRect) {}

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

    func setSelectedSource(_ isSelected: Bool) {
        isSelectedSource = isSelected
        updateAppearanceColors()
    }

    func refreshDashboardAppearance() {
        updateAppearanceColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshDashboardAppearance()
    }

    private func updateAppearanceColors() {
        if isSelectedSource {
            layer?.backgroundColor = DashboardLayerColor.cgColor(DashboardPalette.rangeSelectedBackground, for: self)
            layer?.borderColor = DashboardLayerColor.cgColor(DashboardPalette.rangeSelectedBorder, for: self)
            layer?.borderWidth = 1
            let textColor = DashboardLayerColor.nsColor(DashboardPalette.rangeSelectedText, for: self)
            titleLabel.textColor = textColor
            metricLabel.textColor = textColor
        } else if isHovered && action != nil {
            layer?.backgroundColor = DashboardLayerColor.cgColor(DashboardPalette.navigationSelectedBackground, for: self)
            layer?.borderColor = DashboardLayerColor.cgColor(NSColor.clear, for: self)
            layer?.borderWidth = 0
            titleLabel.textColor = DashboardLayerColor.nsColor(DashboardPalette.primaryText, for: self)
            metricLabel.textColor = DashboardLayerColor.nsColor(DashboardPalette.secondaryText, for: self)
        } else {
            layer?.backgroundColor = DashboardLayerColor.cgColor(NSColor.clear, for: self)
            layer?.borderColor = DashboardLayerColor.cgColor(NSColor.clear, for: self)
            layer?.borderWidth = 0
            titleLabel.textColor = DashboardLayerColor.nsColor(
                isAuthorized ? DashboardPalette.secondaryText : DashboardPalette.mutedText,
                for: self
            )
            metricLabel.textColor = DashboardLayerColor.nsColor(DashboardPalette.mutedText, for: self)
        }
    }

    private func setupContent(title: String, metricText: String, statusText: String) {
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.toolTip = statusText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        metricLabel.stringValue = metricText
        metricLabel.font = .systemFont(ofSize: 11, weight: .medium)
        metricLabel.lineBreakMode = .byClipping
        metricLabel.alignment = .right
        metricLabel.toolTip = statusText
        metricLabel.translatesAutoresizingMaskIntoConstraints = false

        dotView.toolTip = statusText

        addSubview(dotView)
        addSubview(titleLabel)
        addSubview(metricLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            metricLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 4),
            metricLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            metricLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}

final class DashboardDisclosureHeaderButton: NSButton, DashboardAppearanceRefreshable {
    private let chevronImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var trackingAreaRef: NSTrackingArea?
    private var isHovered: Bool = false
    private(set) var isExpanded: Bool = false

    init(title: String, isExpanded: Bool, target: AnyObject?, action: Selector?) {
        self.isExpanded = isExpanded
        super.init(frame: .zero)
        self.target = target
        self.action = action
        self.title = ""
        self.identifier = NSUserInterfaceItemIdentifier("DashboardDataSourceOtherToggle")
        setAccessibilityIdentifier("DashboardDataSourceOtherToggle")
        setAccessibilityLabel(title)

        isBordered = false
        bezelStyle = .regularSquare
        wantsLayer = true
        layer?.cornerRadius = 4
        translatesAutoresizingMaskIntoConstraints = false

        setupContent(title: title, isExpanded: isExpanded)
        updateAppearanceColors()
    }

    required init?(coder: NSCoder) {
        fatalError("DashboardDisclosureHeaderButton 必须用指定初始化方法构造")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateAppearanceColors()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateAppearanceColors()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func draw(_ dirtyRect: NSRect) {}

    func setExpanded(_ expanded: Bool, title: String) {
        isExpanded = expanded
        titleLabel.stringValue = title
        setAccessibilityLabel(title)
        let symbolName = expanded ? "chevron.down" : "chevron.right"
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        chevronImageView.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: title
        )?.withSymbolConfiguration(config)
        chevronImageView.image?.isTemplate = true
        updateAppearanceColors()
    }

    func refreshDashboardAppearance() {
        updateAppearanceColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshDashboardAppearance()
    }

    private func updateAppearanceColors() {
        let color = isHovered ? DashboardPalette.secondaryText : DashboardPalette.mutedText
        let resolvedColor = DashboardLayerColor.nsColor(color, for: self)
        titleLabel.textColor = resolvedColor
        chevronImageView.contentTintColor = resolvedColor
        layer?.backgroundColor = isHovered
            ? DashboardLayerColor.cgColor(DashboardPalette.navigationSelectedBackground, for: self)
            : DashboardLayerColor.cgColor(NSColor.clear, for: self)
    }

    private func setupContent(title: String, isExpanded: Bool) {
        let symbolName = isExpanded ? "chevron.down" : "chevron.right"
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        chevronImageView.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: title
        )?.withSymbolConfiguration(config)
        chevronImageView.image?.isTemplate = true
        chevronImageView.imageScaling = .scaleProportionallyDown
        chevronImageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(chevronImageView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            chevronImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            chevronImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronImageView.widthAnchor.constraint(equalToConstant: 10),
            chevronImageView.heightAnchor.constraint(equalToConstant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: chevronImageView.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}

final class DashboardSourcePopUpButton: NSPopUpButton, DashboardAppearanceRefreshable {
    private var isFilterActive: Bool = false
    private var trackingAreaRef: NSTrackingArea?
    private var isHovered: Bool = false

    init(target: AnyObject?, action: Selector?) {
        super.init(frame: .zero, pullsDown: false)
        self.target = target
        self.action = action
        self.identifier = NSUserInterfaceItemIdentifier("DashboardDataSourcePopUp")
        setAccessibilityIdentifier("DashboardDataSourcePopUp")
        userInterfaceLayoutDirection = .leftToRight
        menu?.userInterfaceLayoutDirection = .leftToRight

        bezelStyle = .regularSquare
        isBordered = false
        focusRingType = .none
        font = .systemFont(ofSize: 12, weight: .semibold)
        alignment = .left

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 35),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("DashboardSourcePopUpButton 必须用指定初始化方法构造")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateAppearance()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

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

    func setFilterActive(_ active: Bool) {
        isFilterActive = active
        updateAppearance()
    }

    func refreshDashboardAppearance() {
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshDashboardAppearance()
    }

    private func updateAppearance() {
        if isFilterActive {
            layer?.backgroundColor = DashboardLayerColor.cgColor(DashboardPalette.rangeSelectedBackground, for: self)
            layer?.borderColor = DashboardLayerColor.cgColor(DashboardPalette.rangeSelectedBorder, for: self)
            let textColor = DashboardLayerColor.nsColor(DashboardPalette.rangeSelectedText, for: self)
            contentTintColor = textColor
        } else if isHovered {
            layer?.backgroundColor = DashboardLayerColor.cgColor(DashboardPalette.navigationSelectedBackground, for: self)
            layer?.borderColor = DashboardLayerColor.cgColor(DashboardPalette.glassControlBorder, for: self)
            let textColor = DashboardLayerColor.nsColor(DashboardPalette.primaryText, for: self)
            contentTintColor = textColor
        } else {
            layer?.backgroundColor = DashboardLayerColor.cgColor(NSColor.clear, for: self)
            layer?.borderColor = DashboardLayerColor.cgColor(DashboardPalette.glassControlBorder, for: self)
            let textColor = DashboardLayerColor.nsColor(DashboardPalette.primaryText, for: self)
            contentTintColor = textColor
        }
    }
}
