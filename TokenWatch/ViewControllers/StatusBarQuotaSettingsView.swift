import AppKit
import os.log

/// 设置页“状态栏订阅额度”区块内容。
///
/// 上方在未购买时展示付费说明与购买 / 恢复入口；下方依次为 Claude、Codex 两组，
/// 分别配置 5 小时与一周额度是否在状态栏展示，以及简洁（只显示圆环）/ 详细（附剩余百分比）样式。
/// 两组纵向排列，设置页在窄窗口下也不会被撑宽。
/// 未购买时配置项保留可见但禁用，让用户在购买前即可了解可配置内容。
@MainActor
final class StatusBarQuotaSettingsView: NSView {
    private struct WindowKey: Hashable {
        let provider: SubscriptionQuotaProvider
        let kind: SubscriptionQuotaWindowKind
    }

    private struct WindowRowViews {
        let titleLabel: NSTextField
        let visibilitySwitch: NSSwitch
        let stylePopUpButton: SettingsPopUpButton
    }

    private static let stylePopUpWidth: CGFloat = 112
    private static let controlHeight: CGFloat = 32
    private static let providerGroupSpacing: CGFloat = 18

    private let displaySettings: StatusBarDisplaySettings
    private let quotaAccess: SubscriptionQuotaAccess
    private var language: AppLanguage

    private let descriptionLabel = NSTextField(wrappingLabelWithString: "")
    private let purchasePanel = NSStackView()
    private let lockedMessageLabel = NSTextField(wrappingLabelWithString: "")
    private let purchaseProgressIndicator = NSProgressIndicator()
    private let purchaseButton = DashboardRangeButton(title: "", target: nil, action: nil)
    private let restoreButton = DashboardRangeButton(title: "", target: nil, action: nil)
    private let purchaseMessageLabel = NSTextField(wrappingLabelWithString: "")
    private var windowRows: [WindowKey: WindowRowViews] = [:]

    private var displaySettingsObserverToken: StatusBarDisplaySettings.ObservationToken?
    private var quotaAccessObserverToken: SubscriptionQuotaAccess.ObservationToken?
    private var purchaseObserverToken: WidgetPurchaseController.ObservationToken?
    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "StatusBarQuotaSettings")

    var debugShowsPurchasePanel: Bool { !purchasePanel.isHidden }
    var debugLockedMessage: String { lockedMessageLabel.stringValue }

    /// - Parameters:
    ///   - displaySettings: 状态栏展示设置，修改后状态栏立即重绘。
    ///   - quotaAccess: 订阅额度付费状态与购买入口。
    ///   - language: 初始界面语言。
    init(
        displaySettings: StatusBarDisplaySettings,
        quotaAccess: SubscriptionQuotaAccess,
        language: AppLanguage
    ) {
        self.displaySettings = displaySettings
        self.quotaAccess = quotaAccess
        self.language = language
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        identifier = NSUserInterfaceItemIdentifier("StatusBarQuotaSettings")
        setupSubviews()
        subscribe()
        reloadLocalizedText(language: language)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("StatusBarQuotaSettingsView 必须使用代码 initializer 构造")
    }

    deinit {
        MainActor.assumeIsolated {
            if let displaySettingsObserverToken {
                displaySettings.removeObserver(displaySettingsObserverToken)
            }
            if let quotaAccessObserverToken {
                quotaAccess.removeObserver(quotaAccessObserverToken)
            }
            if let purchaseObserverToken {
                quotaAccess.purchaseController?.removeObserver(purchaseObserverToken)
            }
        }
    }

    /// 按界面语言刷新全部文案并重绘状态。
    /// - Parameter language: 当前界面语言。
    func reloadLocalizedText(language: AppLanguage) {
        self.language = language
        descriptionLabel.stringValue = AppStrings.text(.settingsStatusBarQuotaDescription, language: language)
        lockedMessageLabel.stringValue = AppStrings.text(.quotaPremiumLockedMessage, language: language)
        let styleTitles = StatusBarQuotaWindowStyle.allCases.map { $0.title(language: language) }
        for (key, row) in windowRows {
            let windowTitle = SubscriptionQuotaPresenter.windowTitle(key.kind, language: language)
            row.titleLabel.stringValue = windowTitle
            let accessibilityPrefix = "\(key.provider.displayName) \(windowTitle)"
            row.visibilitySwitch.setAccessibilityLabel(accessibilityPrefix)
            row.stylePopUpButton.removeAllItems()
            row.stylePopUpButton.addItems(withTitles: styleTitles)
            row.stylePopUpButton.setAccessibilityLabel(accessibilityPrefix)
            row.stylePopUpButton.applyDashboardLayerColors()
        }
        render()
    }

    // MARK: - Setup

    private func setupSubviews() {
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.textColor = DashboardPalette.secondaryText
        descriptionLabel.maximumNumberOfLines = 0

        setupPurchasePanel()

        let divider = DashboardBackgroundView(backgroundColor: DashboardPalette.glassDivider)
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let providerGroups = NSStackView()
        providerGroups.orientation = .vertical
        providerGroups.alignment = .leading
        providerGroups.spacing = Self.providerGroupSpacing
        for provider in SubscriptionQuotaProvider.allCases {
            let group = makeProviderGroup(provider)
            providerGroups.addArrangedSubview(group)
            group.widthAnchor.constraint(equalTo: providerGroups.widthAnchor).isActive = true
        }

        let stack = NSStackView(views: [descriptionLabel, purchasePanel, divider, providerGroups])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            descriptionLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            purchasePanel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            divider.widthAnchor.constraint(equalTo: stack.widthAnchor),
            providerGroups.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func setupPurchasePanel() {
        let lockIconView = NSImageView()
        lockIconView.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        lockIconView.contentTintColor = DashboardPalette.yellow
        lockIconView.setAccessibilityElement(false)
        lockIconView.setContentHuggingPriority(.required, for: .horizontal)

        lockedMessageLabel.font = .systemFont(ofSize: 13)
        lockedMessageLabel.textColor = DashboardPalette.primaryText
        lockedMessageLabel.maximumNumberOfLines = 2
        lockedMessageLabel.identifier = NSUserInterfaceItemIdentifier("StatusBarQuotaLockedMessage")
        lockedMessageLabel.setAccessibilityIdentifier("StatusBarQuotaLockedMessage")
        lockedMessageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        lockedMessageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        purchaseProgressIndicator.style = .spinning
        purchaseProgressIndicator.controlSize = .small
        purchaseProgressIndicator.isDisplayedWhenStopped = false

        configureButton(purchaseButton, identifier: "StatusBarQuotaPurchaseButton")
        purchaseButton.target = self
        purchaseButton.action = #selector(purchaseButtonClicked)
        purchaseButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        configureButton(restoreButton, identifier: "StatusBarQuotaRestoreButton")
        restoreButton.target = self
        restoreButton.action = #selector(restoreButtonClicked)
        restoreButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 104).isActive = true

        let messageRow = NSStackView(views: [lockIconView, lockedMessageLabel])
        messageRow.orientation = .horizontal
        messageRow.alignment = .top
        messageRow.spacing = 8

        // 按钮单独成行，避免窄窗口或长译文时挤压付费说明。
        let actionsRow = NSStackView(views: [purchaseButton, restoreButton, purchaseProgressIndicator])
        actionsRow.orientation = .horizontal
        actionsRow.alignment = .centerY
        actionsRow.spacing = 10

        purchaseMessageLabel.font = .systemFont(ofSize: 11)
        purchaseMessageLabel.textColor = DashboardPalette.secondaryText
        purchaseMessageLabel.maximumNumberOfLines = 2
        purchaseMessageLabel.identifier = NSUserInterfaceItemIdentifier("StatusBarQuotaPurchaseMessage")
        purchaseMessageLabel.setAccessibilityIdentifier("StatusBarQuotaPurchaseMessage")

        purchasePanel.orientation = .vertical
        purchasePanel.alignment = .leading
        purchasePanel.spacing = 10
        purchasePanel.identifier = NSUserInterfaceItemIdentifier("StatusBarQuotaPurchasePanel")
        purchasePanel.setAccessibilityIdentifier("StatusBarQuotaPurchasePanel")
        purchasePanel.addArrangedSubview(messageRow)
        purchasePanel.addArrangedSubview(actionsRow)
        purchasePanel.addArrangedSubview(purchaseMessageLabel)
        NSLayoutConstraint.activate([
            messageRow.widthAnchor.constraint(equalTo: purchasePanel.widthAnchor),
            purchaseMessageLabel.widthAnchor.constraint(equalTo: purchasePanel.widthAnchor),
        ])
    }

    private func makeProviderGroup(_ provider: SubscriptionQuotaProvider) -> NSView {
        let iconView = NSImageView()
        iconView.image = NSImage(named: provider == .claude
            ? StatusBarQuotaImageRenderer.claudeIconName
            : StatusBarQuotaImageRenderer.codexIconName)
        iconView.contentTintColor = DashboardPalette.primaryText
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityElement(false)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
        ])

        let nameLabel = NSTextField(labelWithString: provider.displayName)
        nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        nameLabel.textColor = DashboardPalette.primaryText

        let header = NSStackView(views: [iconView, nameLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        let group = NSStackView(views: [header])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 10
        group.identifier = NSUserInterfaceItemIdentifier("StatusBarQuotaProviderGroup.\(provider.rawValue)")
        group.setAccessibilityIdentifier("StatusBarQuotaProviderGroup.\(provider.rawValue)")
        for kind in SubscriptionQuotaWindowKind.allCases {
            let row = makeWindowRow(provider: provider, kind: kind)
            group.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
        }
        return group
    }

    private func makeWindowRow(provider: SubscriptionQuotaProvider, kind: SubscriptionQuotaWindowKind) -> NSView {
        let suffix = "\(provider.rawValue).\(kind.rawValue)"

        let titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = DashboardPalette.primaryText
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let visibilitySwitch = NSSwitch(frame: .zero)
        visibilitySwitch.identifier = NSUserInterfaceItemIdentifier("StatusBarQuotaWindowSwitch.\(suffix)")
        visibilitySwitch.setAccessibilityIdentifier("StatusBarQuotaWindowSwitch.\(suffix)")
        visibilitySwitch.target = self
        visibilitySwitch.action = #selector(visibilitySwitchChanged(_:))

        let stylePopUpButton = SettingsPopUpButton()
        stylePopUpButton.identifier = NSUserInterfaceItemIdentifier("StatusBarQuotaWindowStylePopUpButton.\(suffix)")
        stylePopUpButton.setAccessibilityIdentifier("StatusBarQuotaWindowStylePopUpButton.\(suffix)")
        stylePopUpButton.target = self
        stylePopUpButton.action = #selector(stylePopUpChanged(_:))
        NSLayoutConstraint.activate([
            stylePopUpButton.widthAnchor.constraint(equalToConstant: Self.stylePopUpWidth),
            stylePopUpButton.heightAnchor.constraint(equalToConstant: Self.controlHeight),
        ])

        let spacer = NSView()
        spacer.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.fittingSizeCompression, for: .horizontal)

        let row = NSStackView(views: [titleLabel, spacer, visibilitySwitch, stylePopUpButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        windowRows[WindowKey(provider: provider, kind: kind)] = WindowRowViews(
            titleLabel: titleLabel,
            visibilitySwitch: visibilitySwitch,
            stylePopUpButton: stylePopUpButton
        )
        return row
    }

    private func configureButton(_ button: DashboardRangeButton, identifier: String) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.alignment = .center
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.layer?.borderWidth = 1
        button.translatesAutoresizingMaskIntoConstraints = false
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.setAccessibilityIdentifier(identifier)
        button.heightAnchor.constraint(equalToConstant: Self.controlHeight).isActive = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func subscribe() {
        displaySettingsObserverToken = displaySettings.observe { [weak self] in
            self?.render()
        }
        quotaAccessObserverToken = quotaAccess.observe { [weak self] in
            self?.render()
        }
        purchaseObserverToken = quotaAccess.purchaseController?.observe { [weak self] _ in
            self?.render()
        }
    }

    // MARK: - Render

    private func render() {
        let isUnlocked = quotaAccess.isUnlocked
        purchasePanel.isHidden = isUnlocked
        if !isUnlocked {
            renderPurchaseState()
        }
        for (key, row) in windowRows {
            let configuration = displaySettings.quotaWindowConfiguration(provider: key.provider, kind: key.kind)
            row.visibilitySwitch.state = configuration.isVisible ? .on : .off
            row.visibilitySwitch.isEnabled = isUnlocked
            if let styleIndex = StatusBarQuotaWindowStyle.allCases.firstIndex(of: configuration.style) {
                row.stylePopUpButton.selectItem(at: styleIndex)
            }
            // 周期隐藏时样式不生效，禁用以免误以为可调整。
            row.stylePopUpButton.isEnabled = isUnlocked && configuration.isVisible
            row.titleLabel.textColor = isUnlocked ? DashboardPalette.primaryText : DashboardPalette.secondaryText
        }
    }

    /// 只在未购买时绘制购买入口；购买控制器不可用时只保留付费说明。
    private func renderPurchaseState() {
        let copy = WidgetPurchaseCopy.make(language: language)
        guard let purchaseController = quotaAccess.purchaseController else {
            purchaseButton.isHidden = true
            restoreButton.isHidden = true
            purchaseMessageLabel.isHidden = true
            purchaseProgressIndicator.stopAnimation(nil)
            return
        }
        let state = purchaseController.state
        let (isBusy, message) = copy.operationPresentation(state.operation)
        if isBusy {
            purchaseProgressIndicator.startAnimation(nil)
        } else {
            purchaseProgressIndicator.stopAnimation(nil)
        }
        purchaseMessageLabel.stringValue = message
        purchaseMessageLabel.isHidden = message.isEmpty

        purchaseButton.isHidden = false
        restoreButton.isHidden = false
        purchaseButton.title = state.product.map { copy.purchaseTitle(displayPrice: $0.displayPrice) }
            ?? copy.purchaseUnavailableTitle
        restoreButton.title = copy.restoreTitle
        purchaseButton.isEnabled = !isBusy && state.product != nil
        restoreButton.isEnabled = !isBusy
        applyButtonStyle(
            purchaseButton,
            backgroundColor: DashboardPalette.rangeSelectedBackground,
            borderColor: DashboardPalette.rangeSelectedBorder,
            textColor: DashboardPalette.rangeSelectedText
        )
        applyButtonStyle(
            restoreButton,
            backgroundColor: .clear,
            borderColor: DashboardPalette.glassControlBorder,
            textColor: DashboardPalette.primaryText
        )
    }

    private func applyButtonStyle(
        _ button: DashboardRangeButton,
        backgroundColor: NSColor,
        borderColor: NSColor,
        textColor: NSColor
    ) {
        let isEnabled = button.isEnabled
        button.setDashboardLayerColors(backgroundColor: backgroundColor, borderColor: borderColor)
        button.alphaValue = isEnabled ? 1 : 0.55
        button.setAccessibilityLabel(button.title)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: isEnabled ? textColor : DashboardPalette.secondaryText,
                .paragraphStyle: paragraph,
            ]
        )
    }

    // MARK: - Actions

    private func windowKey(for control: NSControl) -> WindowKey? {
        windowRows.first { $0.value.visibilitySwitch === control || $0.value.stylePopUpButton === control }?.key
    }

    @objc private func visibilitySwitchChanged(_ sender: NSSwitch) {
        guard quotaAccess.isUnlocked, let key = windowKey(for: sender) else {
            render()
            return
        }
        var configuration = displaySettings.quotaWindowConfiguration(provider: key.provider, kind: key.kind)
        configuration.isVisible = sender.state == .on
        logger.info(
            "状态栏额度周期展示变更: \(key.provider.rawValue, privacy: .public).\(key.kind.rawValue, privacy: .public) visible=\(configuration.isVisible)"
        )
        displaySettings.setQuotaWindowConfiguration(configuration, provider: key.provider, kind: key.kind)
        render()
    }

    @objc private func stylePopUpChanged(_ sender: SettingsPopUpButton) {
        let selectedIndex = sender.indexOfSelectedItem
        guard quotaAccess.isUnlocked,
              let key = windowKey(for: sender),
              StatusBarQuotaWindowStyle.allCases.indices.contains(selectedIndex) else {
            render()
            return
        }
        var configuration = displaySettings.quotaWindowConfiguration(provider: key.provider, kind: key.kind)
        configuration.style = StatusBarQuotaWindowStyle.allCases[selectedIndex]
        logger.info(
            "状态栏额度周期样式变更: \(key.provider.rawValue, privacy: .public).\(key.kind.rawValue, privacy: .public) style=\(configuration.style.rawValue, privacy: .public)"
        )
        displaySettings.setQuotaWindowConfiguration(configuration, provider: key.provider, kind: key.kind)
    }

    @objc private func purchaseButtonClicked() {
        guard let purchaseController = quotaAccess.purchaseController, let window else { return }
        Task { @MainActor in
            await purchaseController.purchase(in: window)
        }
    }

    @objc private func restoreButtonClicked() {
        guard let purchaseController = quotaAccess.purchaseController else { return }
        Task { @MainActor in
            await purchaseController.restorePurchases()
        }
    }
}
