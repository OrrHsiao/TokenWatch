import AppKit
import Foundation

/// 纯样式模型,让 collection item 的展示规则可单元测试。
struct CalendarHeatmapCellStyle: Equatable {
    let title: String
    let toolTip: String?
    let isHidden: Bool
    let alpha: CGFloat
    let intensity: Int

    static func make(for cell: CalendarHeatmapCell) -> CalendarHeatmapCellStyle {
        switch cell {
        case .placeholder:
            return CalendarHeatmapCellStyle(
                title: "",
                toolTip: nil,
                isHidden: true,
                alpha: 0,
                intensity: 0
            )
        case .day(let day):
            return CalendarHeatmapCellStyle(
                title: "",
                toolTip: "\(day.dateKey) · \(formatTokens(day.totalTokens)) tokens",
                isHidden: false,
                alpha: day.isFuture ? 0.45 : 1.0,
                intensity: day.intensity
            )
        }
    }

    private static func formatTokens(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
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

    func configure(with cell: CalendarHeatmapCell) {
        let style = CalendarHeatmapCellStyle.make(for: cell)
        dayLabel.stringValue = style.title
        view.toolTip = style.toolTip
        view.isHidden = style.isHidden
        view.alphaValue = style.alpha
        cellView.heatmapBackgroundColor = CalendarHeatmapGitHubPalette.color(forIntensity: style.intensity)
        cellView.hoverText = style.toolTip
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
        }
    }

    private func emitHoverText() {
        guard let hoverText, !isHidden else { return }
        onHoverTextChange?(hoverText)
    }
}

private enum CalendarHeatmapGitHubPalette {
    private static let lightColors = [
        color(red: 235, green: 237, blue: 240),
        color(red: 155, green: 233, blue: 168),
        color(red: 64, green: 196, blue: 99),
        color(red: 48, green: 161, blue: 78),
        color(red: 33, green: 110, blue: 57),
    ]

    private static let darkColors = [
        color(red: 25, green: 30, blue: 37),
        color(red: 14, green: 68, blue: 41),
        color(red: 0, green: 109, blue: 50),
        color(red: 38, green: 166, blue: 65),
        color(red: 57, green: 211, blue: 83),
    ]

    static func color(forIntensity intensity: Int) -> NSColor {
        let clampedIntensity = min(max(intensity, 0), 4)
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return (isDark ? darkColors : lightColors)[clampedIntensity]
        }
    }

    private static func color(red: CGFloat, green: CGFloat, blue: CGFloat) -> NSColor {
        NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }
}
