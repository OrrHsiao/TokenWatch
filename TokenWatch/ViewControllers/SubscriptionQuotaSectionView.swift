import AppKit

/// 左键弹窗顶部新增的订阅剩余区。
///
/// 高度固定，各状态只替换内容不改变尺寸，因此弹窗总高度稳定为“原区域 + 本区域”；
/// 不使用独立描边卡片，只用对齐、间距和底部一条中性分隔线组织层级。
enum SubscriptionQuotaSectionLayout {
    static let topPadding: CGFloat = 15
    static let titleHeight: CGFloat = 22
    static let titleToProviderSpacing: CGFloat = 12
    static let providerHeaderHeight: CGFloat = 14
    static let providerHeaderToContentSpacing: CGFloat = 9
    static let providerContentHeight: CGFloat = 46
    static let providerSpacing: CGFloat = 17
    static let dividerTopSpacing: CGFloat = 17
    static let dividerHeight: CGFloat = 1
    static let windowColumnSpacing: CGFloat = 17
    static let windowLabelRowHeight: CGFloat = 19
    static let meterHeight: CGFloat = 4
    static let iconSize: CGFloat = 14
    static let lockedIconSize: CGFloat = 18
    static let lockedContentSpacing: CGFloat = 8
    static let infoButtonSize: CGFloat = 16
    static let infoPopoverTextWidth: CGFloat = 280
    static let infoPopoverPadding: CGFloat = 12

    static var providerHeight: CGFloat {
        providerHeaderHeight + providerHeaderToContentSpacing + providerContentHeight
    }

    /// 新增区总高度，包含底部分隔线。
    static var height: CGFloat {
        topPadding
            + titleHeight
            + titleToProviderSpacing
            + providerHeight * CGFloat(SubscriptionQuotaProvider.allCases.count)
            + providerSpacing * CGFloat(SubscriptionQuotaProvider.allCases.count - 1)
            + dividerTopSpacing
            + dividerHeight
    }
}

@MainActor
final class SubscriptionQuotaSectionView: NSView, NSPopoverDelegate {
    /// 用户点击未授权分组中的授权入口。
    var onAction: ((SubscriptionQuotaProviderPresentation.Action) -> Void)?
    /// 用户点击未购买状态下的解锁入口。
    var onUnlock: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let divider = DashboardBackgroundView(backgroundColor: DashboardPalette.border)
    private var providerViews: [SubscriptionQuotaProvider: SubscriptionQuotaProviderView] = [:]
    /// 未购买时替代两个工具分组的锁定提示；占用同一区域，弹窗高度不变。
    private let lockedView = NSStackView()
    private let lockedIconView = NSImageView()
    private let lockedMessageLabel = NSTextField(wrappingLabelWithString: "")
    private let unlockButton = NSButton(title: "", target: nil, action: nil)
    /// 标题右侧的感叹号：点击弹出数据来源说明（读取本地记录、可能略有延迟、不调用网络 API）。
    private let infoButton = NSButton(title: "", target: nil, action: nil)
    private var infoText = ""
    private var infoPopover: NSPopover?
    /// transient 气泡在 mouseDown 时已关闭，按钮 action 要到 mouseUp 才触发；
    /// 记录关闭时间，避免再次点击感叹号想关闭说明时又被重新打开。
    private var infoPopoverClosedAt: Date?
    private static let infoPopoverReopenSuppressionInterval: TimeInterval = 0.3

    var debugTitle: String { titleLabel.stringValue }
    var debugInfoText: String { infoText }
    var debugInfoButton: NSButton { infoButton }
    var debugIsInfoPopoverShown: Bool { infoPopover?.isShown ?? false }
    func debugPerformInfo() {
        infoButtonClicked()
    }
    var debugIsLocked: Bool { !lockedView.isHidden }
    var debugLockedMessage: String? { lockedView.isHidden ? nil : lockedMessageLabel.stringValue }
    var debugUnlockTitle: String? { lockedView.isHidden ? nil : unlockButton.title }
    func debugProviderView(_ provider: SubscriptionQuotaProvider) -> SubscriptionQuotaProviderView? {
        providerViews[provider]
    }
    func debugPerformUnlock() {
        unlockButtonClicked()
    }

    /// - Parameter horizontalInset: 与原区域内容边缘对齐的左右内边距。
    init(horizontalInset: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupSubviews(horizontalInset: horizontalInset)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SubscriptionQuotaSectionView 不支持 storyboard 初始化")
    }

    /// 应用两个工具的最新展示模型；与当前内容一致的部分不会触发重绘。
    func apply(
        title: String,
        presentations: [SubscriptionQuotaProviderPresentation]
    ) {
        if titleLabel.stringValue != title {
            titleLabel.stringValue = title
        }
        setLocked(false)
        for presentation in presentations {
            providerViews[presentation.provider]?.apply(presentation)
        }
    }

    /// 未购买时隐藏两个工具分组，只展示付费说明与解锁入口。
    /// - Parameters:
    ///   - title: 区域标题。
    ///   - message: 付费功能说明。
    ///   - unlockTitle: 解锁按钮文案。
    func applyLocked(title: String, message: String, unlockTitle: String) {
        if titleLabel.stringValue != title {
            titleLabel.stringValue = title
        }
        setLocked(true)
        lockedMessageLabel.stringValue = message
        unlockButton.title = unlockTitle
        unlockButton.attributedTitle = NSAttributedString(
            string: unlockTitle,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: DashboardPalette.accent,
            ]
        )
        unlockButton.setAccessibilityLabel(unlockTitle)
    }

    /// 更新标题右侧说明入口的提示文案。
    /// - Parameters:
    ///   - text: 数据来源说明。
    ///   - accessibilityLabel: 读屏时说明入口的名称。
    func applyInfo(text: String, accessibilityLabel: String) {
        infoText = text
        infoButton.toolTip = text
        infoButton.setAccessibilityLabel(accessibilityLabel)
        infoButton.setAccessibilityHelp(text)
    }

    /// 弹窗关闭时一并收起说明气泡。
    func closeInfoPopover() {
        infoPopover?.close()
        infoPopover = nil
    }

    /// 说明气泡所在窗口编号；状态栏控制器据此把气泡内点击视为弹窗内部点击。
    var infoPopoverWindowNumber: Int? {
        guard let infoPopover, infoPopover.isShown else { return nil }
        return infoPopover.contentViewController?.view.window?.windowNumber
    }

    func popoverWillClose(_ notification: Notification) {
        infoPopoverClosedAt = Date()
    }

    private func setLocked(_ isLocked: Bool) {
        guard lockedView.isHidden == isLocked else { return }
        lockedView.isHidden = !isLocked
        for providerView in providerViews.values {
            providerView.isHidden = isLocked
        }
    }

    private func setupSubviews(horizontalInset: CGFloat) {
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = DashboardPalette.primaryText
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)

        infoButton.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        infoButton.imagePosition = .imageOnly
        infoButton.isBordered = false
        infoButton.bezelStyle = .inline
        infoButton.setButtonType(.momentaryChange)
        infoButton.contentTintColor = DashboardPalette.secondaryText
        infoButton.target = self
        infoButton.action = #selector(infoButtonClicked)
        infoButton.identifier = NSUserInterfaceItemIdentifier("SubscriptionQuotaInfoButton")
        infoButton.setAccessibilityIdentifier("SubscriptionQuotaInfoButton")
        infoButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoButton)

        var constraints = [
            heightAnchor.constraint(equalToConstant: SubscriptionQuotaSectionLayout.height),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),
            infoButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 4),
            infoButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            infoButton.widthAnchor.constraint(equalToConstant: SubscriptionQuotaSectionLayout.infoButtonSize),
            infoButton.heightAnchor.constraint(equalToConstant: SubscriptionQuotaSectionLayout.infoButtonSize),
            infoButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -horizontalInset),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: SubscriptionQuotaSectionLayout.topPadding),
            titleLabel.heightAnchor.constraint(equalToConstant: SubscriptionQuotaSectionLayout.titleHeight),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: SubscriptionQuotaSectionLayout.dividerHeight),
        ]

        var previousBottom = titleLabel.bottomAnchor
        var spacing = SubscriptionQuotaSectionLayout.titleToProviderSpacing
        for provider in SubscriptionQuotaProvider.allCases {
            let providerView = SubscriptionQuotaProviderView(provider: provider)
            providerView.onAction = { [weak self] action in
                self?.onAction?(action)
            }
            addSubview(providerView)
            providerViews[provider] = providerView
            constraints += [
                providerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),
                providerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset),
                providerView.topAnchor.constraint(equalTo: previousBottom, constant: spacing),
            ]
            previousBottom = providerView.bottomAnchor
            spacing = SubscriptionQuotaSectionLayout.providerSpacing
        }
        constraints += setupLockedView(horizontalInset: horizontalInset)
        NSLayoutConstraint.activate(constraints)
    }

    /// 锁定提示居中放在标题与分隔线之间，与两个工具分组共享同一区域。
    private func setupLockedView(horizontalInset: CGFloat) -> [NSLayoutConstraint] {
        lockedIconView.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: SubscriptionQuotaSectionLayout.lockedIconSize, weight: .regular))
        lockedIconView.contentTintColor = DashboardPalette.secondaryText
        lockedIconView.setAccessibilityElement(false)

        lockedMessageLabel.font = .systemFont(ofSize: 12)
        lockedMessageLabel.textColor = DashboardPalette.secondaryText
        lockedMessageLabel.alignment = .center
        lockedMessageLabel.maximumNumberOfLines = 3

        unlockButton.isBordered = false
        unlockButton.bezelStyle = .inline
        unlockButton.setButtonType(.momentaryChange)
        unlockButton.target = self
        unlockButton.action = #selector(unlockButtonClicked)
        unlockButton.identifier = NSUserInterfaceItemIdentifier("SubscriptionQuotaUnlockButton")
        unlockButton.setAccessibilityIdentifier("SubscriptionQuotaUnlockButton")

        lockedView.orientation = .vertical
        lockedView.alignment = .centerX
        lockedView.spacing = SubscriptionQuotaSectionLayout.lockedContentSpacing
        lockedView.isHidden = true
        lockedView.translatesAutoresizingMaskIntoConstraints = false
        for subview in [lockedIconView, lockedMessageLabel, unlockButton] as [NSView] {
            lockedView.addArrangedSubview(subview)
        }
        addSubview(lockedView)

        // 锁定区域与工具分组区域相同：标题下方到分隔线上方。
        let areaGuide = NSLayoutGuide()
        addLayoutGuide(areaGuide)
        return [
            areaGuide.topAnchor.constraint(equalTo: titleLabel.bottomAnchor),
            areaGuide.bottomAnchor.constraint(equalTo: divider.topAnchor),
            lockedView.centerYAnchor.constraint(equalTo: areaGuide.centerYAnchor),
            lockedView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),
            lockedView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset),
            lockedMessageLabel.widthAnchor.constraint(equalTo: lockedView.widthAnchor),
        ]
    }

    @objc private func unlockButtonClicked() {
        onUnlock?()
    }

    @objc private func infoButtonClicked() {
        if let infoPopover, infoPopover.isShown {
            closeInfoPopover()
            return
        }
        if let infoPopoverClosedAt,
           Date().timeIntervalSince(infoPopoverClosedAt) < Self.infoPopoverReopenSuppressionInterval {
            return
        }
        guard !infoText.isEmpty else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.appearance = effectiveAppearance
        popover.contentViewController = SubscriptionQuotaInfoViewController(text: infoText)
        popover.show(relativeTo: infoButton.bounds, of: infoButton, preferredEdge: .minY)
        infoPopover = popover
    }
}

/// 订阅剩余数据来源说明气泡的内容：固定宽度、按文案自动换行。
@MainActor
private final class SubscriptionQuotaInfoViewController: NSViewController {
    private let text: String

    init(text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SubscriptionQuotaInfoViewController 不支持 storyboard 初始化")
    }

    override func loadView() {
        let layout = SubscriptionQuotaSectionLayout.self
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.isSelectable = false
        label.preferredMaxLayoutWidth = layout.infoPopoverTextWidth
        label.translatesAutoresizingMaskIntoConstraints = false
        label.identifier = NSUserInterfaceItemIdentifier("SubscriptionQuotaInfoText")

        let container = NSView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: layout.infoPopoverPadding),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -layout.infoPopoverPadding),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: layout.infoPopoverPadding),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -layout.infoPopoverPadding),
            label.widthAnchor.constraint(equalToConstant: layout.infoPopoverTextWidth),
        ])
        view = container
        // NSPopover 按 preferredContentSize 定尺寸；文案长度随语言变化，按实际换行高度计算。
        preferredContentSize = container.fittingSize
    }
}

/// 单个工具分组：标题行（图标、名称、独立记录时间）+ 两列窗口或一行提示。
@MainActor
final class SubscriptionQuotaProviderView: NSView {
    var onAction: ((SubscriptionQuotaProviderPresentation.Action) -> Void)?

    private let provider: SubscriptionQuotaProvider
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let windowsRow = NSView()
    private var windowViews: [SubscriptionQuotaWindowKind: SubscriptionQuotaWindowView] = [:]
    private let messageRow = NSView()
    private let messageLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)
    private var presentation: SubscriptionQuotaProviderPresentation?

    var debugStatusText: String { statusLabel.stringValue }
    var debugMessageText: String? { messageRow.isHidden ? nil : messageLabel.stringValue }
    var debugActionTitle: String? { actionButton.isHidden || messageRow.isHidden ? nil : actionButton.title }
    var debugShowsWindows: Bool { !windowsRow.isHidden }
    func debugWindowView(_ kind: SubscriptionQuotaWindowKind) -> SubscriptionQuotaWindowView? {
        windowViews[kind]
    }
    func debugPerformAction() {
        actionButtonClicked()
    }

    init(provider: SubscriptionQuotaProvider) {
        self.provider = provider
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SubscriptionQuotaProviderView 不支持 storyboard 初始化")
    }

    func apply(_ presentation: SubscriptionQuotaProviderPresentation) {
        guard self.presentation != presentation else { return }
        self.presentation = presentation

        statusLabel.stringValue = presentation.statusText
        statusLabel.textColor = presentation.isStatusHighlighted
            ? DashboardPalette.yellow
            : DashboardPalette.secondaryText

        if let message = presentation.message {
            windowsRow.isHidden = true
            messageRow.isHidden = false
            messageLabel.stringValue = message
            if let actionTitle = presentation.actionTitle, presentation.action != nil {
                actionButton.isHidden = false
                actionButton.attributedTitle = NSAttributedString(
                    string: actionTitle,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                        .foregroundColor: DashboardPalette.accent,
                    ]
                )
                actionButton.setAccessibilityLabel("\(provider.displayName), \(actionTitle)")
            } else {
                actionButton.isHidden = true
            }
        } else {
            windowsRow.isHidden = false
            messageRow.isHidden = true
            for window in presentation.windows {
                windowViews[window.kind]?.apply(window)
            }
        }
    }

    private func setupSubviews() {
        let iconName = provider == .claude
            ? StatusBarQuotaImageRenderer.claudeIconName
            : StatusBarQuotaImageRenderer.codexIconName
        iconView.image = NSImage(named: iconName)
        iconView.contentTintColor = DashboardPalette.primaryText
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityElement(false)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.stringValue = provider.displayName
        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.textColor = DashboardPalette.primaryText
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = DashboardPalette.secondaryText
        statusLabel.alignment = .right
        statusLabel.lineBreakMode = .byTruncatingHead
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        windowsRow.translatesAutoresizingMaskIntoConstraints = false
        messageRow.translatesAutoresizingMaskIntoConstraints = false
        messageRow.isHidden = true

        messageLabel.font = .systemFont(ofSize: 11)
        messageLabel.textColor = DashboardPalette.secondaryText
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        actionButton.isBordered = false
        actionButton.bezelStyle = .inline
        actionButton.setButtonType(.momentaryChange)
        actionButton.target = self
        actionButton.action = #selector(actionButtonClicked)
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(statusLabel)
        addSubview(windowsRow)
        addSubview(messageRow)
        messageRow.addSubview(messageLabel)
        messageRow.addSubview(actionButton)

        let fiveHourView = SubscriptionQuotaWindowView()
        let sevenDayView = SubscriptionQuotaWindowView()
        windowViews = [.fiveHour: fiveHourView, .sevenDay: sevenDayView]
        windowsRow.addSubview(fiveHourView)
        windowsRow.addSubview(sevenDayView)

        let layout = SubscriptionQuotaSectionLayout.self
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: layout.providerHeight),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.topAnchor.constraint(equalTo: topAnchor),
            iconView.widthAnchor.constraint(equalToConstant: layout.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: layout.iconSize),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            windowsRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            windowsRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            windowsRow.bottomAnchor.constraint(equalTo: bottomAnchor),
            windowsRow.heightAnchor.constraint(equalToConstant: layout.providerContentHeight),

            messageRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            messageRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            messageRow.bottomAnchor.constraint(equalTo: bottomAnchor),
            messageRow.heightAnchor.constraint(equalToConstant: layout.providerContentHeight),

            messageLabel.leadingAnchor.constraint(equalTo: messageRow.leadingAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: messageRow.centerYAnchor),
            actionButton.leadingAnchor.constraint(greaterThanOrEqualTo: messageLabel.trailingAnchor, constant: 8),
            actionButton.trailingAnchor.constraint(equalTo: messageRow.trailingAnchor),
            actionButton.centerYAnchor.constraint(equalTo: messageRow.centerYAnchor),

            fiveHourView.leadingAnchor.constraint(equalTo: windowsRow.leadingAnchor),
            fiveHourView.topAnchor.constraint(equalTo: windowsRow.topAnchor),
            fiveHourView.bottomAnchor.constraint(equalTo: windowsRow.bottomAnchor),
            sevenDayView.leadingAnchor.constraint(
                equalTo: fiveHourView.trailingAnchor,
                constant: layout.windowColumnSpacing
            ),
            sevenDayView.trailingAnchor.constraint(equalTo: windowsRow.trailingAnchor),
            sevenDayView.topAnchor.constraint(equalTo: windowsRow.topAnchor),
            sevenDayView.bottomAnchor.constraint(equalTo: windowsRow.bottomAnchor),
            sevenDayView.widthAnchor.constraint(equalTo: fiveHourView.widthAnchor),
        ])
    }

    @objc private func actionButtonClicked() {
        guard let action = presentation?.action else { return }
        onAction?(action)
    }
}

/// 单个额度窗口：窗口名与剩余百分比、4pt 横条、重置说明。
@MainActor
final class SubscriptionQuotaWindowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let meterView = SubscriptionQuotaMeterView()
    private let detailLabel = NSTextField(labelWithString: "")

    var debugTitle: String { titleLabel.stringValue }
    var debugValueText: String { valueLabel.stringValue }
    var debugDetailText: String { detailLabel.stringValue }
    var debugMeterFraction: Double? { meterView.fraction }
    var debugMeterStyle: SubscriptionQuotaMeterView.Style { meterView.style }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SubscriptionQuotaWindowView 不支持 storyboard 初始化")
    }

    func apply(_ window: SubscriptionQuotaWindowPresentation) {
        titleLabel.stringValue = window.title
        valueLabel.stringValue = window.valueText
        detailLabel.stringValue = window.detailText
        detailLabel.toolTip = window.detailText.isEmpty ? nil : window.detailText
        meterView.update(
            fraction: window.remainingPercent.map { $0 / 100 },
            style: SubscriptionQuotaMeterView.Style(window: window)
        )
        setAccessibilityLabel(window.accessibilityText)
        setAccessibilityValue(window.remainingPercent.map { NSNumber(value: $0) })
    }

    private func setupSubviews() {
        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.textColor = DashboardPalette.secondaryText
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        valueLabel.textColor = DashboardPalette.primaryText
        valueLabel.alignment = .right
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        detailLabel.font = .systemFont(ofSize: 10)
        detailLabel.textColor = DashboardPalette.secondaryText
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for subview in [titleLabel, valueLabel, meterView, detailLabel] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            subview.setAccessibilityElement(false)
            addSubview(subview)
        }

        let layout = SubscriptionQuotaSectionLayout.self
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.firstBaselineAnchor.constraint(equalTo: valueLabel.firstBaselineAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 6),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.topAnchor.constraint(equalTo: topAnchor),
            valueLabel.heightAnchor.constraint(equalToConstant: layout.windowLabelRowHeight),

            meterView.leadingAnchor.constraint(equalTo: leadingAnchor),
            meterView.trailingAnchor.constraint(equalTo: trailingAnchor),
            meterView.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 5),
            meterView.heightAnchor.constraint(equalToConstant: layout.meterHeight),

            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: meterView.bottomAnchor, constant: 5),
        ])
    }
}

/// 4pt 剩余额度横条：填充越少表示剩余越少。
@MainActor
final class SubscriptionQuotaMeterView: NSView, DashboardAppearanceRefreshable {
    enum Style: Equatable {
        case normal
        case warning
        case danger
        case stale

        init(window: SubscriptionQuotaWindowPresentation) {
            if window.isStale {
                self = .stale
                return
            }
            switch window.severity {
            case .normal:
                self = .normal
            case .warning:
                self = .warning
            case .danger:
                self = .danger
            }
        }

        /// 正常横条延续现有绿色热力图色，低额度才使用强调色。
        var fillColor: NSColor {
            switch self {
            case .normal:
                return DashboardPalette.green
            case .warning:
                return .systemOrange
            case .danger:
                return .systemRed
            case .stale:
                return DashboardPalette.secondaryText.withAlphaComponent(0.55)
            }
        }
    }

    private(set) var fraction: Double?
    private(set) var style: Style = .normal

    func update(fraction: Double?, style: Style) {
        guard self.fraction != fraction || self.style != style else { return }
        self.fraction = fraction
        self.style = style
        needsDisplay = true
    }

    func refreshDashboardAppearance() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        DashboardPalette.border.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        guard let fraction, fraction > 0 else { return }
        var fillRect = bounds
        fillRect.size.width = max(bounds.height, bounds.width * CGFloat(min(fraction, 1)))
        style.fillColor.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }
}
