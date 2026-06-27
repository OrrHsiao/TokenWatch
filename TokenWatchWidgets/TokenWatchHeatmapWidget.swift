import SwiftUI
import WidgetKit

struct TokenWatchHeatmapWidget: Widget {
    private let kind = "TokenWatchHeatmapWidget"
    private let galleryLanguageIdentifier = TokenWatchWidgetCopy.preferredLanguageIdentifier()

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TokenWatchWidgetTimelineProvider()) { entry in
            TokenWatchHeatmapWidgetView(snapshot: entry.snapshot)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(TokenWatchWidgetCopy.text(.tokenHeatmapDisplayName, languageIdentifier: galleryLanguageIdentifier))
        .description(TokenWatchWidgetCopy.text(.tokenHeatmapDescription, languageIdentifier: galleryLanguageIdentifier))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct TokenWatchHeatmapWidgetView: View {
    let snapshot: TokenWatchWidgetSnapshot

    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.colorScheme) private var colorScheme

    private var layout: TokenWatchHeatmapWidgetLayout {
        TokenWatchHeatmapWidgetLayout.layout(for: widgetFamily.tokenWatchDisplayFamily)
    }

    var body: some View {
        Group {
            switch snapshot.status {
            case .ready:
                content
            case .needsAuthorization:
                statusView(.openAppToAuthorize)
            case .empty:
                statusView(.noTokenData)
            case .waitingForRefresh:
                statusView(.waitingForRefresh)
            }
        }
        .padding(widgetPadding)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            header
            if layout != .compact {
                summaryRow
            }
            heatmapGrid
            if layout == .expanded {
                legend
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.heatmap.title)
                    .font(.system(size: layout == .compact ? 12 : 13, weight: .semibold))
                    .lineLimit(1)
                Text("\(TokenWatchWidgetCopy.text(.today, languageIdentifier: snapshot.languageIdentifier)) \(TokenWatchWidgetCompactNumberFormatter.format(snapshot.heatmap.summary.todayTokens))")
                    .font(.system(size: layout == .compact ? 18 : 20, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if layout != .compact {
                Text(updatedText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 8) {
            summaryItem(.month, snapshot.heatmap.summary.monthTokens)
            summaryItem(.week, snapshot.heatmap.summary.weekTokens)
            summaryItem(.dailyAverage, snapshot.heatmap.summary.averageDailyTokens)
        }
    }

    private func summaryItem(_ key: TokenWatchWidgetCopyKey, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(TokenWatchWidgetCopy.text(key, languageIdentifier: snapshot.languageIdentifier))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(TokenWatchWidgetCompactNumberFormatter.format(value))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heatmapGrid: some View {
        let rows = Array(repeating: GridItem(.fixed(tileSize), spacing: tileSpacing), count: 7)
        return LazyHGrid(rows: rows, spacing: tileSpacing) {
            ForEach(snapshot.heatmap.cells) { cell in
                RoundedRectangle(cornerRadius: max(1.5, tileSize * 0.18), style: .continuous)
                    .fill(color(for: cell))
                    .overlay {
                        if cell.isToday {
                            RoundedRectangle(cornerRadius: max(1.5, tileSize * 0.18), style: .continuous)
                                .stroke(Color.primary.opacity(0.45), lineWidth: 1)
                        }
                    }
                    .opacity(cell.isFuture ? 0.45 : 1)
                    .frame(width: tileSize, height: tileSize)
                    .accessibilityLabel(cell.dateKey ?? "")
                    .accessibilityValue(TokenWatchWidgetCompactNumberFormatter.format(cell.totalTokens))
                    .accessibilityHidden(cell.kind != .day)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Spacer()
            ForEach(0...4, id: \.self) { intensity in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(paletteColor(for: intensity))
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityHidden(true)
    }

    private func statusView(_ key: TokenWatchWidgetCopyKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TokenWatchWidgetCopy.text(.tokenHeatmapDisplayName, languageIdentifier: snapshot.languageIdentifier))
                .font(.system(size: 13, weight: .semibold))
            Text(TokenWatchWidgetCopy.text(key, languageIdentifier: snapshot.languageIdentifier))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            heatmapGrid
                .opacity(0.35)
        }
    }

    private func color(for cell: TokenWatchWidgetHeatmapCell) -> Color {
        guard cell.kind == .day else { return .clear }
        return paletteColor(for: cell.intensity)
    }

    private func paletteColor(for intensity: Int) -> Color {
        let clamped = min(max(intensity, 0), 4)
        let light: [(Double, Double, Double)] = [
            (235, 237, 240),
            (155, 233, 168),
            (64, 196, 99),
            (48, 161, 78),
            (33, 110, 57),
        ]
        let dark: [(Double, Double, Double)] = [
            (25, 30, 37),
            (14, 68, 41),
            (0, 109, 50),
            (38, 166, 65),
            (57, 211, 83),
        ]
        let value = (colorScheme == .dark ? dark : light)[clamped]
        return Color(red: value.0 / 255, green: value.1 / 255, blue: value.2 / 255)
    }

    private var updatedText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(TokenWatchWidgetCopy.text(.updated, languageIdentifier: snapshot.languageIdentifier)) \(formatter.string(from: snapshot.generatedAt))"
    }

    private var widgetPadding: CGFloat {
        switch layout {
        case .compact:
            return 12
        case .summary:
            return 14
        case .expanded:
            return 16
        }
    }

    private var verticalSpacing: CGFloat {
        switch layout {
        case .compact:
            return 8
        case .summary:
            return 10
        case .expanded:
            return 12
        }
    }

    private var tileSize: CGFloat {
        switch layout {
        case .compact:
            return 4.6
        case .summary:
            return 8.4
        case .expanded:
            return 10.8
        }
    }

    private var tileSpacing: CGFloat {
        switch layout {
        case .compact:
            return 1.2
        case .summary:
            return 2.4
        case .expanded:
            return 3
        }
    }
}

extension WidgetFamily {
    var tokenWatchDisplayFamily: TokenWatchWidgetDisplayFamily {
        switch self {
        case .systemSmall:
            return .small
        case .systemLarge:
            return .large
        case .systemMedium:
            return .medium
        default:
            return .medium
        }
    }
}
