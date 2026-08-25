import SwiftUI

struct WidgetChartHeader: View {
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

struct WidgetMetricItem {
    let symbolName: String
    let text: String
}

struct WidgetMetricStrip: View {
    let items: [WidgetMetricItem]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                if index > 0 {
                    Divider()
                        .frame(height: 10)
                }
                HStack(spacing: 3) {
                    Image(systemName: items[index].symbolName)
                        .accessibilityHidden(true)
                    Text(items[index].text)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
