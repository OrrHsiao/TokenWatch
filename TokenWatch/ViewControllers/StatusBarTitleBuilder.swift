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
        // 显式不加 reasoningTokens:Codex 的 reasoning 已计入 output(README 已说明),
        // 累加它会双计;与 ProviderStatsViewController 的展示口径保持一致。
        let total = states.values.reduce(0) { acc, state in
            guard let summary = state.stats?.byDay[todayKey] else { return acc }
            return acc
                + summary.inputTokens
                + summary.outputTokens
                + summary.cacheReadTokens
                + summary.cacheCreationTokens
        }

        return CompactNumberFormatter.format(total)
    }
}
