import AppKit

/// 可复用的最近会话明细 AppKit 视图。外部注入 snapshot 后只负责渲染,不读取 ViewModel。
@MainActor
final class RecentSessionDetailsView: NSView {
    private enum Layout {
        static let timeWidth: CGFloat = 96
        static let toolWidth: CGFloat = 56
        static let tokensWidth: CGFloat = 66
        static let costWidth: CGFloat = 70
        static let recordsWidth: CGFloat = 50
        static let rowSpacing: CGFloat = 8
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let headerStack = NSStackView()
    private let rowsStack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "")

    private(set) var debugRowTexts: [String] = []
    private(set) var debugHeaderTexts: [String] = []

    var debugTitleText: String {
        titleLabel.stringValue
    }

    var debugEmptyText: String {
        emptyLabel.isHidden ? "" : emptyLabel.stringValue
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    /// 用新的最近会话 snapshot 替换标题、表头、空状态和明细行。
    /// - Parameters:
    ///   - snapshot: 最近会话明细数据快照。
    ///   - language: 当前应用语言,用于标题、空状态和表头文案。
    func configure(with snapshot: RecentSessionDetailsSnapshot, language: AppLanguage) {
        titleLabel.stringValue = AppStrings.text(.recentDetailsTitle, language: language)
        emptyLabel.stringValue = AppStrings.text(.recentDetailsEmpty, language: language)
        debugHeaderTexts = [
            AppStrings.text(.recentDetailsTime, language: language),
            AppStrings.text(.recentDetailsSession, language: language),
            AppStrings.text(.recentDetailsTool, language: language),
            AppStrings.text(.recentDetailsProject, language: language),
            AppStrings.text(.recentDetailsModel, language: language),
            AppStrings.text(.recentDetailsTokens, language: language),
            AppStrings.text(.recentDetailsCost, language: language),
            AppStrings.text(.recentDetailsRecords, language: language),
        ]

        rebuildHeader()
        rebuildRows(snapshot.rows, language: language)

        let isEmpty = snapshot.rows.isEmpty
        emptyLabel.isHidden = !isEmpty
        headerStack.isHidden = isEmpty
        rowsStack.isHidden = isEmpty
    }

    private func setupView() {
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .left

        headerStack.orientation = .vertical
        headerStack.alignment = .width
        headerStack.spacing = 3

        rowsStack.orientation = .vertical
        rowsStack.alignment = .width
        rowsStack.spacing = 0

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .left
        emptyLabel.lineBreakMode = .byTruncatingTail
        emptyLabel.isHidden = true

        let rootStack = NSStackView(views: [titleLabel, headerStack, emptyLabel, rowsStack])
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.orientation = .vertical
        rootStack.alignment = .width
        rootStack.spacing = 8
        rootStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func rebuildHeader() {
        removeArrangedSubviews(from: headerStack)
        guard debugHeaderTexts.count == 8 else { return }

        let topRow = makeHorizontalStack(views: [
            makeHeaderLabel(debugHeaderTexts[0], width: Layout.timeWidth),
            makeHeaderLabel(debugHeaderTexts[1]),
            makeHeaderLabel(debugHeaderTexts[2], width: Layout.toolWidth),
            makeHeaderLabel(debugHeaderTexts[5], width: Layout.tokensWidth, alignment: .right),
            makeHeaderLabel(debugHeaderTexts[6], width: Layout.costWidth, alignment: .right),
            makeHeaderLabel(debugHeaderTexts[7], width: Layout.recordsWidth, alignment: .right),
        ])
        let detailRow = makeHorizontalStack(views: [
            makeHeaderLabel(debugHeaderTexts[3]),
            makeHeaderLabel(debugHeaderTexts[4]),
        ])
        if let first = detailRow.arrangedSubviews.first,
           let last = detailRow.arrangedSubviews.last {
            first.widthAnchor.constraint(equalTo: last.widthAnchor).isActive = true
        }

        headerStack.addArrangedSubview(topRow)
        headerStack.addArrangedSubview(detailRow)
    }

    private func rebuildRows(_ rows: [RecentSessionRow], language: AppLanguage) {
        removeArrangedSubviews(from: rowsStack)
        debugRowTexts = rows.map { debugText(for: $0) }

        for (index, row) in rows.enumerated() {
            rowsStack.addArrangedSubview(makeRowView(for: row, language: language))
            if index < rows.count - 1 {
                rowsStack.addArrangedSubview(makeSeparator())
            }
        }
    }

    private func makeRowView(for row: RecentSessionRow, language: AppLanguage) -> NSView {
        let timeText = formatDate(row.lastActiveAt)
        let providerText = providerDisplayName(row.provider)
        let projectText = projectDisplayText(for: row)
        let modelText = modelDisplayText(for: row)
        let tokensText = formatInteger(row.totalTokens)
        let costText = formatCost(row.cost)
        let recordsText = formatInteger(row.entryCount)

        let topRow = makeHorizontalStack(views: [
            makeValueLabel(timeText, width: Layout.timeWidth, isMonospaced: true),
            makeValueLabel(row.sessionID, lineBreakMode: .byTruncatingMiddle),
            makeValueLabel(providerText, width: Layout.toolWidth),
            makeValueLabel(tokensText, width: Layout.tokensWidth, alignment: .right, isMonospaced: true),
            makeValueLabel(costText, width: Layout.costWidth, alignment: .right, isMonospaced: true),
            makeValueLabel(recordsText, width: Layout.recordsWidth, alignment: .right, isMonospaced: true),
        ])

        let projectValue = makeDetailValueLabel(projectText)
        let modelValue = makeDetailValueLabel(modelText)
        let detailRow = makeHorizontalStack(views: [
            makeDetailPair(label: AppStrings.text(.recentDetailsProject, language: language), valueLabel: projectValue),
            makeDetailPair(label: AppStrings.text(.recentDetailsModel, language: language), valueLabel: modelValue),
        ])
        if let first = detailRow.arrangedSubviews.first,
           let last = detailRow.arrangedSubviews.last {
            first.widthAnchor.constraint(equalTo: last.widthAnchor).isActive = true
        }

        let rowStack = NSStackView(views: [topRow, detailRow])
        rowStack.orientation = .vertical
        rowStack.alignment = .width
        rowStack.spacing = 3
        rowStack.edgeInsets = NSEdgeInsets(top: 5, left: 0, bottom: 5, right: 0)
        rowStack.toolTip = debugText(for: row)
        rowStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        return rowStack
    }

    private func makeDetailPair(label: String, valueLabel: NSTextField) -> NSView {
        let keyLabel = NSTextField(labelWithString: label)
        keyLabel.font = .systemFont(ofSize: 10, weight: .medium)
        keyLabel.textColor = .tertiaryLabelColor
        keyLabel.setContentHuggingPriority(.required, for: .horizontal)
        keyLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = NSStackView(views: [keyLabel, valueLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.distribution = .fill
        stack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return stack
    }

    private func makeHeaderLabel(
        _ text: String,
        width: CGFloat? = nil,
        alignment: NSTextAlignment = .left
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        configureHorizontalPriorities(label, width: width)
        return label
    }

    private func makeValueLabel(
        _ text: String,
        width: CGFloat? = nil,
        alignment: NSTextAlignment = .left,
        lineBreakMode: NSLineBreakMode = .byTruncatingTail,
        isMonospaced: Bool = false
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = isMonospaced
            ? .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            : .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.alignment = alignment
        label.lineBreakMode = lineBreakMode
        label.maximumNumberOfLines = 1
        label.toolTip = text
        configureHorizontalPriorities(label, width: width)
        return label
    }

    private func makeDetailValueLabel(_ text: String) -> NSTextField {
        let label = makeValueLabel(text, lineBreakMode: .byTruncatingMiddle)
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func makeHorizontalStack(views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = Layout.rowSpacing
        stack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return stack
    }

    private func makeSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }

    private func configureHorizontalPriorities(_ label: NSTextField, width: CGFloat?) {
        if let width {
            label.widthAnchor.constraint(equalToConstant: width).isActive = true
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        } else {
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
    }

    private func removeArrangedSubviews(from stack: NSStackView) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func debugText(for row: RecentSessionRow) -> String {
        [
            formatDate(row.lastActiveAt),
            row.sessionID,
            providerDisplayName(row.provider),
            projectDisplayText(for: row),
            modelDisplayText(for: row),
            formatInteger(row.totalTokens),
            formatCost(row.cost),
            formatInteger(row.entryCount),
        ].joined(separator: " | ")
    }

    private func providerDisplayName(_ provider: ProviderID) -> String {
        switch provider {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .opencode:
            return "opencode"
        }
    }

    private func modelDisplayText(for row: RecentSessionRow) -> String {
        let model = row.primaryModel.isEmpty ? "-" : row.primaryModel
        guard row.additionalModelCount > 0 else { return model }
        return "\(model) +\(row.additionalModelCount)"
    }

    private func projectDisplayText(for row: RecentSessionRow) -> String {
        guard let projectPath = row.projectPath, !projectPath.isEmpty else {
            return "unknown"
        }
        return projectPath
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "-" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func formatInteger(_ value: Int) -> String {
        String(max(value, 0))
    }

    private func formatCost(_ value: Double) -> String {
        String(format: "$%.4f", max(value, 0))
    }
}
