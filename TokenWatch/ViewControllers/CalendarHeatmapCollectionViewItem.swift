import AppKit
import Foundation

/// 纯样式模型,让 collection item 的展示规则可单元测试。
struct CalendarHeatmapCellStyle: Equatable {
    let title: String
    let toolTip: String?
    let isHidden: Bool
    let alpha: CGFloat
    let intensity: Int
    let isAccessibilityElement: Bool
    let accessibilityLabel: String?
    let accessibilityValue: String?

    static func make(
        for cell: CalendarHeatmapCell,
        language: AppLanguage = .zhHans,
        calendar: Calendar = .current
    ) -> CalendarHeatmapCellStyle {
        switch cell {
        case .placeholder:
            return CalendarHeatmapCellStyle(
                title: "",
                toolTip: nil,
                isHidden: true,
                alpha: 0,
                intensity: 0,
                isAccessibilityElement: false,
                accessibilityLabel: nil,
                accessibilityValue: nil
            )
        case .day(let day):
            let formattedTokens = CompactNumberFormatter.formatHoverTokens(day.totalTokens)
            let tokenUnit = AppStrings.text(.statusBarTokenUnit, language: language)
            return CalendarHeatmapCellStyle(
                title: "",
                toolTip: "\(day.dateKey) · \(formattedTokens)",
                isHidden: false,
                alpha: day.isFuture ? 0.45 : 1.0,
                intensity: day.intensity,
                isAccessibilityElement: true,
                accessibilityLabel: localizedDate(
                    day.date,
                    language: language,
                    calendar: calendar
                ),
                accessibilityValue: "\(formattedTokens) \(tokenUnit)"
            )
        }
    }

    private static func localizedDate(
        _ date: Date,
        language: AppLanguage,
        calendar: Calendar
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

/// 日历热力图单个 collection item。
final class CalendarHeatmapCollectionViewItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("CalendarHeatmapCollectionViewItem")
    static let tileSize = NSSize(width: 12, height: 12)
    static let cornerRadius: CGFloat = 2

    private let dayLabel = NSTextField(labelWithString: "")
    var onHoverTextChange: ((String?) -> Void)? {
        didSet {
            guard isViewLoaded else { return }
            cellView.onHoverTextChange = onHoverTextChange
        }
    }

    override func loadView() {
        let cellView = CalendarHeatmapCellView(frame: NSRect(origin: .zero, size: Self.tileSize))
        cellView.wantsLayer = true
        cellView.layer?.cornerRadius = Self.cornerRadius
        cellView.layer?.masksToBounds = true
        cellView.onHoverTextChange = onHoverTextChange
        view = cellView

        dayLabel.translatesAutoresizingMaskIntoConstraints = false
        dayLabel.alignment = .center
        dayLabel.font = .systemFont(ofSize: 11, weight: .medium)
        dayLabel.textColor = .labelColor
        dayLabel.isHidden = true

        view.addSubview(dayLabel)
        NSLayoutConstraint.activate([
            dayLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dayLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func configure(
        with cell: CalendarHeatmapCell,
        language: AppLanguage = .zhHans,
        calendar: Calendar = .current
    ) {
        let style = CalendarHeatmapCellStyle.make(
            for: cell,
            language: language,
            calendar: calendar
        )
        dayLabel.stringValue = style.title
        view.toolTip = style.toolTip
        view.isHidden = style.isHidden
        view.alphaValue = style.alpha
        cellView.heatmapBackgroundColor = CalendarHeatmapGitHubPalette.color(forIntensity: style.intensity)
        cellView.hoverText = style.toolTip

        view.setAccessibilityElement(style.isAccessibilityElement)
        if style.isAccessibilityElement {
            view.setAccessibilityRole(.staticText)
            view.setAccessibilityLabel(style.accessibilityLabel)
            view.setAccessibilityValue(style.accessibilityValue)
        } else {
            view.setAccessibilityRole(nil)
            view.setAccessibilityLabel(nil)
            view.setAccessibilityValue(nil)
        }

        if style.toolTip == nil {
            onHoverTextChange?(nil)
        }
    }

    private var cellView: CalendarHeatmapCellView {
        guard let cellView = view as? CalendarHeatmapCellView else {
            preconditionFailure("CalendarHeatmapCollectionViewItem.view must be CalendarHeatmapCellView")
        }
        return cellView
    }

    func debugSimulateMouseEntered() {
        cellView.debugSimulateMouseEntered()
    }

    func debugSimulateMouseExited() {
        cellView.debugSimulateMouseExited()
    }
}

private final class CalendarHeatmapCellView: NSView {
    var heatmapBackgroundColor: NSColor = .clear {
        didSet {
            applyHeatmapBackgroundColor()
        }
    }
    var hoverText: String? {
        didSet {
            updateTrackingAreas()
        }
    }
    var onHoverTextChange: ((String?) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
            self.hoverTrackingArea = nil
        }

        guard hoverText != nil, !isHidden else { return }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        emitHoverText()
    }

    override func mouseExited(with event: NSEvent) {
        onHoverTextChange?(nil)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyHeatmapBackgroundColor()
    }

    func debugSimulateMouseEntered() {
        emitHoverText()
    }

    func debugSimulateMouseExited() {
        onHoverTextChange?(nil)
    }

    private func applyHeatmapBackgroundColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = heatmapBackgroundColor.cgColor
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            layer?.borderWidth = 0.5
            layer?.borderColor = isDark
                ? NSColor(white: 1.0, alpha: 0.08).cgColor
                : NSColor(white: 0.0, alpha: 0.06).cgColor
        }
    }

    private func emitHoverText() {
        guard let hoverText, !isHidden else { return }
        onHoverTextChange?(hoverText)
    }
}

enum CalendarHeatmapGitHubPalette {
    static let maxIntensity = WidgetChartVisualStyle.heatmapMaximumIntensity

    static func color(forIntensity intensity: Int) -> NSColor {
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return color(WidgetChartVisualStyle.heatmapRGBA(
                intensity: intensity,
                isDark: isDark
            ))
        }
    }

    static var maxIntensityColor: NSColor {
        color(forIntensity: maxIntensity)
    }

    private static func color(_ rgba: WidgetChartRGBA) -> NSColor {
        NSColor(
            calibratedRed: CGFloat(rgba.red),
            green: CGFloat(rgba.green),
            blue: CGFloat(rgba.blue),
            alpha: CGFloat(rgba.alpha)
        )
    }
}
