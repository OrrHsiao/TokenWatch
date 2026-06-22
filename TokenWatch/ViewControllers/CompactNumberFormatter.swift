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

    /// 把 token 总数统一换算成百万单位
    /// - Parameter value: 整数 token 数,负数会被视为 0
    /// - Returns: 使用 `M` 作为单位的字符串,用于本年内容页
    static func formatMillions(_ value: Int) -> String {
        let safeValue = max(value, 0)
        let tenths = safeValue / 100_000
        let whole = tenths / 10
        let frac = tenths % 10
        return "\(whole).\(frac)M"
    }
}
