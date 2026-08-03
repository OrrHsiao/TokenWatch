# App Review 支持页与支持入口 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 提供无需登录即可联系开发者的公开支持页，把固定 HTTPS URL 接入应用主菜单，并准备 App Store Connect 可直接使用的 Support URL、Review Notes 和审核回复。

**Architecture:** 应用主菜单通过可注入的 URL opener 打开单一 `AppDelegate.supportURL`，应用自身不发起网络请求。GitHub Pages 的 `/support/` 英文主页以公开邮箱为主要渠道，Bug/Feature GitHub 表单为辅助渠道，并链接现有隐私政策。仓库内与网页隐私政策使用相同正文，直接指向支持页和邮箱。审核材料保存在 `app-store/review/`，避免被 `docs` Pages 发布；Pages 线上返回 200 且正文验证通过后才能填写 Support URL，而 Review Notes/Reply 还必须等包含整改的新 binary 完成 processing 并被当前 submission 选中后才能发送。

**Tech Stack:** Swift 6、AppKit `NSMenu` / `NSWorkspace`、Swift Testing、Jekyll-compatible Markdown、GitHub Pages、Ruby 静态校验、GitHub CLI、curl

## Global Constraints

- 先完整执行并验证 `2026-07-16-provider-directory-authorization.md`，再执行本计划；Review Notes 不得提前声称目录修复已通过。
- 主菜单只新增 “Support”；现有 Dashboard 侧边栏 Privacy Policy 入口保持不变，不新增主菜单 Privacy 项。
- 固定 Support URL 为 `https://orrhsiao.github.io/TokenWatch/support/`；不得填写相对路径或 GitHub Issues 列表 URL。
- 支持邮箱固定公开为 `orrhsiao@126.com`，正文必须同时显示纯文本地址和 `mailto:` 链接。
- GitHub Issues 只能描述为可选的公开辅助渠道；没有 GitHub 账号的用户必须仍可通过邮箱联系。
- 不修改 App Sandbox、readonly User Selected Files、outgoing network entitlement 或 `PrivacyInfo.xcprivacy`。`project.pbxproj` 只允许在 Task 5 Step 7 把 app target 的 Debug/Release `CURRENT_PROJECT_VERSION` 更新为 App Store Connect 中尚未使用且大于 8 的构建号；不得改变其他 build setting。
- 不新增运行时网络请求；Support 和 Privacy 都只交给默认浏览器。
- `docs/_config.yml` 已排除 `superpowers/`，但不会排除其他 `docs` 子目录；Review Notes 必须位于仓库根部 `app-store/review/`，不能放到 `docs/`。
- Pages 当前发布源是 `main:/docs`。本地文件或 PR 存在不代表 Support URL 可用；必须等目标 commit 的 Pages build 完成，并用无 cookie 的 curl 验证最终 HTTP 200、标题和邮箱。
- 本地 Debug/Release build 不等于 App Store build。Review Notes 和审核回复只能在包含整改的新 binary 上传完成处理、并被当前 submission 明确选中后发送。
- 每个代码行为先写 RED 测试。文档任务先运行会失败的内容校验，再写正文并跑 GREEN。
- 测试与构建使用 `-derivedDataPath .build/DerivedData`；app-hosted tests 必须在真实 `testmanagerd` 环境运行。
- 提交信息使用中文 Conventional Commit 格式（例如 `docs(support): 新增中英文支持页面`）；发布前工作树必须干净，且不得把未验证的 URL 写入 App Store Connect。

---

## 文件职责

### 应用与测试

- `TokenWatch/AppDelegate.swift`：固定 URL、可注入 opener 和 `openSupport(_:)`。
- `TokenWatch/AppMainMenuBuilder.swift`：在 Refresh 后加入 Support 菜单项。
- `TokenWatch/Localization/AppStrings.swift`：12 语言 `.support` 文案。
- `TokenWatchTests/AppMainMenuBuilderTests.swift`：菜单结构、selector、target 和固定 URL 行为。
- `TokenWatchTests/Localization/AppLanguageSettingsTests.swift`：12 语言显式值覆盖。

### 网站与审核材料

- Create: `docs/support/index.md`
- Create: `docs/support/zh-CN.md`
- Modify: `PRIVACY.md`
- Modify: `PRIVACY.zh-CN.md`
- Modify: `docs/privacy/index.md`
- Modify: `docs/privacy/zh-CN.md`
- Create: `app-store/review/2026-07-16.md`

明确不修改：`TokenWatch/ViewControllers/DashboardViewController.swift` 的 Privacy Policy 入口、`.github/ISSUE_TEMPLATE/*`、`docs/_config.yml`、`.github/workflows/*` 和工程 entitlement。

---

### Task 1: 在应用主菜单加入固定 Support URL

**Files:**
- Modify: `TokenWatch/AppDelegate.swift:8-35,87-100`
- Modify: `TokenWatch/AppMainMenuBuilder.swift:16-68`
- Modify: `TokenWatch/Localization/AppStrings.swift:8-148,185-1875`
- Modify: `TokenWatchTests/AppMainMenuBuilderTests.swift:8-115`
- Modify: `TokenWatchTests/Localization/AppLanguageSettingsTests.swift:115-179`

**Interfaces:**
- Produces: `AppDelegate.supportURL`。
- Produces: `@objc func openSupport(_:)`。
- Adds initializer dependency: `externalURLOpener: (URL) -> Bool`。
- Produces localized key: `AppStringKey.support`。

- [ ] **Step 1: 写菜单、URL 行为和完整本地化 RED 测试**

将 `applicationMenuContainsOnlySupportedCommands()` 的英文期望改为：

```swift
#expect(items.map(\.title) == [
    "About AI Token Watch",
    "Open AI Token Watch",
    "Settings...",
    "Refresh Now",
    "Support",
    "Hide AI Token Watch",
    "Hide Others",
    "Show All",
    "Quit AI Token Watch",
])
#expect(items.map { $0.action.map(NSStringFromSelector) } == [
    "orderFrontStandardAboutPanel:",
    "openMainWindow:",
    "showSettings:",
    "refreshNow:",
    "openSupport:",
    "hide:",
    "hideOtherApplications:",
    "unhideAllApplications:",
    "terminate:",
])
#expect(items[1].target === actionTarget)
#expect(items[2].target === actionTarget)
#expect(items[3].target === actionTarget)
#expect(items[4].target === actionTarget)
```

另加一个不经过 separator 过滤的相邻关系测试，锁定 Support 必须紧跟 Refresh 且后面仍是原分隔符：

```swift
@Test("Support 位于 Refresh 与原分隔符之间")
func supportItemIsAdjacentToRefreshAndSeparator() throws {
    let actionTarget = AppDelegate()
    let menu = AppMainMenuBuilder.build(actionTarget: actionTarget)
    let appMenu = try #require(menu.items.first?.submenu)
    let supportIndex = try #require(
        appMenu.items.firstIndex {
            $0.action == #selector(AppDelegate.openSupport(_:))
        }
    )

    try #require(supportIndex > 0)
    try #require(appMenu.items.indices.contains(supportIndex + 1))
    #expect(
        appMenu.items[supportIndex - 1].action
            == #selector(AppDelegate.refreshNow(_:))
    )
    #expect(appMenu.items[supportIndex + 1].isSeparatorItem)
}
```

将中文菜单期望在“立即刷新”后加入“支持”。新增 URL side-effect 测试：

```swift
@Test("Support 命令打开固定 HTTPS 页面")
func supportCommandOpensFixedHTTPSURL() {
    var openedURLs: [URL] = []
    let actionTarget = AppDelegate(
        languageSettings: .shared,
        externalURLOpener: { url in
            openedURLs.append(url)
            return true
        }
    )

    actionTarget.openSupport(nil)

    #expect(openedURLs == [AppDelegate.supportURL])
    #expect(
        AppDelegate.supportURL.absoluteString
            == "https://orrhsiao.github.io/TokenWatch/support/"
    )
    #expect(AppDelegate.supportURL.scheme == "https")
}
```

在 `AppLanguageSettingsTests` 增加：

```swift
@Test("Support 文案显式覆盖全部支持语言")
func supportStringCoversEverySupportedLanguage() {
    let expected: [AppLanguage: String] = [
        .zhHans: "支持",
        .zhHant: "支援",
        .en: "Support",
        .ja: "サポート",
        .ko: "지원",
        .es: "Soporte",
        .de: "Support",
        .fr: "Assistance",
        .ptBR: "Suporte",
        .it: "Supporto",
        .nl: "Ondersteuning",
        .pl: "Wsparcie",
    ]

    #expect(expected.count == AppLanguage.allCases.count)
    for (language, text) in expected {
        #expect(AppStrings.text(.support, language: language) == text)
    }
}
```

这项显式测试不能用现有 `allStringKeysResolveToNonEmptyText()` 替代，因为后者的英文 fallback 会掩盖非英语表漏项。

- [ ] **Step 2: 运行测试并确认 RED**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchTests/AppMainMenuBuilderTests/applicationMenuContainsOnlySupportedCommands()' \
  '-only-testing:TokenWatchTests/AppMainMenuBuilderTests/mainMenuUsesChineseTitlesWhenLanguageIsChinese()' \
  '-only-testing:TokenWatchTests/AppMainMenuBuilderTests/supportCommandOpensFixedHTTPSURL()' \
  '-only-testing:TokenWatchTests/AppMainMenuBuilderTests/supportItemIsAdjacentToRefreshAndSeparator()' \
  '-only-testing:TokenWatchTests/AppLanguageSettingsTests/supportStringCoversEverySupportedLanguage()' \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test
```

Expected: FAIL；缺少 `.support`、`supportURL`、`openSupport`、opener initializer 或菜单项。

- [ ] **Step 3: 实现 URL opener 和主菜单项**

在 `AppDelegate` 增加：

```swift
static let supportURL = URL(
    string: "https://orrhsiao.github.io/TokenWatch/support/"
)!

private let externalURLOpener: (URL) -> Bool
```

保持当前两个 initializer，但让它们都初始化 opener：

```swift
override init() {
    self.languageSettings = .shared
    self.externalURLOpener = { NSWorkspace.shared.open($0) }
    super.init()
}

init(
    languageSettings: AppLanguageSettings,
    externalURLOpener: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
) {
    self.languageSettings = languageSettings
    self.externalURLOpener = externalURLOpener
    super.init()
}
```

增加带注释和失败日志的 action：

```swift
/// 使用默认浏览器打开公开支持页面。
@objc func openSupport(_ sender: Any?) {
    guard externalURLOpener(Self.supportURL) else {
        NSLog("TokenWatch failed to open the support page")
        return
    }
}
```

在 `AppMainMenuBuilder.makeApplicationMenuItem` 的 Refresh item 后、现有分隔符前加入：

```swift
appMenu.addItem(makeApplicationItem(
    title: text(.support, language: language),
    action: #selector(AppDelegate.openSupport(_:)),
    target: actionTarget
))
```

在 `AppStringKey` 及 12 个语言表加入 Step 1 固定值。不要复用 `.privacyPolicy`，不要改 Dashboard 的 Privacy button。

- [ ] **Step 4: 运行测试并确认 GREEN**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchTests/AppMainMenuBuilderTests/applicationMenuContainsOnlySupportedCommands()' \
  '-only-testing:TokenWatchTests/AppMainMenuBuilderTests/mainMenuUsesChineseTitlesWhenLanguageIsChinese()' \
  '-only-testing:TokenWatchTests/AppMainMenuBuilderTests/supportCommandOpensFixedHTTPSURL()' \
  '-only-testing:TokenWatchTests/AppMainMenuBuilderTests/supportItemIsAdjacentToRefreshAndSeparator()' \
  '-only-testing:TokenWatchTests/AppLanguageSettingsTests/supportStringCoversEverySupportedLanguage()' \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test
```

Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 5: 提交应用内 Support 入口**

```bash
set -euo pipefail
git add TokenWatch/AppDelegate.swift \
  TokenWatch/AppMainMenuBuilder.swift \
  TokenWatch/Localization/AppStrings.swift \
  TokenWatchTests/AppMainMenuBuilderTests.swift \
  TokenWatchTests/Localization/AppLanguageSettingsTests.swift
git commit -m "feat(menu): 新增公开支持页入口"
```

---

### Task 2: 新增无需登录的英文与中文支持页

**Files:**
- Create: `docs/support/index.md`
- Create: `docs/support/zh-CN.md`

**Content contract:**
- English permalink `/support/`；中文 permalink `/support/zh-CN/`。
- 邮箱为主要渠道；Bug、Feature 和 Privacy 为清晰入口。
- 明确收集 app/build、macOS、provider、复现步骤、预期/实际行为。
- 明确警告删除 API key、prompt、response、私人项目路径、原始使用记录和原始 provider 文件。

- [ ] **Step 1: 先运行内容校验并确认 RED**

```bash
ruby -e '
contracts = {
  "docs/support/index.md" => {
    front_matter: "---\ntitle: AI Token Watch Support\npermalink: /support/\n---\n",
    needles: [
      "# AI Token Watch Support",
      "## Report a Bug",
      "## Request a Feature",
      "## Protect Your Privacy",
      "## Privacy Policy",
      "[简体中文](./zh-CN/)",
      "[orrhsiao@126.com](mailto:orrhsiao@126.com)",
      "GitHub Issues are an optional public channel.",
      "A GitHub account is not required to contact support by email.",
      "issues/new?template=bug_report.yml",
      "issues/new?template=feature_request.yml",
      "[AI Token Watch Privacy Policy](../privacy/)",
      "AI Token Watch version and build number",
      "macOS version",
      "affected data source",
      "steps to reproduce",
      "expected and actual behavior",
      "API keys",
      "prompts",
      "responses",
      "private project paths",
      "raw usage records",
      "original provider data files"
    ]
  },
  "docs/support/zh-CN.md" => {
    front_matter: "---\ntitle: AI Token Watch 支持\npermalink: /support/zh-CN/\n---\n",
    needles: [
      "# AI Token Watch 支持",
      "## 报告问题",
      "## 功能建议",
      "## 保护你的隐私",
      "## 隐私政策",
      "[English](../)",
      "[orrhsiao@126.com](mailto:orrhsiao@126.com)",
      "GitHub Issues 只是可选的公开渠道。",
      "通过邮箱联系支持不需要 GitHub 账号。",
      "issues/new?template=bug_report.yml",
      "issues/new?template=feature_request.yml",
      "[AI Token Watch 隐私政策](../../privacy/zh-CN/)",
      "AI Token Watch 版本和构建号",
      "macOS 版本",
      "涉及的数据源",
      "清晰的复现步骤",
      "预期行为和实际行为",
      "API key",
      "prompt",
      "response",
      "私人项目路径",
      "原始使用记录",
      "provider 的原始数据文件"
    ]
  }
}
contracts.each do |path, contract|
  abort("#{path}: missing") unless File.file?(path)
  text = File.read(path)
  prefix = contract.fetch(:front_matter) + "\n"
  abort("#{path}: front matter must be exactly four lines") unless text.start_with?(prefix)
  contract.fetch(:needles).each do |needle|
    abort("#{path}: missing #{needle}") unless text.include?(needle)
  end
end
'
```

Expected: FAIL with `docs/support/index.md: missing`。

- [ ] **Step 2: 创建英文支持主页**

`docs/support/index.md` 使用完整正文：

```markdown
---
title: AI Token Watch Support
permalink: /support/
---

# AI Token Watch Support

[简体中文](./zh-CN/)

Need help with AI Token Watch? Email [orrhsiao@126.com](mailto:orrhsiao@126.com). This address accepts app questions, general feedback, and feature suggestions.

GitHub Issues are an optional public channel. If you do not have a GitHub account, email us directly. A GitHub account is not required to contact support by email.

## Report a Bug

[Open the Bug Report form](https://github.com/OrrHsiao/TokenWatch/issues/new?template=bug_report.yml)

To help us investigate, include:

- your AI Token Watch version and build number, shown under **AI Token Watch > About AI Token Watch**;
- your macOS version;
- the affected data source: Claude Code, Codex, opencode, or more than one;
- clear steps to reproduce the problem;
- the expected and actual behavior.

You can send the same information by email instead of using GitHub.

## Request a Feature

[Open the Feature Request form](https://github.com/OrrHsiao/TokenWatch/issues/new?template=feature_request.yml)

You can also email feature suggestions and general feedback to [orrhsiao@126.com](mailto:orrhsiao@126.com).

## Protect Your Privacy

Before sending a report, remove or redact API keys, prompts, responses, private project paths, and raw usage records. Do not attach original provider data files. A small sanitized example is usually enough.

## Privacy Policy

Read the [AI Token Watch Privacy Policy](../privacy/).
```

- [ ] **Step 3: 创建简体中文支持页**

`docs/support/zh-CN.md` 使用完整正文：

```markdown
---
title: AI Token Watch 支持
permalink: /support/zh-CN/
---

# AI Token Watch 支持

[English](../)

如需 AI Token Watch 帮助，请发送邮件至 [orrhsiao@126.com](mailto:orrhsiao@126.com)。该邮箱接受应用问题、一般反馈和功能建议。

GitHub Issues 只是可选的公开渠道。如果你没有 GitHub 账号，可以直接发送邮件；通过邮箱联系支持不需要 GitHub 账号。

## 报告问题

[打开 Bug Report 表单](https://github.com/OrrHsiao/TokenWatch/issues/new?template=bug_report.yml)

为了帮助我们定位问题，请提供：

- AI Token Watch 版本和构建号，可在 **AI Token Watch > 关于 AI Token Watch** 中查看；
- macOS 版本；
- 涉及的数据源：Claude Code、Codex、opencode 或多个数据源；
- 清晰的复现步骤；
- 预期行为和实际行为。

你也可以通过邮箱发送同样的信息，无需使用 GitHub。

## 功能建议

[打开 Feature Request 表单](https://github.com/OrrHsiao/TokenWatch/issues/new?template=feature_request.yml)

也可以将功能建议和一般反馈发送至 [orrhsiao@126.com](mailto:orrhsiao@126.com)。

## 保护你的隐私

提交信息前，请删除或遮盖 API key、prompt、response、私人项目路径和原始使用记录。请勿附加 provider 的原始数据文件；通常只需提供经过清理的最小示例。

## 隐私政策

阅读 [AI Token Watch 隐私政策](../../privacy/zh-CN/)。
```

使用相对链接是为了让 GitHub Pages 保留 `/TokenWatch` 项目基路径；不要改成站点根绝对路径 `/privacy/`。

- [ ] **Step 4: 运行内容校验并确认 GREEN**

```bash
ruby -e '
contracts = {
  "docs/support/index.md" => {
    front_matter: "---\ntitle: AI Token Watch Support\npermalink: /support/\n---\n",
    needles: [
      "# AI Token Watch Support",
      "## Report a Bug",
      "## Request a Feature",
      "## Protect Your Privacy",
      "## Privacy Policy",
      "[简体中文](./zh-CN/)",
      "[orrhsiao@126.com](mailto:orrhsiao@126.com)",
      "GitHub Issues are an optional public channel.",
      "A GitHub account is not required to contact support by email.",
      "issues/new?template=bug_report.yml",
      "issues/new?template=feature_request.yml",
      "[AI Token Watch Privacy Policy](../privacy/)",
      "AI Token Watch version and build number",
      "macOS version",
      "affected data source",
      "steps to reproduce",
      "expected and actual behavior",
      "API keys",
      "prompts",
      "responses",
      "private project paths",
      "raw usage records",
      "original provider data files"
    ]
  },
  "docs/support/zh-CN.md" => {
    front_matter: "---\ntitle: AI Token Watch 支持\npermalink: /support/zh-CN/\n---\n",
    needles: [
      "# AI Token Watch 支持",
      "## 报告问题",
      "## 功能建议",
      "## 保护你的隐私",
      "## 隐私政策",
      "[English](../)",
      "[orrhsiao@126.com](mailto:orrhsiao@126.com)",
      "GitHub Issues 只是可选的公开渠道。",
      "通过邮箱联系支持不需要 GitHub 账号。",
      "issues/new?template=bug_report.yml",
      "issues/new?template=feature_request.yml",
      "[AI Token Watch 隐私政策](../../privacy/zh-CN/)",
      "AI Token Watch 版本和构建号",
      "macOS 版本",
      "涉及的数据源",
      "清晰的复现步骤",
      "预期行为和实际行为",
      "API key",
      "prompt",
      "response",
      "私人项目路径",
      "原始使用记录",
      "provider 的原始数据文件"
    ]
  }
}
contracts.each do |path, contract|
  abort("#{path}: missing") unless File.file?(path)
  text = File.read(path)
  prefix = contract.fetch(:front_matter) + "\n"
  abort("#{path}: front matter must be exactly four lines") unless text.start_with?(prefix)
  contract.fetch(:needles).each do |needle|
    abort("#{path}: missing #{needle}") unless text.include?(needle)
  end
end
'
```

Expected: exit 0，无输出。

- [ ] **Step 5: 提交支持页面**

```bash
set -euo pipefail
git add docs/support/index.md docs/support/zh-CN.md
git commit -m "docs(support): 新增中英文支持页面"
```

---

### Task 3: 同步四份隐私政策的目录语义与直接联系方式

**Files:**
- Modify: `PRIVACY.md:1-33`
- Modify: `PRIVACY.zh-CN.md:1-33`
- Modify: `docs/privacy/index.md:1-38`
- Modify: `docs/privacy/zh-CN.md:1-38`

**Content contract:**
- Data Collection 原声明保持不变。
- Local File Access 改为 provider 分别选择、启动不弹窗、只读本地处理。
- Local Storage 改为 provider 独立 security-scoped bookmarks。
- Network Access 同时说明 Privacy 和 Support 交给默认浏览器，app 本身不联网。
- Contact 直接列支持页与 `mailto:orrhsiao@126.com`，不再循环引用 App Store 产品页。
- 英文网页/仓库正文完全相同；中文网页/仓库正文完全相同。

- [ ] **Step 1: 运行旧文案与正文一致性检查并确认 RED**

```bash
ruby -e '
contracts = [
  {
    repo: "PRIVACY.md",
    web: "docs/privacy/index.md",
    front_matter: "---\ntitle: AI Token Watch Privacy Policy\npermalink: /privacy/\n---\n",
    needles: [
      "[简体中文](https://orrhsiao.github.io/TokenWatch/privacy/zh-CN/)",
      "Effective Date: July 16, 2026",
      "does not collect, transmit, sell, share, or upload user data",
      "does not require an account or login. It does not include analytics, advertising, telemetry, tracking, or third-party SDKs",
      "does not display a file picker automatically when it launches",
      "separately choose a data folder for Claude Code, Codex, or opencode",
      "independent security-scoped bookmark for each provider folder",
      "The Privacy Policy and Support entries open public webpages in your default browser.",
      "[AI Token Watch Support page](https://orrhsiao.github.io/TokenWatch/support/)",
      "[orrhsiao@126.com](mailto:orrhsiao@126.com)",
      "A GitHub account is not required to contact support by email."
    ]
  },
  {
    repo: "PRIVACY.zh-CN.md",
    web: "docs/privacy/zh-CN.md",
    front_matter: "---\ntitle: AI Token Watch 隐私政策\npermalink: /privacy/zh-CN/\n---\n",
    needles: [
      "[English](https://orrhsiao.github.io/TokenWatch/privacy/)",
      "生效日期：2026 年 7 月 16 日",
      "不收集、传输、出售、分享或上传用户数据",
      "不需要账户或登录。它不包含分析、广告、遥测、追踪或第三方 SDK",
      "启动时不会自动显示文件选择器",
      "分别为 Claude Code、Codex 或 opencode 选择数据文件夹",
      "为你选择的每个 provider 文件夹分别保存 security-scoped bookmark",
      "“隐私政策”和“支持”入口会使用你的默认浏览器打开公开网页。",
      "[AI Token Watch 支持页](https://orrhsiao.github.io/TokenWatch/support/)",
      "[orrhsiao@126.com](mailto:orrhsiao@126.com)",
      "通过电子邮件联系支持不需要 GitHub 账号。"
    ]
  }
]
forbidden = [
  "support contact listed on the App Store product page",
  "App Store 产品页面列出的支持联系方式",
  "https://github.com/OrrHsiao/TokenWatch/issues"
]
contracts.each do |contract|
  repo_text = File.read(contract.fetch(:repo))
  web_text = File.read(contract.fetch(:web))
  prefix = contract.fetch(:front_matter) + "\n"
  abort("#{contract.fetch(:web)}: front matter must be exactly four lines") unless web_text.start_with?(prefix)
  web_body = web_text.delete_prefix(prefix)
  abort("#{contract.fetch(:repo)} and #{contract.fetch(:web)} drifted") unless repo_text == web_body
  contract.fetch(:needles).each do |needle|
    abort("#{contract.fetch(:repo)}: missing #{needle}") unless repo_text.include?(needle)
  end
  forbidden.each do |needle|
    abort("#{contract.fetch(:repo)}: still contains #{needle}") if repo_text.include?(needle)
  end
end
'
```

Expected: FAIL，因为当前日期、目录语义、联系方式和网页/仓库正文尚未满足 contract。

- [ ] **Step 2: 写统一英文正文**

`PRIVACY.md` 和 `docs/privacy/index.md` 去除 front matter 后的正文都固定为：

```markdown
# AI Token Watch Privacy Policy

[简体中文](https://orrhsiao.github.io/TokenWatch/privacy/zh-CN/)

Effective Date: July 16, 2026

AI Token Watch is a local-only macOS app for summarizing token usage from coding-agent records on your Mac.

## Data Collection

AI Token Watch does not collect, transmit, sell, share, or upload user data.

AI Token Watch does not require an account or login. It does not include analytics, advertising, telemetry, tracking, or third-party SDKs.

## Local File Access

AI Token Watch does not display a file picker automatically when it launches. In Settings, you may separately choose a data folder for Claude Code, Codex, or opencode. The app uses each selected folder directly as that provider's data root and reads it with read-only access granted through the standard macOS file picker.

All parsing, aggregation, and cost estimation happen locally on your device. An unselected provider does not prevent the app from using data from providers you selected.

The app may display local information derived from those files, such as token counts, model names, session identifiers, and project paths. This information remains on your device.

## Local Storage

AI Token Watch stores app preferences and an independent security-scoped bookmark for each provider folder you select in local UserDefaults. This lets the app remember settings and restore only the folder access you granted. This data is stored only on your device and is not transmitted anywhere.

## Network Access

AI Token Watch itself does not access the network. The Privacy Policy and Support entries open public webpages in your default browser.

## Contact

For privacy questions or app support, visit the [AI Token Watch Support page](https://orrhsiao.github.io/TokenWatch/support/) or email [orrhsiao@126.com](mailto:orrhsiao@126.com). A GitHub account is not required to contact support by email.
```

网页文件在该正文前保留自己的四行 front matter；仓库文件不加 front matter。

- [ ] **Step 3: 写统一简体中文正文**

`PRIVACY.zh-CN.md` 和 `docs/privacy/zh-CN.md` 去除 front matter 后的正文都固定为：

```markdown
# AI Token Watch 隐私政策

[English](https://orrhsiao.github.io/TokenWatch/privacy/)

生效日期：2026 年 7 月 16 日

AI Token Watch 是一款仅在本地运行的 macOS 应用，用于汇总你 Mac 上 coding agent 记录中的 token 用量。

## 数据收集

AI Token Watch 不收集、传输、出售、分享或上传用户数据。

AI Token Watch 不需要账户或登录。它不包含分析、广告、遥测、追踪或第三方 SDK。

## 本地文件访问

AI Token Watch 启动时不会自动显示文件选择器。你可以在设置中分别为 Claude Code、Codex 或 opencode 选择数据文件夹。应用会把每个所选文件夹直接作为对应 provider 的数据根目录，并通过标准 macOS 文件选择器授予的只读权限进行读取。

所有解析、汇总和费用估算都在你的设备本地完成。未选择的 provider 不会阻止应用使用你已选择的其他 provider 数据。

应用可能会显示从这些文件中得到的本地信息，例如 token 数量、模型名称、会话标识符和项目路径。这些信息会保留在你的设备上。

## 本地存储

AI Token Watch 会在本地 UserDefaults 中保存应用偏好设置，并为你选择的每个 provider 文件夹分别保存 security-scoped bookmark。这样应用可以记住设置，并且只恢复你已授予的文件夹访问权限。这些数据只存储在你的设备上，不会被传输到任何地方。

## 网络访问

AI Token Watch 应用本身不访问网络。“隐私政策”和“支持”入口会使用你的默认浏览器打开公开网页。

## 联系方式

如有隐私问题或需要应用支持，请访问 [AI Token Watch 支持页](https://orrhsiao.github.io/TokenWatch/support/)，或发送邮件至 [orrhsiao@126.com](mailto:orrhsiao@126.com)。通过电子邮件联系支持不需要 GitHub 账号。
```

- [ ] **Step 4: 运行同步与旧文案检查并确认 GREEN**

```bash
ruby -e '
contracts = [
  {
    repo: "PRIVACY.md",
    web: "docs/privacy/index.md",
    front_matter: "---\ntitle: AI Token Watch Privacy Policy\npermalink: /privacy/\n---\n",
    needles: [
      "[简体中文](https://orrhsiao.github.io/TokenWatch/privacy/zh-CN/)",
      "Effective Date: July 16, 2026",
      "does not collect, transmit, sell, share, or upload user data",
      "does not require an account or login. It does not include analytics, advertising, telemetry, tracking, or third-party SDKs",
      "does not display a file picker automatically when it launches",
      "separately choose a data folder for Claude Code, Codex, or opencode",
      "independent security-scoped bookmark for each provider folder",
      "The Privacy Policy and Support entries open public webpages in your default browser.",
      "[AI Token Watch Support page](https://orrhsiao.github.io/TokenWatch/support/)",
      "[orrhsiao@126.com](mailto:orrhsiao@126.com)",
      "A GitHub account is not required to contact support by email."
    ]
  },
  {
    repo: "PRIVACY.zh-CN.md",
    web: "docs/privacy/zh-CN.md",
    front_matter: "---\ntitle: AI Token Watch 隐私政策\npermalink: /privacy/zh-CN/\n---\n",
    needles: [
      "[English](https://orrhsiao.github.io/TokenWatch/privacy/)",
      "生效日期：2026 年 7 月 16 日",
      "不收集、传输、出售、分享或上传用户数据",
      "不需要账户或登录。它不包含分析、广告、遥测、追踪或第三方 SDK",
      "启动时不会自动显示文件选择器",
      "分别为 Claude Code、Codex 或 opencode 选择数据文件夹",
      "为你选择的每个 provider 文件夹分别保存 security-scoped bookmark",
      "“隐私政策”和“支持”入口会使用你的默认浏览器打开公开网页。",
      "[AI Token Watch 支持页](https://orrhsiao.github.io/TokenWatch/support/)",
      "[orrhsiao@126.com](mailto:orrhsiao@126.com)",
      "通过电子邮件联系支持不需要 GitHub 账号。"
    ]
  }
]
forbidden = [
  "support contact listed on the App Store product page",
  "App Store 产品页面列出的支持联系方式",
  "https://github.com/OrrHsiao/TokenWatch/issues"
]
contracts.each do |contract|
  repo_text = File.read(contract.fetch(:repo))
  web_text = File.read(contract.fetch(:web))
  prefix = contract.fetch(:front_matter) + "\n"
  abort("#{contract.fetch(:web)}: front matter must be exactly four lines") unless web_text.start_with?(prefix)
  web_body = web_text.delete_prefix(prefix)
  abort("#{contract.fetch(:repo)} and #{contract.fetch(:web)} drifted") unless repo_text == web_body
  contract.fetch(:needles).each do |needle|
    abort("#{contract.fetch(:repo)}: missing #{needle}") unless repo_text.include?(needle)
  end
  forbidden.each do |needle|
    abort("#{contract.fetch(:repo)}: still contains #{needle}") if repo_text.include?(needle)
  end
end
'
```

Expected: exit 0，无输出；该命令同时强断言四份文件正文同步、四行 front matter、直接邮箱/支持链接、provider 目录语义以及旧循环联系方式已删除。

- [ ] **Step 5: 提交隐私政策同步**

```bash
set -euo pipefail
git add PRIVACY.md PRIVACY.zh-CN.md \
  docs/privacy/index.md docs/privacy/zh-CN.md
git commit -m "docs(privacy): 同步数据目录与支持联系方式"
```

---

### Task 4: 准备不会被 Pages 发布的审核材料

**Files:**
- Create: `app-store/review/2026-07-16.md`

- [ ] **Step 1: 先运行审核材料 contract 并确认 RED**

```bash
ruby -e '
path = "app-store/review/2026-07-16.md"
abort("#{path}: missing") unless File.file?(path)
text = File.read(path)
required = [
  "# App Review Follow-up — July 16, 2026",
  "## Submission Gate",
  "uploaded, finished processing, and selected for this submission",
  "https://orrhsiao.github.io/TokenWatch/support/",
  "in the build selected for this submission",
  "AI Token Watch > Settings",
  "In the Data Folders section",
  "does not assign `NSOpenPanel.directoryURL`",
  "macOS controls the location initially displayed by the standard panel",
  "The user-selected folder is used directly as that provider’s data root",
  "orrhsiao@126.com",
  "A GitHub account is not required to contact support by email.",
  "Full unit test suite passed.",
  "Full UI test suite passed, including fresh launch with no authorization panel.",
  "Debug build passed.",
  "Release build passed.",
  "App Sandbox is enabled with read-only User Selected Files and outgoing network disabled.",
  "English and Chinese Support and Privacy pages all return HTTP 200 without authentication.",
  "English and Chinese Support and Privacy content contracts passed.",
  "A new macOS binary containing these changes was uploaded, finished processing, and selected for this submission.",
  "App Store Connect Support URL was manually changed to the complete HTTPS URL above."
]
required.each do |needle|
  abort("#{path}: missing #{needle}") unless text.include?(needle)
end
forbidden = [
  "Settings > Data Folders",
  "new submitted build",
  "No account or login is required to contact support",
  "does not set or suggest a starting location"
]
forbidden.each do |needle|
  abort("#{path}: forbidden wording #{needle}") if text.include?(needle)
end
abort("#{path}: evidence list must have exactly nine items") unless text.scan(/^- \[[ x]\] /).length == 9
abort("#{path}: draft must start with every evidence item unchecked") unless text.scan(/^- \[x\] /).empty?
'
```

Expected: FAIL with `app-store/review/2026-07-16.md: missing`。

- [ ] **Step 2: 创建审核材料文件并固定所有对外文案**

文件使用以下完整内容：

```markdown
# App Review Follow-up — July 16, 2026

## Submission Gate

Do not paste the Review Notes or send the reply below until the public Support URL has been verified with HTTP 200, a new macOS binary containing these changes has been uploaded, finished processing, and selected for this submission, and the complete Support URL has been saved in App Store Connect.

## App Store Connect Support URL

https://orrhsiao.github.io/TokenWatch/support/

Enter this complete HTTPS URL in the Support URL field. Do not use `/support/` or the GitHub Issues URL.

## Review Notes

We addressed Guideline 2.4.5(i) and Guideline 1.5 in the build selected for this submission.

Directory access:

- The app no longer presents an Open panel at launch.
- The user opens AI Token Watch > Settings. In the Data Folders section, the user explicitly chooses a separate data folder for Claude Code, Codex, or opencode.
- Each standard NSOpenPanel is shown only after the user clicks the corresponding Choose Folder, Reselect, or Choose Again button.
- The app does not assign `NSOpenPanel.directoryURL` or otherwise set, suggest, or control the panel’s initial location. macOS controls the location initially displayed by the standard panel.
- The user-selected folder is used directly as that provider’s data root; the app does not treat it as the Home folder or append a Home-relative provider path.
- Each provider uses a separate security-scoped bookmark. The legacy shared Home folder bookmark is deleted and is not restored or migrated.
- App Sandbox remains enabled with read-only User Selected Files access. No broader file entitlement or network entitlement was added.

Support:

- The Support URL opens a public page with the support email orrhsiao@126.com, Bug Report and Feature Request links, privacy guidance, and the Privacy Policy link.
- A GitHub account is not required to contact support by email.

Review steps:

1. Launch the app and confirm that no file picker appears.
2. Open AI Token Watch > Settings and locate the Data Folders section.
3. Click Choose Folder for any provider and confirm that a standard folder picker appears with provider-specific instructions. The app does not set the initial location; macOS controls the location initially displayed by the panel.
4. Cancel the picker and confirm that no folder is saved.
5. Optionally select a provider data root and confirm that only that provider is loaded.

## Reply to App Review

Hello App Review,

Thank you for the follow-up. We addressed both remaining issues in the build selected for this submission.

For Guideline 2.4.5(i), AI Token Watch no longer requests or offers a preset Home Folder. The app does not show a file picker at launch. A standard macOS folder picker appears only after the user opens AI Token Watch > Settings and clicks the action for a specific provider in the Data Folders section. The app does not assign `NSOpenPanel.directoryURL` or otherwise control the initial location; macOS controls the location initially displayed by the standard panel. Each provider has its own security-scoped bookmark for its user-selected folder, file access remains read-only, and the selected folder is used directly as that provider's data root. The old shared Home Folder bookmark is removed and is not migrated.

For Guideline 1.5, we added a public support page with the direct support email orrhsiao@126.com, Bug Report and Feature Request options, privacy guidance, and a Privacy Policy link. A GitHub account is not required to contact support by email:

https://orrhsiao.github.io/TokenWatch/support/

Please review the build selected for this submission using the steps in the Review Notes. Thank you.

## Pre-submission Evidence

- [ ] Full unit test suite passed.
- [ ] Full UI test suite passed, including fresh launch with no authorization panel.
- [ ] Debug build passed.
- [ ] Release build passed.
- [ ] App Sandbox is enabled with read-only User Selected Files and outgoing network disabled.
- [ ] English and Chinese Support and Privacy pages all return HTTP 200 without authentication.
- [ ] English and Chinese Support and Privacy content contracts passed.
- [ ] A new macOS binary containing these changes was uploaded, finished processing, and selected for this submission.
- [ ] App Store Connect Support URL was manually changed to the complete HTTPS URL above.
```

不得加入未经确认的 build number。Submission Gate 是硬门禁：Support URL 未通过线上 HTTP 200 contract、新二进制未完成处理并被本次 submission 选中、或完整 Support URL 尚未保存时，都不得粘贴 Review Notes 或发送 Reply。最后两个 checkbox 只能在对应 App Store Connect 操作实际完成后勾选。

- [ ] **Step 3: 运行审核材料 contract 并确认 GREEN**

```bash
ruby -e '
path = "app-store/review/2026-07-16.md"
abort("#{path}: missing") unless File.file?(path)
text = File.read(path)
required = [
  "# App Review Follow-up — July 16, 2026",
  "## Submission Gate",
  "uploaded, finished processing, and selected for this submission",
  "https://orrhsiao.github.io/TokenWatch/support/",
  "in the build selected for this submission",
  "AI Token Watch > Settings",
  "In the Data Folders section",
  "does not assign `NSOpenPanel.directoryURL`",
  "macOS controls the location initially displayed by the standard panel",
  "The user-selected folder is used directly as that provider’s data root",
  "orrhsiao@126.com",
  "A GitHub account is not required to contact support by email.",
  "Full unit test suite passed.",
  "Full UI test suite passed, including fresh launch with no authorization panel.",
  "Debug build passed.",
  "Release build passed.",
  "App Sandbox is enabled with read-only User Selected Files and outgoing network disabled.",
  "English and Chinese Support and Privacy pages all return HTTP 200 without authentication.",
  "English and Chinese Support and Privacy content contracts passed.",
  "A new macOS binary containing these changes was uploaded, finished processing, and selected for this submission.",
  "App Store Connect Support URL was manually changed to the complete HTTPS URL above."
]
required.each do |needle|
  abort("#{path}: missing #{needle}") unless text.include?(needle)
end
forbidden = [
  "Settings > Data Folders",
  "new submitted build",
  "No account or login is required to contact support",
  "does not set or suggest a starting location"
]
forbidden.each do |needle|
  abort("#{path}: forbidden wording #{needle}") if text.include?(needle)
end
abort("#{path}: evidence list must have exactly nine items") unless text.scan(/^- \[[ x]\] /).length == 9
abort("#{path}: draft must start with every evidence item unchecked") unless text.scan(/^- \[x\] /).empty?
'
```

Expected: exit 0，无输出。

- [ ] **Step 4: 验证审核材料不会进入 Pages**

```bash
set -euo pipefail
test -f app-store/review/2026-07-16.md
test ! -e docs/app-store
ruby -e '
path = "app-store/review/2026-07-16.md"
text = File.read(path)
abort("missing Support URL") unless text.scan("https://orrhsiao.github.io/TokenWatch/support/").length >= 2
abort("missing support email") unless text.scan("orrhsiao@126.com").length >= 2
'
```

Expected: all commands exit 0；文件只在仓库根 `app-store/review/`。

- [ ] **Step 5: 提交审核材料草案**

```bash
set -euo pipefail
git add app-store/review/2026-07-16.md
git commit -m "docs(review): 准备审核回复与测试步骤"
```

---

### Task 5: 完整验证、发布 Pages 并交付 App Store Connect URL

**Files:**
- Modify after evidence: `app-store/review/2026-07-16.md`
- Modify at binary gate: `TokenWatch.xcodeproj/project.pbxproj:399,446`（仅 app target 的 Debug/Release `CURRENT_PROJECT_VERSION`）

- [ ] **Step 1: 运行应用回归、构建和 entitlement 静态检查**

```bash
set -euo pipefail
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchTests \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test

xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test

xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -configuration Debug \
  -derivedDataPath .build/DerivedData build

xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -configuration Release \
  -derivedDataPath .build/DerivedData build

ruby -e '
text = File.read("TokenWatch.xcodeproj/project.pbxproj")
expected = {
  "ENABLE_APP_SANDBOX = YES;" => 2,
  "ENABLE_OUTGOING_NETWORK_CONNECTIONS = NO;" => 2,
  "ENABLE_USER_SELECTED_FILES = readonly;" => 2
}
expected.each do |setting, count|
  actual = text.scan(setting).length
  abort("#{setting}: expected #{count}, got #{actual}") unless actual == count
end
'
```

Expected: tests `** TEST SUCCEEDED **`；builds `** BUILD SUCCEEDED **`；entitlement contract exit 0。此时只记录输出，**不要编辑 checklist**；Task 5 Step 2 还要在 clean worktree 上完成 committed-range 审计。这里的 Release build 也不是上传到 App Store Connect 的二进制，不能据此勾选“uploaded / selected”门禁。

- [ ] **Step 2: 运行全部页面本地校验**

```bash
set -euo pipefail
ruby -e '
support_contracts = {
  "docs/support/index.md" => {
    front_matter: "---\ntitle: AI Token Watch Support\npermalink: /support/\n---\n",
    needles: [
      "# AI Token Watch Support",
      "## Report a Bug",
      "## Request a Feature",
      "## Protect Your Privacy",
      "## Privacy Policy",
      "[简体中文](./zh-CN/)",
      "[orrhsiao@126.com](mailto:orrhsiao@126.com)",
      "GitHub Issues are an optional public channel.",
      "A GitHub account is not required to contact support by email.",
      "issues/new?template=bug_report.yml",
      "issues/new?template=feature_request.yml",
      "[AI Token Watch Privacy Policy](../privacy/)",
      "AI Token Watch version and build number",
      "macOS version",
      "affected data source",
      "steps to reproduce",
      "expected and actual behavior",
      "API keys",
      "prompts",
      "responses",
      "private project paths",
      "raw usage records",
      "original provider data files"
    ]
  },
  "docs/support/zh-CN.md" => {
    front_matter: "---\ntitle: AI Token Watch 支持\npermalink: /support/zh-CN/\n---\n",
    needles: [
      "# AI Token Watch 支持",
      "## 报告问题",
      "## 功能建议",
      "## 保护你的隐私",
      "## 隐私政策",
      "[English](../)",
      "[orrhsiao@126.com](mailto:orrhsiao@126.com)",
      "GitHub Issues 只是可选的公开渠道。",
      "通过邮箱联系支持不需要 GitHub 账号。",
      "issues/new?template=bug_report.yml",
      "issues/new?template=feature_request.yml",
      "[AI Token Watch 隐私政策](../../privacy/zh-CN/)",
      "AI Token Watch 版本和构建号",
      "macOS 版本",
      "涉及的数据源",
      "清晰的复现步骤",
      "预期行为和实际行为",
      "API key",
      "prompt",
      "response",
      "私人项目路径",
      "原始使用记录",
      "provider 的原始数据文件"
    ]
  }
}
support_contracts.each do |path, contract|
  text = File.read(path)
  prefix = contract.fetch(:front_matter) + "\n"
  abort("#{path}: front matter must be exactly four lines") unless text.start_with?(prefix)
  contract.fetch(:needles).each do |needle|
    abort("#{path}: missing #{needle}") unless text.include?(needle)
  end
end

privacy_contracts = [
  {
    repo: "PRIVACY.md",
    web: "docs/privacy/index.md",
    front_matter: "---\ntitle: AI Token Watch Privacy Policy\npermalink: /privacy/\n---\n",
    needles: [
      "Effective Date: July 16, 2026",
      "does not collect, transmit, sell, share, or upload user data",
      "does not require an account or login. It does not include analytics, advertising, telemetry, tracking, or third-party SDKs",
      "does not display a file picker automatically when it launches",
      "separately choose a data folder for Claude Code, Codex, or opencode",
      "independent security-scoped bookmark for each provider folder",
      "The Privacy Policy and Support entries open public webpages in your default browser.",
      "[AI Token Watch Support page](https://orrhsiao.github.io/TokenWatch/support/)",
      "[orrhsiao@126.com](mailto:orrhsiao@126.com)",
      "A GitHub account is not required to contact support by email."
    ]
  },
  {
    repo: "PRIVACY.zh-CN.md",
    web: "docs/privacy/zh-CN.md",
    front_matter: "---\ntitle: AI Token Watch 隐私政策\npermalink: /privacy/zh-CN/\n---\n",
    needles: [
      "生效日期：2026 年 7 月 16 日",
      "不收集、传输、出售、分享或上传用户数据",
      "不需要账户或登录。它不包含分析、广告、遥测、追踪或第三方 SDK",
      "启动时不会自动显示文件选择器",
      "分别为 Claude Code、Codex 或 opencode 选择数据文件夹",
      "为你选择的每个 provider 文件夹分别保存 security-scoped bookmark",
      "“隐私政策”和“支持”入口会使用你的默认浏览器打开公开网页。",
      "[AI Token Watch 支持页](https://orrhsiao.github.io/TokenWatch/support/)",
      "[orrhsiao@126.com](mailto:orrhsiao@126.com)",
      "通过电子邮件联系支持不需要 GitHub 账号。"
    ]
  }
]
privacy_contracts.each do |contract|
  repo_text = File.read(contract.fetch(:repo))
  web_text = File.read(contract.fetch(:web))
  prefix = contract.fetch(:front_matter) + "\n"
  abort("#{contract.fetch(:web)}: front matter must be exactly four lines") unless web_text.start_with?(prefix)
  abort("#{contract.fetch(:repo)} and #{contract.fetch(:web)} drifted") unless repo_text == web_text.delete_prefix(prefix)
  contract.fetch(:needles).each do |needle|
    abort("#{contract.fetch(:repo)}: missing #{needle}") unless repo_text.include?(needle)
  end
  abort("#{contract.fetch(:repo)}: old GitHub Issues contact remains") if repo_text.include?("https://github.com/OrrHsiao/TokenWatch/issues")
end

review_path = "app-store/review/2026-07-16.md"
review = File.read(review_path)
review_required = [
  "## Submission Gate",
  "uploaded, finished processing, and selected for this submission",
  "https://orrhsiao.github.io/TokenWatch/support/",
  "AI Token Watch > Settings",
  "In the Data Folders section",
  "does not assign `NSOpenPanel.directoryURL`",
  "macOS controls the location initially displayed by the standard panel",
  "The user-selected folder is used directly as that provider’s data root",
  "A GitHub account is not required to contact support by email."
]
review_required.each do |needle|
  abort("#{review_path}: missing #{needle}") unless review.include?(needle)
end
abort("#{review_path}: evidence list must have exactly nine items") unless review.scan(/^- \[[ x]\] /).length == 9
abort("#{review_path}: evidence must still be unchecked before verification commit") unless review.scan(/^- \[x\] /).empty?
'

if rg -n \
  'authorize access to your user directory|user-directory access once|授权访问你的用户目录|请求一次用户目录|home 目录|support contact listed on the App Store product page|App Store 产品页面列出的支持联系方式|No account or login is required to contact support' \
  README.md README.zh-CN.md PRIVACY.md PRIVACY.zh-CN.md docs/privacy docs/support app-store/review/2026-07-16.md
then
  echo 'unexpected legacy support or Home-directory wording found' >&2
  exit 1
else
  rg_status=$?
  if test "$rg_status" -ne 1
  then
    echo "rg failed with status ${rg_status}" >&2
    exit "$rg_status"
  fi
fi

if rg -n -F 'Settings > Data Folders' app-store/review/2026-07-16.md
then
  echo 'review material must describe Data Folders as a Settings section' >&2
  exit 1
else
  rg_status=$?
  if test "$rg_status" -ne 1
  then
    echo "rg failed with status ${rg_status}" >&2
    exit "$rg_status"
  fi
fi
```

Expected: Ruby exit 0；两个负向 `rg` 都以 no-match 状态 1 进入 `else` 并正常结束。任何 match 或 `rg` 自身错误都会显式 `exit` 失败。

```bash
set -euo pipefail
git diff --check
test -z "$(git status --porcelain)"
git status --short --branch
```

Expected: no whitespace errors；`git status --porcelain` 为空；所有 Task 1–4 修改已提交。此 clean-worktree 断言发生在任何 checklist 编辑之前。

- [ ] **Step 3: 审计 committed range，并把目标内容发布到 `main:/docs`**

```bash
set -euo pipefail
git fetch origin main
BASE_SHA="$(git merge-base origin/main HEAD)"
test -n "$BASE_SHA"
git log --oneline --decorate "$BASE_SHA"..HEAD
git diff --name-status "$BASE_SHA"..HEAD
git diff --check "$BASE_SHA"..HEAD
git branch --show-current
```

Expected: `BASE_SHA..HEAD` 日志和文件清单包含计划基线、全部目录授权 commits、本计划 Task 1–4 commits，且没有范围内 whitespace error 或意外文件。不能只审计 working-tree diff，因为此时实现已经提交。

调用 `superpowers:finishing-a-development-branch`，让用户在以下发布路径中明确选择一个。只执行被选中的代码块；不得把 `codex/*` 强推成远端 `main`。

当前分支已经是 `main` 时，执行直接发布路径：

```bash
set -euo pipefail
test "$(git branch --show-current)" = main
git push origin main
git fetch origin main
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
```

当前分支是 `codex/*` 且用户选择 PR 时，执行 PR 发布路径：

```bash
set -euo pipefail
BRANCH="$(git branch --show-current)"
case "$BRANCH" in
  codex/*) ;;
  *) echo 'PR publication requires a codex/* branch' >&2; exit 1 ;;
esac
git push -u origin "$BRANCH"
gh pr create \
  --base main \
  --head "$BRANCH" \
  --title 'fix(review): 修复目录授权与支持入口' \
  --body '修复 App Review Guideline 2.4.5(i) 的目录选择流程，并新增符合 Guideline 1.5 的公开支持页、应用菜单入口与审核材料。已完成 unit/UI tests、Debug/Release build 和本地页面 contract。'
gh pr view "$BRANCH" \
  --json url,state,isDraft,mergeStateStatus,statusCheckRollup
```

把 PR URL 和检查状态交付用户；只有用户明确批准 merge 后，才执行：

```bash
set -euo pipefail
BRANCH="$(git branch --show-current)"
case "$BRANCH" in
  codex/*) ;;
  *) echo 'PR merge requires the published codex/* branch' >&2; exit 1 ;;
esac
gh pr merge "$BRANCH" --merge --delete-branch
git fetch origin main
git switch main
git merge --ff-only origin/main
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
```

Expected: direct route push 成功，或 PR route 已创建、展示检查状态并合并；两条路径最终都让本地 `main` 与 `origin/main` 完全相同。Pages 只跟踪 `main:/docs`，所以 PR 仅创建、尚未合并时不能进入下一步。

- [ ] **Step 4: 等待目标 Pages build 完成**

```bash
set -euo pipefail
gh api repos/OrrHsiao/TokenWatch/pages \
  | ruby -rjson -e '
data = JSON.parse(STDIN.read)
abort("Pages is not public") unless data["public"] == true
abort("Pages does not enforce HTTPS") unless data["https_enforced"] == true
source = data.fetch("source")
abort("Pages source branch is not main") unless source["branch"] == "main"
abort("Pages source path is not /docs") unless source["path"] == "/docs"
puts({status: data["status"], build_type: data["build_type"], source: source}.inspect)
'

gh api repos/OrrHsiao/TokenWatch/pages/builds/latest \
  --jq '{status,commit,error,created_at,updated_at}'
```

Expected: Pages 配置 contract exit 0；latest build 指向 `origin/main`。若 latest build 尚未完成，用下面的有界查询；执行期间保持用户更新，单次查询最多约 45 秒：

```bash
set -euo pipefail
PUBLISHED_SHA="$(git rev-parse origin/main)"
for attempt in 1 2 3 4
do
  STATUS="$(gh api repos/OrrHsiao/TokenWatch/pages/builds/latest --jq '.status')"
  COMMIT="$(gh api repos/OrrHsiao/TokenWatch/pages/builds/latest --jq '.commit')"
  echo "Pages attempt ${attempt}: status=${STATUS} commit=${COMMIT}"
  if test "$STATUS" = built && test "$COMMIT" = "$PUBLISHED_SHA"
  then
    exit 0
  fi
  case "$STATUS" in
    built) echo 'latest built Pages commit is not the published target yet' ;;
    building|queued) ;;
    *) gh api repos/OrrHsiao/TokenWatch/pages/builds/latest \
         --jq '{status,commit,error,created_at,updated_at}'; exit 1 ;;
  esac
  if test "$attempt" -lt 4
  then
    sleep 15
  fi
done
echo 'Pages build did not finish within this bounded poll' >&2
exit 1
```

Expected: exit 0 only when status is `built` and Pages build commit exactly equals `origin/main`。若四次内未完成，Task 5 Step 4 仍未通过：结束本次命令、向用户更新，并在下一工作回合重新进入本 Step 的完整有界查询；若返回错误状态，先检查 `error`，不得进入 HTTP 验证。

- [ ] **Step 5: 用无登录 HTTP 请求验证最终页面与关键正文**

```bash
set -euo pipefail
test "$(curl -q -fsSL -o /dev/null -w '%{http_code} %{url_effective}' \
  https://orrhsiao.github.io/TokenWatch/support/)" \
  = '200 https://orrhsiao.github.io/TokenWatch/support/'

test "$(curl -q -fsSL -o /dev/null -w '%{http_code} %{url_effective}' \
  https://orrhsiao.github.io/TokenWatch/support/zh-CN/)" \
  = '200 https://orrhsiao.github.io/TokenWatch/support/zh-CN/'

test "$(curl -q -fsSL -o /dev/null -w '%{http_code} %{url_effective}' \
  https://orrhsiao.github.io/TokenWatch/privacy/)" \
  = '200 https://orrhsiao.github.io/TokenWatch/privacy/'

test "$(curl -q -fsSL -o /dev/null -w '%{http_code} %{url_effective}' \
  https://orrhsiao.github.io/TokenWatch/privacy/zh-CN/)" \
  = '200 https://orrhsiao.github.io/TokenWatch/privacy/zh-CN/'

curl -q -fsSL https://orrhsiao.github.io/TokenWatch/support/ \
  | ruby -e '
text = STDIN.read
[
  "AI Token Watch Support",
  "mailto:orrhsiao@126.com",
  "issues/new?template=bug_report.yml",
  "issues/new?template=feature_request.yml",
  "../privacy/",
  "A GitHub account is not required to contact support by email."
].each { |needle| abort("English support page missing #{needle}") unless text.include?(needle) }
abort("English support page must display and link the email") unless text.scan("orrhsiao@126.com").length >= 2
'

curl -q -fsSL https://orrhsiao.github.io/TokenWatch/support/zh-CN/ \
  | ruby -e '
text = STDIN.read
[
  "AI Token Watch 支持",
  "mailto:orrhsiao@126.com",
  "issues/new?template=bug_report.yml",
  "issues/new?template=feature_request.yml",
  "../../privacy/zh-CN/",
  "通过邮箱联系支持不需要 GitHub 账号。"
].each { |needle| abort("Chinese support page missing #{needle}") unless text.include?(needle) }
abort("Chinese support page must display and link the email") unless text.scan("orrhsiao@126.com").length >= 2
'

curl -q -fsSL https://orrhsiao.github.io/TokenWatch/privacy/ \
  | ruby -e '
text = STDIN.read
[
  "AI Token Watch Privacy Policy",
  "https://orrhsiao.github.io/TokenWatch/support/",
  "mailto:orrhsiao@126.com",
  "does not display a file picker automatically when it launches",
  "independent security-scoped bookmark for each provider folder"
].each { |needle| abort("English privacy page missing #{needle}") unless text.include?(needle) }
abort("English privacy page must display and link the email") unless text.scan("orrhsiao@126.com").length >= 2
'

curl -q -fsSL https://orrhsiao.github.io/TokenWatch/privacy/zh-CN/ \
  | ruby -e '
text = STDIN.read
[
  "AI Token Watch 隐私政策",
  "https://orrhsiao.github.io/TokenWatch/support/",
  "mailto:orrhsiao@126.com",
  "启动时不会自动显示文件选择器",
  "分别保存 security-scoped bookmark"
].each { |needle| abort("Chinese privacy page missing #{needle}") unless text.include?(needle) }
abort("Chinese privacy page must display and link the email") unless text.scan("orrhsiao@126.com").length >= 2
'
```

Expected: English/Chinese Support 与 English/Chinese Privacy 四个完整 URL 都严格得到最终 `200` URL；四个 HTML contract 全部 exit 0。CDN 短暂 404 时停止本 Step，等待 Pages build 和缓存收敛，不能把本地文件存在当成上线成功。此时仍不要修改 checklist；统一在 Step 6 更新前七项。

- [ ] **Step 6: 提交证据状态并再次推送**

只把 `app-store/review/2026-07-16.md` 的前七项改为 `[x]`：unit、UI、Debug、Release、entitlement、四个线上 URL、双语内容 contract。最后两个 App Store Connect 项保持 `[ ]`；Step 1 的本地 Release build 不等于已上传/已选中的 App Store build。

```bash
set -euo pipefail
ruby -e '
path = "app-store/review/2026-07-16.md"
text = File.read(path)
checked = [
  "Full unit test suite passed.",
  "Full UI test suite passed, including fresh launch with no authorization panel.",
  "Debug build passed.",
  "Release build passed.",
  "App Sandbox is enabled with read-only User Selected Files and outgoing network disabled.",
  "English and Chinese Support and Privacy pages all return HTTP 200 without authentication.",
  "English and Chinese Support and Privacy content contracts passed."
]
unchecked = [
  "A new macOS binary containing these changes was uploaded, finished processing, and selected for this submission.",
  "App Store Connect Support URL was manually changed to the complete HTTPS URL above."
]
checked.each { |item| abort("not checked: #{item}") unless text.include?("- [x] #{item}") }
unchecked.each { |item| abort("must remain unchecked: #{item}") unless text.include?("- [ ] #{item}") }
abort("expected exactly seven checked items") unless text.scan(/^- \[x\] /).length == 7
abort("expected exactly two unchecked items") unless text.scan(/^- \[ \] /).length == 2
'
git diff --check
git add app-store/review/2026-07-16.md
git diff --cached --check
git commit -m "docs(review): 记录审核整改验证结果"
```

若 Step 3 使用 direct-main 发布策略：

```bash
set -euo pipefail
test "$(git branch --show-current)" = main
git push origin main
git fetch origin main
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
test -z "$(git status --porcelain)"
```

若仓库策略要求所有后续更改也经 PR：

```bash
set -euo pipefail
test "$(git branch --show-current)" = main
git switch -c codex/app-review-evidence-2026-07-16
git push -u origin codex/app-review-evidence-2026-07-16
gh pr create \
  --base main \
  --head codex/app-review-evidence-2026-07-16 \
  --title 'docs(review): 记录审核整改验证结果' \
  --body '记录已由命令验证的 unit/UI tests、Debug/Release build、entitlement 与四个线上页面证据；App Store Connect 人工门禁仍保持未勾选。'
gh pr view codex/app-review-evidence-2026-07-16 \
  --json url,state,isDraft,mergeStateStatus,statusCheckRollup
```

把证据 PR URL 和检查状态交付用户；只有用户明确批准 merge 后，才执行：

```bash
set -euo pipefail
gh pr merge codex/app-review-evidence-2026-07-16 --merge --delete-branch
git fetch origin main
git switch main
git merge --ff-only origin/main
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
test -z "$(git status --porcelain)"
```

- [ ] **Step 7: 完成新 build 硬门禁和 App Store Connect Support URL**

向用户明确提供：

```text
Support URL: https://orrhsiao.github.io/TokenWatch/support/
```

此步骤是人工硬门禁，不授权 agent 自动修改 App Store Connect。必须按以下顺序完成：

1. 先在 App Store Connect 查看 version 1.0 已使用的全部 macOS build number，选择一个尚未使用、严格大于其中最大值且大于本次被拒 build 8 的整数；因此最低可能值是 9，但如果 9 或更大的值已经存在，必须继续增加，不能从仓库当前值 1 简单加一得到 2。
2. 使用 `apply_patch` 只把 `TokenWatch` app target 的 Debug 和 Release 两处 `CURRENT_PROJECT_VERSION` 改为上一步选定的同一个整数；测试 target、`MARKETING_VERSION = 1.0`、entitlement 和其他 build setting 都保持不变。提交并按本计划已选定的 direct-main 或 PR 路径让该 build-number commit 到达 `origin/main`，再开始归档。
3. 从已经包含目录授权整改、Support 菜单和新 build number 的干净 `origin/main` commit 归档 macOS binary；验证归档内 `CFBundleShortVersionString` 仍为 `1.0`，`CFBundleVersion` 精确等于已核对的未使用整数。上传至 App Store Connect 并等待 processing 完成。
4. 在当前 macOS version submission 中选择该新 build；不能继续选用本次被拒的 version 1.0 (build 8)，也不能仅凭 Step 1 的本地 Release build 或归档成功声称已上传。
5. 在当前 macOS version 的 Support URL 字段填入完整 URL `https://orrhsiao.github.io/TokenWatch/support/` 并保存。
6. 只有新 build 已在当前 submission 中选中、Support URL 也已保存成功后，才把 Task 4 的 Review Notes 粘贴到对应字段，并逐字发送 “Reply to App Review”。在此之前，材料中的 “build selected for this submission” 不得对外发送。
7. 只在上述操作已真实完成后，把审核材料最后两个 checkbox 改为 `[x]`。

更新 build setting 后、提交前运行以下静态断言。执行时把 `EXPECTED_BUILD` 设为刚在 App Store Connect 核对过的整数；该值必须大于 8：

```bash
set -euo pipefail
test -n "${EXPECTED_BUILD:-}"
case "$EXPECTED_BUILD" in
  *[!0-9]*|'') echo 'EXPECTED_BUILD must be an integer' >&2; exit 1 ;;
esac
test "$EXPECTED_BUILD" -gt 8

for configuration in Debug Release
do
  ACTUAL_BUILD="$(
    xcodebuild -project TokenWatch.xcodeproj \
      -target TokenWatch \
      -configuration "$configuration" \
      -showBuildSettings 2>/dev/null \
      | awk '$1 == "CURRENT_PROJECT_VERSION" && $2 == "=" { print $3; exit }'
  )"
  test "$ACTUAL_BUILD" = "$EXPECTED_BUILD"
done

test "$(rg -n '^\s*CURRENT_PROJECT_VERSION = ' TokenWatch.xcodeproj/project.pbxproj | wc -l | tr -d ' ')" = 6
test "$(rg -n "^\s*CURRENT_PROJECT_VERSION = ${EXPECTED_BUILD};" TokenWatch.xcodeproj/project.pbxproj | wc -l | tr -d ' ')" = 2
test "$(rg -n '^\s*CURRENT_PROJECT_VERSION = 1;' TokenWatch.xcodeproj/project.pbxproj | wc -l | tr -d ' ')" = 4
git diff --check
git diff -- TokenWatch.xcodeproj/project.pbxproj
```

Expected: app target 的 Debug/Release 都解析为 `EXPECTED_BUILD`；工程中仍有六处 build setting，其中只有 app target 两处是新值，两个测试 target 的四处值仍为 1；diff 不包含其他 build setting。确认 diff 后提交：

```bash
set -euo pipefail
git add TokenWatch.xcodeproj/project.pbxproj
git diff --cached --check
git commit -m "chore(release): 更新审核构建号"
```

沿用 Step 6 已选定的 direct-main 或 PR 发布路径，直到本地 `main` 与 `origin/main` 指向包含该 commit 的同一 SHA 且工作树干净。随后使用确定路径创建归档并验证归档中的实际版本：

```bash
set -euo pipefail
test -n "${EXPECTED_BUILD:-}"
test "$(git branch --show-current)" = main
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
test -z "$(git status --porcelain)"

ARCHIVE_PATH=".build/Archives/TokenWatch-1.0-${EXPECTED_BUILD}.xcarchive"
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath .build/DerivedData archive

APP_INFO="$ARCHIVE_PATH/Products/Applications/AI Token Watch.app/Contents/Info.plist"
test -f "$APP_INFO"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_INFO")" = 1.0
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_INFO")" = "$EXPECTED_BUILD"
```

Expected: `** ARCHIVE SUCCEEDED **`，归档内版本严格为 `1.0 (EXPECTED_BUILD)`。若签名或 provisioning 阻止命令行归档，应在 Xcode Organizer 从同一干净 commit 重新 Archive，并对 Organizer 中实际生成的 `.xcarchive/Products/Applications/AI Token Watch.app/Contents/Info.plist` 运行同样两个 `PlistBuddy` 断言；不得跳过版本验证。只有验证过的归档才可上传。

对最后两个 checkbox 运行强断言并提交：

```bash
set -euo pipefail
ruby -e '
path = "app-store/review/2026-07-16.md"
text = File.read(path)
items = [
  "Full unit test suite passed.",
  "Full UI test suite passed, including fresh launch with no authorization panel.",
  "Debug build passed.",
  "Release build passed.",
  "App Sandbox is enabled with read-only User Selected Files and outgoing network disabled.",
  "English and Chinese Support and Privacy pages all return HTTP 200 without authentication.",
  "English and Chinese Support and Privacy content contracts passed.",
  "A new macOS binary containing these changes was uploaded, finished processing, and selected for this submission.",
  "App Store Connect Support URL was manually changed to the complete HTTPS URL above."
]
items.each { |item| abort("not checked: #{item}") unless text.include?("- [x] #{item}") }
abort("expected all nine items checked") unless text.scan(/^- \[x\] /).length == 9
abort("unexpected unchecked evidence") unless text.scan(/^- \[ \] /).empty?
'
git diff --check
git add app-store/review/2026-07-16.md
git diff --cached --check
git commit -m "docs(review): 记录 App Store Connect 更新"
```

若 Step 6 使用 direct-main 发布策略：

```bash
set -euo pipefail
test "$(git branch --show-current)" = main
git push origin main
git fetch origin main
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
test -z "$(git status --porcelain)"
```

若仓库策略要求该最终 checkbox commit 也经 PR：

```bash
set -euo pipefail
test "$(git branch --show-current)" = main
git switch -c codex/app-review-connect-update-2026-07-16
git push -u origin codex/app-review-connect-update-2026-07-16
gh pr create \
  --base main \
  --head codex/app-review-connect-update-2026-07-16 \
  --title 'docs(review): 记录 App Store Connect 更新' \
  --body '记录新 macOS binary 已完成 processing 并被当前 submission 选中，以及完整 Support URL 已保存到 App Store Connect。'
gh pr view codex/app-review-connect-update-2026-07-16 \
  --json url,state,isDraft,mergeStateStatus,statusCheckRollup
```

把最终 evidence PR URL 和检查状态交付用户；只有用户明确批准 merge 后，才执行：

```bash
set -euo pipefail
gh pr merge codex/app-review-connect-update-2026-07-16 --merge --delete-branch
git fetch origin main
git switch main
git merge --ff-only origin/main
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
test -z "$(git status --porcelain)"
```

Expected: 最终 checkbox 状态经过单文件 commit 并实际到达 `origin/main`；Review Notes/Reply 只描述当前 submission 已选中的新 build，不虚假声称本地构建已经上传。
