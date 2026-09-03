# TokenWatch 数据可信度中心实施计划

> 本计划按五个交付批次执行。每个 Task 对应一个可独立验证、可独立回滚的提交；使用复选框记录进度，不允许跨批次提前暴露后续产品界面。

**日期**：2026-08-28

**状态**：待实施

**目标**：把现有扫描、last-good、聚合快照和离线定价升级为可测试、可持久化、可向用户解释的可信契约，让用户能区分数据读取完整性、费用覆盖和数据新鲜度。

**架构**：Provider 只上送扫描与解析事实；UsageCostResolver 返回金额与费用来源；UsageAggregator 在同一遍循环中生成统计和费用覆盖；TokenStatsViewModel 管理时间、展示来源与快照生命周期；DataTrustCenterSnapshotBuilder 纯函数化派生状态、问题和动作；独立 AppKit 页面只负责渲染。

**技术栈**：Swift 6、AppKit、Foundation、OSLog、Swift Testing、XCTest UI Testing、macOS 15+

**确认设计**：[数据可信度中心详细设计](../specs/2026-08-11-data-trust-center-design.md)

**关联路线图**：[TokenWatch P0 功能路线图](./2026-08-11-p0-feature-roadmap.md)

## 交付批次

| 批次 | 用户可见结果 | 内部结果 | 完成后状态 |
|---|---|---|---|
| A. 可信口径与领域模型 | Dashboard 不再展示错误口径 | 诊断、费用覆盖、展示来源和问题代码具有稳定模型与真值表 | 后续 Provider 可只上送事实 |
| B. Provider 诊断与隐私缓存 | 暂不新增入口 | 三个 Provider 可区分完整、last-good、跳过、拒绝和正常过滤；磁盘不再直接保存原始 tail/anchor bytes | 扫描完整性可审计 |
| C. 费用覆盖、pipeline 与快照 v2 | 未知模型不再等同免费 | 单条费用来源、全量覆盖率、pipeline revision、可信快照与冷启动旧汇总闭环 | 金额与缓存来源可解释 |
| D. App 状态与可信度页面 | 新增“数据质量”页面、修复入口和安全文案 | ViewModel 时间语义、状态 builder、导航、深链、本地化、RTL 与无障碍接通 | P0-1 功能完整 |
| E. 隐私披露与发布验收 | 隐私说明与实际存储一致 | 单元/UI/本地化/隐私/Debug/Release 全量验收并回写路线图 | P0-1 可发布 |

## 全局约束

- 范围只包含 Claude Code、Codex 和 opencode；不新增 Provider、联网价格、自定义价格、多币种、团队能力、通知、预算页面、通用会话搜索或清除 UI。
- 不新增第三方依赖，不改变 macOS 15.0、Swift 6、App Sandbox、用户选择文件只读和禁止任意出站网络的工程边界。
- 不读取、持久化或展示 prompt、response、原始记录、完整数据根、cwd、session/message/request ID 或未清洗的底层错误。
- 不做综合可信度分数；数据读取、费用估算和数据新鲜度始终独立表达。
- 正常 cache hit、last-good、内存旧结果和磁盘汇总快照必须是不同来源；失败尝试不得推进成功时间。
- 未接入 Provider 是中性状态；显式上游 0 美元属于已覆盖，未知价格属于未覆盖，不能用金额正负判断覆盖。
- 快照或磁盘缓存迁移只删除 TokenWatch 的可重建派生数据，任何测试都必须证明外部 JSONL/SQLite 字节未变化。
- 核心公共方法添加作用、参数和返回值注释；关键状态变化记录简洁日志。日志只允许 Provider ID、稳定 issue code、计数和时间，不记录路径、原始行或未清洗 error description。
- TokenWatch、TokenWatchTests 和 TokenWatchUITests 使用 filesystem-synchronized root；这些目录内新增 Swift 文件不修改 project.pbxproj。诊断和主 App UI 文件不得放进 TokenWatchShared，避免误编进 Widget Extension。
- 每个行为 Task 先写 RED 测试并确认按预期失败，再最小实现并运行定向 GREEN 与相邻回归；最终 Task 不伪造 RED。
- 每个 Task 一个中文提交，格式为 type(scope): summary；提交前运行 git diff --check，只暂存该 Task 文件。
- 优先使用 Xcode MCP。回退到 xcodebuild 时统一指定 -derivedDataPath .build/DerivedData；build-for-testing 只能证明编译，不能代替真实测试。

## 文件地图

### 新增生产文件

- TokenWatch/Diagnostics/ProviderScanDiagnostics.swift
  - 扫描/解析事实、稳定诊断代码和饱和计数。
- TokenWatch/Diagnostics/PricingCoverage.swift
  - UsageCostResolution、CostBasis、PricingMatch、覆盖报告和未知模型摘要。
- TokenWatch/Diagnostics/ProviderTrustState.swift
  - 时间、展示来源、持久化问题和 Provider 可信状态。
- TokenWatch/Diagnostics/DataTrustCenterSnapshot.swift
  - 总体状态、问题、Provider 卡和纯状态 builder。
- TokenWatch/Services/LegacyDataCacheMigrator.swift
  - 在目录授权判断之前清理已知旧版 JSONL/聚合派生缓存，并返回结构化清理结果。
- TokenWatch/Services/PipelineRevision.swift
  - parser、聚合、resolver、alias、fast 映射和定价资源的稳定 revision。
- TokenWatch/Services/AppLifecycleRefreshCoordinator.swift
  - 统一处理 wake/didBecomeActive 后的静默刷新调度与去重。
- TokenWatch/ViewControllers/DataTrustCenterViewController.swift
  - 独立 AppKit 页面及安全动作转发。

### 主要修改文件

- TokenWatch/ViewControllers/DashboardRangeSnapshot.swift
- TokenWatch/ViewControllers/DashboardViewController.swift
- TokenWatch/ViewControllers/TotalStatsBuilder.swift
- TokenWatch/Providers/UsageProvider.swift
- TokenWatch/Providers/JSONLLastGoodCacheCoordinator.swift
- TokenWatch/Providers/IncrementalJSONLFileState.swift
- TokenWatch/Providers/JSONLDiskCacheStore.swift
- TokenWatch/Providers/Claude/ClaudeJSONLParser.swift
- TokenWatch/Providers/Claude/ClaudeProvider.swift
- TokenWatch/Providers/Codex/CodexModelResolver.swift
- TokenWatch/Providers/Codex/CodexRolloutParsingState.swift
- TokenWatch/Providers/Codex/CodexRolloutParser.swift
- TokenWatch/Providers/Codex/CodexProvider.swift
- TokenWatch/Providers/OpenCode/OpenCodeMessageParser.swift
- TokenWatch/Providers/OpenCode/OpenCodePricingCandidateResolver.swift
- TokenWatch/Providers/OpenCode/OpenCodeSQLiteScanner.swift
- TokenWatch/Providers/OpenCode/OpenCodeProvider.swift
- TokenWatch/Analytics/UsageCostResolver.swift
- TokenWatch/Analytics/UsageAggregator.swift
- TokenWatch/Models/ParsedUsageEntry.swift
- TokenWatch/Pricing/PricingTable.swift
- TokenWatch/Pricing/PricingEngine.swift
- TokenWatch/Providers/ProviderStatsSnapshotStore.swift
- TokenWatch/ViewModels/TokenStatsViewModel.swift
- TokenWatch/AppDelegate.swift
- TokenWatch/ViewControllers/StatusPopoverViewController.swift
- TokenWatch/Localization/AppStrings.swift
- TokenWatch/Localization/Resources/*/Localizable.strings
- PRIVACY.md、PRIVACY.zh-CN.md
- docs/privacy/index.md、docs/privacy/zh-CN.md
- fastlane/metadata/en-US/release_notes.txt
- fastlane/metadata/zh-Hans/release_notes.txt

### 新增或重点修改测试

- TokenWatchTests/Diagnostics/ProviderScanDiagnosticsTests.swift
- TokenWatchTests/Diagnostics/PricingCoverageTests.swift
- TokenWatchTests/Diagnostics/ProviderTrustStateTests.swift
- TokenWatchTests/Diagnostics/DataTrustCenterSnapshotTests.swift
- TokenWatchTests/Services/LegacyDataCacheMigratorTests.swift
- TokenWatchTests/Services/PipelineRevisionTests.swift
- TokenWatchTests/Services/AppLifecycleRefreshCoordinatorTests.swift
- TokenWatchTests/Providers/JSONLLastGoodCacheCoordinatorTests.swift
- TokenWatchTests/Providers/IncrementalJSONLFileStateTests.swift
- TokenWatchTests/Providers/JSONLDiskCacheStoreTests.swift
- TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift
- TokenWatchTests/Providers/Codex/CodexModelResolverTests.swift
- TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift
- TokenWatchTests/Providers/OpenCode/OpenCodeMessageParserTests.swift
- TokenWatchTests/Providers/OpenCode/OpenCodeSQLiteScannerTests.swift
- TokenWatchTests/Analytics/UsageCostResolverTests.swift
- TokenWatchTests/Analytics/UsageAggregatorTests.swift
- TokenWatchTests/Pricing/PricingTableTests.swift
- TokenWatchTests/Pricing/PricingEngineTests.swift
- TokenWatchTests/Pricing/CCUsagePricingParityTests.swift
- TokenWatchTests/Providers/ProviderStatsSnapshotStoreTests.swift
- TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift
- TokenWatchTests/ViewModels/TokenStatsViewModelWidgetPublishingTests.swift
- TokenWatchTests/ViewControllers/DashboardRangeSnapshotTests.swift
- TokenWatchTests/ViewControllers/TotalStatsBuilderTests.swift
- TokenWatchTests/ViewControllers/DataTrustCenterViewControllerTests.swift
- TokenWatchTests/Localization/AppLocalizationResourcesTests.swift
- TokenWatchTests/Localization/LocalizationEnglishReuseAllowlist.swift
- TokenWatchTests/TokenWatchTests.swift
- TokenWatchUITests/TokenWatchUITests.swift

---

## 批次 A：可信口径与领域模型

### Task A1：修正 Dashboard 的三处可信口径

**Files**

- Modify: TokenWatch/ViewControllers/DashboardRangeSnapshot.swift
- Modify: TokenWatch/ViewControllers/DashboardViewController.swift
- Modify: TokenWatch/ViewControllers/TotalStatsBuilder.swift
- Modify: TokenWatch/Localization/AppStrings.swift
- Modify: TokenWatch/Localization/Resources/*/Localizable.strings
- Modify: TokenWatchTests/ViewControllers/DashboardRangeSnapshotTests.swift
- Modify: TokenWatchTests/ViewControllers/TotalStatsBuilderTests.swift
- Modify: TokenWatchTests/Localization/AppLocalizationResourcesTests.swift
- Modify: TokenWatchTests/Localization/LocalizationEnglishReuseAllowlist.swift

**接口与不变量**

- 当前范围 summary 必须携带从范围内 modelBreakdown 派生的模型排行；Dashboard 不再用全量 TotalStatsBuilder.modelRows 渲染范围排行。
- entryCount 的总览卡片复用现有 dashboardMetricRecords，显示“记录数”；会话页继续使用 dashboardMetricSessions，不在本批次定义跨日唯一会话。
- 删除按 Token 比例反推输入/输出/推理费用；改用冻结清单中的 dataHealthPricingDisclaimer，不改变总费用数值。
- 本批次只提前加入上述 91 个冻结 key 中的 dataHealthPricingDisclaimer；AppStringKey、65 份资源、expected count 189→190、format signature、英文复用 allowlist 与首次 UI 引用必须原子更新。

- [ ] 写 RED：7 天窗口只包含窗口内模型，all 范围仍包含全量模型；Dashboard 文案表达记录而非会话；费用详情不再出现伪拆分。
- [ ] 写 RED：dataHealthPricingDisclaimer 是相对 189-key 基线唯一新增项，65 份资源直接定义且 expected count 为 190。
- [ ] 运行 DashboardRangeSnapshotTests、TotalStatsBuilderTests 与本地化定向测试，确认新断言失败。
- [ ] 最小修改 range snapshot 与 Dashboard render；保留会话页及其真实 Sessions 文案不变。
- [ ] 运行上述测试及 DashboardSessionPaginationTests、MonthlyTokenChartBuilderTests。
- [ ] 静态检查 DashboardViewController 不再调用 formatCostBreakdown，范围模型排行不再读取 totalSnapshot.modelRows。
- [ ] 提交：fix(dashboard): 修正用量与费用可信口径

### Task A2：建立诊断、可信状态与问题优先级模型

**Files**

- Create: TokenWatch/Diagnostics/ProviderScanDiagnostics.swift
- Create: TokenWatch/Diagnostics/PricingCoverage.swift
- Create: TokenWatch/Diagnostics/ProviderTrustState.swift
- Create: TokenWatch/Diagnostics/DataTrustCenterSnapshot.swift
- Create: TokenWatchTests/Diagnostics/ProviderScanDiagnosticsTests.swift
- Create: TokenWatchTests/Diagnostics/PricingCoverageTests.swift
- Create: TokenWatchTests/Diagnostics/ProviderTrustStateTests.swift
- Create: TokenWatchTests/Diagnostics/DataTrustCenterSnapshotTests.swift

**接口与不变量**

- 定义 ProviderScanDiagnosticsState、ProviderScanDiagnostics、ProviderParseDiagnostics、DiagnosticCount 和 DataDiagnosticCode。
- 定义 DataReadingConclusion、PricingConclusion、FreshnessConclusion 三个独立轴；总体状态只按严重度聚合，禁止用一个轴推导另一个轴。
- 定义 ProviderScanCompleteness、DisplayedDataOrigin、DataRootIdentityFingerprint、ProviderAttemptOutcome、ProviderRefreshFailureCode、LocalPersistenceIssue、ProviderTrustState 和 DataTrustIssueCode。
- 定义 PricingCoverageState/Report、UnpricedModelSummary 和费用来源的最小 Codable 外壳，Task C1/C2 在此稳定类型上补齐解析和聚合行为。
- builder 只消费结构化事实，不消费 raw Error 或路径；问题按严重度、Provider 固定顺序、issue code 稳定排序。
- isChecking 与 healthy/attention/limited/noData 正交；只有首次无结果时使用 checking。最近 attempt 失败必须先于保留的旧 scan diagnostics 决定当前完整性。
- 未接入 Provider 中性；只有全部未接入时产生 setupRequired。legacyCacheCleanupFailed 为 limited，其余本地持久化问题为 attention。

- [ ] 写 RED 三轴真值表，逐一覆盖 DataReadingConclusion、PricingConclusion、FreshnessConclusion 的全部枚举，并覆盖 setupRequired、checking、limited、attention、noData、healthy 总体聚合。
- [ ] 写 RED：正常过滤/去重不降级；异常 usage 候选为 degraded；无回退源跳过为 incomplete；全局失败无旧结果为 failed。
- [ ] 写 RED：全局失败但保留内存/磁盘结果仍由 failed attempt outcome 驱动 lastCheckFailed 与旧数据来源；未接入 Provider 中性；任一已接入 coverage unavailable 不计算全局误导百分比。
- [ ] 写 RED：legacy cleanup failure 为 limited；snapshot write/delete failure 为 attention；问题排序与稳定 code 不依赖底层 error description。
- [ ] 实现纯模型、显式 kind+payload Codable、身份摘要值对象和饱和计数；不接入生产 Provider。
- [ ] 运行四个新 suite，做 encode/decode、三轴真值表与排序稳定性回归。
- [ ] 确认新增文件自动进入主 App/Test target，project.pbxproj 无 diff，TokenWatchShared 无新增。
- [ ] 提交：feat(diagnostics): 建立数据可信状态契约

**批次 A 完成门槛**

- [ ] Dashboard 三处口径问题已修正并通过本地化回归。
- [ ] 状态真值表不依赖 UI、颜色或底层错误字符串。
- [ ] 后续 Provider 只需上送事实，不自行决定用户文案或总体颜色。

---

## 批次 B：Provider 诊断与隐私缓存

### Task B1：让 JSONL 磁盘状态不再保存原始 tail/anchor bytes

**Files**

- Create: TokenWatch/Services/LegacyDataCacheMigrator.swift
- Create: TokenWatchTests/Services/LegacyDataCacheMigratorTests.swift
- Modify: TokenWatch/AppDelegate.swift
- Modify: TokenWatch/Providers/IncrementalJSONLFileState.swift
- Modify: TokenWatch/Providers/JSONLDiskCacheStore.swift
- Modify: TokenWatch/Providers/JSONLLastGoodCacheCoordinator.swift
- Modify: TokenWatch/ViewModels/TokenStatsViewModel.swift
- Modify: TokenWatch/Providers/Claude/ClaudeJSONLParser.swift
- Modify: TokenWatch/Providers/Codex/CodexRolloutParser.swift
- Modify: TokenWatchTests/Providers/IncrementalJSONLFileStateTests.swift
- Modify: TokenWatchTests/Providers/JSONLDiskCacheStoreTests.swift
- Modify: TokenWatchTests/Providers/JSONLLastGoodCacheCoordinatorTests.swift
- Modify: TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift
- Modify: TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift

**接口与不变量**

- continuity anchor 只保存 offset、byteCount 和 SHA-256；校验时从同一 opened descriptor 读取对应区间。
- 磁盘使用显式 DTO，不保存 provisionalTail；保存 requiresTailReplayOnRestore。
- 恢复后需要 tail replay 时绕过 exact metadata hit，并以 restoredTailReplay 原因重建。
- JSONL store 先解码只含 version 的 envelope，再决定是否解码 State；协议增加可抛错的显式 remove，不能把“解码失败”静默等同“已删除”。
- LegacyDataCacheMigrator 在 App 启动且判断目录授权之前检查已知 Claude/Codex namespace，删除含原始 bytes 的旧 schema；它不依赖 Provider 是否仍接入，也不扫描 TokenWatch 缓存目录之外的位置。
- 清理失败返回稳定结果并写入 legacyCacheCleanupFailed；失败允许 App 保守启动但属于发布阻断，不能只记日志后宣称迁移完成。
- 新 schema 重建不迁移原始 bytes，不触碰 Bookmark、偏好、Widget、购买权益或外部日志。

- [ ] 写 RED：编码结果不含 fixture 中的 prompt/response/tail/anchor 明文。
- [ ] 写 RED：provisional tail 冷启动恢复会 replay，且与热启动得到相同 entries 与 source revision。
- [ ] 写 RED：append、truncate、replace、last-good 和 prune 后外部文件 hash/字节不变。
- [ ] 写 RED：两个 Provider 都未授权时仍会删除已知旧 JSONL cache；version envelope 可在 State 已不兼容时识别版本；删除失败产生 legacyCacheCleanupFailed 且文件不会被当成新 schema 复用。
- [ ] 实现 digest anchor、持久化 DTO、replay 原因、显式 remove 和启动迁移；迁移必须先于首次授权引导/常规扫描分支。
- [ ] 运行六个相关 suite；追加静态搜索，确保持久化 DTO 没有 Data 类型的原始 tail/bytes 字段，并比较迁移前后外部 fixture 字节。
- [ ] 提交：fix(privacy): 移除增量缓存中的原始字节

### Task B2：扩展共享 coordinator 的结构化扫描结果

**Files**

- Modify: TokenWatch/Providers/JSONLLastGoodCacheCoordinator.swift
- Modify: TokenWatch/Providers/UsageProvider.swift
- Modify: TokenWatchTests/Providers/JSONLLastGoodCacheCoordinatorTests.swift
- Modify: TokenWatchTests/Providers/ProviderRegistryTests.swift
- Modify: TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift
- Modify: TokenWatchTests/ViewModels/TokenStatsViewModelWidgetPublishingTests.swift

**接口与不变量**

- coordinator 的产品结果返回 discovered/current/last-good/skipped；memory/disk hit、append/rebuild、tail replay 和 prune 只进入本轮临时 JSONLCoordinatorRunDiagnostics，不进入 ProviderStatsSnapshot、UI 严重度或 source revision。
- UsageProviderLoadResult 增加 diagnostics，显式 initializer 对测试替身默认 unavailable；三个生产 Provider 最终不得依赖默认值。
- 诊断不参与 sourceRevision 或 entry fingerprint。

- [ ] 写 RED：内存命中、磁盘命中、rebuild、append、last-good、首次失败跳过和 prune 计数互斥且稳定。
- [ ] 写 RED：正常 cache hit 映射为 currentScan/verifiedUnchanged，不计入 last-good。
- [ ] 演进 coordinator 与 UsageProviderLoadResult，并最小迁移测试替身。
- [ ] 运行 coordinator、registry 和全部 ViewModel 定向 suite。
- [ ] 提交：feat(provider): 上送结构化扫描事实

### Task B3：Claude 与 Codex 上送解析诊断

**Files**

- Modify: TokenWatch/Providers/Claude/ClaudeJSONLParser.swift
- Modify: TokenWatch/Providers/Claude/ClaudeProvider.swift
- Modify: TokenWatch/Providers/Codex/CodexRolloutParsingState.swift
- Modify: TokenWatch/Providers/Codex/CodexRolloutParser.swift
- Modify: TokenWatch/Providers/Codex/CodexProvider.swift
- Modify: TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift
- Modify: TokenWatchTests/Providers/Codex/CodexRolloutParsingStateTests.swift
- Modify: TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift

**接口与不变量**

- 每文件 state 区分 committed/provisional diagnostics；只有 committed newline 推进永久计数。
- 普通事件、零 Token、重复、sidechain replacement 和 replay 为正常过滤；usage-like 损坏、非法时间/Token/必要字段为异常拒绝。
- unchanged fast path 若无兼容全局 parse report，强制 materialize，不能返回全零诊断。
- Codex model fallback 为 informational，不降低 Token 完整性。

- [ ] 写 RED fixture：普通过滤、重复/replay、损坏 usage、append provisional、last-good 与首次失败跳过。
- [ ] 实现 per-file 诊断累加、projection 后 accepted/duplicate 重算和 Provider 映射。
- [ ] 运行 Claude/Codex parser、state、scanner 与 provider registry 回归。
- [ ] 提交：feat(provider): 补充 JSONL 解析诊断

### Task B4：opencode 上送结构化诊断

**Files**

- Modify: TokenWatch/Providers/OpenCode/OpenCodeMessageParser.swift
- Modify: TokenWatch/Providers/OpenCode/OpenCodeSQLiteScanner.swift
- Modify: TokenWatch/Providers/OpenCode/OpenCodeProvider.swift
- Modify: TokenWatchTests/Providers/OpenCode/OpenCodeMessageParserTests.swift
- Modify: TokenWatchTests/Providers/OpenCode/OpenCodeSQLiteScannerTests.swift

**接口与不变量**

- 已由 SQL 证明为 assistant 的行，解码失败、missing tokens 或缺必填列才是异常拒绝。
- notAssistant、allZero 为正常过滤；全表无法归类的 invalid JSON 只作 informational/unknown。
- 本批次不引入 SQLite source revision；每次完整查询仍可标 complete。
- opencode 的文件级 sourceUsingLastGood/sourceSkippedWithoutFallback 固定为 0；数据库打开/查询失败只写 ProviderAttemptOutcome，并根据已有数据选择 retainedMemory/persistedSummarySnapshot/none。

- [ ] 写 RED：assistant decode/missing field 与正常过滤被分到不同集合。
- [ ] 写 RED：无法证明属于 usage 的 invalid JSON 不降低完整性。
- [ ] 写 RED：数据库失败不会伪造 JSONL last-good/skip；有内存旧结果、只有兼容磁盘汇总和没有回退三条路径分别得到稳定来源与失败代码。
- [ ] 实现 scanner/parser 诊断并由 OpenCodeProvider 返回 available；全局失败继续由 ViewModel 的 attempt outcome 归一化。
- [ ] 运行 opencode 两个 suite 与 ProviderRegistryTests。
- [ ] 提交：feat(opencode): 上送 SQLite 解析诊断

**批次 B 完成门槛**

- [ ] 三个生产 Provider 成功 load 都返回 available diagnostics。
- [ ] cache hit、last-good、skipped 和 rejected 具有不同事实与测试。
- [ ] 磁盘缓存不含原始 tail/anchor bytes，外部源文件始终只读不变。

---

## 批次 C：费用覆盖、pipeline 与快照 v2

### Task C1：让定价查询返回来源与实际匹配

**Files**

- Modify: TokenWatch/Diagnostics/PricingCoverage.swift
- Modify: TokenWatch/Pricing/PricingTable.swift
- Modify: TokenWatch/Pricing/PricingEngine.swift
- Modify: TokenWatch/Analytics/UsageCostResolver.swift
- Modify: TokenWatch/Models/ParsedUsageEntry.swift
- Modify: TokenWatch/Providers/Codex/CodexModelResolver.swift
- Modify: TokenWatch/Providers/Codex/CodexRolloutParser.swift
- Modify: TokenWatch/Providers/Codex/CodexProvider.swift
- Modify: TokenWatchTests/Pricing/PricingTableTests.swift
- Modify: TokenWatchTests/Pricing/PricingEngineTests.swift
- Modify: TokenWatchTests/Analytics/UsageCostResolverTests.swift
- Modify: TokenWatchTests/Providers/Codex/CodexModelResolverTests.swift
- Modify: TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift
- Modify: TokenWatchTests/Pricing/CCUsagePricingParityTests.swift

**接口与不变量**

- PricingTable.lookup 返回 pricing、matchedModelID、baseCatalog、exact/normalizedBoundary、table adjustments 和 validThrough；UsageCostResolver/PricingEngine 再把上游模型映射、OpenCode candidate、alias/boundary、long-context、fast 与 service tier 按固定顺序合并成完整 PricingMatch.adjustments。
- ParsedUsageEntry 增加默认空的 pricingInputAdjustments；Codex auto-review 日期映射只记录稳定 adjustment 与目标模型 ID，不保存原始事件。该字段随 B1 新 cache schema 编码并纳入 pipeline revision。
- PricingAdjustment.detail 只允许 canonical 模型/catalog ID 或稳定 tier code，禁止任意 Provider 文本、路径和底层 error。
- ParsedUsageEntry 对缺失新字段按空数组解码，保持 Claude 与测试 fixture 兼容；Codex cache version 必须提升，强制从源重新派生历史 auto-review adjustment，不能把旧缓存的空数组误当完整 provenance。
- resolver 返回 UsageCostResolution；旧 resolvedCost 暂作兼容包装。
- 只有 upstreamCost 有限且大于等于 0 才为 upstreamReported，包括显式 0；NaN、正负无穷或负数产生 invalidUpstreamCost 并继续尝试本地价格。
- resolver 接受可注入 now；本地条目达到 validThrough 后产生 expiredLocalPrice，过期条目不算覆盖。当前 2026-12-31 限时价精确冻结为 `2027-01-01T00:00:00Z` 前有效。
- LiteLLM+builtin primary 过期时，只有 models.dev 等更低优先级 catalog 存在独立、仍有效匹配才可回退，不能把同一过期条目换名继续使用。
- OpenCode 保留正金额候选优先与现有 ccusage 金额语义；零金额 pricing hit 仍算有来源，源数据 cost<=0 继续按现有 adapter 规则不进入 upstreamCost。

- [ ] 写 RED：LiteLLM、builtin override、models.dev、alias、boundary、long-context、fast、service tier、auto-review 和 OpenCode candidate 均可审计。
- [ ] 写 RED：多个 adjustment 同时发生时顺序固定，encode/decode 后不丢失；Codex auto-review 只携带安全模型 ID，不携带原始事件内容。
- [ ] 写 RED：未知模型 amountUSD 为 0 但 basis unavailable；显式 upstream 0 为 covered；非法 upstream 先本地回退、无回退时为 unavailable。
- [ ] 写 RED：validThrough 前一瞬仍有效、边界时刻失效；primary 过期时只接受独立有效 fallback，所有价格过期时 basis unavailable。
- [ ] 实现 provenance lookup、adjustments、有效期与 resolver path，不改变既有合法金额 fixture。
- [ ] 运行 PricingTable、PricingEngine、UsageCostResolver 与 CCUsagePricingParity 全 suite。
- [ ] 提交：feat(pricing): 返回可审计的费用来源

### Task C2：单遍聚合费用覆盖报告

**Files**

- Modify: TokenWatch/Analytics/UsageAggregator.swift
- Modify: TokenWatch/Models/UsageAggregation.swift
- Modify: TokenWatchTests/Analytics/UsageAggregatorTests.swift
- Modify: TokenWatchTests/Diagnostics/PricingCoverageTests.swift

**接口与不变量**

- UsageAggregationResult 同时包含 stats 与 PricingCoverageState。
- UsageAggregating 增加 aggregateWithDiagnostics；测试替身可用默认 unavailable，生产实现必须 available。
- 覆盖分母使用 aggregateTotalTokens；未知模型按 Token 降序、Provider/模型稳定排序，最多 50 项并记录省略数。
- 报告覆盖授权根内全部已读取数据，不跟随 Dashboard 范围。

- [ ] 写 RED：Token/记录覆盖、上游/本地/未计价拆分、极值饱和、50 项截断、零总量。
- [ ] 写 RED：同一批 entries 的旧 aggregate 与新 result.stats 完全一致。
- [ ] 在现有 entry 循环内累加 coverage，禁止第二遍完整 cost resolve。
- [ ] 运行 UsageAggregatorTests、UsageCostResolverTests 与现有 widget/dashboard 聚合相邻回归。
- [ ] 提交：feat(analytics): 聚合费用覆盖报告

### Task C3：建立稳定 pipeline revision

**Files**

- Create: TokenWatch/Services/PipelineRevision.swift
- Modify: TokenWatch/Providers/Claude/ClaudeJSONLParser.swift
- Modify: TokenWatch/Providers/Codex/CodexRolloutParser.swift
- Modify: TokenWatch/Providers/Codex/CodexModelResolver.swift
- Modify: TokenWatch/Providers/OpenCode/OpenCodeMessageParser.swift
- Modify: TokenWatch/Providers/OpenCode/OpenCodeSQLiteScanner.swift
- Modify: TokenWatch/Providers/OpenCode/OpenCodePricingCandidateResolver.swift
- Modify: TokenWatch/Analytics/UsageAggregator.swift
- Modify: TokenWatch/Analytics/UsageCostResolver.swift
- Modify: TokenWatch/Pricing/PricingTable.swift
- Create: TokenWatchTests/Services/PipelineRevisionTests.swift

**接口与不变量**

- revision 固定覆盖 parser/dedup、聚合口径、resolver、builtin 全量 canonical 条目及 validThrough、alias、boundary/fuzzy、long-context overlay、fast multiplier、service tier、auto-review、OpenCode candidate 映射与 LiteLLM/models.dev 两个内置价格资源 hash。
- 不使用 App 版本、时间或诊断计数。
- 资源 hash 为静态/构建期常量；测试用实际资源校验常量，刷新时不重复读取资源计算。

- [ ] 写 RED：任一语义版本、builtin 条目/有效期、adjustment 映射或价格 hash 变化都会改变 revision；纯 UI/App 版本变化不参与。
- [ ] 实现固定字段顺序和 SHA-256 摘要。
- [ ] 运行 PipelineRevisionTests 及定价资源加载测试。
- [ ] 提交：feat(cache): 添加数据口径版本摘要

### Task C4：升级 ProviderStatsSnapshot v2 与冷启动回退

**Files**

- Modify: TokenWatch/Services/LegacyDataCacheMigrator.swift
- Modify: TokenWatch/AppDelegate.swift
- Modify: TokenWatch/Providers/ProviderStatsSnapshotStore.swift
- Modify: TokenWatch/ViewModels/TokenStatsViewModel.swift
- Modify: TokenWatchTests/Services/LegacyDataCacheMigratorTests.swift
- Modify: TokenWatchTests/Diagnostics/ProviderTrustStateTests.swift
- Modify: TokenWatchTests/Providers/ProviderStatsSnapshotStoreTests.swift
- Modify: TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift

**接口与不变量**

- v2 原子保存 stats、DataRootIdentityFingerprint、source/pipeline revision、与同一 stats/source/pipeline 精确对应的 scan diagnostics、pricing coverage、成功/完整成功时间；degraded/incomplete 也保存本轮原事实，不能回填“最近完整”诊断。
- DataRootIdentityFingerprint 固定摘要 Provider ID、解析符号链接后的标准化路径、volume identifier 和根目录 file resource identifier；任一 identity 无法稳定取得时仍可扫描，但禁止冷启动快照回退。
- v1 是可重建缓存：LegacyDataCacheMigrator 在授权判断前主动删除所有已知 Provider v1 文件，不猜测迁移字段；无法解码完整 State 时仍先读 schema envelope 决定删除。
- 复用同时要求 Provider、非 nil 数据根 identity、时区、source 和 pipeline 兼容；Bookmark/目录校验失败不展示旧快照。
- ProviderStatsSnapshotStoring 增加 remove(for:) throws。切换新数据根时，在新根校验成功后、扫描开始前清空旧根 entries/stats/trust/fingerprint/source revision 并删除旧快照；删除失败设置 providerSnapshotDeleteFailed 且禁止继续复用旧文件。
- 删除只影响 TokenWatch 可重建派生数据，不清除 Bookmark、偏好、购买权益、Widget 或外部日志。

- [ ] 写 RED：未授权 Provider 的 v1 仍在启动时删除重算；清理失败产生 legacyCacheCleanupFailed 并成为发布阻断。
- [ ] 写 RED：pipeline mismatch 重算、source/pipeline match 复用、时区变化不复用；同一路径目录被替换不复用；volume/file identity 缺失不允许冷启动回退。
- [ ] 写 RED：degraded/incomplete 快照保存的诊断与同轮 stats/source/pipeline 完全一致，不偷换成最近 complete report。
- [ ] 写 RED：冷启动失败只在授权根、identity、时区和 pipeline 均可验证时显示旧汇总，entries 为空且会话明细不可用。
- [ ] 写 RED：新根校验后先清空旧内存并调用 remove；删除失败禁止旧快照复用。写入失败保留本轮内存成功结果并产生仅内存 issue。
- [ ] 实现 v2 reader/writer、identity fingerprint、显式 remove、启动迁移扩展和 ViewModel 最小接线。
- [ ] 运行 migrator、identity、snapshot store 与 ViewModel 全 suite；比较迁移/切根前后外部 fixture 字节。
- [ ] 提交：feat(snapshot): 升级可信聚合快照

**批次 C 完成门槛**

- [ ] 未知模型与真实 0 美元在领域模型中可区分。
- [ ] stats、parse、pricing coverage 来自同一 source/pipeline revision。
- [ ] 旧快照不会因纯 source 未变化而复用过期价格或算法。
- [ ] v1 聚合快照与含原始字节的旧 JSONL cache 在未授权场景也会被清理；任何清理失败均阻止发布。
- [ ] 数据根 identity 不能证明兼容时不走 persisted summary，切根删除失败时绝不复用旧根数据。

---

## 批次 D：App 状态与可信度页面

### Task D1：迁移 ViewModel 的时间与展示来源语义

**Files**

- Create: TokenWatch/Services/AppLifecycleRefreshCoordinator.swift
- Create: TokenWatchTests/Services/AppLifecycleRefreshCoordinatorTests.swift
- Modify: TokenWatch/AppDelegate.swift
- Modify: TokenWatch/ViewModels/TokenStatsViewModel.swift
- Modify: TokenWatch/ViewControllers/DashboardViewController.swift
- Modify: TokenWatch/ViewControllers/StatusPopoverViewController.swift
- Modify: TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift
- Modify: TokenWatchTests/ViewControllers/StatusPopoverViewControllerTests.swift

**接口与不变量**

- 每次尝试更新 started/finished；成功验证更新 successful；完整且新鲜才更新 complete。
- attempt 结束写 ProviderAttemptOutcome；失败只推进 attempt，保留内存结果时标 retainedMemory，不把旧数据显示成“刚刚成功”。失败 outcome 必须优先于保留的旧 scan diagnostics 派生 lastCheckFailed。
- unchanged 推进成功检查时间但不伪造 stats generatedAt。
- AppDelegate 持有 AppLifecycleRefreshCoordinator；wake 与 didBecomeActive 合并调度一次 silentIfUnchanged，复用现有 Provider load gate。自动刷新关闭时不启动周期 Timer，但生命周期刷新仍可检查一次，完成前不提前制造 stale，也不发送 VoiceOver 播报。
- FreshnessConclusion 的优先级固定为 lastCheckFailed、neverSucceeded、manualRefreshOnly、stale、current；首次检查进度由正交的 isChecking/读取 checking 表达，未接入 Provider 不参与。
- 所有消费者迁移后删除 lastRefreshedAt；若短暂兼容，只能是 lastSuccessfulScanAt 的只读别名。

- [ ] 写 RED：失败不推进 successful/complete；unchanged 与 retained/persisted 来源时间各自正确。
- [ ] 写 RED：Dashboard/Popover 的“上次更新”来自成功时间而非失败尝试。
- [ ] 写 RED：wake 后再 didBecomeActive 只合并一次静默刷新；自动刷新关闭不创建周期 Timer，生命周期刷新完成前不先变 stale；最近失败优先显示 lastCheckFailed。
- [ ] 实现 ProviderTrustState 生命周期、单 Provider refresh、安全 issue 归一化与 lifecycle coordinator，并在 App 终止时移除观察者。
- [ ] 运行 ViewModel、Dashboard、StatusPopover 与 StatusBarController 相邻 suite。
- [ ] 提交：feat(view-model): 接入可信时间与数据来源

### Task D2：冻结并原子加入全部页面文案

**Files**

- Modify: TokenWatch/Localization/AppStrings.swift
- Modify: TokenWatch/Localization/Resources/*/Localizable.strings
- Modify: TokenWatchTests/Localization/AppLocalizationResourcesTests.swift
- Modify: TokenWatchTests/Localization/LocalizationEnglishReuseAllowlist.swift

**接口与不变量**

- 严格采用详细设计 §十四冻结的 91 个新增 key：导航、页头、三轴状态、问题、Provider 卡、费用说明、动作、空态、加载态、无障碍和格式化文案不得在实施期改名、拆分或临时增加。
- 65 locale key 顺序、format signature、术语、非空和 raw-key 禁止同时通过。
- P0-1 前有 189 个 key；Task A1 已加入 dataHealthPricingDisclaimer 后基线为 190，本 Task 原子加入其余 90 项，最终 expected count 为 280。refreshNow 等八个现有 key 继续复用，不重复新增。
- 不在后续 UI Task 再新增临时硬编码可见文案。

- [ ] 以详细设计冻结表为唯一清单，写 RED 把 enum expected count 从 190 更新为 280，并逐项断言剩余 90 个 key 的 format signature。
- [ ] 原子加入剩余 90 个 AppStringKey、65 份 Localizable.strings、expected count、format signatures 和 allowlist；相对 P0-1 前 189-key 基线的新增集合必须与冻结的 91 项完全相等。
- [ ] 运行全部 Localization tests，校验 65 份资源可被 Bundle 直接读取。
- [ ] 提交：feat(localization): 添加数据质量页面文案

### Task D3：实现纯展示快照与独立 AppKit 页面

**Files**

- Modify: TokenWatch/Diagnostics/DataTrustCenterSnapshot.swift
- Create: TokenWatch/ViewControllers/DataTrustCenterViewController.swift
- Create: TokenWatchTests/ViewControllers/DataTrustCenterViewControllerTests.swift
- Modify: TokenWatchTests/Diagnostics/DataTrustCenterSnapshotTests.swift

**接口与不变量**

- 页面结构固定为页头、总体结论、需要处理的问题、Provider 卡、费用可信度、本地处理说明；三轴分别渲染 DataReadingConclusion、PricingConclusion、FreshnessConclusion，Controller 不自行合并结论。
- Controller 只渲染 snapshot 与转发 refreshAll、refreshProvider、openSettings、showPricingExplanation。
- 扫描中保留上一轮内容；无旧内容才显示首次 loading。
- 状态同时使用图标、标题和解释，颜色只作辅助；装饰点退出 accessibility tree。
- 新页面使用 leading/trailing、natural alignment 和 resolved language direction，最小宽度 860pt。

- [ ] 写 RED presentation/controller 测试覆盖三轴全部枚举，以及 healthy、attention、limited、noData、setup、checking、persisted snapshot。
- [ ] 写 RED：问题稳定排序、未知模型截断、格式化 locale、无 raw path/error 泄漏。
- [ ] 实现页面组件、稳定 accessibility identifiers、焦点与单次手动刷新播报。
- [ ] 运行新 suite；对德/法/俄/阿 fixture 做 860pt 布局与 RTL 定向断言。
- [ ] 提交：feat(data-health-ui): 实现数据可信度页面

### Task D4：接入导航、深链和设置定位

**Files**

- Modify: TokenWatch/ViewControllers/DashboardRangeSnapshot.swift
- Modify: TokenWatch/ViewControllers/DashboardViewController.swift
- Modify: TokenWatch/ViewController.swift
- Modify: TokenWatchTests/TokenWatchTests.swift
- Modify: TokenWatchTests/ViewControllers/DataTrustCenterViewControllerTests.swift
- Modify: TokenWatchUITests/TokenWatchUITests.swift

**接口与不变量**

- DashboardNavigationItem 在 Sessions 与 Settings 之间增加 dataHealth，symbol 为 checkmark.shield。
- 侧边栏 Provider 状态和上次本地扫描区域可进入页面并聚焦对应 Provider。
- 前往设置聚焦目标 Provider 数据目录卡；不得自动弹文件选择器。
- 既有 overview/session 容器继续保持现状 LTR；enforceLeftAlignedContent 必须跳过可信度 child root。
- TokenWatchTests 中中英文导航标题精确数组、DashboardNav 焦点列表和阿拉伯语既有 LTR 断言同步更新。

- [ ] 写 RED：导航顺序、标题、symbol、焦点、Provider 深链和设置定位。
- [ ] 写 RED UI smoke：进入数据质量、触发无副作用的设置定位、稳定 AX identifiers 可见。
- [ ] 接入 child controller 与动作；不在 DashboardViewController 重复状态解释逻辑。
- [ ] 运行 TokenWatchTests 导航相关测试、新 controller suite 和 UI 定向 smoke。
- [ ] 提交：feat(navigation): 接入数据质量入口与修复动作

**批次 D 完成门槛**

- [ ] 用户能在 10 秒内回答接入状态、当前来源、费用覆盖、时间和下一动作。
- [ ] 自动刷新不打断 VoiceOver；手动刷新完成只播报一次。
- [ ] 新页面支持 RTL，既有 Dashboard 布局行为没有被扩大修改。

---

## 批次 E：隐私披露与发布验收

### Task E1：同步四份隐私正文

**Files**

- Modify: PRIVACY.md
- Modify: PRIVACY.zh-CN.md
- Modify: docs/privacy/index.md
- Modify: docs/privacy/zh-CN.md
- Inspect: TokenWatch/PrivacyInfo.xcprivacy
- Inspect: TokenWatch/TokenWatch.entitlements
- Inspect: TokenWatch.xcodeproj/project.pbxproj

**披露内容**

- 本地保存可重建增量缓存、Provider 聚合/诊断快照和 App Group Widget 裁剪快照。
- StoreKit 购买/恢复由 Apple 处理，隐私/支持链接由默认浏览器打开。
- 无自建遥测或用量上传；用户选择目录只读，原始日志永不修改或删除。
- 不承诺 P0-5 尚未实现的清除按钮，也不再笼统声称 App 本身完全不发生任何网络相关系统流程。

- [ ] 同步英文、中文及两份站点镜像正文；只保留站点 front matter 差异。
- [ ] 静态比较仓库正文与站点正文，确认无语义漂移。
- [ ] 运行 plutil -lint TokenWatch/PrivacyInfo.xcprivacy。
- [ ] 确认 PrivacyInfo、entitlements、ENABLE_APP_SANDBOX、ENABLE_USER_SELECTED_FILES、ENABLE_OUTGOING_NETWORK_CONNECTIONS 无非预期变更。
- [ ] 提交：docs(privacy): 对齐本地缓存与系统服务披露

### Task E2：补齐确定性 UI 场景和跨层回归

**Files**

- Modify: TokenWatch/AppDelegate.swift
- Modify: TokenWatchUITests/TokenWatchUITests.swift
- Modify: TokenWatchTests/TokenWatchTests.swift
- Inspect: TokenWatchTests/Diagnostics/DataTrustCenterSnapshotTests.swift
- Inspect: TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift
- Inspect: TokenWatchTests/Services/LegacyDataCacheMigratorTests.swift
- Inspect: TokenWatchTests/Providers/ProviderStatsSnapshotStoreTests.swift
- Inspect: TokenWatchTests/Analytics/UsageCostResolverTests.swift
- Inspect: TokenWatchTests/Providers/OpenCode/OpenCodeSQLiteScannerTests.swift

**接口与不变量**

- DEBUG-only test seam 固定使用四个启动参数值：`--ui-data-trust-fixture=healthy`、`--ui-data-trust-fixture=attention`、`--ui-data-trust-fixture=limited`、`--ui-data-trust-fixture=persisted`；它只能注入无路径、无私人日志的确定性可信状态，Release 编译中不可用，未知值直接忽略。
- UI smoke 至少覆盖导航、healthy/attention/limited 中的代表状态、Provider 深链、设置定位和 AX identifiers。
- 完整状态矩阵留在 unit/presentation 测试，UI 不依赖真实用户目录或 App Group entitlement。
- 跨层回归必须包含未授权启动迁移、同路径根替换、快照 remove 失败、非法 upstream、价格过期边界和 opencode 全局失败三种回退；UI fixture 不替代这些领域测试。

- [ ] 增加四个确定性 fixture 的参数解析、注入和进程级清理，证明无参数/未知参数的正常启动不读取 test seam，Release 源码路径被 `#if DEBUG` 完整隔离。
- [ ] 运行定向 UI smoke，并保存失败时的 xcresult 到 .build/TestResults。
- [ ] 运行所有 diagnostics、provider、pricing、snapshot、ViewModel、Dashboard、localization 单元 suite。
- [ ] 提交：test(data-health): 覆盖可信状态关键流程

### Task E3：完成发布验收并回写路线图

**Files**

- Modify: docs/superpowers/plans/2026-08-11-p0-feature-roadmap.md
- Modify: docs/superpowers/plans/2026-08-28-data-trust-center.md
- Modify: docs/superpowers/specs/2026-08-11-data-trust-center-design.md（仅勾选最终验收和记录已知限制）
- Modify: fastlane/metadata/en-US/release_notes.txt
- Modify: fastlane/metadata/zh-Hans/release_notes.txt

**验证顺序**

- [ ] 运行完整 unit tests：

      xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test

- [ ] 在可连接 testmanagerd 的环境运行完整 UI tests：

      xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchUITests -skip-testing:TokenWatchTests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- CODE_SIGN_ENTITLEMENTS= test

- [ ] 运行 Debug build：

      xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

- [ ] 运行 Release universal build：

      xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Release -destination 'generic/platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO ARCHS='arm64 x86_64' build

- [ ] 用 lipo -archs 验证 Release 主二进制同时包含 arm64 与 x86_64。
- [ ] 验证构建产物恰有 65 份 Localizable.strings，新增文案无 raw key、空值或 placeholder 漂移。
- [ ] 验证 AppStringKey 总数为 280，新增集合与详细设计冻结的 91 个 key 完全相等。
- [ ] 验证未授权启动会清理 v1 聚合快照与旧原字节 JSONL cache；移除失败测试稳定生成 legacyCacheCleanupFailed，外部 JSONL/SQLite hash 不变。
- [ ] 验证非法/非有限 upstream、validThrough 边界、独立 catalog fallback、adjustments 与 pipeline canonical serialization 的全量回归。
- [ ] 静态审计生产代码无 TODO/FIXME、无 DataTrust raw path/error 输出、无 UserNotifications、新 Provider 或网络依赖。
- [ ] 运行 git diff --check，确认 project.pbxproj、entitlements、PrivacyInfo 无非预期 diff。
- [ ] 同步中英文发布说明；把 P0-1 路线图状态改为待验收。人工 UI、VoiceOver、键盘、长文案和隐私验收完成后改为已完成并记录日期、结果与已知限制。
- [ ] 提交：test(data-health): 完成发布验收并回写路线图

## 提交序列

1. fix(dashboard): 修正用量与费用可信口径
2. feat(diagnostics): 建立数据可信状态契约
3. fix(privacy): 移除增量缓存中的原始字节
4. feat(provider): 上送结构化扫描事实
5. feat(provider): 补充 JSONL 解析诊断
6. feat(opencode): 上送 SQLite 解析诊断
7. feat(pricing): 返回可审计的费用来源
8. feat(analytics): 聚合费用覆盖报告
9. feat(cache): 添加数据口径版本摘要
10. feat(snapshot): 升级可信聚合快照
11. feat(view-model): 接入可信时间与数据来源
12. feat(localization): 添加数据质量页面文案
13. feat(data-health-ui): 实现数据可信度页面
14. feat(navigation): 接入数据质量入口与修复动作
15. docs(privacy): 对齐本地缓存与系统服务披露
16. test(data-health): 覆盖可信状态关键流程
17. test(data-health): 完成发布验收并回写路线图

## 回滚策略

- UI 或导航问题先逆序回滚 D4、D3；底层可信模型可以继续保留而不暴露。
- snapshot 回滚必须先停止新 writer，再回滚 reader/schema；旧 v2 文件视为可重建缓存，不尝试降级写成 v1。
- pricing、Provider、diagnostics 按 C2/C1、B4/B3/B2、A2 逆序回滚；Dashboard 正确性修复无需随功能 UI 回滚。
- 原始缓存字节最小化和隐私披露是独立安全修复，即使可信度 UI 回滚也应保留。
- 任何回滚最多导致 TokenWatch 可重建缓存失效，不能删除 Bookmark、StoreKit 权益或外部原始日志。

## 计划自检

- [ ] 五个批次恰好覆盖确认设计的口径、诊断、费用、快照、UI、隐私和验收，没有会话 2.0、预算、提醒或清除 UI。
- [ ] 每个生产行为都有对应 RED、定向 GREEN 和相邻回归。
- [ ] 每个提交单一职责、可独立构建、可逆且使用中文 message。
- [ ] 所有新增文件归属正确的 filesystem-synchronized root，project.pbxproj 无需手工引用。
- [ ] 计划中没有 TODO、TBD、占位符或需要实施者重新决定的产品取舍。
