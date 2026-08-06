import Foundation

/// Framework-neutral color components keep the App and Widget palettes byte-for-byte aligned.
struct WidgetChartRGBA: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    /// Converts the approved eight-bit palette definition into normalized color components.
    static func bytes(_ red: Int, _ green: Int, _ blue: Int) -> WidgetChartRGBA {
        WidgetChartRGBA(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            alpha: 1
        )
    }
}

/// Shared chart invariants consumed by both AppKit/Charts and WidgetKit renderers.
enum WidgetChartVisualStyle {
    static let heatmapColumns = 22
    static let heatmapRows = 7
    static let heatmapMaximumIntensity = 4
    static let heatmapSpacing = 3.0
    static let heatmapCornerRadius = 2.0
    static let hourAxisValues = [0, 6, 12, 18, 23]
    static let lineWidth = 2.0
    static let currentPointSize = 22.0
    static let areaPeakOpacity = 0.8
    static let areaBaselineOpacity = 0.05
    static let gridOpacity = 0.16

    private static let lightPalette: [WidgetChartRGBA] = [
        .bytes(216, 222, 232), .bytes(155, 233, 168),
        .bytes(64, 196, 99), .bytes(48, 161, 78), .bytes(33, 110, 57),
    ]
    private static let darkPalette: [WidgetChartRGBA] = [
        .bytes(25, 30, 37), .bytes(14, 68, 41),
        .bytes(0, 109, 50), .bytes(38, 166, 65), .bytes(57, 211, 83),
    ]
    private static let accentedHeatmapOpacities = [0.14, 0.32, 0.50, 0.72, 1.00]
    private static let vibrantHeatmapWhiteLevels = [0.24, 0.40, 0.58, 0.76, 0.94]

    /// Returns the shared light or dark heatmap color after clamping to the five-level scale.
    static func heatmapRGBA(intensity: Int, isDark: Bool) -> WidgetChartRGBA {
        let clamped = min(max(intensity, 0), heatmapMaximumIntensity)
        return (isDark ? darkPalette : lightPalette)[clamped]
    }

    /// Returns the alpha level that preserves intensity when WidgetKit replaces RGB colors.
    static func heatmapAccentedOpacity(intensity: Int) -> Double {
        let clamped = min(max(intensity, 0), heatmapMaximumIntensity)
        return accentedHeatmapOpacities[clamped]
    }

    /// Returns the opaque grayscale level used by WidgetKit's vibrant desktop treatment.
    static func heatmapVibrantWhiteLevel(intensity: Int) -> Double {
        let clamped = min(max(intensity, 0), heatmapMaximumIntensity)
        return vibrantHeatmapWhiteLevels[clamped]
    }

    /// Fits a square tile inside the fixed 22-by-7 grid without exceeding the approved side length.
    static func heatmapTileSide(availableWidth: Double, availableHeight: Double) -> Double {
        let horizontalGaps = heatmapSpacing * Double(heatmapColumns - 1)
        let verticalGaps = heatmapSpacing * Double(heatmapRows - 1)
        let widthBound = floor((availableWidth - horizontalGaps) / Double(heatmapColumns))
        let heightBound = floor((availableHeight - verticalGaps) / Double(heatmapRows))
        return min(12, max(0, min(widthBound, heightBound)))
    }

    /// Preserves the column-major storage order shared by the popover and Widget heatmaps.
    static func heatmapIndex(column: Int, row: Int) -> Int {
        column * heatmapRows + row
    }

    /// Keeps an all-zero hourly chart drawable by providing the same nonzero Y domain in both targets.
    static func hourlyMaximumY(maxHourlyTokens: Int) -> Double {
        max(1, Double(maxHourlyTokens))
    }
}

/// Shared number formatting preserves the popover's existing truncation and axis-rounding boundaries.
enum WidgetChartNumberFormatter {
    /// Formats status-bar totals with truncated tenths and the legacy one-million suffix boundary.
    static func compact(_ value: Int) -> String {
        guard value > 0 else { return "0" }
        if value < 1_000 { return String(value) }
        let divisor = value < 1_000_000 ? 100 : 100_000
        let suffix = value < 1_000_000 ? "k" : "M"
        let tenths = value / divisor
        return "\(tenths / 10).\(tenths % 10)\(suffix)"
    }

    /// Formats dashboard and hover totals, including `0.0M` and the 100,000 switch to millions.
    static func dashboard(_ value: Int) -> String {
        guard value > 0 else { return "0.0M" }
        if value < 1_000 { return String(value) }
        let divisor = value < 100_000 ? 100 : 100_000
        let suffix = value < 100_000 ? "k" : "M"
        let tenths = value / divisor
        return "\(tenths / 10).\(tenths % 10)\(suffix)"
    }

    /// Rounds chart-axis values with a fixed POSIX locale so both targets emit identical labels.
    static func axis(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0" }
        let rounded = value.rounded()
        if rounded < 1_000 {
            return String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        }
        if rounded < 1_000_000 {
            return String(
                format: "%.0fk",
                locale: Locale(identifier: "en_US_POSIX"),
                (rounded / 1_000).rounded()
            )
        }
        return String(
            format: "%.0fM",
            locale: Locale(identifier: "en_US_POSIX"),
            (rounded / 1_000_000).rounded()
        )
    }
}
