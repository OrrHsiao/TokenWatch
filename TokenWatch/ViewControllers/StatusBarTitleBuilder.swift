import Foundation

/// 状态栏文本生成器
///
/// 把 ViewModel 多 provider 的状态 + 今日 key 折成一个短文本,优先级:
/// 1. 全部 provider 未授权 → "—"
/// 2. 任一 provider 加载中,且没有任何 provider 有 stats → "…"
/// 3. 否则:跨 provider 累加 byDay[today] 的 token,经 CompactNumberFormatter 缩写
///
/// 设计原因:抽成纯函数后无需 NSStatusItem 即可单测,跨日切换、首启 loading、
/// 部分授权等组合都能定向覆盖。
enum StatusBarTitleBuilder {

    /// 生成状态栏文本
    /// - Parameters:
    ///   - states: ViewModel 当前所有 provider 的状态快照
    ///   - todayKey: 今日的 byDay key,格式 "yyyy-MM-dd"(与 UsageAggregator 一致)
    /// - Returns: 状态栏可直接展示的字符串
    static func build(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        todayKey: String
    ) -> String {
        guard !states.isEmpty else { return "—" }

        // 1. 全部未授权
        let allUnauthorized = states.values.allSatisfy { $0.needsAuthorization }
        if allUnauthorized { return "—" }

        // 2. 首启 loading + 全部无数据
        let anyLoading = states.values.contains(where: { $0.isLoading })
        let allEmpty = states.values.allSatisfy { $0.stats == nil }
        if anyLoading && allEmpty { return "…" }

        // 3. 累加每个 provider 今日的 token
        return CompactNumberFormatter.format(totalTokens(states: states, todayKey: todayKey))
    }

    /// 跨 provider 累加 byDay[todayKey] 的 token 总数(纯累加,不考虑 loading/未授权)
    ///
    /// 显式不加 reasoningTokens:Codex 的 reasoning 已计入 output(README 已说明),
    /// 累加它会双计;与 ProviderStatsViewController 的展示口径保持一致。
    /// - Parameters:
    ///   - states: ViewModel 当前所有 provider 的状态快照
    ///   - todayKey: 今日的 byDay key,格式 "yyyy-MM-dd"
    /// - Returns: 当日跨 provider 的 token 累加值;若任一 provider 缺失今日 bucket 视作 0
    static func totalTokens(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        todayKey: String
    ) -> Int {
        states.values.reduce(0) { acc, state in
            guard let summary = state.stats?.byDay[todayKey] else { return acc }
            return acc
                + summary.inputTokens
                + summary.outputTokens
                + summary.cacheReadTokens
                + summary.cacheCreationTokens
        }
    }

    /// 根据当日 token 总数选择状态栏图标
    ///
    /// 使用 SF Symbol `gauge.with.dots.needle.*percent` 系列分 5 档,区间左闭右开。
    /// 0~0.1M 归为 0percent —— 一天还没真正开始用,跳到 33% 会误导;
    /// 0.1M 起进入 33percent,后续按 3.3M / 5M / 6.7M 升档,≥6.7M 打满。
    /// - Parameter total: 当日 token 累加值
    /// - Returns: SF Symbol 名,直接传给 `NSImage(systemSymbolName:)`
    static func symbolName(forTotalTokens total: Int) -> String {
        switch total {
        case ..<100_000: return "gauge.with.dots.needle.0percent"
        case ..<3_300_000: return "gauge.with.dots.needle.33percent"
        case ..<5_000_000: return "gauge.with.dots.needle.50percent"
        case ..<6_700_000: return "gauge.with.dots.needle.67percent"
        default: return "gauge.with.dots.needle.100percent"
        }
    }
}
