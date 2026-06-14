# TokenWatch

macOS 原生应用，统计 Coding Agent（Claude Code / Codex 等）的 Token 用量与费用。

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
┌──────────────┐  ┌──────────────┐
│ ClaudeProvider │  │ CodexProvider │  ... 未来 GeminiProvider
└──────┬───────┘  └──────┬───────┘
       ▼                 ▼
[扫描 + 解析] → ParsedUsageEntry
                    │
                    ▼
             PricingEngine + UsageAggregator (共享)
                    │
                    ▼
             TokenStatsViewModel.states[providerID]
                    │
                    ▼
             NSTabViewController (一个 Tab/provider)
```

### 支持的数据源

- **Claude Code** — `~/.claude/projects/` 下的 JSONL，按 `message.id` 全局去重（`requestId` 缺失时回退到单 key）
- **Codex** — `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`（同时聚合 `archived_sessions/`，同相对路径以 `sessions/` 优先）；按 `(sessionId, timestamp)` 合成 dedup key；`last_token_usage` 优先，缺失则用 `saturatingSub(total, prevTotal)` 推导 delta；`pure_input = input - cached_input` 防双计；`output_tokens` 已含 reasoning，reasoning 不另计费

### 目录结构

```
TokenWatch/
├── AppDelegate.swift                      # @MainActor 应用入口
├── ViewController.swift                   # NSTabViewController 容器（每 provider 一 Tab）
├── ViewControllers/
│   └── ProviderStatsViewController.swift  # 单 provider 用量展示
├── Models/
│   ├── TokenUsage.swift                   # usage 对象 Decodable（共享 token 字段）
│   ├── ParsedUsageEntry.swift             # 展平用量条目（含 provider: ProviderID）
│   ├── UsageAggregation.swift             # UsageSummary + AggregatedStats
│   └── ModelPricing.swift                 # 定价条目模型
├── Providers/
│   ├── ProviderID.swift                   # 数据源标识枚举
│   ├── UsageProvider.swift                # 数据源协议（扫描 + 解析 + UI 元数据）
│   ├── ProviderRegistry.swift             # provider 静态注册表
│   ├── Claude/
│   │   ├── ClaudeRecord.swift             # JSONL 顶层结构 + ISO 8601 解析
│   │   ├── ClaudeMessage.swift            # message 子结构 + content 解析
│   │   ├── ClaudeJSONLScanner.swift       # 扫描 ~/.claude/projects/
│   │   ├── ClaudeJSONLParser.swift        # 逐行解析 + messageId 去重
│   │   └── ClaudeProvider.swift           # 装配 Scanner+Parser
│   └── Codex/
│       ├── CodexRecord.swift              # rollout JSONL 顶层 + payload 分发
│       ├── CodexRolloutScanner.swift      # 扫描 ~/.codex/sessions(/archived_sessions)
│       ├── CodexRolloutParser.swift       # last_token_usage 优先 + total 增量推导
│       └── CodexProvider.swift            # 装配 Scanner+Parser
├── Services/
│   └── SecurityScopedBookmarkManager.swift # 多 key Bookmark 管理
├── Pricing/
│   ├── PricingTable.swift                 # 内置定价表（Claude+DeepSeek+GLM+GPT-5）
│   ├── LiteLLMPriceCatalog.swift          # LiteLLM 全表兜底（2000+ 模型）
│   ├── litellm_prices.json                # 编译时嵌入的定价快照
│   └── PricingEngine.swift                # 成本计算引擎
├── Analytics/
│   └── UsageAggregator.swift              # 多维度聚合
└── ViewModels/
    └── TokenStatsViewModel.swift          # 多 provider 状态协调

TokenWatchTests/
├── Models/                                # 模型解码 + 去重测试
├── Pricing/PricingEngineTests.swift       # 成本 + 定价表测试（含 GPT-5）
├── Analytics/UsageAggregatorTests.swift   # 聚合测试
└── Providers/
    ├── ProviderRegistryTests.swift
    ├── Claude/                            # ClaudeJSONLScanner + Parser 测试
    └── Codex/                             # CodexRecord + Scanner + Parser 测试
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
cost = ( tiered(inputTokens,        inputPrice,         inputPriceAbove200k)
       + tiered(outputTokens,       outputPrice,        outputPriceAbove200k)
       + tiered(cacheCreate5mTokens, cacheWritePrice,   cacheWritePriceAbove200k)
       + tiered(cacheCreate1hTokens, inputPrice  × 2,   inputPriceAbove200k × 2)
       + tiered(cacheReadTokens,    cacheReadPrice,     cacheReadPriceAbove200k) )
     × multiplier

tiered(t, base, above) =
    200_000 × base + (t - 200_000) × above   (above != nil 且 t > 200k)
    t × base                                  (其他情形)

multiplier =
    pricing.fastMultiplier    (usage.speed == "fast")
    1.0                       (其他情形)
```

每类 token 的 200k 阈值独立判断（input 跨阈不会让 output 也走 above）。
LiteLLM 上仅 Claude Sonnet 家族（3.5 / 4 / 4.5）配置了 `*_above_200k` 单价，
Opus / Haiku / Fable / 3.7 Sonnet / DeepSeek 保持 nil → 退化为单价。

Speed::Fast 倍率在所有 tiered_cost 之和上整体乘一次。LiteLLM 上仅
Claude Opus 4.6 / 4.7 / 4.8 配置了非 1.0 值（6.0 / 6.0 / 2.0）。

`cache_creation_input_tokens` 与 `ephemeral_5m/1h_input_tokens` 是同一信息的
两种表达（**总分关系**，非并列）：当 ephemeral 细分存在时使用细分；否则把扁平
字段当作 5m。两者相加会 double-count，所以代码中由 `TokenUsage.cacheCreate5mTokens`
/ `cacheCreate1hTokens` 统一二选一。

> **简化前提（与 ccusage 当前实现的差异，未来按需扩展）**
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

| 模型 | 输入 | 输出 | 缓存读取 | 缓存写入 | 200k+ (in/out/读/写) | Fast |
|------|------|------|---------|---------|---------------------|------|
| Claude Opus 4 | $15.00 | $75.00 | $1.50 | $18.75 | — | — |
| Claude Opus 4.5 | $5.00 | $25.00 | $0.50 | $6.25 | — | — |
| Claude Opus 4.6 | $5.00 | $25.00 | $0.50 | $6.25 | — | **6.0×** |
| Claude Opus 4.7 | $5.00 | $25.00 | $0.50 | $6.25 | — | **6.0×** |
| Claude Opus 4.8 | $5.00 | $25.00 | $0.50 | $6.25 | — | **2.0×** |
| Claude Sonnet 4 | $3.00 | $15.00 | $0.30 | $3.75 | $6 / $22.5 / $0.6 / $7.5 | — |
| Claude Sonnet 4.5 | $3.00 | $15.00 | $0.30 | $3.75 | $6 / $22.5 / $0.6 / $7.5 | — |
| Claude Haiku 4.5 | $1.00 | $5.00 | $0.10 | $1.25 | — | — |
| Claude Fable 5 | $10.00 | $50.00 | $1.00 | $12.50 | — | — |
| Claude 3.5 Haiku | $0.80 | $4.00 | $0.08 | $1.00 | — | — |
| Claude 3.5 Sonnet | $3.00 | $15.00 | $0.30 | $3.75 | $6 / **$30** / $0.6 / $7.5 | — |
| Claude 3.7 Sonnet | $3.00 | $15.00 | $0.30 | $3.75 | — | — |
| DeepSeek V4 Pro | $3.00 | $15.00 | $0.30 | $3.75 | — | — |
| DeepSeek V4 Flash | $1.00 | $5.00 | $0.10 | $1.25 | — | — |
| GLM 5.1 | $1.40 | $4.40 | $0.26 | — | — | — |
| GPT-5 | $1.25 | $10.00 | $0.125 | $1.25 | — | — |
| GPT-5.1 | $1.25 | $10.00 | $0.125 | $1.25 | — | — |
| GPT-5.1 Codex | $1.25 | $10.00 | $0.125 | $1.25 | — | — |
| GPT-5.2 | $1.75 | $14.00 | $0.175 | $1.75 | — | — |
| GPT-5.2 Codex | $1.75 | $14.00 | $0.175 | $1.75 | — | — |
| GPT-5.3 Codex | $1.75 | $14.00 | $0.175 | $1.75 | — | — |
| GPT-5.4 | $2.50 | $15.00 | $0.25 | $2.50 | — | — |
| GPT-5.4 Mini | $0.75 | $4.50 | $0.075 | $0.75 | — | — |
| GPT-5.4 Nano | $0.20 | $1.25 | $0.020 | $0.20 | — | — |
| GPT-5.5 | $5.00 | $30.00 | $0.50 | $5.00 | — | — |

> 价格为每百万 token 的 USD 价格。3.5 Sonnet 的 output above_200k 是 ×2（$30），
> 4 系是 ×1.5（$22.5），区别来自 LiteLLM 上游。Fast 列是 `usage.speed == "fast"`
> 时整体成本的乘倍数(目前仅 Opus 4.6/4.7/4.8 配置)。

### Sandbox 适配

TokenWatch 通过 Security-Scoped Bookmark 在 App Sandbox 环境下安全访问每个数据源的目录，各 provider 的 Bookmark key 互相独立、互不影响：

- `ClaudeDirectoryBookmark` → `~/.claude`
- `CodexDirectoryBookmark` → `~/.codex`

授权流程（每个 provider 独立）：

1. 首次进入对应 Tab → 「授权访问」按钮 → `NSOpenPanel` 默认定位到 provider 期望目录
2. 用户选择 → 创建 Security-Scoped Bookmark → 持久化到 `UserDefaults`（对应 key）
3. 后续启动 → 恢复 Bookmark → `startAccessingSecurityScopedResource()`
4. Tab 切换或刷新完成 → `stopAccessingSecurityScopedResource()`
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
- [x] Phase 7: UI 界面（AppKit 原生界面展示统计数据，NSTabViewController 多 Tab）
- [ ] Phase 8: 支持更多数据源（已支持 Codex，后续 Gemini CLI 等）

## 已知限制

> 已修复:
> - **#3 PricingTable LiteLLM 兜底** — 嵌入 LiteLLM `model_prices_and_context_window.json`(约 140KB,2000+ 模型)作为手写表的查找兜底,Bedrock / Vertex / Azure 等 provider 别名不再计 $0
> - **#8 首次启动授权 UI 入口** — `ViewController` 监听 `TokenStatsViewModel.onStateChange`,无 Bookmark 时显示「授权访问 ~/.claude」按钮触发 `NSOpenPanel`
> - #4 JSONLParser FileHandle 流式读取 / #5 decodeProjectPath `--` 双连字符转义 / #6 UsageAggregator 用 Calendar 替代 DateFormatter / #7 移除空 aliases 死代码 / #9 清理冗余 nonisolated 与对齐 CLAUDE.md

