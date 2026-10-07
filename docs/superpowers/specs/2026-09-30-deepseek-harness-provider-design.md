# DeepSeek Harness（DSH）用量统计接入可行性调研

> 调研日期：2026-09-30
> 调研对象：DeepSeek Harness Desktop（`com.deepseek.dsh`，`/Applications/DeepSeek Harness.app`）
> 目标：评估 TokenWatch 能否新增 `deepseek-harness` provider，与现有 Claude / Codex / opencode / Antigravity 并列

---

## 1. 结论摘要

**可行，且日志中的数据完备度不低于现有 4 个 provider。**

DSH 的会话日志里存在**逐条（per-request）的真实用量记录**，字段包含 `inputTokens`（未命中缓存的输入）、`outputTokens`、`cacheReadTokens`、可选的 `cacheWriteTokens` / `reasoningTokens`，并同时带有 **model、provider、turn、step、毫秒时间戳、消息 UUID**——这正好覆盖 TokenWatch 聚合层所需的全部分组维度（按模型、按小时、按项目、按会话、按子代理）。

但存在 **1 个硬性技术门槛和 1 个数据缺口**：

| 类别 | 问题 | 影响 | 可解性 |
|---|---|---|---|
| **硬门槛** | 会话日志默认使用 **zstd** 压缩；macOS 系统**既没有 libzstd，Compression/Foundation 也不支持 zstd** | 不引入 zstd 解码器就无法读取逐条用量 | 可解：内置 zstd 解码源码，或让用户改 DSH 配置 |
| **数据缺口** | TokenWatch 内置定价目录（LiteLLM 401 条 + models.dev 226 条）**完全没有 DeepSeek 条目** | 费用显示 $0.00 | 可解：DSH 自身捆绑了 pi-ai 定价目录（39 个 provider，含 `deepseek`），可直接读取 |
| 次要 | `session_projcache`（未压缩 JSON）**只有会话级汇总**，无模型/时间维度 | 只能做降级方案 | — |

**推荐路线**：内置 zstd 解码（方案 A），完整读取 `session.vN.jsonl.zstd`，映射到 `ParsedUsageEntry`。

---

## 2. 数据源勘察

### 2.1 数据根

```
DSH_HOME = ~/.dsh            # 环境变量 DSH_HOME，默认 ~/.dsh
├── sessions/                # 会话日志根（dsh-session-persistence-jsonl 的 root）
├── storages/                # 投影缓存根（dsh-session-projection-cache 的 root）
├── profiles/                # profile 配置
├── .credentials.yaml
```

证据（DSH 出厂 base profile 配置，`base.cordis.patch.yml`）：

```yaml
- id: session-persistence-jsonl
  name: '@deepseek-ai/dsh-session-persistence-jsonl'
  config:
    root: !!js dshHomePath('sessions')      # → ~/.dsh/sessions

- id: session-projection-cache
  name: '@deepseek-ai/dsh-session-projection-cache'
  config:
    writeEveryEvents: 200
    writeIntervalMs: 5000
```

> 注意：`~/Library/Application Support/@deepseek-ai/dsh-desktop/` 只是 Electron 的 Chromium 缓存（GPUCache / Session Storage / blob_storage），**与用量无关**，不要作为数据源。

### 2.2 会话日志目录布局

```
~/.dsh/sessions/
  --<normalized-cwd>--/            # 可读的项目目录（无 cwd 时为 _no-cwd/）
    <escaped-session-id>/
      session.jsonl.zstd           # v0 世代（历史）
      session.v3.jsonl.zstd        # v3 世代（历史）
      session.v4.jsonl.zstd        # v4 世代（当前）
      session.lock                 # flock 写锁
```

- 目录名由 cwd 归一化而来（`/`、`\`、`:` → `-`，不安全字符转义为 `~XXXX`，长度上限 251 字符；无 cwd 时为 `_no-cwd`）。
- 会话目录名是 session id 的**单段转义**（`encodeSegment()`）：父会话形如 `session-<uuid>`，子代理形如裸 `<uuid>`。**不要假设前缀一定是 `session-`**。
- 一个会话目录内可能**同时存在多个世代文件**（v0 / v3 / v4 并存，见实测）。
- 世代文件名的规范正则（`dsh-session-format/lib/index.js`）：

  ```js
  /^session(?:\.v([1-9][0-9]*))?\.jsonl$/u     // v0 == 无标签的 session.jsonl；`.v0` 不是规范名
  ```

### 2.3 ⚠️ 重复计数陷阱：世代文件

实测 `~/.dsh/sessions/--...-miaodong--/session-847cc202-.../` 同时存在：

| 文件 | 首行 version | assistant/message 用量条数 |
|---|---|---|
| `session.jsonl.zstd` | 0 | 4 |
| `session.v3.jsonl.zstd` | 3 | 4 |

**两个文件是同一会话的两种编码，内容等价。** 若扫描时 glob 成 `*.jsonl.zstd` 并全部解析，用量会**翻倍**。

DSH 自身的规则（`lib/index.js` → `resolveGenerationInDirectory`）：

> `/** Select the numerically highest canonical generation in one Session directory. */`

**外部读取器必须复刻该规则：每个会话目录只取 version 数值最高的那一个 `session.vN.jsonl(.zstd)`。**

文件名规则（`dsh-session-format/lib/index.js`）：

```js
function sessionFormatLogFilename(version) {
    const generation = sessionFormatVersion(version, "Session log generation version");
    return generation === 0 ? "session.jsonl" : `session.v${generation}.jsonl`;
}
```

即 v0 → `session.jsonl`，vN（N≥1）→ `session.vN.jsonl`。

### 2.4 物理编码：多帧 zstd（可增量解码）

DSH 使用 **Node 内置 `node:zlib` 的 Zstandard API**（`createZstdCompress` / `zstdDecompressSync`），**没有 bundle 任何第三方 JS zstd 库**，因此没有可供复用的现成实现。

编码为**独立帧的拼接流**：

> 「one checksummed frame containing only the header line, then one checksummed frame per durable append batch, using Node's built-in Zstandard API at its default compression level」——`dsh-session-persistence-jsonl/README.md`

实测（`zstd -lv`）：

```
session.v4.jsonl.zstd
# Zstandard Frames: 121
DictID: 0
Window Size: 2.00 MiB
Check: XXH64
```

**关键推论**：帧与写入批次一一对应、且历史上「Committed events are never rewritten」，因此

- 每个帧可独立解压 → **可以按字节偏移做增量解析**，不必每次重解整文件；
- 但必须按 `(路径, inode, size, mtime)` 做缓存键，因为**格式迁移会发布新世代文件**（旧世代保留、不覆盖），沿用现有 `IncrementalJSONLFileState` 的思路即可。

DSH 自己的帧扫描器 `scanZstdFrames` 也印证了这一点：它在不解压 block 的前提下按 magic(`0xFD2FB528`, LE `28 B5 2F FD`) 逐个切帧，并允许「尾部不完整帧」（崩溃恢复场景）。

### 2.5 事件格式与版本

- 当前 `SESSION_FORMAT_VERSION = 4`（`dsh-session-format-catalog`：`currentVersion: 4`，codec v0–v4，相邻迁移 v0→v1→v2→v3→v4）。
- 实测本机存在 v0 / v3 / v4 三种日志。
- 每行一个 `SessionEvent`：`{"type": ..., "seq": <int>, "time": <epoch ms>, "data": {...}}`。
- 首行为 session header。

**v4 header 实测**（父会话与子代理会话）：

```json
{"type":"session","version":4,"id":"session-e37d6e25-...","createdAt":1790757477847,
 "cwd":"/Users/orrhsiao/Desktop/Code/TokenWatch","isSeeded":false,
 "delegationDepth":0,"agentPreset":"standard"}

{"type":"session","version":4,"id":"18ded2c6-fefe-42cc-96ad-62c8c694e56f",
 "createdAt":1790757606879,"cwd":"/Users/orrhsiao/Desktop/Code/TokenWatch",
 "parentSession":"session-e37d6e25-...","isSeeded":false,"origin":"subagent",
 "delegationDepth":1,"agentPreset":"standard"}
```

Header 字段白名单（`HEADER_KEYS`）：必填 `type/version/id/createdAt/isSeeded/delegationDepth`，可选 `cwd/parentSession/origin/agentPreset`。

**v0 header 差异**：v0 没有 `isSeeded`，也**没有 `totalTokens` 字段**（见 2.7）。

**事件序号不变量（可直接用于自校验）**：`seq` 从 0 开始、**严格稠密**（第 i 个事件的 `seq == i`）。DSH 自身以此做格式断言：

```js
if (event.seq !== index) throw new SessionFormatError(`format v4 event ${index} is not dense`);
```

本机全部 8 个日志文件（1×v0 + 4×v3 + 3×v4）实测均满足该不变量。外部分析器可据此校验解析正确性，并按 `seq` 做切片。

**事件字段**：必填 `type/seq/time/data`。

### 2.6 逐条用量事件（核心发现）

用量挂在**三类**事件上（`dsh-llm/lib/typert.host.js` 的 `SessionEventMap`）：

| 事件类型 | 载量字段 | 说明 |
|---|---|---|
| `assistant/message` | `data.usage?: TokenUsage` + `data.stream` | 主路径，durable 结算 |
| `assistant/attempt` | 仅 `data.stream`（无 `data.usage`） | **必须从 stream 里取最后一个 usage chunk** |
| `compaction/summary` | `data.usage?: TokenUsage` + `shadowedTokenCount` | 压缩摘要本身也是一次计费调用 |

DSH 官方的取样函数（`dsh-token-meter/lib/types/usage-projection.js`）：

```js
function usageOf(event) {
    if (event.type === 'assistant/message' && event.data.usage !== undefined) return event.data.usage;
    if (event.type !== 'assistant/message' && event.type !== 'assistant/attempt') return undefined;
    return lastAssistantStreamChunk(event.data.stream, 'usage')?.usage;
}
```

> ⚠️ **只扫 `assistant/message` 会漏掉失败/重试/中断的计费尝试**（它们只以 `assistant/attempt` 形式存在）。

**版本差异（实测）**：

| 世代 | `assistant/message` 的 keys | usage 位置 |
|---|---|---|
| v0 | `message / step / turn / usage`（**无 `stream`**） | 只能读 `data.usage` |
| v3 / v4 | `message / step / stream / turn / usage` | `data.usage`，缺失时回退到 `stream` 末尾 usage chunk |

即「stream 内取最后一个 usage chunk」这条回退路径**只对 v3/v4 有意义**；v0 的流式分片是顶层事件（`assistant/chunk` / `text-chunks` / `reasoning-chunks`），不参与取样。

`TokenUsage` 的权威类型声明（`dsh-llm/lib/typert.host.js`）：

```ts
export interface TokenUsage {
  inputTokens: number;
  outputTokens: number;
  totalTokens?: number;
  cacheReadTokens?: number;
  cacheWriteTokens?: number;
  reasoningTokens?: number;   // 见 2.7：仅旧版本日志出现
}
```

v4 实测样例：

```json
{"type":"assistant/message","seq":24,"time":1790757531540,
 "data":{"turn":1,"step":1,
   "message":{"role":"assistant","content":[...],
     "source":{"kind":"model","provider":"opencode-go","model":"deepseek-v4.1-flash",
               "replayState":{"response":{...,"responseId":"0217907575295209f6cd..."}}},
     "id":"178b99e9-ee6c-402e-a30b-da2cdbdb67eb"},
   "usage":{"inputTokens":888,"outputTokens":111,"totalTokens":27111,"cacheReadTokens":26112},
   "stream":[{"type":"chunk","time":...,"chunk":{"type":"usage","usage":{...}}}, ...]}}
```

可直接取用的字段：

| 目标 | 来源 |
|---|---|
| 时间戳 | `data.time`（epoch **毫秒**） |
| 模型 | `data.message.source.model` |
| 上游 route | `data.message.source.provider` |
| 消息 ID（dedup 用） | `data.message.id`（UUID） |
| 归属 | `data.turn` + `data.step` |
| 用量 | `data.usage` |

**注意**：`data.stream` 里还嵌着流式 `{"type":"usage"}` chunk（一次 message 可能有多个）。DSH 官方口径是**优先 `data.usage`，缺失时取 stream 中最后一个 usage chunk**（`usageOf()`）；外部读取器必须照此实现，不能累加 stream 里的 usage chunk。

### 2.7 用量字段语义

DSH 官方换算（`dsh-token-meter/lib/types/usage-projection.js`）：

```js
const bucketsFrom = (usage) => ({
    uncachedInputTokens: usage.inputTokens,
    outputTokens: usage.outputTokens,
    cacheReadTokens: usage.cacheReadTokens ?? 0,
    cacheWriteTokens: usage.cacheWriteTokens ?? 0,
});
```

| DSH 字段 | 语义 | 是否必填 |
|---|---|---|
| `inputTokens` | **未命中缓存的输入**（uncached input），不是 prompt 总量 | 是 |
| `outputTokens` | 输出（**已包含 reasoning**） | 是 |
| `cacheReadTokens` | 缓存读取 | 否，缺省 0 |
| `cacheWriteTokens` | 缓存写入 | 否，缺省 0 |
| `reasoningTokens` | 思考 token，**⊆ outputTokens**；**当前版本已不再产出** | 否 |
| `totalTokens` | 适配器自定义，**不是统一公式** | 否 |

**`reasoningTokens` 的准确状态（易误判）**：

- **当前构建（app.asar @ 2026-09-29）不产出该字段**。DeepSeek 适配器的 `updateUsage()` 只映射 4 个 wire 字段：

  ```js
  for (const [wire, local] of Object.entries({
      input_tokens: "inputTokens",
      output_tokens: "outputTokens",
      cache_read_input_tokens: "cacheReadTokens",
      cache_creation_input_tokens: "cacheWriteTokens"
  })) { ... }
  ```

  pi-ai route 则明确「reasoning folded into output by pi-ai」。全 asar 中 `reasoningTokens` 只出现在 **类型声明 / 校验器 / UI 聚合器**（`dsh-client-ui-chat`、`dsh-client-ui-trajectory`、`dsh-headless`、`dsh-token-meter`），**没有一处赋值**。
- **但历史日志里确实存在**：本机 v0 会话（`session-847cc202`，2026-08-13）与 v3 会话（`session-f0baeeae`，2026-09-10）**共 31 条记录带 `reasoningTokens`**，均满足 `reasoningTokens <= outputTokens`。

→ 结论：**读取器要容忍该字段，但不应把它当作稳定维度**；`hasReasoningDimension` 建议取 `false`（对齐当前版本，见 3.2）。

**`totalTokens` 不可信**：`dsh-llm-deepseek` 自己算 `input+output+cacheRead+cacheWrite`，而 `dsh-llm-pi-ai` 把上游 SDK 的 `totalTokens` **原样透传**。实测虽恰好满足 `input+output+cacheRead == totalTokens`（v3/v4 全 33 条），但**应当自行重算，不要采信该字段**。

实测校验（本机有数据的 4 个会话）：

- `input + output + cacheRead == totalTokens` 对 v3/v4 **恒成立**（仅供交叉验证）；
- `reasoningTokens <= outputTokens` **恒成立**，且 `totalTokens` **不额外加 reasoning**；
- v0 世代无 `totalTokens`，其余字段同构。

> **结论：`reasoningTokens` 是展示维度（且在旧日志中才是证据），绝不能二次计入总量**——与 TokenWatch 现有 `TokenUsage.aggregateTotalTokens` 的既有约定完全一致。

### 2.8 ⚠️ 重复计数陷阱：同 (turn, step) 的替换与重试

DSH 的官方折叠规则（`usage-projection.js` → `tokenUsageProjectionDefinition.apply`）：

```js
if (event.type === 'llm/retry-started') {
    // 关闭该 (turn, step) 的替换槽位：重试后的新样本将「累加」而非「替换」
    return state.last?.turn === event.data.turn && state.last.step === event.data.step
        ? { ...state, last: null } : state;
}
// 仅 assistant/message / assistant/attempt 参与
const previous = state.last !== null && state.last.turn === turn && state.last.step === step
    ? state.last.buckets : undefined;
if (previous !== undefined && bucketsEqual(previous, buckets)) return state; // 完全相同的重复样本去重
return { totals: addReplacing(state.totals, previous, buckets), last: { turn, step, buckets } };
```

含义：

- 同一 `(turn, step)` 内后到的样本**替换**先到的（`totals - previous + next`）；
- `llm/retry-started` 会**清空替换槽位**，因此**重试产生的是额外计费尝试，应各计一次**；
- 完全相同的重复样本按幂等去重。

**外部分析器必须按 `seq` 顺序回放这套状态机**，否则重试场景会多计或漏计。

dedup key 建议：`<sessionId>:<turn>:<step>:<attemptIndex>`，其中 `attemptIndex` 由 `llm/retry-started` 出现次数推导；`data.message.id` 可作为校验用辅助键。

### 2.9 子代理（subagent）会话

**子代理是独立的会话目录**，与父会话并列在同一个 `--<cwd>--/` 下，带 `origin: "subagent"`、`parentSession`、`delegationDepth: 1`。

本次调研期间正好产生了一个真实子代理会话（43 步、204 KB 压缩、43 条 `assistant/message` 用量），可在本机复核：

```
~/.dsh/sessions/--Users-orrhsiao-Desktop-Code-TokenWatch--/18ded2c6-fefe-42cc-96ad-62c8c694e56f/session.v4.jsonl.zstd
```

**这既是好消息也是坑**：

- ✅ 只要遍历全部会话目录，子代理用量**自然被包含**，不会漏计（DSH 会话动辄 40+ 步，漏掉子代理会显著低估）；且父会话日志里只有一条 `subagent/catalog` 描述行、**不含子代理的 usage**，因此不存在父子重复计数；
- ⚠️ 但 **fork 型子代理**（`dsh-subagent-fork-in-process`）会产生 `isSeeded: true` 的子会话，其日志**物理上包含父会话事件前缀**（`Session.inheritedEventCount`：*"Number of leading events inherited from this Session's fork parent"*）。**读取器必须跳过这段继承前缀，否则父会话用量会被重复计入。**

⚠️ **实现细节更正（易踩坑）**：继承前缀长度**并不写在 header JSON 里**。`encodeHeader(header, inheritedEventCount)` 只把 cut 用于一致性断言：

```js
if (!header.isSeeded && cut !== 0) throw new SessionFormatError("unseeded format v2 Session has inherited events");
// 返回的 header 对象只含 type/version/id/createdAt/cwd/parentSession/isSeeded/origin/delegationDepth/agentPreset
```

真正的 cut 由**日志中最后一个 `data.inherited === true` 的 `session/end-seed` 事件**界定：

```js
if (event.type === "session/end-seed" && event.data["inherited"] === true) lastInheritedMarker = index;
if (artifact.header.isSeeded && lastInheritedMarker !== cut) throw new SessionFormatError("format v4 seeded header disagrees with its last inherited end-seed marker");
if (!artifact.header.isSeeded && lastInheritedMarker !== void 0) throw new SessionFormatError("format v4 unseeded Session contains an inherited end-seed marker");
```

> **注意区分**：本机在 `isSeeded: false` 的会话里也观察到了 `session/end-seed`，但其 `data` 是 `{}`（没有 `inherited: true`）。这类标记表示「初始 seed 阶段结束」，**不是** fork 继承标记，不能用来算 cut。

因此读取逻辑为：`isSeeded == false` → cut = 0；`isSeeded == true` → cut = 最后一个 `data.inherited == true` 的 `session/end-seed` 事件的下标。

本机全部会话 `isSeeded: false`，该分支**未被实测覆盖**；建议首次遇到真实 fork 会话时，用 2.11 的 projcache 对账法**实测确定前缀边界是闭区间还是开区间**（校验器用的是 `lastInheritedMarker !== cut`，与「count」的语义存在一处需要实测确认的偏移）。

### 2.10 备用数据源：`session_projcache`（未压缩，但粒度粗）

```
~/.dsh/storages/session_projcache/sessions/session-<id>.json   # ← 权威：per-record 布局，每会话一份（version 7）
~/.dsh/storages/session_projcache.json                          # ← 遗留：single 布局残留，可能严重过期，不要读
~/.dsh/storages/session_projcache/sessions/<id>.json.bak.<stamp># ← 坏记录备份（invalidRecords: backup-and-skip）
```

> **位置纠正**：权威数据在 **per-record 树** `session_projcache/sessions/`，不在 `session_projcache.json`。后者是 `single` 布局时代的遗留文件（本机 mtime 2026-08-13，只含 1 个会话；而 per-record 树有 7 份、mtime 2026-09-30）。扫描时必须只读 `sessions/*.json` 并**排除 `.bak.*`**。

`record.rows.tokenUsage.val.totals` 即会话级累计：

```json
"tokenUsage": {"ver":2,"seq":85,"val":{
  "totals":{"uncachedInputTokens":14810,"outputTokens":1673,
            "cacheReadTokens":252160,"cacheWriteTokens":0},
  "last":{"turn":1,"step":8,"buckets":{...}}}}
```

**优点**：纯 JSON，零依赖，沙盒内可直接 `Data(contentsOf:)`。
**缺点（决定性的）**：

- 只有**会话级累计**，没有逐条记录；
- 只有 `modelSelection.lastUsed` 的**单个模型**，无法做多模型拆分；
- 没有逐条时间戳，无法做小时桶 / 燃尽率 / 趋势图；
- 是**投影缓存**（`writeEveryEvents: 200` / `writeIntervalMs: 5000`），与日志**不保证同步**：实测本会话在运行中时，projcache 的 totals 既可能落后（42014 vs JSONL 43893），也可能略领先（它采样的是 live fold）。**日志才是真相，projcache 只是加速器**；
- 每行带 `ver`，且不同版本日志的同一行 `ver` 可能不同（v4 记录的 `contextPressure` 是 5、v3 记录是 4）→ 必须按 `row.ver` 门控，不能写死。

→ 仅适合做「降级模式」或**对账校验**，不能作为主数据源。

### 2.11 已完成的正确性对账

用「逐条事件按 2.8 状态机折叠」的结果与 DSH 自己的 projcache `totals` 对比：

| 会话 | 折叠结果 vs projcache totals |
|---|---|
| `session-8d883f81-…`（38 步，已结束） | **完全一致** ✅ input / output / cacheRead 三项全等 |
| `session-f0baeeae-…`（27 步，已结束） | **完全一致** ✅ |
| `session-847cc202-…`（4 步，已结束） | **完全一致** ✅ |
| `session-e37d6e25-…`（本调研会话，仍在运行） | 不一致（JSONL 更新，projcache 滞后）——符合预期 |

**这是接入可行性的最强证据：逐条解析口径与 DSH 自身口径可以做到逐 token 对齐。**

### 2.12 已知盲区：标题生成调用

`session/title-llm-request` 是**另一次独立计费的 LLM 调用**（会话标题生成）。本机观测到的标题走了 `source.kind: "fallback"`，日志中**没有伴随的 `assistant/message` / usage 行**，因此这部分 token 对纯 JSONL 读取器**可能是不可见的**。

→ 影响量级很小（标题 prompt 短、`maxTokens: 64`），但应在文档中如实说明，不要声称「100% 覆盖」。是否可从其他投影/遥测补全**未验证**。

---

## 3. 与 TokenWatch 现有架构的映射

### 3.1 架构契合度：高

现有 `UsageProvider` 协议 + `ProviderRegistry` 是纯注册表驱动，UI/ViewModel/Widget 全部自动感知。新增 provider 的标准动作：

1. `ProviderID` 增加 `case deepSeekHarness`（或用 `dsh`）；
2. 新建 `TokenWatch/Providers/DeepSeekHarness/`：`…Provider.swift` + `…Scanner.swift` + `…Parser.swift` + `…Record.swift`；
3. `ProviderRegistry.allProviders` 追加一行；
4. `AppStringKey` 增加 `deepSeekHarnessDataDirectoryOpenPanelMessage`；
5. 补定价、补测试。

`panel.showsHiddenFiles = true` 已存在（`SecurityScopedBookmarkManager`），`~/.dsh` 这类隐藏目录无需额外改动；`validateDataRoot` 可校验 `sessions/` 存在。

### 3.2 字段映射

| `ParsedUsageEntry` 字段 | DSH 来源 |
|---|---|
| `recordUUID` | `"<sessionId>:<turn>:<step>:<attemptIndex>"` |
| `messageId` | `data.message.id`（UUID） |
| `requestId` | `nil`（DSH 未记录 HTTP request-id） |
| `sessionID` | header `id` |
| `timestamp` | `event.time`（ms → Date） |
| `model` | `data.message.source.model` |
| `upstreamModelID` | 同 `model`（DSH 只有单一 route 模型名） |
| `cwd` | header `cwd` |
| `agentId` | `nil`（DSH 无此概念） |
| `usage.inputTokens` | `usage.inputTokens`（**已是 uncached**） |
| `usage.cacheReadInputTokens` | `usage.cacheReadTokens ?? 0` |
| `usage.cacheCreationInputTokens` | `usage.cacheWriteTokens ?? 0`（`cacheCreation = nil`，走扁平 5m 桶） |
| `usage.outputTokens` | `usage.outputTokens` |
| `usage.reasoningTokens` | `usage.reasoningTokens ?? 0`（**不叠加进总量**） |
| `isSubagent` | header `delegationDepth > 0` 或 `origin == "subagent"` |
| `isSidechain` | `false` |
| `hasSourceMessageID` | `true` |
| `upstreamProviderID` | `data.message.source.provider`（如 `opencode-go` / `deepseek-official`） |
| `upstreamCost` | `nil`（DSH 不记录费用） |

| provider 能力位 | 取值 | 理由 |
|---|---|---|
| `hasCacheWriteDimension` | `true` | DSH 的 wire 字段是 Anthropic 风格（`cache_creation_input_tokens`），能力上支持该维度；DeepSeek route 下恰好恒为 0，但接 Anthropic/Bedrock route 时非 0。**注意该标记当前无任何生产消费者**，见 3.4 |
| `hasReasoningDimension` | `true` | 历史日志（v0/v3）确有 `reasoningTokens`；当前构建不再产出，但 UI 实际按 `> 0` 门控，取 `true` 不会产生空行。同样无生产消费者，见 3.4 |

`loadEntriesWithCacheStatus` 建议实现为**增量**：持久化每个日志文件的 `(路径, size, mtime, inode)` + 每个会话的折叠状态，仅解压新增帧。这需要把 2.8 的替换状态机做成可序列化快照（否则无法只处理增量事件）。

**未来兼容**：DSH 的事件词汇表是**拒绝式**的——未知事件类型会导致解析失败，除非该行带 `ignorable: true`。外部分析器应当**跳过未知类型并记 debug 日志**，绝不能因未知类型而整体失败。

### 3.3 定价来源（比预想的好）

现有定价链路：`litellm_prices.json`(401) + `models-dev-pricing.json`(226) + `PricingTable.builtinPrices`（ccusage 移植）。

**实测：三处均无任何 DeepSeek 条目**（`grep -i deepseek` 命中 0）。

但 DSH 自身**捆绑了一份可直接读取的定价目录**（pi-ai 的 provider 数据，纯 JSON）：

```
~/.dsh/profiles/node_modules/@earendil-works/pi-ai/dist/providers/data/<provider>.json
```

```json
{ "<api>": { "<modelId>": { "id": …, "name": …, "api": …, "provider": …, "baseUrl": …,
                            "reasoning": …,
                            "cost": { "input": …, "output": …, "cacheRead": …, "cacheWrite": … },
                            "contextWindow": …, "maxTokens": … } } }
```

共 **39 个 provider**（`anthropic`、`deepseek`、`openai`、`opencode-go`、`openrouter`、`zai`、`amazon-bedrock`、`google` …）。

**这正好补上 R2**：TokenWatch 可以把该目录作为**追加的定价来源**（fallback 优先级最低，或按 route 精确命中），落在已授权的 `~/.dsh` 目录内，无需网络、无需手工录入。

需要注意：

- DSH **自身不记录任何费用**（`TokenUsage` 没有 cost 字段），费用必须本地计算；
- `cost` 的单位是否 USD/1M tokens **未验证**，接入前需抽样核对；
- 模型/route 字符串是**自由配置，不是受校验的枚举**：例如 `deepseek-v4.1-flash` 在 pi-ai 目录里**不存在**（目录里只有 `deepseek-v4-flash`、`deepseek-v4-pro`、`deepseek-v4-flash-vision-exp`），它只出现在用户自己的 `~/.dsh/profiles/desktop/cordis.patch.yml` → `agent-default-model.model`。**因此不能假设模型集合封闭**，必须有未知模型的兜底与日志；
- 建议定价键做成 `"<provider>/<model>"` 优先、`"<model>"` 兜底，正好可以用 `upstreamProviderID` 承载 route。

### 3.4 能力位已接线（原「死代码」问题已修复）

调研时发现 `hasCacheWriteDimension` / `hasReasoningDimension` 虽然写在协议里，但**没有任何生产消费者**——UI 实际按「数值 > 0」自行门控，且 cache read / write 被合并成一个数字展示。该问题已在本轮一并修复。

**接线后的渲染规则**：

| 维度 | 渲染条件 |
|---|---|
| 缓存读取 | 始终展示（各数据源通用维度） |
| 缓存写入 | `capabilities.hasCacheWrite` **且** `cacheCreationTokens > 0` |
| 思考 | `capabilities.hasReasoning` **且** `reasoningTokens > 0` |

两个条件缺一不可：能力位保证不为「协议外维度」造行，`> 0` 保证不出现恒为 0 的空行。

**聚合视图如何取值**：Dashboard 既可被数据源下拉框收窄到单个 provider，也可能汇总全部。因此能力位**按当前选中的数据源求并集**：

```swift
// DashboardViewController.render()：states 已按 selectedProviderFilter 收窄
let capabilities = ProviderRegistry.capabilities(for: states.keys)
```

语义是「任一被选中的 provider 声明支持即视为该维度可用」。单选 Claude → 只暴露缓存写入；单选 opencode → 只暴露思考；全选 → 两者都暴露。

**用户可见的变化**：

1. `缓存 0.7M` 拆成 `缓存读取 0.6M / 缓存写入 0.1M`（带缓存写入的数据源）。两者单价差异很大（缓存写入约为输入价的 1.25×，缓存读取仅约 0.1×），合并展示会丢失信息。
2. Claude / Codex 不再出现恒为 `$0.00` 的「推理」费用项——它们本就不产出该维度。
3. Codex / opencode / Antigravity 即便上游数据里出现 `cacheCreation`，也不会展示「缓存写入」。

**配套改动**：本地化 key `dashboardCache` 重命名为 `dashboardCacheRead`，并新增 `dashboardCacheWrite`，65 个 locale 全部补齐（key 总数 191 → 192，且写回顺序与 `AppStringKey.allCases` 保持一致）；English-reuse 白名单中 9 条针对旧 key 的记录随之移除。

**DSH 接入时的取值**：按语义取 `hasCacheWriteDimension = true`、`hasReasoningDimension = true`。前者因为 DSH 的 wire 字段是 Anthropic 风格（`cache_creation_input_tokens`），DeepSeek route 下恰好为 0、接 Anthropic/Bedrock route 时非 0；后者因为历史日志确有 reasoning 数据（见 2.7）。由于 `> 0` 门控的存在，取 `true` 不会为 DeepSeek route 留下空行。

**尚未改动的地方（有意为之）**：`formatCacheHitRate` 仍按 `(cacheRead + cacheWrite) / 全部 token` 计算。严格说缓存写入属于「未命中」，把它计入命中率分子并不严谨，但该口径是既有行为、改动会直接影响用户看到的百分比数字，因此不在本轮范围内。

---

## 4. 关键风险

### R1（阻塞级）zstd 解码依赖

实测结论：

```
$ xcrun clang /tmp/zt.c -lzstd -o /tmp/zt
ld: library 'zstd' not found            # SDK 无 stub

$ /tmp/dl                                      # dlopen 探测
/usr/lib/libzstd.1.dylib -> ... (no such file, not in dyld cache)
```

- macOS SDK 27 的 `compression.h` 只有 `LZ4 / ZLIB / LZMA / LZ4_RAW / BROTLI / LZFSE / LZBITMAP / LZRAVEN / LZMESH`——**没有 zstd**；
- Foundation `NSDataCompressionAlgorithm` 同样只有 LZFSE / LZ4 / LZMA / Zlib；
- 系统上**不存在** `libzstd`（连 dyld shared cache 里都没有）；
- 本项目**当前零第三方依赖、零 SPM 包**，且已开启 App Sandbox。

→ 不引入 zstd 解码能力，就无法读取 2.6 的逐条用量。

⚠️ **解码实现注意**：DSH 的日志是**多帧拼接**（concatenated frames），因此**一次性 `ZSTD_decompress()` 只会返回第一帧（即 header 那一行）**。Swift 侧必须用流式 API `ZSTD_decompressStream` 循环解帧，或自行按 magic 切帧后逐帧解压（DSH 的 `scanZstdFrames` 就是后者）。`ZSTD_c_checksumFlag` 是标准特性，任何合规解码器都能处理。

### R2 定价缺失（已找到解法，见 3.3）

不影响「能不能统计 token」，但默认会让费用列显示 $0.00。DSH 捆绑的 pi-ai 目录可直接作为定价来源，因此工作量从「手工录入」降为「接入一个本地 JSON + 校验单位」。

### R3 格式演进

DSH 处于快速迭代（本机同时存在 v0/v3/v4，且 `dsh-session-format-v3-to-v4` 是最近新增）。外部读取器必须：

- 以 `version` 字段做能力门控（> 已知最大版本时降级/跳过并记日志，而不是崩溃）；
- 只依赖本调研已确认稳定的事件契约（`assistant/message` 的 `usage` / `source.model` / `time` / `turn` / `step`），以及 `assistant/attempt` 的 **stream 末尾 usage chunk**；**不要依赖 `stream` 中除 usage chunk 之外的内部结构**（v0 用顶层 `assistant/chunk` / `text-chunks` 平铺，v4 改为内嵌 `stream` 数组，两者差异很大）。

### R4 全量扫描成本

会话日志是 append-only 且单会话可达数百 KB~MB 级（本次 43 步 = 204 KB 压缩）。全量解压所有历史会话在首次扫描时会明显偏慢。必须做增量 + 快照缓存（3.2 已述）。

### R5 沙盒与授权范围

`~/.dsh` 是单一目录即可覆盖 sessions + storages，授权体验与现有 provider 一致（一次 NSOpenPanel）。风险低。

---

## 5. 方案对比

| | 方案 A：内置 zstd 解码 | 方案 B：只读 `session_projcache` | 方案 C：引导用户改 `compression: 'none'` |
|---|---|---|---|
| 逐条用量 / 模型 / 小时桶 | ✅ 完整 | ❌ 仅会话级 | ✅ 完整 |
| 费用精度 | ✅ 按条计价 | ❌ 单模型假设 | ✅ |
| 新增依赖 | 需内置 zstd 解码源码（C） | 无 | 无 |
| 用户侧改动 | 无 | 无 | 需改 `~/.dsh/profiles/desktop/cordis.patch.yml`，且**需换新 root**（历史丢失） |
| 增量读取 | ✅ 多帧 zstd 天然支持 | ✅ | ✅ |
| 对账校验 | ✅ 与 projcache 逐 token 对齐 | — | ✅ |
| 结论 | **推荐** | 降级模式 / 校验用 | 不推荐作为主路径 |

方案 C 的可行性已由 DSH 自身背书——`compression` 是正式配置项（`DEFAULT_COMPRESSION = "zstd"`，schema 同时接受 `'none'`），且官方文档明确写道：

> 「Compressed files are not directly line-readable — use the backend to load them, or **select `compression: 'none'` before writing a fresh root when external line readers are required**.」

出厂 `dsh-sdk-minimal` profile 就是 `compression: none`（写纯文本 `session.vN.jsonl`）。但它**要求换一个全新 root**（`A root belongs to one encoding`，且不支持混合/降级），会丢掉全部历史，因此只适合作为「已经自己改了配置的高级用户」的兼容分支——**建议 A 方案同时兼容读取未压缩的 `session.vN.jsonl`**（同一套解析器，仅去掉解压步骤），成本极低。

**方案 A 中 zstd 的落地子选项：**

1. **内置 decode-only 单文件 C 源码**（zstd 官方 `build/single_file_libs/zstddeclib.c`，BSD-3-Clause，与 App Store 兼容）：加入 target + bridging header，零 SPM 依赖，可离线构建。**推荐**。
2. 引入 SPM 包（如 zstd 的 Swift wrapper）：改动最小，但会引入本项目第一个第三方依赖，需要评估供应链与体积。
3. 运行时 `dlopen`：**不可行**（系统无该库）。

---

## 6. 工作量拆解（方案 A）

| # | 工作项 | 说明 | 量级 |
|---|---|---|---|
| 1 | 引入 zstd 解码 | vendored `zstddeclib.c` + bridging header + 多帧拼接解压封装 + 单测 | M |
| 2 | `DeepSeekHarnessScanner` | 遍历 `sessions/--*--/<id>/`、挑选最高世代文件、解析 header、按 `session/end-seed{data.inherited:true}` 推导 fork 继承前缀并跳过、按帧增量读取 | L |
| 3 | `DeepSeekHarnessParser` | 2.8 的 (turn, step) 替换 + `llm/retry-started` 状态机；三类事件（含 `assistant/attempt` / `compaction/summary`）取样；字段映射（3.2） | M |
| 4 | 增量状态快照 | 复用 `IncrementalJSONLFileState` / `JSONLDiskCacheStore` 模式，缓存折叠状态 | M |
| 5 | Provider 装配 | `ProviderID` / `ProviderRegistry` / `validateDataRoot` / 能力位 | S |
| 6 | 定价 | 接入 DSH 捆绑的 pi-ai 定价目录 + route 维度键 + 未知模型兜底 + 单测 | M |
| 7 | 本地化 | 新增 `deepSeekHarnessDataDirectoryOpenPanelMessage`，需覆盖 **65** 个 `.lproj` | M（机械） |
| 8 | 测试 | Fixture（裁剪自真实 v0/v3/v4 日志）+ 世代选择 / 替换重试 / 子代理 / seed 前缀 / 损坏帧 等用例 | L |
| 9 | 文档 | README / 支持页文案更新 | S |

**建议里程碑**：
M1 = 1+2+3+5（能跑通、能出数）→ M2 = 4+6+8（增量 + 定价 + 测试）→ M3 = 7+9（本地化 + 文档）。

---

## 7. 验证方法（接入后）

1. **逐 token 对账**：对每个已结束会话，把 provider 折叠结果与 `~/.dsh/storages/session_projcache/sessions/<id>.json` 的 `rows.tokenUsage.val.totals` 四项比对，必须全等（2.11 已验证该方法可行）。注意排除 `.bak.*`，且仅对**已结束**会话做严格断言。
2. **世代去重**：构造含 v0+v3+v4 同存的 fixture，断言只统计一次。
3. **替换 / 重试**：构造含 `llm/retry-started` 的 fixture，断言重试计两次、同 (turn,step) 覆盖而非累加。
4. **子代理**：断言 `delegationDepth:1` 会话被计入且 `isSubagent == true`；构造 `isSeeded:true` + `session/end-seed{data:{inherited:true}}` fixture，断言父会话前缀被跳过。
5. **`assistant/attempt` 覆盖**：构造只有 `assistant/attempt`（usage 仅在 `stream` 里）的 fixture，断言不被漏计。
6. **版本门控 / 前向兼容**：构造 `version: 99` 的 header，断言降级跳过并记 warning 不崩溃；构造未知事件类型，断言跳过该行而非整体失败。
7. **解压多帧**：构造 >1 帧的 fixture，断言解出全部帧（防止一次性 API 只返回首帧的实现错误）。
8. **未压缩兼容**：构造 `compression: 'none'`（纯 `.jsonl`）的 fixture，断言同一解析器可读。

---

## 8. 待确认问题

1. ~~**`hasCacheWriteDimension` / `hasReasoningDimension` 的长期处置**~~：**已决策并落地**——选择「接到 UI」而非删除，同时新增独立的「缓存写入」行，详见 3.4。
2. **定价口径与单位**：pi-ai 目录的 `cost.*` 单位是否为 USD/1M tokens 需实测核对；`opencode-go` 这类第三方代理 route 是否要按目录价单独计价，还是统一按 DeepSeek 官方价。
3. **pi-ai 目录的稳定性**：它位于 `~/.dsh/profiles/node_modules/` 下，属于 profile 依赖树，**会随 profile 重装/升级而变**。是否直接依赖它，还是把它当作「尽量读取、失败则回退到内置表」的可选来源。
4. **是否支持未压缩 root**：方案 C 的纯 `.jsonl` 兼容分支成本很低，建议一并做；需确认 UI/文档是否要引导用户改配置。
5. **DSH 是否为可选/推荐数据源**：README 与支持页是否需要说明「需要 DSH 桌面版」以及版本要求。
6. **性能预算**：首次全量解压的最坏情况（例如 1 GB 日志）是否可接受，是否需要首扫限流 / 进度提示。
7. **标题生成 token 的取舍**：2.12 的盲区是否需要在文档中向用户披露，或接受为已知误差。
8. **缓存命中率口径**（3.4 末）：是否要把 cache write 从「命中率」分子中剔除。属既有行为，需产品确认后再改。

---

## 附录 A：证据来源清单

| 结论 | 证据 |
|---|---|
| 数据根与 layout | `base.cordis.patch.yml`（DSH 出厂 profile，`root: !!js dshHomePath('sessions')`）；`~/.dsh/` 实测 |
| 多帧 zstd / checksum / 每批一帧 | `dsh-session-persistence-jsonl/README.md`；`lib/index.js:15,1291` 的 `scanZstdFrames` / `CHECKSUM_OPTIONS` |
| Node 内置 zstd（无第三方库） | `lib/index.js:15`：`import { createZstdCompress, … } from "node:zlib"` |
| 世代文件与「取最高版本」 | `lib/index.js` → `resolveGenerationInDirectory`；`dsh-session-format/lib/index.js:470-491` 的规范正则 |
| `TokenUsage` 类型定义 | `dsh-llm/lib/typert.host.js:529` |
| 逐条 usage 事件与三类载体 | `dsh-api-session-controller/lib/typert.host.js:2133`（`SessionEventMap` 的 `assistant/message` / `assistant/attempt`）；`compaction/summary` 亦带 `usage` |
| 取样规则（prefer data.usage else last stream chunk） | `usage-projection.js` → `usageOf()` |
| 替换 / 重试折叠规则 | `usage-projection.js:91-117` → `tokenUsageProjectionDefinition.apply` |
| 字段语义（inputTokens=uncached） | `usage-projection.js` → `bucketsFrom` |
| `reasoningTokens` 当前不产出 | `dsh-llm-deepseek/lib/index.js:1808-1821` `updateUsage()` 只映射 4 字段；全 asar 仅声明/校验/UI 聚合处出现，无赋值 |
| `totalTokens` 语义不统一 | `dsh-llm-deepseek/lib/index.js:1993`（自算）vs `dsh-llm-pi-ai/lib/index.js:1371-1378`（透传） |
| 压缩可关闭 | `lib/index.js:2285` `DEFAULT_COMPRESSION="zstd"`、`2401`；`dsh-sdk-minimal/cordis.patch.yml:155-157` 用 `none` |
| 子代理独立会话 | 实测 `18ded2c6-…` header；`dsh-subagent/lib/types/child-agent.js:109-124` |
| seed 前缀边界 | `dsh-session-format-v3-to-v4/lib/index.js` → `restoreReleasedV4Artifact`（`data.inherited === true` 判定）；`dsh-session-persistence-jsonl/lib/index.js:833-846` `fromHeaderLine` 恒返回 0（header 不携带 cut） |
| `seq` 稠密不变量 | `restoreReleasedV4Artifact`：`if (event.seq !== index) throw ... "is not dense"`；本机 8 个日志文件（1×v0 + 4×v3 + 3×v4）实测通过 |
| 投影缓存的权威位置与配置 | `base.cordis.patch.yml:178-186`（`writeEveryEvents: 200` / `writeIntervalMs: 5000`）；`dsh-storage-json` README（single→per-record 迁移保留旧文件）；本机 mtime/内容对比 |
| pi-ai 定价目录 | `~/.dsh/profiles/node_modules/@earendil-works/pi-ai/dist/providers/data/<provider>.json`（39 providers，含 `deepseek`、`opencode-go`） |
| 模型 id 是自由配置 | `deepseek-v4.1-flash` 不在 pi-ai 目录，仅见于 `~/.dsh/profiles/desktop/cordis.patch.yml:12` |
| macOS 无 zstd | `MacOSX27.0.sdk/usr/include/compression.h`；`Foundation/NSData.h`；`clang -lzstd` 与 `dlopen` 实测 |
| TokenWatch 定价缺口 | `grep -i deepseek` 于 `PricingTable.swift` / `litellm_prices.json` / `models-dev-pricing.json` 均无命中 |
| Registry 驱动扩展点 | `TokenWatch/Providers/ProviderRegistry.swift`、`UsageProvider.swift`、`ProviderID.swift` |
| 无 CLI 用量子命令 | `app.asar/dsh/node_modules/@deepseek-ai/dsh-desktop-host/lib/cli.js` → `dsh/lib/bin.js`（仅 profile 启动 / plugin / `--dump-config`） |
| 导出仅有浏览器下载 | `dsh-session-log-export/README.md`（`/export` → `GET /api/session.export`，浏览器下载 ZIP，非 Host 落盘） |
| `dsh-session-query-sqlite` 非用量库 | 其 README：派生的 FTS5 全文检索索引，可丢弃、单进程独占 |

## 附录 B：实测样本数据（本机）

| 会话 | 世代 | 步数 | 折叠总量（input / output / cacheRead） |
|---|---|---|---|
| `session-8d883f81-…` | v4 | 38 | 132030 / 26073 / 1603200 |
| `session-f0baeeae-…` | v3 | 27 | 53291 / 13136 / 1070848 |
| `session-847cc202-…` | v0 + v3 | 4 | 10194 / 5224 / 28544 |
| `18ded2c6-…`（子代理） | v4 | 43 | 见 `assistant/message` 逐条 |

模型分布：`deepseek-v4.1-flash`、`deepseek-v4-flash`、`deepseek-flash`；route：`opencode-go`、`deepseek-official`。

---

## 9. 实施记录（2026-10-01）

方案 A 已按本文档落地，新增文件集中在 `TokenWatch/Providers/DeepSeekHarness/`。

### 9.1 落地内容

| 工作项 | 实现 |
|---|---|
| zstd 解码 | vendored zstd v1.5.7 官方单文件解码器（`TokenWatch/Vendor/Zstd/`，BSD-3-Clause）+ bridging header；`DeepSeekHarnessZstdDecoder` 用流式 API 逐帧解压，记录「已完整消费的压缩字节数」 |
| 扫描 | `DeepSeekHarnessScanner`：`sessions/` 两/三层遍历、**每会话目录只取最高世代**、同时接受 `~/.dsh` 与 `~/.dsh/sessions` |
| 解析 | `DeepSeekHarnessSessionLogParser`：header → 逐事件折叠 → 投影为 `ParsedUsageEntry`；未压缩 `.jsonl` 与 `.jsonl.zstd` 共用同一解析器 |
| 折叠 | `DeepSeekHarnessUsageFolder` 复刻 DSH `tokenUsageProjectionDefinition.apply`（同槽位替换 / `llm/retry-started` 累加 / 幂等去重），额外用 `attemptIndex` 保留逐次尝试 |
| 增量 | 复用 `JSONLLastGoodCacheCoordinator` + `SystemJSONLDiskCacheStore`，状态里持久化 `committedByteCount`（压缩偏移）与折叠结果；`isSeeded` 会话每轮整体重建以保证 fork 前缀正确 |
| 装配 | `ProviderID.deepSeekHarness` + `ProviderRegistry` 注册 + `validateDataRoot`（只认 `<root>/sessions` 与名为 `sessions` 的目录）+ `hasCacheWriteDimension`/`hasReasoningDimension` 均为 true |
| 本地化 | 新增 `deepSeekHarnessDataDirectoryOpenPanelMessage`，65 个 locale 全部补齐（key 总数 192 → 193） |
| 定价 | `DeepSeekHarnessPriceCatalogStore`（动态读 pi-ai 目录）+ `DeepSeekHarnessBuiltinPrices`（内置快照）+ `DeepSeekHarnessPricingCandidateResolver`（route 精确 → 模型名 → 次版本归并） |
| 测试 | 5 个新 suite（zstd 多帧/损坏帧、扫描与世代去重、折叠语义、fork 前缀、增量、定价），fixture 由真实 v4 日志裁剪并按 DSH 的「每批次一帧」方式压缩 |

### 9.2 实测对账（本机 `~/.dsh`）

解析结果与 DSH 自身 `session_projcache` 的 `tokenUsage.val.totals` **逐 token 相等**：

| 会话 | 世代 | 记录数 | input | output | cacheRead |
|---|---|---|---|---|---|
| `18ded2c6-…`（子代理） | v4 | 78 | 814365 | 36722 | 7992704 |
| `session-8d883f81-…` | v4 | 38 | 132030 | 26073 | 1603200 |
| `session-e37d6e25-…` | v4 | 293 | 823294 | 218517 | 73554560 |
| `session-f0baeeae-…` | v3 | 27 | 53291 | 13136 | 1070848 |
| `session-847cc202-…` | v0 **与** v3 并存 | 4 | 10194 | 5224 | 28544 |

- 最后一行证明**世代去重**生效：v0 与 v3 是同一会话的两种编码，只统计了一次；
- 记录数与 DSH 逐条样本数一致（全 0 用量的失败尝试不产生条目，但同样占用替换槽位）。

### 9.3 与本文档前期结论的差异（以实测为准）

1. **`compaction/summary` 不计入**。2.6 节认为它是第三类用量载体，但 DSH 官方的
   `usageOf()` 只覆盖 `assistant/message` 与 `assistant/attempt`，`tokenUsage` 投影也不折叠它。
   本实现按官方口径忽略该事件的 `usage`，以保证与 projcache 逐 token 对齐。
2. **沙盒内基本读不到 pi-ai 定价目录**。该路径在 pnpm 安装下是符号链接
   （`~/.dsh/profiles/node_modules/@earendil-works/pi-ai` → `~/.npm/_npx/...`），
   已超出用户授权的 `~/.dsh` 范围，App Sandbox 会直接拒绝。因此定价以**内置 DeepSeek 价格快照**
   为主，动态目录作为「可读时优先」的增强项（已写入 9.4 的待办）。
3. **fork 前缀的闭/开区间不确定，但数值上等价**。校验器断言 `lastInheritedMarker === inheritedEventCount`，
   而该标记事件本身不携带用量，因此「跳过 `seq <= cut`」与「跳过 `seq < cut`」结果相同；
   实现按前者处理，并在每遇到一个 `inherited` 标记时重置折叠状态（等价于只保留最后一个标记之后的事件）。

### 9.4 后续待办

- [ ] pi-ai 定价目录若为符号链接，可提示用户在 DSH 中改用非 pnpm 安装，或提供「额外授权定价目录」入口；
- [ ] 内置价格快照需随 DeepSeek 官方价格更新（当前来源：DSH 2026-09-29 构建内置 catalog）；
- [ ] `session/title-llm-request` 与 `web/deepseek-search-llm-request` 的调用日志中没有 usage 行，
      与 DSH 自身口径一致地未计入（已知盲区，见 2.12）；
- [ ] 首次全量扫描的解压成本：本机 9 个会话日志（约 3 MB 压缩 / 15 MB 明文）无感；
      如遇更大规模可考虑首扫限流。
