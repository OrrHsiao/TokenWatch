import Foundation

/// 编译时内置的模型定价表
/// 数据来源：LiteLLM model_prices_and_context_window.json
/// Mac App Store 分发不允许运行时网络获取定价，因此必须硬编码
/// 参考 ccusage 的 PricingMap 设计，支持精确匹配和前缀模糊匹配
struct PricingTable: Sendable {

    /// 内置定价表（每百万 token USD）
    /// key 为标准化模型 ID（小写+连字符）
    static let prices: [String: ModelPricing] = [
        // MARK: - Claude 系列

        // Opus 4 系列
        "claude-opus-4": ModelPricing(
            modelID: "claude-opus-4",
            displayName: "Claude Opus 4",
            inputPrice: 15.0, outputPrice: 75.0,
            cacheReadPrice: 1.50, cacheWritePrice: 18.75
        ),
        "claude-opus-4-1": ModelPricing(
            modelID: "claude-opus-4-1",
            displayName: "Claude Opus 4.1",
            inputPrice: 15.0, outputPrice: 75.0,
            cacheReadPrice: 1.50, cacheWritePrice: 18.75
        ),
        "claude-opus-4-5": ModelPricing(
            modelID: "claude-opus-4-5",
            displayName: "Claude Opus 4.5",
            inputPrice: 5.0, outputPrice: 25.0,
            cacheReadPrice: 0.50, cacheWritePrice: 6.25
        ),

        // Opus 4.6 / 4.7 / 4.8:与 4.5 同价,但带 fast_multiplier
        // (LiteLLM `provider_specific_entry.fast`,4.6/4.7=6.0,4.8=2.0)
        // 这是当前 PricingTable 中唯一会触发 fastMultiplier 的模型组
        "claude-opus-4-6": ModelPricing(
            modelID: "claude-opus-4-6",
            displayName: "Claude Opus 4.6",
            inputPrice: 5.0, outputPrice: 25.0,
            cacheReadPrice: 0.50, cacheWritePrice: 6.25,
            fastMultiplier: 6.0
        ),
        "claude-opus-4-7": ModelPricing(
            modelID: "claude-opus-4-7",
            displayName: "Claude Opus 4.7",
            inputPrice: 5.0, outputPrice: 25.0,
            cacheReadPrice: 0.50, cacheWritePrice: 6.25,
            fastMultiplier: 6.0
        ),
        "claude-opus-4-8": ModelPricing(
            modelID: "claude-opus-4-8",
            displayName: "Claude Opus 4.8",
            inputPrice: 5.0, outputPrice: 25.0,
            cacheReadPrice: 0.50, cacheWritePrice: 6.25,
            fastMultiplier: 2.0
        ),

        // Sonnet 4 系列
        // 200k 阈值之上的 above_200k 单价（来自 LiteLLM）：
        //   input  3.0  → 6.0
        //   output 15.0 → 22.5  （×1.5，注意区别于 3.5 Sonnet 的 ×2）
        //   cacheRead 0.30 → 0.60
        //   cacheWrite 3.75 → 7.50
        "claude-sonnet-4": ModelPricing(
            modelID: "claude-sonnet-4",
            displayName: "Claude Sonnet 4",
            inputPrice: 3.0, outputPrice: 15.0,
            cacheReadPrice: 0.30, cacheWritePrice: 3.75,
            inputPriceAbove200k: 6.0,
            outputPriceAbove200k: 22.5,
            cacheReadPriceAbove200k: 0.60,
            cacheWritePriceAbove200k: 7.50
        ),
        "claude-sonnet-4-5": ModelPricing(
            modelID: "claude-sonnet-4-5",
            displayName: "Claude Sonnet 4.5",
            inputPrice: 3.0, outputPrice: 15.0,
            cacheReadPrice: 0.30, cacheWritePrice: 3.75,
            inputPriceAbove200k: 6.0,
            outputPriceAbove200k: 22.5,
            cacheReadPriceAbove200k: 0.60,
            cacheWritePriceAbove200k: 7.50
        ),

        // Haiku 4.5
        "claude-haiku-4-5": ModelPricing(
            modelID: "claude-haiku-4-5",
            displayName: "Claude Haiku 4.5",
            inputPrice: 1.0, outputPrice: 5.0,
            cacheReadPrice: 0.10, cacheWritePrice: 1.25
        ),

        // Fable 5
        "claude-fable-5": ModelPricing(
            modelID: "claude-fable-5",
            displayName: "Claude Fable 5",
            inputPrice: 10.0, outputPrice: 50.0,
            cacheReadPrice: 1.00, cacheWritePrice: 12.50
        ),

        // Claude 3.5 系列
        // 仅 3.5 Sonnet 在 LiteLLM 上配置了 above_200k；output above 是 ×2（30.0），
        // 区别于 4 系的 ×1.5（22.5）。3.5 Haiku 没有 above 价。
        "claude-3.5-haiku": ModelPricing(
            modelID: "claude-3.5-haiku",
            displayName: "Claude 3.5 Haiku",
            inputPrice: 0.80, outputPrice: 4.0,
            cacheReadPrice: 0.08, cacheWritePrice: 1.00
        ),
        "claude-3.5-sonnet": ModelPricing(
            modelID: "claude-3.5-sonnet",
            displayName: "Claude 3.5 Sonnet",
            inputPrice: 3.0, outputPrice: 15.0,
            cacheReadPrice: 0.30, cacheWritePrice: 3.75,
            inputPriceAbove200k: 6.0,
            outputPriceAbove200k: 30.0,
            cacheReadPriceAbove200k: 0.60,
            cacheWritePriceAbove200k: 7.50
        ),

        // Claude 3.7 系列
        "claude-3.7-sonnet": ModelPricing(
            modelID: "claude-3.7-sonnet",
            displayName: "Claude 3.7 Sonnet",
            inputPrice: 3.0, outputPrice: 15.0,
            cacheReadPrice: 0.30, cacheWritePrice: 3.75
        ),

        // MARK: - DeepSeek 系列
        //
        // 价位参考 TokenTracker `pricing/curated-overrides.json`(DeepSeek 官方 API 价位):
        // https://api-docs.deepseek.com/quick_start/pricing
        // 与 ccusage 内置表不一致:ccusage 通过 models.dev 模糊匹配,会落到第三方代理价位
        // (1.74/3.48/0.145 等),取决于运行时哈希顺序;TokenTracker curated 价位锁定为
        // 官方价,数据来源更稳定。

        "deepseek-v4-pro": ModelPricing(
            modelID: "deepseek-v4-pro",
            displayName: "DeepSeek V4 Pro",
            inputPrice: 0.435, outputPrice: 0.87,
            cacheReadPrice: 0.003625, cacheWritePrice: 0.435
        ),
        "deepseek-v4-flash": ModelPricing(
            modelID: "deepseek-v4-flash",
            displayName: "DeepSeek V4 Flash",
            inputPrice: 0.14, outputPrice: 0.28,
            cacheReadPrice: 0.0028, cacheWritePrice: 0.14
        ),

        // MARK: - GLM(智谱)系列
        //
        // 价位参考 TokenTracker `curated-overrides.json` 与 ccusage Rust 主表
        // (`pricing.rs::put_builtin_pricing` 中 glm-5.1 = 1.4 / 4.4 / 0.26),两侧一致。

        "glm-5.1": ModelPricing(
            modelID: "glm-5.1",
            displayName: "GLM 5.1",
            inputPrice: 1.4, outputPrice: 4.4,
            cacheReadPrice: 0.26, cacheWritePrice: 0
        ),

        // MARK: - OpenAI GPT-5 系列(供 Codex provider 使用)
        //
        // 价位参考 ccusage `rust/crates/ccusage/src/pricing.rs::put_builtin_pricing`。
        // GPT-5 family 没有 200k tier above 单价,也没有 fast multiplier。
        // cache_write 与 input 同价(ccusage 表中显式写入),Codex 实际不会产生
        // cache write tokens(无 5m/1h ephemeral 概念),但保持字段对齐以防万一。
        //
        // Codex 的 reasoning_output_tokens 已包含在 output_tokens 中,
        // CodexRolloutParser 仅记录 outputTokens,此处定价直接对 outputTokens 计费即可。

        "gpt-5": ModelPricing(
            modelID: "gpt-5",
            displayName: "GPT-5",
            inputPrice: 1.25, outputPrice: 10.0,
            cacheReadPrice: 0.125, cacheWritePrice: 1.25
        ),
        "gpt-5.1": ModelPricing(
            modelID: "gpt-5.1",
            displayName: "GPT-5.1",
            inputPrice: 1.25, outputPrice: 10.0,
            cacheReadPrice: 0.125, cacheWritePrice: 1.25
        ),
        "gpt-5.1-codex": ModelPricing(
            modelID: "gpt-5.1-codex",
            displayName: "GPT-5.1 Codex",
            inputPrice: 1.25, outputPrice: 10.0,
            cacheReadPrice: 0.125, cacheWritePrice: 1.25
        ),
        "gpt-5.2": ModelPricing(
            modelID: "gpt-5.2",
            displayName: "GPT-5.2",
            inputPrice: 1.75, outputPrice: 14.0,
            cacheReadPrice: 0.175, cacheWritePrice: 1.75
        ),
        "gpt-5.2-codex": ModelPricing(
            modelID: "gpt-5.2-codex",
            displayName: "GPT-5.2 Codex",
            inputPrice: 1.75, outputPrice: 14.0,
            cacheReadPrice: 0.175, cacheWritePrice: 1.75
        ),
        "gpt-5.3-codex": ModelPricing(
            modelID: "gpt-5.3-codex",
            displayName: "GPT-5.3 Codex",
            inputPrice: 1.75, outputPrice: 14.0,
            cacheReadPrice: 0.175, cacheWritePrice: 1.75
        ),
        "gpt-5.4": ModelPricing(
            modelID: "gpt-5.4",
            displayName: "GPT-5.4",
            inputPrice: 2.5, outputPrice: 15.0,
            cacheReadPrice: 0.25, cacheWritePrice: 2.5
        ),
        "gpt-5.4-mini": ModelPricing(
            modelID: "gpt-5.4-mini",
            displayName: "GPT-5.4 Mini",
            inputPrice: 0.75, outputPrice: 4.5,
            cacheReadPrice: 0.075, cacheWritePrice: 0.75
        ),
        "gpt-5.4-nano": ModelPricing(
            modelID: "gpt-5.4-nano",
            displayName: "GPT-5.4 Nano",
            inputPrice: 0.20, outputPrice: 1.25,
            cacheReadPrice: 0.020, cacheWritePrice: 0.20
        ),
        "gpt-5.5": ModelPricing(
            modelID: "gpt-5.5",
            displayName: "GPT-5.5",
            inputPrice: 5.0, outputPrice: 30.0,
            cacheReadPrice: 0.5, cacheWritePrice: 5.0
        ),
    ]

    // 注：曾有 `static let aliases: [String: String]` 用于非标准名称 → 标准 key 的映射,
    // 长期为空且无任何引用,作为死代码移除。如未来需为模型加同义名,
    // 可在此处恢复 dict + 在 pricing(for:) 中精确匹配后、前缀匹配前先查 aliases。

    /// 候选 key 按长度倒序的预排序数组（长 key 优先匹配）
    /// 在模块加载时构造一次，避免每次查找都重排
    private static let prefixCandidates: [(key: String, pricing: ModelPricing)] = {
        prices.sorted { lhs, rhs in
            if lhs.key.count != rhs.key.count {
                return lhs.key.count > rhs.key.count
            }
            return lhs.key > rhs.key
        }.map { ($0.key, $0.value) }
    }()

    /// 判断 modelID 在 candidate 之后紧跟的后缀是否表示新版本号
    /// 用于阻止 "claude-sonnet-4" 错误命中 "claude-sonnet-4-5-..."
    ///
    /// 规则（参考 ccusage `suffix_starts_with_numeric_model_version`）：
    /// - candidate 以数字结尾，且
    /// - 后缀以 `-` 或 `.` 开始，紧跟若干位数字
    /// - 例外：8 位数字（YYYYMMDD 日期后缀）后接边界字符则视为日期，允许匹配
    ///
    /// `internal`: LiteLLMPriceCatalog 复用同一规则,确保兜底表查找语义一致
    static func suffixStartsWithNumericVersion(candidate: String, suffix: String) -> Bool {
        guard let lastByte = candidate.utf8.last, isAsciiDigit(lastByte) else { return false }
        guard let firstByte = suffix.utf8.first, firstByte == 0x2D /* - */ || firstByte == 0x2E /* . */
        else { return false }

        let rest = suffix.dropFirst()
        let digitCount = rest.utf8.prefix(while: isAsciiDigit).count
        guard digitCount > 0 else { return false }

        // 8 位数字 + 边界（结尾或非字母数字）→ 视为日期后缀，允许命中
        let MODEL_DATE_SUFFIX_DIGITS = 8
        if digitCount == MODEL_DATE_SUFFIX_DIGITS {
            let afterDigits = rest.utf8.dropFirst(digitCount).first
            if let after = afterDigits {
                if !isAsciiAlphanumeric(after) { return false }   // 是日期，允许
            } else {
                return false                                       // 完整以 8 位数字结尾，是日期
            }
        }
        return true
    }

    private static func isAsciiDigit(_ byte: UInt8) -> Bool {
        byte >= 0x30 && byte <= 0x39
    }

    private static func isAsciiAlphanumeric(_ byte: UInt8) -> Bool {
        isAsciiDigit(byte)
            || (byte >= 0x41 && byte <= 0x5A)  // A-Z
            || (byte >= 0x61 && byte <= 0x7A)  // a-z
    }

    /// 查找定价，匹配优先级：手写表精确 → 手写表前缀（按 candidate key 长度倒序 + 版本号守卫）
    ///                    → LiteLLM 全表精确 → LiteLLM 全表前缀
    ///                    → 截掉 "{provider}/" 前缀,递归查一次裸 modelID
    ///
    /// 手写表优先于 LiteLLM:手写表的 displayName / 200k tier / fastMultiplier 元数据更准确
    /// 且语义稳定;LiteLLM 全表用于兜底未知 modelID(如带 provider 前缀的 Bedrock / Vertex 别名)。
    ///
    /// "{provider}/{model}" 前缀剥离用于 opencode 之类把 providerID 拼到 modelID 前的源:
    /// 如 "huoshan-zijie/glm-5.1" 整串 miss 后,以 "glm-5.1" 再查一次。
    /// LiteLLM 全表里有些 key 本身就含 `/`(如 `bedrock/anthropic.claude-3-5-sonnet`),
    /// 这些会在前面的精确/前缀阶段优先命中,不会被错误剥离。
    ///
    /// - Parameter modelID: 从 JSONL 中读取的原始模型名称
    /// - Returns: 匹配的定价条目，未找到返回 nil
    static func pricing(for modelID: String) -> ModelPricing? {
        let normalized = modelID.lowercased()

        // 1. 手写表精确匹配
        if let pricing = prices[normalized] {
            return pricing
        }

        // 2. 手写表前缀匹配（长 key 优先 + 版本号守卫）
        // 例：modelID = "claude-sonnet-4-5-20250514"
        //  - candidate "claude-sonnet-4-5" → suffix "-20250514"，8 位日期，命中 ✓
        //  - candidate "claude-sonnet-4"   → suffix "-5-20250514"，"-5" 是新版本号，跳过 ✗
        for (key, pricing) in prefixCandidates {
            guard normalized.hasPrefix(key) else { continue }
            let suffix = String(normalized.dropFirst(key.count))
            if suffix.isEmpty { return pricing }
            if suffixStartsWithNumericVersion(candidate: key, suffix: suffix) {
                continue
            }
            return pricing
        }

        // 3. LiteLLM 全表兜底
        // 覆盖手写表外的 2000+ 条目(Bedrock anthropic.* / Vertex / Azure / DeepSeek 等)
        if let pricing = LiteLLMPriceCatalog.shared.pricing(forNormalized: normalized) {
            return pricing
        }

        // 4. 剥离 "{provider}/" 前缀重试 — 处理 opencode 等把上游 provider 拼到 modelID 前的源
        // 与 ccusage 行为对齐:同一 base 模型走不同代理时,统一回退到官方价位
        if let slashIdx = normalized.firstIndex(of: "/") {
            let bareModel = String(normalized[normalized.index(after: slashIdx)...])
            if !bareModel.isEmpty && bareModel != normalized {
                return pricing(for: bareModel)
            }
        }

        return nil
    }
}
