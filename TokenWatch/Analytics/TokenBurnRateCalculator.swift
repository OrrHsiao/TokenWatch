import Foundation

/// 近时 Token 燃烧速率与成本消耗计算器
///
/// 对齐 ccusage 核心指标设计：
/// 1. 净活跃指标：以 `inputTokens + outputTokens` 为基准计算指示器速率（tok/s），剥离 Prompt Cache 读取对指示器的虚假膨胀。
/// 2. 动态区间平滑：避免固定除以 900 秒导致的冷启动严重低估，使用 `effectiveDuration = min(windowSeconds, max(30.0, activeSpan))`。
/// 3. 成本燃烧率：基于 `UsageCostResolver` 聚合计算当前消耗的每小时成本开销（USD/hr）。
/// 4. 三级活跃阈值：对齐 ccusage 阈值（Normal: <2,000 tok/min 即 <33.3 tok/s，Moderate: 2,000~5,000 tok/min 即 33.3~83.3 tok/s，High: >5,000 tok/min 即 >83.3 tok/s）。
enum TokenBurnRateCalculator {

    /// 燃烧速率综合结果模型
    struct TokenBurnRate: Equatable, Sendable {
        /// 净活跃每秒 Token 消耗速率（tok/s，剔除 CacheRead，对应 ccusage tokens_per_minute_for_indicator）
        let activeTokensPerSecond: Double
        /// 全量每秒 Token 消耗速率（tok/s，含全部 Token，对应 ccusage tokens_per_minute）
        let totalTokensPerSecond: Double
        /// 成本燃烧率（USD/小时）
        let costPerHour: Double
        /// 活跃状态等级
        let level: Level

        enum Level: String, Equatable, Sendable {
            case idle
            case normal    // < 2,000 tok/min (< 33.3 tok/s)
            case moderate  // 2,000 ~ 5,000 tok/min (33.3 ~ 83.3 tok/s)
            case high      // > 5,000 tok/min (> 83.3 tok/s)
        }

        static let idle = TokenBurnRate(
            activeTokensPerSecond: 0.0,
            totalTokensPerSecond: 0.0,
            costPerHour: 0.0,
            level: .idle
        )
    }

    /// 默认滑动窗口：15 分钟（平滑单次请求的波动突刺，同时保持交互敏锐度）
    static let defaultWindowSeconds: TimeInterval = 15 * 60
    /// 空闲判定阈值：若最新一条记录距当前时间超过 15 分钟，视为空闲
    static let idleThresholdSeconds: TimeInterval = 15 * 60
    /// 最小有效时间跨度截断（秒），防止极短时间内的单个请求造成除以极小数值的过激突刺
    static let minimumActiveDurationSeconds: TimeInterval = 30.0

    /// ccusage 活跃指示器阈值（单位：Tokens / min）
    static let normalThresholdTokPerMin: Double = 2_000.0
    static let moderateThresholdTokPerMin: Double = 5_000.0

    /// 计算多 Provider 状态下的整体近时燃烧速率模型
    /// - Parameters:
    ///   - states: ViewModel 当前所有 Provider 的状态快照
    ///   - now: 当前时刻
    ///   - windowSeconds: 滑动窗口长度（秒），默认 15 分钟
    ///   - costResolver: 成本解析器实例，用于计算各条目的 USD 消耗
    /// - Returns: 包含净活跃速率、全量速率、成本燃烧率与状态等级的 `TokenBurnRate` 模型
    static func calculateRate(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        now: Date,
        windowSeconds: TimeInterval = defaultWindowSeconds,
        costResolver: UsageCostResolver = UsageCostResolver()
    ) -> TokenBurnRate {
        let entries = states.values.compactMap(\.entries).flatMap { $0 }
        return calculateRate(entries: entries, now: now, windowSeconds: windowSeconds, costResolver: costResolver)
    }

    /// 计算指定用量条目列表在给定时刻的近时燃烧速率模型
    /// - Parameters:
    ///   - entries: 已去重的用量条目列表
    ///   - now: 当前时刻
    ///   - windowSeconds: 滑动窗口长度（秒），默认 15 分钟
    ///   - costResolver: 成本解析器实例，用于计算各条目的 USD 消耗
    /// - Returns: 包含净活跃速率、全量速率、成本燃烧率与状态等级的 `TokenBurnRate` 模型
    static func calculateRate(
        entries: [ParsedUsageEntry],
        now: Date,
        windowSeconds: TimeInterval = defaultWindowSeconds,
        costResolver: UsageCostResolver = UsageCostResolver()
    ) -> TokenBurnRate {
        guard !entries.isEmpty, windowSeconds > 0 else { return .idle }

        // 1. 查找最新一条有效记录的时间戳
        var latestTimestamp: Date?
        for entry in entries {
            guard let ts = entry.timestamp else { continue }
            if latestTimestamp == nil || ts > latestTimestamp! {
                latestTimestamp = ts
            }
        }

        guard let latest = latestTimestamp else { return .idle }

        // 2. 空闲判定：若最新记录距 now 已超过 idleThresholdSeconds，直接归零
        if now.timeIntervalSince(latest) > idleThresholdSeconds {
            return .idle
        }

        // 3. 统计落在 [now - windowSeconds, now] 内的有效记录
        let windowStart = now.addingTimeInterval(-windowSeconds)
        var windowEntries: [ParsedUsageEntry] = []
        var earliestInWindow: Date?

        for entry in entries {
            guard let ts = entry.timestamp, ts >= windowStart, ts <= now else { continue }
            windowEntries.append(entry)
            if earliestInWindow == nil || ts < earliestInWindow! {
                earliestInWindow = ts
            }
        }

        guard !windowEntries.isEmpty, let earliest = earliestInWindow else { return .idle }

        // 4. 动态计算有效活跃时长：
        // 采用 min(windowSeconds, max(30.0, activeSpan))：
        // - 既解决刚使用时直接除以 900 秒造成的低估 30 倍问题；
        // - 又通过 30 秒保底，防止 1 秒内单条记录除以过小分母引起的严重突刺。
        let activeSpan = now.timeIntervalSince(earliest)
        let effectiveDuration = min(windowSeconds, max(minimumActiveDurationSeconds, activeSpan))

        // 5. 统计净活跃 Token (input + output)、全量 Token 以及成本
        var activeTokens = 0
        var totalTokens = 0
        var totalCostUSD: Double = 0.0

        for entry in windowEntries {
            let nonCache = entry.usage.inputTokens.addingSaturated(entry.usage.outputTokens)
            activeTokens = activeTokens.addingSaturated(nonCache)
            totalTokens = totalTokens.addingSaturated(entry.usage.aggregateTotalTokens)
            totalCostUSD += costResolver.resolvedCost(for: entry)
        }

        guard activeTokens > 0 || totalTokens > 0 else { return .idle }

        let activeTokensPerSecond = Double(activeTokens) / effectiveDuration
        let totalTokensPerSecond = Double(totalTokens) / effectiveDuration
        let costPerHour = (totalCostUSD / effectiveDuration) * 3600.0

        // 6. 对齐 ccusage 指示器等级判定（按 tok/min 判定）
        let activeTokPerMin = activeTokensPerSecond * 60.0
        let level: TokenBurnRate.Level
        if activeTokPerMin < normalThresholdTokPerMin {
            level = .normal
        } else if activeTokPerMin < moderateThresholdTokPerMin {
            level = .moderate
        } else {
            level = .high
        }

        return TokenBurnRate(
            activeTokensPerSecond: activeTokensPerSecond,
            totalTokensPerSecond: totalTokensPerSecond,
            costPerHour: costPerHour,
            level: level
        )
    }

    /// 计算多 Provider 状态下的整体近时净活跃燃烧速率（Token/s）
    /// - Parameters:
    ///   - states: ViewModel 当前所有 Provider 的状态快照
    ///   - now: 当前时刻
    ///   - windowSeconds: 滑动窗口长度（秒），默认 15 分钟
    /// - Returns: 每秒净活跃消耗的 Token 数（tok/s）
    static func calculate(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        now: Date,
        windowSeconds: TimeInterval = defaultWindowSeconds
    ) -> Double {
        calculateRate(states: states, now: now, windowSeconds: windowSeconds).activeTokensPerSecond
    }

    /// 计算指定用量条目列表在给定时刻的近时净活跃燃烧速率（Token/s）
    /// - Parameters:
    ///   - entries: 已去重的用量条目列表
    ///   - now: 当前时刻
    ///   - windowSeconds: 滑动窗口长度（秒），默认 15 分钟
    /// - Returns: 每秒净活跃消耗的 Token 数（tok/s）
    static func calculate(
        entries: [ParsedUsageEntry],
        now: Date,
        windowSeconds: TimeInterval = defaultWindowSeconds
    ) -> Double {
        calculateRate(entries: entries, now: now, windowSeconds: windowSeconds).activeTokensPerSecond
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

    /// 格式化每小时成本消耗（USD/hr）
    /// - Parameter costPerHour: 每小时美元金额
    /// - Returns: 如 "$0.00/hr", "<$0.01/hr", "$0.15/hr", "$12.45/hr"
    static func formatCostPerHour(_ costPerHour: Double) -> String {
        guard costPerHour.isFinite, costPerHour > 0 else {
            return "$0.00/hr"
        }
        if costPerHour < 0.01 {
            return "<$0.01/hr"
        }
        if costPerHour >= 100 {
            return String(format: "$%.0f/hr", costPerHour)
        }
        return String(format: "$%.2f/hr", costPerHour)
    }

    /// 生成状态栏弹窗顶部描述行组合文案
    /// - Parameters:
    ///   - baseText: 今日 Token 基础用量文案
    ///   - todayTokens: 今日 Token 总量
    ///   - burnRate: 当前计算出的燃烧速率
    ///   - costPerHour: 每小时成本消耗
    ///   - language: 当前应用语言
    /// - Returns: 组合后的描述文案
    static func descriptionText(
        baseText: String,
        todayTokens: Int,
        burnRate: Double,
        costPerHour: Double = 0.0,
        language: AppLanguage
    ) -> String {
        guard todayTokens > 0 else { return baseText }
        let isChinese = language.baseLanguageCode == "zh"
        if burnRate > 0 {
            let rateString = formatRate(burnRate)
            if costPerHour >= 0.01 {
                let costString = formatCostPerHour(costPerHour)
                return "\(baseText) · 🔥 \(rateString) (\(costString))"
            }
            return "\(baseText) · 🔥 \(rateString)"
        } else {
            let idleText = isChinese ? "空闲" : "Idle"
            return "\(baseText) · \(idleText)"
        }
    }

    /// 生成状态栏弹窗顶部描述行组合文案（直接接收 TokenBurnRate 模型）
    /// - Parameters:
    ///   - baseText: 今日 Token 基础用量文案
    ///   - todayTokens: 今日 Token 总量
    ///   - rate: 当前计算出的综合燃烧速率模型
    ///   - language: 当前应用语言
    /// - Returns: 组合后的描述文案
    static func descriptionText(
        baseText: String,
        todayTokens: Int,
        rate: TokenBurnRate,
        language: AppLanguage
    ) -> String {
        descriptionText(
            baseText: baseText,
            todayTokens: todayTokens,
            burnRate: rate.activeTokensPerSecond,
            costPerHour: rate.costPerHour,
            language: language
        )
    }
}
