import Foundation

/// 近时 Token 燃烧速率与格式化计算器
///
/// 核心职责：
/// 1. 计算滑动时间窗口（默认 15 分钟）内的 Token 消耗速率（tok/s）。
/// 2. 判定空闲状态（Idle）：若最新一条记录距当前时间超过 15 分钟，说明当前无活跃消耗，判定为 0。
/// 3. 提供状态栏弹窗与仪表盘统一的速率格式化（如 "0 /s", "0.5 /s", "45 /s", "1.2k /s"）。
enum TokenBurnRateCalculator {

    /// 默认滑动窗口：15 分钟（平滑单次请求的波动突刺，同时保持交互敏锐度）
    static let defaultWindowSeconds: TimeInterval = 15 * 60
    /// 空闲判定阈值：若最新一条记录距当前时间超过 15 分钟，视为空闲
    static let idleThresholdSeconds: TimeInterval = 15 * 60

    /// 计算多 Provider 状态下的整体近时燃烧速率（Token/s）
    /// - Parameters:
    ///   - states: ViewModel 当前所有 Provider 的状态快照
    ///   - now: 当前时刻
    ///   - windowSeconds: 滑动窗口长度（秒），默认 15 分钟
    /// - Returns: 每秒消耗的 Token 数（tok/s）
    static func calculate(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        now: Date,
        windowSeconds: TimeInterval = defaultWindowSeconds
    ) -> Double {
        let entries = states.values.compactMap(\.entries).flatMap { $0 }
        return calculate(entries: entries, now: now, windowSeconds: windowSeconds)
    }

    /// 计算指定用量条目列表在给定时刻的近时燃烧速率（Token/s）
    /// - Parameters:
    ///   - entries: 已去重的用量条目列表
    ///   - now: 当前时刻
    ///   - windowSeconds: 滑动窗口长度（秒），默认 15 分钟
    /// - Returns: 每秒消耗的 Token 数（tok/s）
    static func calculate(
        entries: [ParsedUsageEntry],
        now: Date,
        windowSeconds: TimeInterval = defaultWindowSeconds
    ) -> Double {
        guard !entries.isEmpty, windowSeconds > 0 else { return 0.0 }

        // 1. 查找最新一条有效记录的时间戳
        var latestTimestamp: Date?
        for entry in entries {
            guard let ts = entry.timestamp else { continue }
            if latestTimestamp == nil || ts > latestTimestamp! {
                latestTimestamp = ts
            }
        }

        guard let latest = latestTimestamp else { return 0.0 }

        // 2. 空闲判定：若最新记录距 now 已超过 idleThresholdSeconds，直接归零
        if now.timeIntervalSince(latest) > idleThresholdSeconds {
            return 0.0
        }

        // 3. 统计落在 [now - windowSeconds, now] 内的 Token 总量
        let windowStart = now.addingTimeInterval(-windowSeconds)
        var windowTokens = 0
        for entry in entries {
            guard let ts = entry.timestamp, ts >= windowStart, ts <= now else { continue }
            windowTokens = windowTokens.addingSaturated(entry.usage.aggregateTotalTokens)
        }

        guard windowTokens > 0 else { return 0.0 }

        // 4. 计算速率 (tok/s)
        return Double(windowTokens) / windowSeconds
    }

    /// 把每秒速率格式化为紧凑字符串（例如 "0 /s", "0.5 /s", "45 /s", "1.2k /s"）
    /// - Parameter tokensPerSecond: 每秒 Token 数
    /// - Returns: 紧凑格式化文本
    static func formatRate(_ tokensPerSecond: Double) -> String {
        guard tokensPerSecond.isFinite, tokensPerSecond > 0 else {
            return "0 /s"
        }
        if tokensPerSecond < 10 {
            let roundedOneDecimal = (tokensPerSecond * 10).rounded() / 10
            if roundedOneDecimal < 0.1 {
                return "<0.1 /s"
            }
            if roundedOneDecimal.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(roundedOneDecimal)) /s"
            }
            return "\(roundedOneDecimal) /s"
        }
        let rounded = Int(tokensPerSecond.rounded())
        if rounded < 1_000 {
            return "\(rounded) /s"
        }
        return "\(CompactNumberFormatter.format(rounded)) /s"
    }

    /// 生成状态栏弹窗顶部描述行组合文案
    /// - Parameters:
    ///   - baseText: 今日 Token 基础用量文案
    ///   - todayTokens: 今日 Token 总量
    ///   - burnRate: 当前计算出的燃烧速率
    ///   - language: 当前应用语言
    /// - Returns: 组合后的描述文案
    static func descriptionText(
        baseText: String,
        todayTokens: Int,
        burnRate: Double,
        language: AppLanguage
    ) -> String {
        guard todayTokens > 0 else { return baseText }
        let isChinese = language.baseLanguageCode == "zh"
        if burnRate > 0 {
            let rateString = formatRate(burnRate)
            return "\(baseText) · 🔥 \(rateString)"
        } else {
            let idleText = isChinese ? "空闲" : "Idle"
            return "\(baseText) · \(idleText)"
        }
    }
}
