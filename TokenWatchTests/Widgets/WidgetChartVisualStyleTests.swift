import Testing
@testable import TokenWatch

@Suite("Widget chart visual style")
struct WidgetChartVisualStyleTests {
    @Test("heatmap geometry and hourly chart constants match the popover")
    func constantsMatchPopover() {
        #expect(WidgetChartVisualStyle.heatmapColumns == 22)
        #expect(WidgetChartVisualStyle.heatmapRows == 7)
        #expect(WidgetChartVisualStyle.heatmapMaximumIntensity == 4)
        #expect(WidgetChartVisualStyle.heatmapSpacing == 3)
        #expect(WidgetChartVisualStyle.heatmapCornerRadius == 2)
        #expect(WidgetChartVisualStyle.hourAxisValues == [0, 6, 12, 18, 23])
        #expect(WidgetChartVisualStyle.lineWidth == 2)
        #expect(WidgetChartVisualStyle.currentPointSize == 22)
        #expect(WidgetChartVisualStyle.areaPeakOpacity == 0.8)
        #expect(WidgetChartVisualStyle.areaBaselineOpacity == 0.05)
        #expect(WidgetChartVisualStyle.gridOpacity == 0.16)
        #expect(WidgetChartRendering.lineInterpolationStyle == .catmullRom)
        #expect(WidgetChartRendering.lineInterpolationMethodName == "catmullRom")
    }

    @Test("palette values exactly match light and dark popover colors")
    func paletteMatchesPopover() {
        #expect(WidgetChartVisualStyle.heatmapRGBA(intensity: 0, isDark: false) == .bytes(216, 222, 232))
        #expect(WidgetChartVisualStyle.heatmapRGBA(intensity: 4, isDark: false) == .bytes(33, 110, 57))
        #expect(WidgetChartVisualStyle.heatmapRGBA(intensity: 0, isDark: true) == .bytes(25, 30, 37))
        #expect(WidgetChartVisualStyle.heatmapRGBA(intensity: 4, isDark: true) == .bytes(57, 211, 83))
        #expect(WidgetChartVisualStyle.heatmapRGBA(intensity: -1, isDark: false) == .bytes(216, 222, 232))
        #expect(WidgetChartVisualStyle.heatmapRGBA(intensity: 9, isDark: true) == .bytes(57, 211, 83))
    }

    @Test("system-rendered heatmap keeps all five intensity levels")
    func systemRenderedHeatmapKeepsIntensityLevels() {
        #expect(
            (0...4).map(WidgetChartVisualStyle.heatmapAccentedOpacity)
                == [0.14, 0.32, 0.50, 0.72, 1.00]
        )
        #expect(
            (0...4).map(WidgetChartVisualStyle.heatmapVibrantWhiteLevel)
                == [0.24, 0.40, 0.58, 0.76, 0.94]
        )
        #expect(WidgetChartVisualStyle.heatmapAccentedOpacity(intensity: -1) == 0.14)
        #expect(WidgetChartVisualStyle.heatmapAccentedOpacity(intensity: 9) == 1.00)
        #expect(WidgetChartVisualStyle.heatmapVibrantWhiteLevel(intensity: -1) == 0.24)
        #expect(WidgetChartVisualStyle.heatmapVibrantWhiteLevel(intensity: 9) == 0.94)
    }

    @Test("medium heatmap and zero chart calculations are stable")
    func layoutAndZeroScaleAreStable() {
        #expect(WidgetChartVisualStyle.heatmapTileSide(availableWidth: 327, availableHeight: 102) == 12)
        #expect(WidgetChartVisualStyle.heatmapIndex(column: 0, row: 0) == 0)
        #expect(WidgetChartVisualStyle.heatmapIndex(column: 21, row: 6) == 153)
        #expect(WidgetChartVisualStyle.hourlyMaximumY(maxHourlyTokens: 0) == 1)
    }

    @Test("shared formatter matches existing widget and axis boundaries")
    func formatterMatchesExistingBoundaries() {
        #expect(WidgetChartNumberFormatter.compact(99_999) == "99.9k")
        #expect(WidgetChartNumberFormatter.compact(1_234_567) == "1.2M")
        #expect(WidgetChartNumberFormatter.dashboard(0) == "0.0M")
        #expect(WidgetChartNumberFormatter.axis(0) == "0")
        #expect(WidgetChartNumberFormatter.axis(1_500_000) == "2M")
    }
}
