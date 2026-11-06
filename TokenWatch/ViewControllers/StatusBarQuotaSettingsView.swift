import AppKit
import os.log

/// 设置页“状态栏订阅额度”区块内容。
///
/// 依次展示 Claude、Codex 两组，
/// 分别配置 5 小时与一周额度是否在状态栏展示，以及简洁（只显示圆环）/ 详细（附剩余百分比）样式。
/// 两组纵向排列，设置页在窄窗口下也不会被撑宽。
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

    private let descriptionLabel = NSTextField(wrappingLabelWithString: "")
    private var windowRows: [WindowKey: WindowRowViews] = [:]

    private var displaySettingsObserverToken: StatusBarDisplaySettings.ObservationToken?
    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "StatusBarQuotaSettings")

    /// - Parameters:
    ///   - displaySettings: 状态栏展示设置，修改后状态栏立即重绘。
    ///   - language: 初始界面语言。
    init(
        displaySettings: StatusBarDisplaySettings,
        language: AppLanguage
    ) {
        self.displaySettings = displaySettings
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
        }
    }

    /// 按界面语言刷新全部文案并重绘状态。
    /// - Parameter language: 当前界面语言。
    func reloadLocalizedText(language: AppLanguage) {
        descriptionLabel.stringValue = AppStrings.text(.settingsStatusBarQuotaDescription, language: language)
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

        let stack = NSStackView(views: [descriptionLabel, divider, providerGroups])
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
            divider.widthAnchor.constraint(equalTo: stack.widthAnchor),
            providerGroups.widthAnchor.constraint(equalTo: stack.widthAnchor),
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

    private func subscribe() {
        displaySettingsObserverToken = displaySettings.observe { [weak self] in
            self?.render()
        }
    }

    // MARK: - Render

    private func render() {
        for (key, row) in windowRows {
            let configuration = displaySettings.quotaWindowConfiguration(provider: key.provider, kind: key.kind)
            row.visibilitySwitch.state = configuration.isVisible ? .on : .off
            row.visibilitySwitch.isEnabled = true
            if let styleIndex = StatusBarQuotaWindowStyle.allCases.firstIndex(of: configuration.style) {
                row.stylePopUpButton.selectItem(at: styleIndex)
            }
            // 周期隐藏时样式不生效，禁用以免误以为可调整。
            row.stylePopUpButton.isEnabled = configuration.isVisible
            row.titleLabel.textColor = DashboardPalette.primaryText
        }
    }

    // MARK: - Actions

    private func windowKey(for control: NSControl) -> WindowKey? {
        windowRows.first { $0.value.visibilitySwitch === control || $0.value.stylePopUpButton === control }?.key
    }

    @objc private func visibilitySwitchChanged(_ sender: NSSwitch) {
        guard let key = windowKey(for: sender) else {
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
        guard let key = windowKey(for: sender),
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
}
