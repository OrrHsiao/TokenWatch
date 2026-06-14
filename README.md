# TokenWatch

macOS 原生应用，用于统计 Coding Agent（Claude Code 等）的 Token 用量与费用。

## 架构设计

TokenWatch 完全参考 [ccusage](https://github.com/ryoppippi/ccusage) 的核心逻辑（读 JSONL → 解析 usage → 统计费用），并采纳 [TokenTracker](https://github.com/mm7894215/TokenTracker) 的 `message.id` 去重策略，以纯 Swift 原生实现适配 Mac App Store Sandbox 环境。

### 参考方案对比

| 方面 | ccusage | TokenTracker | TokenWatch 采纳 |
|------|---------|-------------|----------------|
| 数据读取 | 直接读 JSONL | Hooks + 被动读取 + 30min 桶聚合到 SQLite | **直接读 JSONL** |
| 去重策略 | `message.id` (+可选 reqId) | `message.id` (+可选 reqId) | **`message.id` (+可选 reqId)** |
| 定价来源 | LiteLLM 编译时嵌入 | LiteLLM 2200+ 模型，每日刷新 | **编译时嵌入** |
| 聚合维度 | 日/周/月/会话/blocks | 日/时/月/项目/模型 + 热力图 | **日/周/月/会话/模型/项目** |
| 存储 | 无持久化（即时计算） | SQLite | **无持久化**（后续可加 SQLite） |
| UI | CLI 表格输出 | Web 仪表盘 + 菜单栏 + 4 Widgets | **AppKit 原生 UI** |

### 数据流

```
~/.claude/projects/<project>/<session>.jsonl
        │
        ▼
┌─────────────────────┐
│ SecurityScopedBM    │  NSOpenPanel 授权 → Bookmark 持久化
│ (Sandbox 访问)       │
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│ JSONLScanner         │  递归扫描 projects/ 目录
│ + JSONLParser        │  逐行解析 assistant 记录 → 提取 usage
│                      │  去重键: message.id (+ 可选 requestId)
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│ PricingEngine        │  成本 = input×inputPrice/1e6
│ + PricingTable       │       + output×outputPrice/1e6
│                      │       + cache5m×cacheWritePrice/1e6
│                      │       + cache1h×(inputPrice×2)/1e6
│                      │       + cacheRead×cacheReadPrice/1e6
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│ UsageAggregator      │  按日/周/月/会话/模型/项目 聚合
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│ TokenStatsViewModel  │  协调全流程，为 UI 准备数据
└─────────────────────┘
```

### 目录结构

```
TokenWatch/
├── AppDelegate.swift                      # @MainActor 应用入口
├── ViewController.swift                   # 主视图控制器
├── Models/
│   ├── TokenUsage.swift                   # usage 对象 Decodable（含 ServerToolUse, CacheCreation）
│   ├── ClaudeMessage.swift                # message 子结构 + MessageContent
│   ├── ClaudeRecord.swift                 # JSONL 记录顶层结构 + ISO 8601 解析
│   ├── ParsedUsageEntry.swift             # 展平用量条目，Hashable 复合键去重
│   ├── UsageAggregation.swift             # UsageSummary + AggregatedStats
│   └── ModelPricing.swift                 # 定价条目模型（每百万 token USD）
├── Services/
│   ├── SecurityScopedBookmarkManager.swift # Sandbox 核心：Bookmark 创建/恢复/释放
│   ├── JSONLScanner.swift                 # 扫描 projects/ 下所有 .jsonl
│   └── JSONLParser.swift                  # 逐行解析 + 去重
├── Pricing/
│   ├── PricingTable.swift                 # 内置定价表（Claude + DeepSeek 系列）
│   └── PricingEngine.swift                # 成本计算引擎
├── Analytics/
│   └── UsageAggregator.swift              # 多维度聚合
└── ViewModels/
    └── TokenStatsViewModel.swift          # 协调层

TokenWatchTests/
├── Models/TokenUsageDecodingTests.swift    # 解码 + 去重测试
├── Pricing/PricingEngineTests.swift        # 成本计算 + 定价表测试
├── Analytics/UsageAggregatorTests.swift    # 聚合逻辑测试
└── Services/JSONLParserTests.swift         # 解析器 + 去重测试
```

### 数据模型

#### usage 对象（Claude Code JSONL）

```json
{
  "input_tokens": 5790,
  "cache_creation_input_tokens": 0,
  "cache_read_input_tokens": 10240,
  "output_tokens": 601,
  "cache_creation": {
    "ephemeral_1h_input_tokens": 0,
    "ephemeral_5m_input_tokens": 0
  },
  "server_tool_use": { "web_search_requests": 0, "web_fetch_requests": 0 },
  "service_tier": "standard",
  "speed": "standard"
}
```

#### 成本计算

参考 ccusage `cost.rs::calculate_cost_from_tokens` + `tiered_cost`：

```
cost = tiered(inputTokens,        inputPrice,         inputPriceAbove200k)
     + tiered(outputTokens,       outputPrice,        outputPriceAbove200k)
     + tiered(cacheCreate5mTokens, cacheWritePrice,   cacheWritePriceAbove200k)
     + tiered(cacheCreate1hTokens, inputPrice  × 2,   inputPriceAbove200k × 2)
     + tiered(cacheReadTokens,    cacheReadPrice,     cacheReadPriceAbove200k)

tiered(t, base, above) =
    200_000 × base + (t - 200_000) × above   (above != nil 且 t > 200k)
    t × base                                  (其他情形)
```

每类 token 的 200k 阈值独立判断（input 跨阈不会让 output 也走 above）。
LiteLLM 上仅 Claude Sonnet 家族（3.5 / 4 / 4.5）配置了 `*_above_200k` 单价，
Opus / Haiku / Fable / 3.7 Sonnet / DeepSeek 保持 nil → 退化为单价。

`cache_creation_input_tokens` 与 `ephemeral_5m/1h_input_tokens` 是同一信息的
两种表达（**总分关系**，非并列）：当 ephemeral 细分存在时使用细分；否则把扁平
字段当作 5m。两者相加会 double-count，所以代码中由 `TokenUsage.cacheCreate5mTokens`
/ `cacheCreate1hTokens` 统一二选一。

> **简化前提（与 ccusage 当前实现的差异，未来按需扩展）**
> - 不实现 Speed::Fast 的 `fast_multiplier`
> - 定价表为 per-1M token USD（ccusage 使用 LiteLLM 的 per-token 字段）

#### 去重策略

参考 TokenTracker 当前实现（`rollout.js::claudeMessageDedupKey`，issue #64）：

```
去重键 = message.id            （Anthropic 协议保证全局唯一）
       | message.id:requestId  （存在 requestId 时拼接，但不强制）
```

旧版方案曾强制要求 `(messageId, requestId)` 双键，但 DeepSeek/Kimi/Mimo/MiniMax
等 Anthropic 兼容端点不返回 `request-id` HTTP header，sub-agent / thinking
transport 路径也会丢字段，导致 dedup 完全失效、出现 1.6-3.7× 多计。
TokenWatch 采用 fallback：`requestId` 缺失时使用 `messageId` 单独作键。
`messageId` 不含 `:`，所以两种格式可在同一 Set 中无碰撞共存。

### 定价表

内置覆盖 Claude + DeepSeek 系列（数据来源：LiteLLM）：

| 模型 | 输入 | 输出 | 缓存读取 | 缓存写入 | 200k+ (in/out/读/写) |
|------|------|------|---------|---------|---------------------|
| Claude Opus 4 | $15.00 | $75.00 | $1.50 | $18.75 | — |
| Claude Opus 4.5 | $5.00 | $25.00 | $0.50 | $6.25 | — |
| Claude Sonnet 4 | $3.00 | $15.00 | $0.30 | $3.75 | $6 / $22.5 / $0.6 / $7.5 |
| Claude Sonnet 4.5 | $3.00 | $15.00 | $0.30 | $3.75 | $6 / $22.5 / $0.6 / $7.5 |
| Claude Haiku 4.5 | $1.00 | $5.00 | $0.10 | $1.25 | — |
| Claude Fable 5 | $10.00 | $50.00 | $1.00 | $12.50 | — |
| Claude 3.5 Haiku | $0.80 | $4.00 | $0.08 | $1.00 | — |
| Claude 3.5 Sonnet | $3.00 | $15.00 | $0.30 | $3.75 | $6 / **$30** / $0.6 / $7.5 |
| Claude 3.7 Sonnet | $3.00 | $15.00 | $0.30 | $3.75 | — |
| DeepSeek V4 Pro | $3.00 | $15.00 | $0.30 | $3.75 | — |
| DeepSeek V4 Flash | $1.00 | $5.00 | $0.10 | $1.25 | — |

> 以上价格为每百万 token 的 USD 价格。3.5 Sonnet 的 output above_200k 是 ×2（$30），
> 4 系是 ×1.5（$22.5），区别来自 LiteLLM 上游。

### Sandbox 适配

TokenWatch 通过 Security-Scoped Bookmark 在 App Sandbox 环境下安全访问 `~/.claude` 目录：

1. 首次启动 → `NSOpenPanel` 引导用户选择 `~/.claude`
2. 创建 Security-Scoped Bookmark → 持久化到 `UserDefaults`
3. 后续启动 → 恢复 Bookmark → `startAccessingSecurityScopedResource()`
4. 读取完毕 → `stopAccessingSecurityScopedResource()`
5. Bookmark 过期 → 自动重建或引导重新授权

## 构建与测试

### 环境要求

- Xcode 26.5+
- macOS 15.0+
- Swift 6.0

### Build

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build
```

### Test

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

## 开发计划

- [x] Phase 1: 数据模型层（TokenUsage, ClaudeRecord 等 6 个模型）
- [x] Phase 2: 定价引擎（PricingTable + PricingEngine）
- [x] Phase 3: 数据访问层（Bookmark 管理 + JSONL 扫描/解析 + 去重）
- [x] Phase 4: 聚合分析（UsageAggregator 多维度聚合）
- [x] Phase 5: ViewModel 与 App 集成（TokenStatsViewModel + AppDelegate）
- [x] Phase 6: 单元测试（42 个测试用例全部通过）
- [ ] Phase 7: UI 界面（AppKit 原生界面展示统计数据）
- [ ] Phase 8: 支持更多数据源（Codex, Gemini CLI 等）

## 已知限制

以下问题已识别但尚未处理，按"是否影响成本正确性 / 何时该做"分组。

### 计费准确性差异（与 ccusage 对账时可能出现偏差）

| # | 项 | 影响 | 何时处理 |
|---|---|---|---|
| 2 | **`Speed::Fast` multiplier 未实现**：JSONL `speed: "fast"` 请求 ccusage 会乘以模型对应的 fast multiplier（如 2.5×）；当前实现忽略 `speed`。 | 用 Fast 模式时**严重低估成本**。 | `PricingTable` 扩展字段时一并加上 `fastMultiplier`。 |
| 3 | **PricingTable 仅 12 条手写条目**：ccusage `pricing.rs::find` 还会回退查 `models_dev_pricing()` + 内嵌镜像作为 LiteLLM 兜底；TokenWatch 没这层。 | 用 Bedrock / Vertex / 第三方 provider 别名时模型查不到 → 成本计 $0。 | 决定是否在编译时嵌入 LiteLLM 全表（要权衡 App 体积 vs 定价覆盖度）。 |

### 可维护性 / 性能

| # | 项 | 位置 | 何时处理 |
|---|---|---|---|
| 4 | **JSONLParser 一次性 `String(contentsOf:)` 读入**：长 session 单文件可达数百 MB，目前会全量进内存。建议改 `FileHandle` 流式读取。 | `Services/JSONLParser.swift` | 真实数据 >50MB 出现性能问题时。 |
| 5 | **`JSONLScanner.decodeProjectPath` 还原规则太粗**：把所有 `-` 替换为 `/`，项目名本身含 `-`（如 `my-cool-app`）会被错误展开成 `/my/cool/app`。需查 Claude Code 真实编码规则（疑似 `--` 转义）。 | `Services/JSONLScanner.swift` | UI 展示项目维度时看到错误目录名时。 |
| 6 | **`UsageAggregator` 每条 entry 新建 `DateFormatter`**：分组时反复分配，数据量大时有开销。可静态缓存或改 `Calendar.dateComponents` 拼字符串。 | `Analytics/UsageAggregator.swift` | profile 显示成为热点时。 |
| 7 | **`PricingTable.aliases` 是空 dict 但仍参与查找**：当前为死代码。 | `Pricing/PricingTable.swift` | 添加首个别名时。 |

### UI / 集成

| # | 项 | 何时处理 |
|---|---|---|
| 8 | **首次启动没有触发授权的 UI 入口**：`AppDelegate.applicationDidFinishLaunching` 调用 `loadStats` 后会把 `needsAuthorization` 置 `true`，但目前没有视图监听此状态弹出 `NSOpenPanel`。 | 与 Phase 7 UI 一起做。 |
| 9 | **CLAUDE.md 与 pbxproj 不一致**：`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 已从 build settings 中移除，但 CLAUDE.md 仍写「all code is `@MainActor` by default」，代码里也散布着冗余的 `nonisolated` 标注。 | 确认 actor isolation 方向后顺手改。 |

