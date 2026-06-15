import Foundation

/// ISO 8601 日期解析辅助工具
enum ISO8601DateFormatterHelper {
    /// 兼容带/不带毫秒的 ISO 8601 格式
    static func parse(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
