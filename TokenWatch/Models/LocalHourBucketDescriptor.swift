import Foundation

/// 本地自然日中的一个墙上小时；不持有绝对 Date，避免 DST 跳时或回拨改变桶数量。
struct LocalHourBucketDescriptor: Sendable, Equatable, Identifiable {
    let hour: Int
    let key: String

    var id: String { key }

    /// 直接以本地年月日和 0..<24 生成固定 24 个墙上小时。
    static func buckets(
        forDayContaining date: Date,
        calendar: Calendar
    ) -> [LocalHourBucketDescriptor] {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return []
        }

        return (0..<24).map { hour in
            LocalHourBucketDescriptor(
                hour: hour,
                key: String(format: "%04d-%02d-%02dT%02d", year, month, day, hour)
            )
        }
    }

    /// 把真实时间映射为与墙上小时列表相同格式的本地 key。
    static func key(for date: Date?, calendar: Calendar) -> String {
        guard let date else { return "unknown" }
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let hour = components.hour else {
            return "unknown"
        }
        return String(format: "%04d-%02d-%02dT%02d", year, month, day, hour)
    }

    /// 返回当前 App 语言下的小时标签。
    func label(language: AppLanguage) -> String {
        switch language {
        case .zhHans, .zhHant:
            return "\(hour)时"
        case .ja:
            return "\(hour)時"
        case .ko:
            return "\(hour)시"
        case .en, .es, .de, .fr, .ptBR, .it, .nl, .pl:
            return "\(hour)"
        }
    }
}
