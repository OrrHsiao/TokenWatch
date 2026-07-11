import Foundation

/// 把整数压缩成状态栏可读的短字符串(Locale 中立、无千分位)
///
/// 规则:
/// - 0..<1_000          → "0" / "823"
/// - 1_000..<1_000_000  → "1.2k" / "99.9k" / "823.4k"  (一位小数,向下截断)
/// - >=1_000_000        → "1.2M" / "12.3M" / "123.4M"   (一位小数,向下截断)
/// - 负数视作 0(防御性输入,不抛错)
enum CompactNumberFormatter {

    /// 把 token 总数压缩成短字符串
    /// - Parameter value: 整数 token 数,负数会被视作 0
    /// - Returns: 状态栏可直接展示的字符串
    static func format(_ value: Int) -> String {
        guard value > 0 else { return "0" }

        if value < 1_000 {
            return String(value)
        }

        if value < 1_000_000 {
            // 1.0k ~ 999.9k:统一保留一位小数,向下截断到 0.1k
            let tenths = value / 100              // value / 1_000 * 10
            let whole = tenths / 10
            let frac = tenths % 10
            return "\(whole).\(frac)k"
        }

        // 1.0M+:保留一位小数,向下截断到 0.1M
        let tenths = value / 100_000             // value / 1_000_000 * 10
        let whole = tenths / 10
        let frac = tenths % 10
        return "\(whole).\(frac)M"
    }

    /// 按 Dashboard 约定压缩 token 数；零保留 `0.0M`，正数绝不显示为零。
    static func formatMillions(_ value: Int) -> String {
        formatDashboardTokens(value)
    }

    /// 按 Dashboard hover 约定压缩 token 数，与 `formatMillions` 使用相同边界。
    static func formatHoverTokens(_ value: Int) -> String {
        formatDashboardTokens(value)
    }

    private static func formatDashboardTokens(_ value: Int) -> String {
        guard value > 0 else { return "0.0M" }

        if value < 1_000 {
            return String(value)
        }

        if value < 100_000 {
            let tenths = value / 100
            return "\(tenths / 10).\(tenths % 10)k"
        }

        let tenths = value / 100_000
        return "\(tenths / 10).\(tenths % 10)M"
    }
}
