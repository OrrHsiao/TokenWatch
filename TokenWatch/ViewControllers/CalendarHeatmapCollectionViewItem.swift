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
                title: "\(day.dayNumber)",
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

    private let dayLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let cellView = CalendarHeatmapCellView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        cellView.wantsLayer = true
        cellView.layer?.cornerRadius = 5
        cellView.layer?.masksToBounds = true
        view = cellView

        dayLabel.translatesAutoresizingMaskIntoConstraints = false
        dayLabel.alignment = .center
        dayLabel.font = .systemFont(ofSize: 11, weight: .medium)
        dayLabel.textColor = .labelColor

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
        cellView.heatmapBackgroundColor = backgroundColor(forIntensity: style.intensity)
    }

    private func backgroundColor(forIntensity intensity: Int) -> NSColor {
        switch intensity {
        case 1:
            return NSColor.systemGreen.withAlphaComponent(0.28)
        case 2:
            return NSColor.systemGreen.withAlphaComponent(0.46)
        case 3:
            return NSColor.systemGreen.withAlphaComponent(0.68)
        case 4:
            return NSColor.systemGreen.withAlphaComponent(0.92)
        default:
            return NSColor.separatorColor.withAlphaComponent(0.35)
        }
    }

    private var cellView: CalendarHeatmapCellView {
        guard let cellView = view as? CalendarHeatmapCellView else {
            preconditionFailure("CalendarHeatmapCollectionViewItem.view must be CalendarHeatmapCellView")
        }
        return cellView
    }
}

private final class CalendarHeatmapCellView: NSView {
    var heatmapBackgroundColor: NSColor = .clear {
        didSet {
            applyHeatmapBackgroundColor()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyHeatmapBackgroundColor()
    }

    private func applyHeatmapBackgroundColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = heatmapBackgroundColor.cgColor
        }
    }
}
