/// Framework-neutral interpolation semantics force every UI target to map the same approved case.
enum WidgetLineInterpolationStyle: String, Equatable, Sendable {
    case catmullRom
}

/// Shared rendering names remain independent of Swift Charts so the Widget target can reuse them.
enum WidgetChartRendering {
    static let lineInterpolationStyle: WidgetLineInterpolationStyle = .catmullRom
    static let lineInterpolationMethodName = lineInterpolationStyle.rawValue
}
