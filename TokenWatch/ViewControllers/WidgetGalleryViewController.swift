import AppKit
import Charts
import SwiftUI

/// 展示当前桌面小组件的固定示例，便于在应用内查看可用样式。
@MainActor
final class WidgetGalleryViewController: NSViewController {
    private static let pageInset: CGFloat = 28
    private static let rowGap: CGFloat = 18
    private static let minimumContentWidth: CGFloat = 860

    /// WidgetKit 可因展示上下文调整实际尺寸；此值是图库使用的 macOS 中号小组件参考画布。
    static let systemMediumPreviewSize = CGSize(width: 329, height: 155)
    static let systemSmallPreviewSize = CGSize(width: 155, height: 155)

    private let scrollView = NSScrollView()
    private let contentView = NSView()
    private let contentStack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let heatmapPreviewHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let hourlyLinePreviewHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let weeklySmallPreviewHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let weeklyMediumPreviewHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let monthlyBudgetPreviewHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let todayAnomalySmallPreviewHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let todayAnomalyMediumPreviewHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let projectFocusPreviewHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let modelFocusPreviewHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let heatmapPreviewContainer = NSView()
    private let hourlyLinePreviewContainer = NSView()
    private let weeklySmallPreviewContainer = NSView()
    private let weeklyMediumPreviewContainer = NSView()
    private let monthlyBudgetPreviewContainer = NSView()
    private let todayAnomalySmallPreviewContainer = NSView()
    private let todayAnomalyMediumPreviewContainer = NSView()
    private let projectFocusPreviewContainer = NSView()
    private let modelFocusPreviewContainer = NSView()

    override func loadView() {
        let root = NSView()
        root.userInterfaceLayoutDirection = .leftToRight
        root.identifier = NSUserInterfaceItemIdentifier("DashboardWidgetsPage")
        root.setAccessibilityIdentifier("DashboardWidgetsPage")
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
    }

    /// 用当前语言生成固定示例快照并更新所有小组件预览。
    /// - Parameters:
    ///   - now: 用于突出示例中的当前小时并生成本地日期文案。
    ///   - calendar: 定义示例日期和当前小时的本地日历。
    ///   - language: 主应用当前使用的文案语言。
    func render(now: Date, calendar: Calendar, language: AppLanguage) {
        guard isViewLoaded else { return }

        titleLabel.stringValue = AppStrings.text(.dashboardWidgetsTitle, language: language)
        subtitleLabel.stringValue = AppStrings.text(.dashboardWidgetsSubtitle, language: language)

        let state = WidgetUsageEntryState.placeholder(
            WidgetGallerySampleSnapshotFactory.make(
                now: now,
                calendar: calendar,
                language: language
            )
        )
        let heatmap = WidgetChartPresentationBuilder.heatmap(for: state)
        let hourlyLine = WidgetChartPresentationBuilder.hourlyLine(for: state)
        let weeklySummary = WidgetChartPresentationBuilder.weeklySummary(for: state)
        let monthlyBudget = WidgetChartPresentationBuilder.monthlyBudget(for: state)
        let todayAnomaly = WidgetChartPresentationBuilder.todayAnomaly(for: state)
        let projectFocus = WidgetChartPresentationBuilder.projectFocus(for: state)
        let modelFocus = WidgetChartPresentationBuilder.modelFocus(for: state)
        heatmapPreviewContainer.setAccessibilityLabel(heatmap.title)
        hourlyLinePreviewContainer.setAccessibilityLabel(hourlyLine.title)
        weeklySmallPreviewContainer.setAccessibilityLabel(weeklySummary.title)
        weeklyMediumPreviewContainer.setAccessibilityLabel(weeklySummary.title)
        monthlyBudgetPreviewContainer.setAccessibilityLabel(monthlyBudget.title)
        todayAnomalySmallPreviewContainer.setAccessibilityLabel(todayAnomaly.title)
        todayAnomalyMediumPreviewContainer.setAccessibilityLabel(todayAnomaly.title)
        projectFocusPreviewContainer.setAccessibilityLabel(projectFocus.title)
        modelFocusPreviewContainer.setAccessibilityLabel(modelFocus.title)
        heatmapPreviewHost.rootView = AnyView(
            WidgetGalleryPreviewSurface {
                WidgetGalleryHeatmapPreview(presentation: heatmap)
            }
        )
        hourlyLinePreviewHost.rootView = AnyView(
            WidgetGalleryPreviewSurface {
                WidgetGalleryHourlyLinePreview(presentation: hourlyLine, language: language)
            }
        )
        weeklySmallPreviewHost.rootView = AnyView(
            WidgetGalleryPreviewSurface {
                WidgetGalleryWeeklySummaryPreview(presentation: weeklySummary)
            }
        )
        weeklyMediumPreviewHost.rootView = AnyView(
            WidgetGalleryPreviewSurface {
                WidgetGalleryWeeklySummaryPreview(presentation: weeklySummary)
            }
        )
        monthlyBudgetPreviewHost.rootView = AnyView(
            WidgetGalleryPreviewSurface {
                WidgetGalleryMonthlyBudgetPreview(presentation: monthlyBudget)
            }
        )
        todayAnomalySmallPreviewHost.rootView = AnyView(
            WidgetGalleryPreviewSurface {
                WidgetGalleryTodayAnomalyPreview(presentation: todayAnomaly, showsChart: false)
            }
        )
        todayAnomalyMediumPreviewHost.rootView = AnyView(
            WidgetGalleryPreviewSurface {
                WidgetGalleryTodayAnomalyPreview(presentation: todayAnomaly, showsChart: true)
            }
        )
        projectFocusPreviewHost.rootView = AnyView(
            WidgetGalleryPreviewSurface {
                WidgetGalleryProjectFocusPreview(presentation: projectFocus)
            }
        )
        modelFocusPreviewHost.rootView = AnyView(
            WidgetGalleryPreviewSurface {
                WidgetGalleryModelFocusPreview(presentation: modelFocus)
            }
        )
    }

    private func setupLayout() {
        scrollView.identifier = NSUserInterfaceItemIdentifier("DashboardWidgetsScrollView")
        scrollView.setAccessibilityIdentifier("DashboardWidgetsScrollView")
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentView

        contentView.userInterfaceLayoutDirection = .leftToRight
        contentView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = Self.rowGap
        contentStack.identifier = NSUserInterfaceItemIdentifier("DashboardWidgetsSection")
        contentStack.setAccessibilityIdentifier("DashboardWidgetsSection")
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)

        addFullWidthArrangedSubview(makeHeaderView(), to: contentStack)
        addFullWidthArrangedSubview(makePreviewRow(), to: contentStack)
        addFullWidthArrangedSubview(makeWeeklySummaryPreviewRow(), to: contentStack)
        addFullWidthArrangedSubview(makeTodayAnomalyPreviewRow(), to: contentStack)
        addFullWidthArrangedSubview(makeMonthlyBudgetPreviewRow(), to: contentStack)
        addFullWidthArrangedSubview(makeFocusPreviewRow(), to: contentStack)

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.pageInset),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Self.pageInset),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.pageInset),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Self.pageInset),
            contentStack.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumContentWidth),
        ])
    }

    private func makeHeaderView() -> NSView {
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        titleLabel.textColor = DashboardPalette.primaryText
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = DashboardPalette.secondaryText

        let stack = NSStackView(views: [titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        NSLayoutConstraint.activate([
            stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
        ])
        return stack
    }

    private func makePreviewRow() -> NSView {
        configurePreviewContainer(
            heatmapPreviewContainer,
            hostingView: heatmapPreviewHost,
            identifier: "DashboardWidgetPreview.heatmap"
        )
        configurePreviewContainer(
            hourlyLinePreviewContainer,
            hostingView: hourlyLinePreviewHost,
            identifier: "DashboardWidgetPreview.hourlyLine"
        )

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(heatmapPreviewContainer)
        row.addSubview(hourlyLinePreviewContainer)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: Self.systemMediumPreviewSize.height),
            heatmapPreviewContainer.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            heatmapPreviewContainer.topAnchor.constraint(equalTo: row.topAnchor),
            hourlyLinePreviewContainer.leadingAnchor.constraint(
                equalTo: heatmapPreviewContainer.trailingAnchor,
                constant: 16
            ),
            hourlyLinePreviewContainer.topAnchor.constraint(equalTo: row.topAnchor),
        ])
        return row
    }

    private func makeWeeklySummaryPreviewRow() -> NSView {
        configurePreviewContainer(
            weeklySmallPreviewContainer,
            hostingView: weeklySmallPreviewHost,
            identifier: "DashboardWidgetPreview.weeklySummary.small",
            size: Self.systemSmallPreviewSize
        )
        configurePreviewContainer(
            weeklyMediumPreviewContainer,
            hostingView: weeklyMediumPreviewHost,
            identifier: "DashboardWidgetPreview.weeklySummary.medium"
        )

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(weeklySmallPreviewContainer)
        row.addSubview(weeklyMediumPreviewContainer)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: Self.systemMediumPreviewSize.height),
            weeklySmallPreviewContainer.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            weeklySmallPreviewContainer.topAnchor.constraint(equalTo: row.topAnchor),
            weeklyMediumPreviewContainer.leadingAnchor.constraint(
                equalTo: weeklySmallPreviewContainer.trailingAnchor,
                constant: 16
            ),
            weeklyMediumPreviewContainer.topAnchor.constraint(equalTo: row.topAnchor),
        ])
        return row
    }

    private func makeTodayAnomalyPreviewRow() -> NSView {
        configurePreviewContainer(
            todayAnomalySmallPreviewContainer,
            hostingView: todayAnomalySmallPreviewHost,
            identifier: "DashboardWidgetPreview.todayAnomaly.small",
            size: Self.systemSmallPreviewSize
        )
        configurePreviewContainer(
            todayAnomalyMediumPreviewContainer,
            hostingView: todayAnomalyMediumPreviewHost,
            identifier: "DashboardWidgetPreview.todayAnomaly.medium"
        )

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(todayAnomalySmallPreviewContainer)
        row.addSubview(todayAnomalyMediumPreviewContainer)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: Self.systemMediumPreviewSize.height),
            todayAnomalySmallPreviewContainer.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            todayAnomalySmallPreviewContainer.topAnchor.constraint(equalTo: row.topAnchor),
            todayAnomalyMediumPreviewContainer.leadingAnchor.constraint(
                equalTo: todayAnomalySmallPreviewContainer.trailingAnchor,
                constant: 16
            ),
            todayAnomalyMediumPreviewContainer.topAnchor.constraint(equalTo: row.topAnchor),
        ])
        return row
    }

    private func makeMonthlyBudgetPreviewRow() -> NSView {
        configurePreviewContainer(
            monthlyBudgetPreviewContainer,
            hostingView: monthlyBudgetPreviewHost,
            identifier: "DashboardWidgetPreview.monthlyBudget"
        )

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(monthlyBudgetPreviewContainer)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: Self.systemMediumPreviewSize.height),
            monthlyBudgetPreviewContainer.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            monthlyBudgetPreviewContainer.topAnchor.constraint(equalTo: row.topAnchor),
        ])
        return row
    }

    private func makeFocusPreviewRow() -> NSView {
        configurePreviewContainer(
            projectFocusPreviewContainer,
            hostingView: projectFocusPreviewHost,
            identifier: "DashboardWidgetPreview.projectFocus"
        )
        configurePreviewContainer(
            modelFocusPreviewContainer,
            hostingView: modelFocusPreviewHost,
            identifier: "DashboardWidgetPreview.modelFocus"
        )

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(projectFocusPreviewContainer)
        row.addSubview(modelFocusPreviewContainer)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: Self.systemMediumPreviewSize.height),
            projectFocusPreviewContainer.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            projectFocusPreviewContainer.topAnchor.constraint(equalTo: row.topAnchor),
            modelFocusPreviewContainer.leadingAnchor.constraint(
                equalTo: projectFocusPreviewContainer.trailingAnchor,
                constant: 16
            ),
            modelFocusPreviewContainer.topAnchor.constraint(equalTo: row.topAnchor),
        ])
        return row
    }

    private func configurePreviewContainer(
        _ container: NSView,
        hostingView: NSHostingView<AnyView>,
        identifier: String,
        size: CGSize? = nil
    ) {
        let previewSize = size ?? Self.systemMediumPreviewSize
        container.identifier = NSUserInterfaceItemIdentifier(identifier)
        container.setAccessibilityIdentifier(identifier)
        container.setAccessibilityElement(true)
        container.setAccessibilityRole(.group)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.setContentHuggingPriority(.required, for: .horizontal)
        container.setContentCompressionResistancePriority(.required, for: .horizontal)
        container.addSubview(hostingView)
        hostingView.identifier = NSUserInterfaceItemIdentifier("\(identifier).content")
        hostingView.setAccessibilityIdentifier("\(identifier).content")
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: previewSize.width),
            container.heightAnchor.constraint(equalToConstant: previewSize.height),
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    private func addFullWidthArrangedSubview(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
}

/// 预览使用固定的、与用户数据无关的样例，以确保首次打开也能看清全部组件样式。
enum WidgetGallerySampleSnapshotFactory {
    /// 构建满足 Widget 固定网格和小时形状约束的本地化示例快照。
    static func make(
        now: Date,
        calendar: Calendar,
        language: AppLanguage
    ) -> WidgetUsageSnapshot {
        let cells = (0..<(WidgetChartVisualStyle.heatmapColumns * WidgetChartVisualStyle.heatmapRows))
            .map { index in
                let intensity = index % (WidgetChartVisualStyle.heatmapMaximumIntensity + 1)
                return WidgetHeatmapCell(
                    dateKey: "widget-preview-day-\(index)",
                    totalTokens: intensity * 100_000,
                    intensity: intensity,
                    isPlaceholder: false
                )
            }
        let currentHour = calendar.component(.hour, from: now)
        let points = (0...23).map { hour in
            let total = max(0, 18 - abs(14 - hour) * 2) * 100_000
            return WidgetHourlyPoint(
                hour: hour,
                hourKey: "widget-preview-hour-\(hour)",
                hourLabel: "\(hour)",
                totalTokens: total,
                isCurrentHour: hour == currentHour
            )
        }
        let dateText = localizedMonthDay(now, calendar: calendar, language: language)
        let localDayKey = dayKey(now, calendar: calendar)
        let windowStart = calendar.date(byAdding: .day, value: -6, to: now) ?? now
        let windowStartDayKey = dayKey(windowStart, calendar: calendar)

        return WidgetUsageSnapshot(
            schemaVersion: WidgetSharedConfiguration.schemaVersion,
            generatedAt: now,
            localDayKey: localDayKey,
            localizedText: WidgetLocalizedText(
                heatmapTitle: AppStrings.text(.widgetHeatmapTitle, language: language),
                todayUsageTitle: AppStrings.text(.widgetTodayUsageTitle, language: language),
                datedUsageTitle: String(
                    format: AppStrings.text(.widgetDatedUsageTitleFormat, language: language),
                    dateText
                ),
                updatedThroughTitle: String(
                    format: AppStrings.text(.widgetUpdatedThroughTitleFormat, language: language),
                    dateText
                ),
                notReadyMessage: AppStrings.text(.widgetNotReadyMessage, language: language),
                weeklySummaryTitle: UsageStatsPeriod.recent7Days.title(language: language),
                projectFocusTitle: AppStrings.text(.dashboardProjectUsageTitle, language: language),
                projectFocusNoDataMessage: AppStrings.text(.dashboardNoProjectData, language: language),
                modelFocusTitle: AppStrings.text(.dashboardPrimaryModel, language: language),
                modelFocusNoDataMessage: AppStrings.text(.totalEmptyModels, language: language)
            ),
            heatmap: WidgetHeatmapSnapshot(
                totalTokens: cells.reduce(0) { $0 + $1.totalTokens },
                maxDailyTokens: cells.map(\.totalTokens).max() ?? 0,
                cells: cells
            ),
            hourlyLine: WidgetHourlyLineSnapshot(
                dayKey: localDayKey,
                totalTokens: points.reduce(0) { $0 + $1.totalTokens },
                maxHourlyTokens: points.map(\.totalTokens).max() ?? 0,
                points: points
            ),
            monthlyBudget: makeMonthlyBudget(language: language),
            projectFocus: WidgetProjectFocusSnapshot(
                windowStartDayKey: windowStartDayKey,
                windowEndDayKey: localDayKey,
                windowTotalTokens: 4_000_000,
                topProjectName: "TokenWatch",
                topProjectTokens: 2_500_000
            ),
            modelFocus: WidgetModelFocusSnapshot(
                windowStartDayKey: windowStartDayKey,
                windowEndDayKey: localDayKey,
                windowTotalTokens: 4_000_000,
                providerName: "Claude",
                modelName: "claude-sonnet-4",
                modelTokens: 2_100_000
            )
        )
    }

    private static func makeMonthlyBudget(
        language: AppLanguage
    ) -> WidgetMonthlyBudgetSnapshot {
        let copy = MonthlyBudgetCopy.make(language: language)
        return WidgetMonthlyBudgetSnapshot(
            monthKey: "2026-08",
            spentUSD: 42.75,
            budgetUSD: 100,
            forecastUSD: 86.50,
            title: copy.title,
            forecastTitle: copy.forecastTitle,
            unconfiguredMessage: copy.unconfiguredMessage,
            forecastOverBudgetMessage: copy.forecastOverBudgetMessage
        )
    }

    private static func localizedMonthDay(
        _ date: Date,
        calendar: Calendar,
        language: AppLanguage
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

private struct WidgetGalleryPreviewSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(WidgetGalleryPreviewAppearance.contentInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                .background,
                in: RoundedRectangle(
                    cornerRadius: WidgetGalleryPreviewAppearance.cornerRadius,
                    style: .continuous
                )
            )
    }
}

private enum WidgetGalleryPreviewAppearance {
    static let contentInset: CGFloat = 16
    static let cornerRadius: CGFloat = 20
}

private struct WidgetGalleryPreviewHeader: View {
    let title: String
    let subtitle: String?
    let total: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(total)
                .font(.headline)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct WidgetGalleryHeatmapPreview: View {
    let presentation: WidgetHeatmapPresentation
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            WidgetGalleryPreviewHeader(
                title: presentation.title,
                subtitle: presentation.subtitle,
                total: presentation.totalText
            )
            ZStack {
                GeometryReader { proxy in
                    let side = CGFloat(WidgetChartVisualStyle.heatmapTileSide(
                        availableWidth: Double(proxy.size.width),
                        availableHeight: Double(proxy.size.height)
                    ))
                    let spacing = CGFloat(WidgetChartVisualStyle.heatmapSpacing)
                    let radius = CGFloat(WidgetChartVisualStyle.heatmapCornerRadius)

                    HStack(spacing: spacing) {
                        ForEach(0..<WidgetChartVisualStyle.heatmapColumns, id: \.self) { column in
                            VStack(spacing: spacing) {
                                ForEach(0..<WidgetChartVisualStyle.heatmapRows, id: \.self) { row in
                                    let index = WidgetChartVisualStyle.heatmapIndex(
                                        column: column,
                                        row: row
                                    )
                                    RoundedRectangle(cornerRadius: radius)
                                        .fill(color(for: presentation.cells[index]))
                                        .frame(width: side, height: side)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func color(for cell: WidgetHeatmapPresentationCell) -> Color {
        guard cell.isVisible else { return .clear }
        let rgba = WidgetChartVisualStyle.heatmapRGBA(
            intensity: cell.intensity,
            isDark: colorScheme == .dark
        )
        return Color(
            .sRGB,
            red: rgba.red,
            green: rgba.green,
            blue: rgba.blue,
            opacity: rgba.alpha
        )
    }
}

private struct WidgetGalleryHourlyLinePreview: View {
    let presentation: WidgetHourlyLinePresentation
    let language: AppLanguage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            WidgetGalleryPreviewHeader(
                title: presentation.title,
                subtitle: nil,
                total: presentation.totalText
            )
            Chart {
                ForEach(presentation.points) { point in
                    AreaMark(
                        x: .value(hourAxisValueName, point.hour),
                        y: .value(tokenAxisValueName, point.totalTokens)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(areaGradient)
                }
                ForEach(presentation.points) { point in
                    LineMark(
                        x: .value(hourAxisValueName, point.hour),
                        y: .value(tokenAxisValueName, point.totalTokens)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(
                        lineWidth: CGFloat(WidgetChartVisualStyle.lineWidth),
                        lineCap: .round,
                        lineJoin: .round
                    ))
                }
                if let point = presentation.currentPoint {
                    PointMark(
                        x: .value(hourAxisValueName, point.hour),
                        y: .value(tokenAxisValueName, point.totalTokens)
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(CGFloat(WidgetChartVisualStyle.currentPointSize))
                }
            }
            .chartLegend(.hidden)
            .chartXScale(domain: 0...23)
            .chartYScale(domain: 0...presentation.maximumY)
            .chartXAxis {
                AxisMarks(values: WidgetChartVisualStyle.hourAxisValues) { value in
                    AxisTick()
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text(verbatim: "\(hour)").font(.system(size: 8))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                        .foregroundStyle(.secondary.opacity(WidgetChartVisualStyle.gridOpacity))
                    AxisTick()
                    AxisValueLabel {
                        if let tokens = value.as(Double.self) {
                            Text(WidgetChartNumberFormatter.axis(tokens))
                                .font(.system(size: 8))
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private var areaGradient: LinearGradient {
        let rgba = WidgetChartVisualStyle.heatmapRGBA(
            intensity: WidgetChartVisualStyle.heatmapMaximumIntensity,
            isDark: colorScheme == .dark
        )
        let green = Color(
            .sRGB,
            red: rgba.red,
            green: rgba.green,
            blue: rgba.blue,
            opacity: rgba.alpha
        )
        return LinearGradient(
            colors: [
                green.opacity(WidgetChartVisualStyle.areaPeakOpacity),
                green.opacity(WidgetChartVisualStyle.areaBaselineOpacity),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var hourAxisValueName: String {
        AppStrings.text(.recentDetailsTime, language: language)
    }

    private var tokenAxisValueName: String {
        AppStrings.text(.recentDetailsTokens, language: language)
    }
}

private struct WidgetGalleryWeeklySummaryPreview: View {
    let presentation: WidgetWeeklySummaryPresentation

    var body: some View {
        VStack(spacing: 7) {
            WidgetGalleryPreviewHeader(
                title: presentation.title,
                subtitle: presentation.subtitle,
                total: presentation.totalText
            )
            Chart(presentation.points) { point in
                BarMark(
                    x: .value("Day", point.position),
                    y: .value("Tokens", point.totalTokens)
                )
                .foregroundStyle(
                    point.isCurrentDay
                        ? Color.accentColor
                        : Color.accentColor.opacity(0.45)
                )
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .chartLegend(.hidden)
            .chartXScale(domain: -0.5...6.5)
            .chartYScale(domain: 0...presentation.maximumY)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

private struct WidgetGalleryMonthlyBudgetPreview: View {
    let presentation: WidgetMonthlyBudgetPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(presentation.title)
                        .font(.headline)
                        .lineLimit(1)
                    if let subtitle = presentation.subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text(presentation.spentText)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if let budgetText = presentation.budgetText,
               let progress = presentation.progress {
                Text("\(presentation.spentText) / \(budgetText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                GeometryReader { proxy in
                    let width = proxy.size.width * min(max(progress, 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.secondary.opacity(0.2))
                        Capsule()
                            .fill(
                                presentation.isForecastOverBudget
                                    ? Color.red
                                    : Color.accentColor
                            )
                            .frame(width: width)
                    }
                }
                .frame(height: 8)
                if let forecastText = presentation.forecastText {
                    Text(forecastText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let message = presentation.message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(
                        presentation.isForecastOverBudget ? .red : .secondary
                    )
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

private struct WidgetGalleryTodayAnomalyPreview: View {
    let presentation: WidgetTodayAnomalyPresentation
    let showsChart: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetGalleryPreviewHeader(
                title: presentation.title,
                subtitle: presentation.subtitle,
                total: presentation.totalText
            )
            if let message = presentation.message {
                Spacer(minLength: 0)
                Text(message)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: statusSymbol)
                        .foregroundStyle(presentation.isElevated ? .red : .accentColor)
                    if let multiplier = presentation.multiplierText {
                        Text(multiplier)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    } else {
                        Text("—")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 2)
                    if let baseline = presentation.baselineText {
                        Text(baseline)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                if showsChart {
                    Chart(presentation.points) { point in
                        BarMark(
                            x: .value("Day", point.position),
                            y: .value("Tokens", point.totalTokens)
                        )
                        .foregroundStyle(color(for: point))
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                    .chartLegend(.hidden)
                    .chartXScale(domain: -0.5...7.5)
                    .chartYScale(domain: 0...presentation.maximumY)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private var statusSymbol: String {
        if presentation.isElevated {
            return "exclamationmark.triangle.fill"
        }
        return presentation.hasComparableBaseline
            ? "checkmark.circle.fill"
            : "circle.dashed"
    }

    private func color(for point: WidgetTodayAnomalyPoint) -> Color {
        guard point.isToday else { return Color.accentColor.opacity(0.38) }
        return presentation.isElevated ? .red : .accentColor
    }
}

private struct WidgetGalleryProjectFocusPreview: View {
    let presentation: WidgetProjectFocusPresentation

    var body: some View {
        WidgetGalleryFocusPreview(
            title: presentation.title,
            subtitle: presentation.subtitle,
            primaryName: presentation.projectName,
            secondaryName: nil,
            total: presentation.totalText,
            share: presentation.shareText,
            progress: presentation.progress,
            message: presentation.message,
            accessibilityLabel: presentation.accessibilityLabel
        )
    }
}

private struct WidgetGalleryModelFocusPreview: View {
    let presentation: WidgetModelFocusPresentation

    var body: some View {
        WidgetGalleryFocusPreview(
            title: presentation.title,
            subtitle: presentation.subtitle,
            primaryName: presentation.modelName,
            secondaryName: presentation.providerName,
            total: presentation.totalText,
            share: presentation.shareText,
            progress: presentation.progress,
            message: presentation.message,
            accessibilityLabel: presentation.accessibilityLabel
        )
    }
}

private struct WidgetGalleryFocusPreview: View {
    let title: String
    let subtitle: String?
    let primaryName: String?
    let secondaryName: String?
    let total: String
    let share: String?
    let progress: Double
    let message: String?
    let accessibilityLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetGalleryPreviewHeader(
                title: title,
                subtitle: subtitle,
                total: total
            )
            if let primaryName {
                Text(primaryName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let secondaryName {
                        Text(secondaryName)
                    }
                    if secondaryName != nil, share != nil {
                        Text("·")
                    }
                    if let share {
                        Text(share)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                GeometryReader { proxy in
                    let width = proxy.size.width * min(max(progress, 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.secondary.opacity(0.2))
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: width)
                    }
                }
                .frame(height: 8)
            } else if let message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}
