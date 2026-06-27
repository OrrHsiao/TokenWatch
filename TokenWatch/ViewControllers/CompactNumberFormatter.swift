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
        TokenWatchWidgetCompactNumberFormatter.format(value)
    }

    /// 把 token 总数统一换算成百万单位
    /// - Parameter value: 整数 token 数,负数会被视为 0
    /// - Returns: 使用 `M` 作为单位的字符串,用于最近 12 个月内容页
    static func formatMillions(_ value: Int) -> String {
        TokenWatchWidgetCompactNumberFormatter.formatMillions(value)
    }

    /// 把 hover 文案里的 token 总数压缩成 `M` 单位,0 保持 `M`,不足 0.1M 且非 0 时使用 `k`。
    /// - Parameter value: 整数 token 数,负数会被视为 0
    /// - Returns: 用于 hover label 的短字符串
    static func formatHoverTokens(_ value: Int) -> String {
        TokenWatchWidgetCompactNumberFormatter.formatHoverTokens(value)
    }
}
