# TokenWatch

macOS 原生应用，用于统计 Coding Agent（Claude Code 等）的 Token 用量与费用。

## 架构设计

TokenWatch 完全参考 [ccusage](https://github.com/ryoppippi/ccusage) 的核心逻辑（读 JSONL → 解析 usage → 统计费用），并结合 [TokenTracker](https://github.com/mm7894215/TokenTracker) 的复合键去重策略，以纯 Swift 原生实现适配 Mac App Store Sandbox 环境。

### 参考方案对比

| 方面 | ccusage | TokenTracker | TokenWatch 采纳 |
|------|---------|-------------|----------------|
| 数据读取 | 直接读 JSONL | Hooks + 被动读取 + 30min 桶聚合到 SQLite | **直接读 JSONL** |
| 去重策略 | 无特殊去重 | 复合键去重（避免 1.6-3.7× 多计） | **复合键去重** |
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
│                      │  复合键去重: (sessionID, ts, model, in, out)
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│ PricingEngine        │  成本 = input×inputPrice/1e6
│ + PricingTable       │       + output×outputPrice/1e6
│                      │       + cacheCreate×cacheWritePrice/1e6
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

完全参考 ccusage 公式：

```
cost = inputTokens × inputPrice / 1,000,000
     + outputTokens × outputPrice / 1,000,000
     + cacheCreationInputTokens × cacheWritePrice / 1,000,000
     + cacheReadInputTokens × cacheReadPrice / 1,000,000
```

#### 去重策略

参考 TokenTracker，使用复合键去重避免 DeepSeek 等模型因缺失 reqId 导致的 1.6-3.7× 多计：

```
去重键 = (sessionID, timestamp, model, inputTokens, outputTokens)
```

### 定价表

内置覆盖 Claude + DeepSeek 系列（数据来源：LiteLLM）：

| 模型 | 输入 | 输出 | 缓存读取 | 缓存写入 |
|------|------|------|---------|---------|
| Claude Opus 4 | $15.00 | $75.00 | $1.50 | $18.75 |
| Claude Opus 4.5 | $5.00 | $25.00 | $0.50 | $6.25 |
| Claude Sonnet 4 | $3.00 | $15.00 | $0.30 | $3.75 |
| Claude Haiku 4.5 | $1.00 | $5.00 | $0.10 | $1.25 |
| Claude Fable 5 | $10.00 | $50.00 | $1.00 | $12.50 |
| Claude 3.5 Haiku | $0.80 | $4.00 | $0.08 | $1.00 |
| Claude 3.5 Sonnet | $3.00 | $15.00 | $0.30 | $3.75 |
| Claude 3.7 Sonnet | $3.00 | $15.00 | $0.30 | $3.75 |
| DeepSeek V4 Pro | $3.00 | $15.00 | $0.30 | $3.75 |
| DeepSeek V4 Flash | $1.00 | $5.00 | $0.10 | $1.25 |

> 以上价格为每百万 token 的 USD 价格。

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
- [x] Phase 6: 单元测试（30 个测试用例全部通过）
- [ ] Phase 7: UI 界面（AppKit 原生界面展示统计数据）
- [ ] Phase 8: 支持更多数据源（Codex, Gemini CLI 等）
