# TokenWatch 全工程正确性与 ccusage 计价对齐设计

**日期**：2026-07-10
**状态**：已确认
**范围**：修复全工程 review 中除 Release 签名外的问题，并让计价结果与固定版本 ccusage 一致

## 背景与目标

全工程 review 暴露了四类问题：计价结果与 ccusage 漂移、provider 数据解析在边界输入下丢数或重复、活动 JSONL 重复全量扫描，以及 macOS UI 的键盘与辅助功能缺口。

本轮目标：

1. 以 ccusage `v20.0.16 --offline` 的默认 Auto 成本模式为可复现计价契约，同一用量输入必须得到相同 USD 结果。
2. 修复 DST、损坏 JSON、sidechain replay、瞬时文件失败和 bookmark 保存失败导致的正确性问题。
3. 让 Claude 与 Codex 活动 JSONL 在追加场景只读取新增范围，同时在截断或替换时安全回退全量解析。
4. 保持现有视觉设计，补齐水平访问路径、键盘操作、accessibility 语义与系统状态表达。
5. 所有行为先由失败测试复现，再写最小实现。

## 固定基线

- ccusage：[`v20.0.16 / e32cc482`](https://github.com/ccusage/ccusage/releases/tag/v20.0.16)，比较模式为 `--offline`，cost mode 保持默认 Auto。
- ccusage 当前 `main` 在审查时仅比该 tag 多一个文档提交，相关源码无差异。
- LiteLLM：[`49ca04d8c3ddea336237ce6f3082dbc26d19e944`](https://github.com/BerriAI/litellm/blob/49ca04d8c3ddea336237ce6f3082dbc26d19e944/model_prices_and_context_window.json)
- models.dev fallback：ccusage `v20.0.16` 内嵌的 `models-dev-pricing.json`。
- App 继续离线内嵌定价，不增加运行时网络请求。

ccusage 无参数运行会尝试在线刷新 LiteLLM/models.dev，价格可随上游变化，不能作为静态 App 的永久 fixture。若在线结果与本契约不同，应先用上述固定版本 `--offline` 复核，再判断是否需要单独升级价格基线。

### Parity 边界

验收目标是：对 TokenWatch 当前明确支持的 Claude JSONL、Codex `rollout-*.jsonl` 与 OpenCode SQLite/legacy message 来源，同一批有效 billing rows 的最终金额与 pinned ccusage `v20.0.16` 一致。本轮不把产品数据源范围扩张为 ccusage CLI 的全部发现能力：多 Claude/Codex root、XDG/隐藏目录、非 rollout 的 Codex saved/headless exec 和其 mtime timestamp fallback 不在本轮实施范围。固定金额 fixture 验证费率/模型/tier/fast/fallback，provider parser fixture 单独验证已支持来源的行选择与去重。

## 明确不做

- 不改变 `.github/workflows/release.yml` 中关闭签名并直接打包的现有设计。
- 不新增 web search、web fetch 或 `inference_geo` 费用；ccusage `TokenUsageRaw` 不计这些字段。
- 不把 Claude 200K 计价改为整请求切档；ccusage 对普通 LiteLLM `*_above_200k_tokens` 使用每类别独立的边际阶梯。
- 不把 Claude 全局去重键改成仅 `messageId`；普通记录继续使用 `messageId + requestId`。
- 不在本轮引入通用 TOML、数据库或第三方图表依赖。

## 方案选择

### 方案一：逐项补丁

只修当前已知分支，改动最少，但无法形成稳定的 ccusage 契约，后续模型或算法更新容易再次漂移。

### 方案二：固定 ccusage 契约（采用）

保留现有 Swift 架构，将 ccusage 的相关查价、计价和 fallback 语义映射到小型 Swift 类型，并用固定金额 fixture 锁定行为。该方案既能审计，又不需要把 Rust 构建系统引入 App。

### 方案三：直接生成或搬运上游定价子系统

原始数据最接近上游，但会引入生成脚本、上游构建约定和较大维护面，不符合本项目简洁优先原则。

## 一、计价与模型查找

### Auto 成本语义

`UsageCostResolver` 采用 ccusage 默认 Auto 模式：

1. `ParsedUsageEntry.upstreamCost` 有值时直接采用，包括显式 `0`。
2. 没有 upstream cost 时才调用本地 `PricingEngine`。
3. 未知模型且没有 upstream cost 时返回 `0`。

Claude 顶层记录需要解码 `costUSD`，并原样传播到 `ParsedUsageEntry.upstreamCost`，所以 `Some(0)` 仍是 authoritative。ccusage 的 OpenCode adapter 有 provider-specific 例外：只有 `parsed.cost > 0` 才传播 upstream cost；零与缺失都保持 `nil` 并尝试本地 token 计价，现有 `> 0` 过滤应保留。

OpenCode 本地计价候选也逐字对齐 ccusage：先尝试裸 model 及 Claude 点号/紧凑版本规范化，再尝试将 provider 的 `-` 转成 `_` 后组成的 provider/model；`gemini-3-pro-high` 映射到 `gemini-3-pro-preview`，`k2p6` 映射到 `kimi-k2.6`。候选按顺序尝试，只有正成本才停止。

### ModelPricing 表达能力

`ModelPricing` 增加：

- `cacheReadPriceIsExplicit`：区分上游明确 cache-read 价与按 input 推导的默认值。
- `longContextThreshold`：普通 LiteLLM 条目为 `nil`；OpenAI 两阶段模型为 `272_000`。
- 现有 above 价格字段继续保留。

LiteLLM 与 models.dev 条目的缺省值都与 ccusage 一致：

- cache write = input × 1.25
- cache read = input × 0.1

两种来源都要根据原始 cache-read 字段是否存在设置 `cacheReadPriceIsExplicit`，不能根据应用缺省值之后的数值反推。

Codex 对该字段有独立计价规则：显式 cache-read 价格存在时使用该价格；缺失时 cached input 使用完整 input price，而不是通用缺省的 input × 0.1。若请求进入 OpenAI long-context tier，缺失显式价格的 cached input 同样使用 long-context input price。

### 查价顺序

先构建与 ccusage offline 相同的 primary map：对 pinned LiteLLM 逐字复刻 ccusage `v20.0.16 build.rs::is_embedded_model` 的前缀过滤，只载入其离线构建会内嵌的条目；再让逐项复制自同版本 `put_builtin_pricing` 的 builtin 按 canonical exact key 覆盖。TokenWatch 原有但 ccusage builtin 中不存在的产品特有手写价格不得进入 parity map。models.dev snapshot 保持为独立 fallback map，不能覆盖或扰动 primary。

metadata overlay 也按上游优先级执行：

- canonical exact key 同时出现在 LiteLLM 与 builtin 时，builtin 整条覆盖，包括 fast；这一点与 ccusage 先载入 LiteLLM、再执行 `put_builtin_pricing` 的顺序一致。
- 对未被 exact builtin 覆盖的 LiteLLM 条目，`provider_specific_entry.fast` 优先，builtin fast override 只填缺失值。
- 只要 LiteLLM 条目已有任意 above-tier 字段，整组 builtin long-context overlay 都不混入；只有该组字段全部缺失时，才一次性补完整 rates 与 threshold。

查价统一为：

1. 在 primary map 中先 exact，再将 `.`、`@` 规范化为 `-` 做非字母数字边界 fuzzy。
2. 原始 model 在 primary 完全 miss 后才解析明确 alias，例如 `gpt-5.3-spark → gpt-5.3-codex-spark`，并对 alias 再做 primary exact/fuzzy。
3. primary 与 alias 都 miss 后，才在独立 models.dev map 中对 resolved alias 做 exact/fuzzy。
4. fuzzy 多候选同时命中时选择最长 key；等长时选择 canonical key 字典序最小者，不能依赖字典遍历顺序。
5. 保留 provider-prefixed 模型的边界匹配和 OpenCode 裸 model fallback 能力。

来源冲突必须有合成 fixture：builtin 与 LiteLLM 同 key 时 builtin 胜；LiteLLM 与 models.dev 同 key时 LiteLLM 胜；LiteLLM exact 与 builtin fuzzy 同时可用时 exact 胜。

这保证 `gpt-5-mini`、`gpt-5-nano` 不会被 `gpt-5` 抢先截获，并支持历史 Claude ID 与点号变体。

### 两类长上下文算法

普通 LiteLLM/Claude 条目继续使用当前算法：每个 token 类别独立，前 200K 使用 base，超出部分使用 above。

带 `longContextThreshold` 的 OpenAI/Codex 条目使用整请求切档：

1. 通用 OpenAI 路径逐字使用 ccusage `TokenUsageRaw.input_tokens` 判断是否大于 272K；Codex rollout 的统一模型中 input 已拆成 pure/cached，因此只有 `.codex` 语义需要以 `pure input + cached input` 重建原始 input。
2. 超过阈值时，通用 OpenAI 两阶段 token 公式的 pure input、cached input、output 与 cache write 均完整使用 long-context 价格；Codex rollout 本身没有 cache-write 维度，只对其实际存在的 input、cached input 与 output 应用该 tier。
3. 判断发生在单条请求计价时，不能先跨请求聚合再判断。

### Fast/priority

- Claude 继续由 JSONL `usage.speed == "fast"` 触发模型 multiplier。
- Codex 在 `.codex/config.toml` 中识别 `service_tier = "fast"` 或 `"priority"`。
- GPT 5.5 multiplier 为 2.5；GPT 5.4 与 GPT 5.3 Codex 为 2.0。
- Codex fast 模式遇到模型 multiplier 为 1.0 时使用 ccusage 的默认 2.0。
- Provider-prefixed Claude Opus 4.6/4.7/4.8 仍应用 6.0/6.0/2.0。

### Codex 模型 fallback

- 无模型元数据时回退 `gpt-5`。
- `codex-auto-review` 根据事件日期映射到 ccusage 固定表中的当时模型。
- 保留真实模型优先级，fallback 只在缺失或特殊占位模型时使用。

解析器内部以 `explicit / fallback` model source 保存当前模型状态，供追加解析恢复和后续真实模型覆盖；`ParsedUsageEntry` 只保存最终 resolved model，不新增没有产品消费者的公开 fallback 字段。

### 计价 fixture

新增带基线元数据的 `ccusage-v20.0.16` fixture，至少覆盖：

| 场景 | 预期 USD |
|---|---:|
| Sonnet 4.5，input 250K | 0.900000 |
| Sonnet 4.5，input 100K、output 300K | 5.550000 |
| Sonnet 4.5，cache 5m=10、1h=20、read=30 | 0.0001665 |
| Opus 4.8，input/output 各 1M，fast | 60.000000 |
| `gpt-5-mini`，input/output 各 1M | 2.250000 |
| `gpt-5-nano`，input/output 各 1M | 0.450000 |
| GPT 5.4，raw input 300K、cached 100K、output 1K | 1.072500 |
| GPT 5.5，同上 | 2.145000 |
| GPT 5.6 Sol，同上 | 2.145000 |
| GPT 5.4，raw input 100K（含 cached 40K）、output 1K，fast | 0.350000 |
| GPT 5.5，同上，fast | 0.875000 |
| `claude-3-5-haiku-20241022`，input/output 各 1M | 4.800000 |
| `gpt-5.3-spark`，input/output 各 1M | 15.750000 |
| Claude 已知模型且 `costUSD=0.123` | 0.123000 |
| Claude 已知模型且 `costUSD=0` | 0.000000 |
| Claude 未知模型且 `costUSD=0.123` | 0.123000 |
| Claude 未知模型且没有 `costUSD` | 0.000000 |
| OpenCode 已知 Sonnet 4.5，input=1K/output=100、`cost=0` | 0.004500 |
| OpenCode `kimi-for-coding/k2p6`，input/output 各 1M、无上游 cost | 4.950000 |
| OpenCode Sonnet 4.5，只有 `tokens.total=1000` | 0.015000 |
| Codex `gpt-4`，raw input=1K（含 cached=400）、output=0 | 0.030000 |

fixture 不在测试时联网，文件中记录 ccusage commit、`--offline` 模式、LiteLLM revision 与 models.dev snapshot 来源。

## 二、数据正确性与授权

### DST 墙上时钟桶

新增共享的本地小时桶描述符，以当天日期和 `0..<24` 直接生成 `yyyy-MM-ddTHH` key。UI 的 24 个标签不再依赖从午夜连续增加绝对小时：

- 春季跳时日仍展示 `00...23`，不存在的 `02` 为零。
- 秋季回拨日两个真实 `01` 继续汇总到同一个 key。
- 不再把次日 `00` 混入当天，也不会生成重复字典 key。

### 宽容 usage 解码

- `ServerToolUse` 两个子字段均使用 `decodeIfPresent ?? 0`。
- `CacheCreation` 两个子字段均使用 `decodeIfPresent ?? 0`。
- `TokenUsage.cacheCreation` 改为 `CacheCreation?`：JSON 中缺失 breakdown 时为 `nil`；对象存在时为非 nil，即使两个子字段都是零，也不回退扁平 `cache_creation_input_tokens`。Codex/OpenCode 构造的扁平 usage 明确传 `nil`。
- OpenCode `tokens.input/output/reasoning/cache.read/cache.write/total` 缺失或不是非负 JSON 整数时均按零解码，坏类型的子对象/cost 不令整行失败。若 `total` 大于已知 input + output + cache read + cache write，差额按 ccusage 的 `extra_total_tokens` 规则以 output rate 计价；TokenWatch 统一 token model 没有独立 extra 维度，因此将差额并入 billable output，保持金额和汇总一致。
- Codex 先将 `cached_input_tokens` 限制为 `0...input_tokens`，再计算 pure input；不得保留超过 raw input 的 cache read，避免多计价和误入长上下文档位。

### Claude daily 行形状与过滤

为使最终 daily 金额与 ccusage `v20.0.16` 一致，Claude 解析同时接受顶层 direct usage 行和 `data.message` AgentProgress 包装行，并先归一化为同一 candidate。`message.id/model/sessionId/requestId` 为 optional：缺失不会丢掉 usage，但显式空字符串会被过滤；显式 `version` 必须具有合法 semver 前缀。缺失 message id 的 candidate 使用文件路径与行起始 offset 合成稳定的仅本地 identity，只用于 TokenWatch 数据结构，不参与 Claude exact/sidechain 去重。

行选择还要保留 pinned adapter 的 raw bytes 契约：只解码含精确 `"usage":{` marker 的行，并在 JSON 解码前执行 compact null-field guard。使用独立 billing DTO，token 只接受非负整数，speed 只接受 standard/fast，timestamp 只接受 pinned 的无小数或 3 位毫秒格式；role/content 等无关字段的坏类型不得使 billing row 失败。scanner 在进入单遍去重前按 standardized full path 排序。

### Claude sidechain-aware 去重

`ParsedUsageEntry` 增加记录级 `isSidechain`（其他 provider 默认为 false），Claude 从归一化 usage 行传播；per-file cache 保存尚未全局去重的 entry candidates，不能把文件级 `isSubagent` 当作 sidechain。`UsageEntriesFingerprint` 与测试 deep snapshot 同步包含该字段。

去重按 ccusage daily adapter 的单遍索引算法执行：每条 candidate 先用结构化 `(messageId, requestId)` 做 exact lookup，miss 后才在同 `messageId` 的 index 中寻找任一侧 `isSidechain == true` 的 replay。不使用字符串拼接 key，避免 ID 中的分隔符造成边界碰撞。无论由哪一种 lookup 找到 duplicate，都使用同一 replacement 顺序：

1. parent（非 sidechain）优先；
2. 同类再比较 magnitude；
3. magnitude 平局时按默认 Auto 模式比较 resolved cost，较大者优先；
4. cost 仍平局时优先带 `speed`。

magnitude 与 ccusage 的 `cache_creation_token_count()` 一致：input + output + cache read + cache creation；cache creation 对象存在时使用 5m/1h breakdown 之和，否则使用扁平 `cache_creation_input_tokens`，不加入 reasoning。

两个都不是 sidechain、requestId 不同的记录继续保留为两条。

为锁定 pinned daily adapter 的可观察结果，sidechain fallback 发生 replacement 时不为新 requestId 补建 exact index；回归 fixture 覆盖 `sidechain(m,r1) → parent(m,r2) → duplicate parent(m,r2)` 这一边界序列。这是与 ccusage `v20.0.16 daily.rs` 的结果兼容要求，不将其“优化”为两阶段全局合并。

### Codex event 与跨文件去重

Codex 与 ccusage 一样始终优先使用非空 `last_token_usage`；只在它缺失时才用 `total_token_usage - previousTotals`。不因 total 与上一条相同就自定义抑制非零 last usage，否则最终金额会与 pinned ccusage 不同。

rollout timestamp 同时接受 RFC3339 字符串、Unix 秒和毫秒数字，规范为毫秒 key；session token_count 缺/空/无效 timestamp 直接跳过。model 在 payload 和 info 内都按 `model → model_name → metadata.model` 取 trim 后首个非空值，且只在非零 usage guard 之后更新 model state。usage 数值用 lossy unsigned alias decoder，`total_tokens` 按 upstream 规则归一化。

所有文件解析完成后，按 `(timestamp, model, input, cached, output, reasoning, total)` 做结构化的 first-wins 全局去重，不包含 session ID，以消除复制或分支会话历史。replay session/path 的同秒首段还要按 upstream 专用规则跳过，但用其 total 更新 `previousTotals`，避免后续 delta 放大。

### OpenCode 损坏 JSON

SQL 使用 `json_valid(m.data)` 保护 `json_extract`。单条 malformed JSON 被跳过，其他合法 assistant 行继续返回。

### 瞬时文件失败

首次从未成功解析的坏文件继续跳过。scanner 已返回某个 `fileInfo`，但随后 open/fstat/seek/read 失败且该 cache key 已有上次成功结果时，复用 last-good candidates 并记录 warning，避免部分列表覆盖完整统计。metadata 必须由已打开的同一 descriptor `fstat` 获取，避免“旧 stat + atomic replace 后新 stream”。Codex last-good 只能在 pricing speed 相同时复用。scanner 未返回的文件仍按真实删除处理并 prune；本轮不引入 tombstone 或 grace period。Claude 与 Codex 共享一个只负责 per-file last-good 编排的最小泛型 helper，provider-specific candidate、解析状态与业务去重继续各自维护，避免复制两套同构循环。

### Bookmark 保存结果

bookmark data 创建器与 bookmark store 都作为依赖注入。生产 store 写入 `UserDefaults` 后读取同一 key 验证数据一致，并以 Bool 返回持久化结果；测试 store 可确定性模拟写入失败。创建或保存失败时：

- open panel 流程返回 `nil`；
- ViewModel 不标记授权成功；
- 记录一次明确错误日志；
- 不触发基于不存在 bookmark 的刷新。

## 三、增量 JSONL 解析

### 公共文件状态

缓存记录：文件身份、文件大小、最后成功修改时间、committed offset、截至该 offset 的 stable raw entry candidates，以及 provisional EOF tail 和它临时解码出的 candidates。缓存不能只保存最终去重 entries，因为后续追加的 parent、更大 magnitude 或带 speed 的 duplicate 可能替换旧 candidate；每次返回前都对全部 stable + provisional candidates 重新做全局去重，或维护语义等价的可更新索引。

- identity、size、mtime 全部相同：直接复用缓存，读取 0 字节。
- identity 相同且 size 增长：从 committed offset 读取 tail + suffix。
- identity 相同但 size 缩小，或 size 相同但 mtime 改变：全量重建缓存。
- identity 改变、无法验证或其他状态不一致：全量重建缓存。
- 只有以换行结束的字节范围才进入 stable candidates 并推进 committed offset。
- EOF 中没有换行的片段作为 provisional tail：若它已经是完整 JSON，则临时计入本次返回结果；若尚不完整则不计入。两种情况都不推进 offset。
- 下一次扫描从 tail 起点重读，并用新结果替换上一轮 provisional entries，避免续写时丢失或重复记录。
- 为识别“同 inode 先 truncate、再在两次扫描之间重写为更大文件”，state 保存 committed prefix 末尾的有界 continuity anchor。size 增长时先重读并校验该 anchor；不匹配立即从 0 重建，匹配才从 committed offset 读 tail + suffix。

### Claude 状态

Claude 每行独立，只需保存 stable raw entries（包含 `isSidechain`）、committed offset 与 provisional tail/candidate。

### Codex 状态

Codex 还需在已提交 offset 保存：

- 当前 resolved model 与 `explicit / fallback` source；
- session ID、cwd；
- previous total usage。
- replay classification/skip state；
- 尚未做 loader first-wins 的 `CodexUsageCandidate`，包含 source timestamp key、raw/clamped token 与 total。

追加解析从该状态恢复，保证后续 delta 与模型归属和全量解析一致。Codex 的 pricing 模式状态只写入并比较 `serviceTier`；`ParsedUsageEntry.speed` 继续保持空值，不复制 Claude 的 `usage.speed` 语义。

### 失败与回退

- scanner 已返回文件但 stat/seek/read 失败时返回该文件的 last-good cache；从未成功读取过则保持现有跳过行为。
- 截断、替换和无法验证的文件身份触发一次全量解析。
- 全量解析成功后原子替换缓存；失败不破坏旧缓存。

## 四、UI、辅助功能与系统状态

### 会话表水平访问

固定列宽继续保留。表格区域增加独立水平 `NSScrollView`，document/table 最小宽度为 1108pt；页面其他区块仍跟随外层垂直滚动。

### 键盘操作

移除 `DashboardNavigationButton`、`DashboardRangeButton`、`DashboardSessionButton` 永久拒绝 first responder 的实现，恢复键盘聚焦和 focus ring。主窗口根视图显式接受 first responder，窗口启动时把它设为真实初始焦点，避免自动选中操作按钮，而不是禁用按钮的键盘能力；测试必须验证 `window.firstResponder` 的实际结果，而不只检查 `initialFirstResponder` 属性。

### Accessibility

- 设置页 popup、switch、授权和刷新操作在每次语言刷新时设置可读 label。
- 热力图日期单元是 `.staticText` accessibility element；label 使用当前 App 语言格式化的日期，value 使用带本地化 token 语义的文案，而不是只有 ISO 日期或缩写数字。
- placeholder 不进入 accessibility 树。
- 窗口标题设为 `TokenWatch`，同时使用 `titleVisibility = .hidden` 保持视觉隐藏。

### Login Item 状态

`LoginItemSettingsControlling` 从 Bool 提升为 `notRegistered / enabled / requiresApproval / unavailable`，分别映射 `SMAppService.Status` 的 `notRegistered / enabled / requiresApproval / notFound`：

- notRegistered：switch off；切换到 on 执行 register。
- enabled：switch on；切换到 off 执行 unregister。
- requiresApproval：switch on，显示本地化待批准说明和独立“打开系统设置”操作；该操作不重复 register，切换到 off 仍执行 unregister。
- unavailable：switch off 且 disabled，显示本地化错误说明，不调用 register/unregister。
- 设置页监听 `NSApplication.didBecomeActiveNotification` 并重新读取状态，确保用户从系统设置批准或移除后立即刷新。

### 数字格式

- 状态栏使用的 `format` 保持现有契约：零为 `0`，`1...999` 为整数，`1_000..<1_000_000` 为一位小数 `k`，`1_000_000` 起为一位小数 `M`。
- Dashboard 使用的 `formatMillions` 与 `formatHoverTokens`：零为 `0.0M`，`1...999` 为整数，`1_000...99_999` 为一位小数 `k`，`100_000` 起为一位小数 `M`。
- 小数继续向下截断；任意正数不得格式化为零。

### 外观测试隔离

`settingsPageReappliesLightColorsWhenOpenedAfterAppearanceOverride` 显式注入未授权状态，不再读取用户真实 `HomeDirectoryBookmark`。生产外观代码不为测试添加分支，并另测已授权按钮的中性色状态。

## 实施阶段

1. **计价 parity**：Auto、模型查找、cache 默认、Claude/Codex 两类 tier、fast、fallback 与固定金额 fixture；在 Pricing Task 3 首次使用 `cacheCreation: nil` 之前，先执行数据正确性计划的 Task 1，使 `TokenUsage.cacheCreation` 的 optional 契约成为已验证前置条件。
2. **数据正确性与授权**：跳过已在上一阶段完成的 Task 1，再执行 DST、sidechain、Codex 防重、OpenCode、last-good cache 与 bookmark。
3. **增量解析**：Claude 与 Codex append/truncate/replace/state restore。
4. **UI 与辅助功能**：水平滚动、键盘、accessibility、窗口标题、Login Item、数字格式与 flaky test。

每阶段都必须先通过定向测试和任务级 review，再进入下一阶段。

## 验证标准

1. 每个问题都有先失败后通过的最小回归测试。
2. ccusage parity fixture 全部在 `1e-9` 或明确的浮点容差内一致。
3. Claude 与 Codex 增量结果和全量重扫结果按 stable key 排序后做 deep snapshot 比较；snapshot 覆盖 model、timestamp、全部 token、speed、sidechain、upstream cost 等业务字段，不能使用只比较 `dedupKey` 的 `ParsedUsageEntry.==`。
4. DST 春秋转换日都稳定生成 24 个唯一墙上时钟桶。
5. 通过可注入 reader 或 debug read metrics 验证：unchanged 文件读取 0 字节；append 只额外读取有界 continuity anchor 与 tail + suffix，并从 committed offset 开始解析新 candidate；测试不能仅比较最终结果。
6. 一条坏 OpenCode JSON、scanner 已发现但随后暂时不可读的文件，或一次 bookmark 创建/保存失败，不会产生错误成功状态或统计骤减。
7. 默认窗口可通过水平滚动访问会话表所有列，主要操作可键盘聚焦。
8. 设置控件、热力图和窗口具备本地化 accessibility 语义。
9. 完整单元测试与 UI 测试通过。
10. Debug、Release、Universal `arm64 + x86_64` 构建与 `xcodebuild analyze` 通过。
11. Release 无签名继续视为已确认设计，不作为失败。
12. 单个 Swift Testing 用例的 `xcodebuild -only-testing` 必须使用枚举出的完整 identifier，保留结尾 `()` 并用 shell 引号保护；验证结果不得接受“命令成功但实际执行 0 个测试”。
