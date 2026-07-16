# App Review 目录授权与支持页整改设计

## 背景

App Review 在 2026 年 7 月 15 日对版本 1.0（8）再次提出两项问题：

- Guideline 2.4.5(i)：应用仍然使用或提供预设的 Home Folder。审核截图中的标准目录面板显示 “AI Token Watch wants to access your home folder”。
- Guideline 1.5：App Store Connect 当前填写的 Support URL `https://github.com/OrrHsiao/TokenWatch/issues` 没有向普通用户提供清晰、直接的支持联系方式。

2026 年 7 月 14 日的修复只删除了对 `NSOpenPanel.directoryURL` 的显式赋值，但保留了首次启动自动弹窗、Home Folder 文案、三个 provider 共享 `HomeDirectoryBookmark`，以及把所选 URL 当作用户主目录再拼接隐藏子目录的完整行为。因此，该修复没有改变审核员实际看到的授权语义。

## 目标

1. 应用启动时不主动显示文件选择器，任何授权面板都只能由用户明确点击触发。
2. Claude Code、Codex 和 opencode 分别使用用户选择的数据目录及独立的 security-scoped bookmark。
3. 应用不预设、推荐或请求整个 Home Folder，也不再把所选目录解释为用户主目录。
4. 保持 App Sandbox 和只读 User Selected Files 权限，不扩大 entitlement。
5. 提供公开、无需登录即可联系开发者的支持页，并将完整 URL 用作 App Store Connect Support URL。
6. 覆盖审核员的全新安装路径，并准备可直接提交的英文 Review Notes 和回复文案。

## 非目标

- 不自动探测或绕过标准文件选择器获取用户目录。
- 不改为 Full Disk Access，不增加 Home-relative、Downloads、Documents 等固定位置 entitlement。
- 不改变 usage 解析、聚合或定价规则；provider 只调整授权根目录的语义。
- 不迁移旧 Home Folder bookmark 到新的 provider bookmark。
- 不在本次代码修改中自动操作 App Store Connect；Support URL 仍需在页面发布并验证后手动填写。

## 方案选择

采用“每个 provider 独立选择数据根目录”的方案。

未采用以下方案：

- 选择具体叶子文件或多个子目录：权限范围更窄，但 Claude Code 和 Codex 数据跨多个子目录，会产生更多 bookmark，也容易遗漏归档会话和配置。
- 继续选择共同父目录：改动较小，但实际仍会引导用户选择 Home，无法可靠消除本次审核风险。

## 授权架构

### Provider 契约

每个 `UsageProvider` 拥有独立的 bookmark key 和选择器说明文案。用户所选 URL 直接代表该 provider 的数据根目录，不再代表 Home。

| Provider | Bookmark key | 用户选择目录后的读取语义 |
| --- | --- | --- |
| Claude Code | `ClaudeDataDirectoryBookmark` | 从所选目录的 `projects` 等 Claude 数据子目录读取 |
| Codex | `CodexDataDirectoryBookmark` | 从所选目录的 `sessions`、归档会话和配置读取 |
| opencode | `OpenCodeDataDirectoryBookmark` | 从所选目录读取 `opencode.db` |

provider 不要求目录必须位于固定绝对路径，也不强制目录名称。这样既支持用户实际选择，也允许工具使用自定义数据位置。

### 启动流程

- 删除首次启动自动授权行为；应用启动后只调用现有数据加载流程。
- 未保存 provider bookmark 时，该 provider 进入“需要选择数据文件夹”状态，不弹出面板。
- 不再读取 `TokenWatch.didPromptInitialHomeAuthorization`。
- 启动时删除遗留的 `HomeDirectoryBookmark` 和旧首次提示标记；旧 bookmark 不解析、不恢复、不迁移。
- 其他设置、窗口偏好和自动刷新配置保持不变。

### 标准目录选择器

- 继续使用 AppKit `NSOpenPanel` 和只读 User Selected Files entitlement。
- 面板只能由对应 provider 的“选择文件夹”或“重新选择”按钮触发。
- 面板允许单选目录，不允许选择文件，不允许多选，并继续显示隐藏项目，方便用户导航到工具数据目录。
- 不设置 `directoryURL`，不提供 Home 快捷预设，也不在文案中使用 Home Folder 或用户目录语义。
- 面板说明使用 provider 名称，例如 “Choose the Claude Code data folder”。确认按钮使用中性的 “Choose”。
- 用户确认后，只为 `panel.url` 创建并保存对应 provider 的 security-scoped bookmark。

### Security-scoped bookmark 生命周期

- bookmark 创建成功后才替换该 provider 的已有 bookmark；取消或创建失败时保留旧授权。
- 加载时只恢复当前 provider 的 bookmark，并在读取结束后成对停止 security-scoped 访问。
- bookmark 解析、过期刷新或 `startAccessingSecurityScopedResource()` 失败时，只清除当前 provider 的 bookmark，并将其状态恢复为需要选择文件夹。
- 现有访问会话引用计数机制保留为通用实现，但不同 provider 不再共享 key。

## 数据流

1. 用户在设置页点击某个 provider 的“选择文件夹”。
2. `TokenStatsViewModel.requestAuthorization(for:)` 请求 bookmark manager 展示 provider 专属 `NSOpenPanel`。
3. 用户取消时流程结束且不改变状态；用户确认时保存该 provider bookmark。
4. ViewModel 只更新该 provider 的授权状态，并通过 `loadStats(for:)` 只加载该 provider；不因一次授权重新加载其他 provider。
5. provider 将恢复得到的 URL 直接当作自己的数据根目录扫描，不再追加 `.claude`、`.codex` 或 `.local/share/opencode` 之前的 Home 层级。
6. 聚合层和 UI 继续接收现有 `ParsedUsageEntry`，无需感知授权模型变化。

## 设置页交互

用“数据文件夹”区域替换现有“通用访问权限”单行控件，包含 Claude Code、Codex 和 opencode 三行。

每行显示：

- provider 名称；
- 独立状态：“未选择”“已选择”或“需要重新选择”；
- 操作按钮：“选择文件夹”“重新选择”或“再次选择”。

按钮只操作对应 provider。选择成功后其他 provider 的状态不变。全局刷新、自动刷新、开机启动和语言设置保持原有布局与行为。

总览和会话页在尚无任何数据时，将原来的“请授权 Home Folder”提示改为“请在设置中选择一个或多个数据文件夹”。部分 provider 未授权时不覆盖已授权 provider 的可用数据。

## 错误处理

- 用户取消：不写 bookmark、不显示错误、不改变已有授权。
- bookmark 创建或保存失败：记录简洁错误日志，并显示对应 provider 的本地化授权失败信息。
- 所选目录没有预期数据：保留用户选择，不把它判定为授权失败；该 provider 显示“所选文件夹中未发现数据，可重新选择”。
- 重新选择失败：旧 bookmark 和旧数据状态保持可用。
- bookmark 恢复失败：只影响当前 provider，并提供“再次选择”入口。

所有新增状态、按钮、选择器说明和错误信息覆盖现有全部应用语言。支持网页提供英文主页和简体中文页面。

## 应用内支持入口

在现有应用菜单的 Privacy Policy 附近新增 “Support” 项，使用默认浏览器打开：

`https://orrhsiao.github.io/TokenWatch/support/`

应用不直接发起网络请求，因此无需改变当前网络 entitlement。

## 支持页与文档

### 页面

新增：

- `docs/support/index.md`，固定 permalink `/support/`；
- `docs/support/zh-CN.md`，固定 permalink `/support/zh-CN/`。

英文主页至少包含：

- 明确的 “AI Token Watch Support” 标题；
- 可点击邮箱 `mailto:orrhsiao@126.com`；
- 说明该邮箱接受应用问题、一般反馈和功能建议；
- Bug Report 直达链接；
- Feature Request 直达链接；
- Privacy Policy 链接；
- 提交 App 版本、macOS 版本、数据源和复现步骤的说明；
- 删除 API key、prompt、response、私人项目路径和原始使用记录的隐私提醒。

GitHub Issues 只作为辅助渠道。没有 GitHub 账号的用户仍可通过公开邮箱请求支持。

### 现有文档同步

- 更新英文和中文 README 的安装、首次运行、架构与隐私说明，移除“一次授权用户目录”的描述。
- 更新网页和仓库内隐私政策的 Contact 部分，直接指向支持页与支持邮箱，消除当前循环引用 App Store 产品页的文案。
- 保留隐私政策原有数据收集声明，只把文件访问描述改成按 provider 选择数据目录。

### App Store Connect

页面发布后，先确认以下 URL 无需登录且返回 HTTP 200：

`https://orrhsiao.github.io/TokenWatch/support/`

随后把该完整 HTTPS URL 填入 App Store Connect 的 Support URL 字段。不能填写相对路径 `/support/`，也不再填写 GitHub Issues 列表 URL。

## 测试设计

### 单元测试

- 启动策略：全新状态与已有部分 bookmark 的状态都不会请求或展示授权面板，只执行数据加载。
- Provider 注册表：三个 bookmark key 互不相同，面板文案不包含 Home Folder 语义。
- Provider 根目录：Claude、Codex、opencode 都直接从用户选择的数据根目录加载现有 fixture。
- 面板配置：目录单选、显示隐藏项目、provider 专属文案，并保持系统管理的初始目录不被覆盖。
- Bookmark：取消、保存失败、重新选择失败、过期 bookmark 和各 provider 独立恢复均符合错误处理约定。
- ViewModel：授权一个 provider 不改变其他 provider 状态；已授权数据与未授权状态可并存。
- 设置页：三行状态与按钮独立，按钮把正确的 `ProviderID` 传给 ViewModel。
- 本地化：所有新增 key 在现有语言表中完整覆盖。
- 应用菜单：Support 项存在，且打开固定的 HTTPS 支持页 URL。

### UI 测试

- 使用真实全新启动路径，断言应用启动后没有自动出现文件选择器。
- 打开设置页，断言三个 provider 的文件夹选择控件均存在且可访问。
- 用户点击某一 provider 后只出现一次标准目录面板，取消后仍停留在未选择状态。
- 不再通过 `TokenWatch.didPromptInitialHomeAuthorization` 参数跳过审核路径。

### 静态与构建验证

- 生产代码不存在 `NSOpenPanel.directoryURL` 赋值。
- 除仅用于删除遗留数据的常量外，生产代码不把 `HomeDirectoryBookmark` 用作任何活跃授权 key；应用可见文案不存在 Home Folder 授权或共享用户目录授权语义。
- 运行全部单元测试和 UI 测试。
- 完成 Debug 与 Release 构建。
- 检查支持页 front matter、内部链接和邮箱链接；发布后再验证线上 HTTP 200。

## 审核交付物

实施完成后提供：

1. 可填写到 App Store Connect 的 Support URL。
2. 英文 Review Notes，说明首次启动不再弹窗、每个 provider 由用户主动选择数据目录以及 entitlement 仍为只读 User Selected Files。
3. 对本次 Guideline 2.4.5(i) 和 1.5 消息的英文回复。
4. 审核员可复现的测试步骤：启动应用、进入 Settings、分别点击 provider 的选择按钮、确认没有 Home 预设。

## 验收标准

- 全新安装启动时没有授权面板。
- 所有授权面板都由明确用户动作触发，并且不预设或推荐 Home Folder。
- 三个 provider 的权限范围、bookmark 和状态相互独立。
- 应用不再恢复或使用旧 Home Folder bookmark。
- 未选择或无数据的 provider 不影响其他 provider 的已加载数据。
- 应用内 Support 项和公开支持页都提供易于使用的联系方式。
- 支持页公开可访问后，App Store Connect 使用完整 HTTPS URL。
- 测试、静态检查和 Debug/Release 构建全部通过。
