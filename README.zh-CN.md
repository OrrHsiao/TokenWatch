# TokenWatch

[English](./README.md) | [简体中文](./README.zh-CN.md)

[![CI](https://github.com/OrrHsiao/TokenWatch/actions/workflows/ci.yml/badge.svg)](https://github.com/OrrHsiao/TokenWatch/actions/workflows/ci.yml)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue)](./LICENSE)
![macOS 15+](https://img.shields.io/badge/macOS-15.0%2B-000000?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![AppKit](https://img.shields.io/badge/AppKit-native-0A84FF)
![Menu Bar App](https://img.shields.io/badge/menu%20bar-app-34C759)
![Privacy: local only](https://img.shields.io/badge/privacy-local--only-30D158)

TokenWatch 是一个原生 macOS 应用，用于从本地 coding agent 数据中统计 token 用量和预估费用。它会读取 Claude Code、Codex 和 opencode 的本地使用记录，并按日期、月份、模型、项目和 provider 汇总数据。

应用使用 Swift、AppKit 和 macOS App Sandbox 构建。TokenWatch 不会把你的使用数据发送到任何地方。

## 功能

- 原生 macOS 菜单栏和窗口体验
- 总计、今日、最近 30 天、最近 12 个月视图
- 按 provider 和模型拆分 token 用量与费用
- 日历热力图和图表视图，方便快速查看趋势
- 本地解析 Claude Code JSONL、Codex rollout JSONL 和 opencode SQLite 数据
- 使用 security-scoped bookmark 适配沙盒环境下的本地文件授权
- 内置 LiteLLM 价格快照，并对常用模型做了手动价格修正

## 支持的数据源

| 数据源 | TokenWatch 读取的本地数据 | 说明 |
| --- | --- | --- |
| Claude Code | `~/.claude/projects/**/*.jsonl` | 按 `message.id` 去重，并把 `requestId` 作为可选后缀。 |
| Codex | `~/.codex/sessions/**/rollout-*.jsonl` 和归档 session | 优先使用 `last_token_usage`，没有时从累计 token 数推导增量。 |
| opencode | `~/.local/share/opencode/opencode.db` | 以只读模式读取 SQLite 中的 assistant 消息，并保留上游提供的费用。 |

## 隐私

TokenWatch 被设计为只在本地运行的工具。

- 只有在你通过 macOS 打开面板授权后，它才会读取文件。
- 它会把 security-scoped bookmark 存在 `UserDefaults` 中，便于应用下次重新打开同一批本地目录。
- 它不会上传使用记录、项目路径、prompt、response 或价格数据。
- 它不包含 analytics 或 telemetry。

由于本地 agent 日志中本身可能包含项目路径，应用界面里也可能展示这些本地路径。

## 安装

目前还没有打包发布版本。现在请从源码构建：

1. Clone 本仓库。
2. 用 Xcode 打开 `TokenWatch.xcodeproj`。
3. 选择 `TokenWatch` scheme。
4. 在 macOS 上构建并运行。
5. 打开应用设置，并在提示时授权访问你的用户目录。

## 首次运行

TokenWatch 会请求一次用户目录访问权限，然后扫描你 home 目录下受支持的 provider 文件夹。如果你没有使用其中某个工具，对应 provider 会显示为没有数据。

你可以在主窗口或菜单栏弹窗里手动刷新。自动刷新间隔可以在设置中调整。

## 构建

要求：

- macOS 15.0+
- Xcode 16.4+
- Swift 6.0

构建应用：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build
```

运行单元测试：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

运行全部测试：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' test
```

## 架构

每个 provider 都拥有自己的 scanner 和 parser，然后输出统一的 `ParsedUsageEntry`。`PricingEngine` 和 `UsageAggregator` 会把这些 entry 汇总成统计结果，再由 AppKit view controller 渲染。

```text
Provider scanner/parser
        |
        v
ParsedUsageEntry
        |
        v
PricingEngine + UsageAggregator
        |
        v
TokenStatsViewModel
        |
        v
AppKit sidebar, charts, menu bar popover
```

关键目录：

```text
TokenWatch/
  Analytics/       汇总逻辑
  Models/          共享的用量和价格模型
  Pricing/         价格表、LiteLLM catalog 和费用计算
  Providers/       Claude Code、Codex 和 opencode 适配器
  Services/        Security-scoped bookmark 管理
  ViewControllers/ AppKit UI
  ViewModels/      Provider 状态协调

TokenWatchTests/   Swift Testing 单元测试
TokenWatchUITests/ XCTest UI 测试
```

## 价格数据

TokenWatch 使用内置价格数据预估费用。价格可能和上游 provider 的实际账单存在差异，因此应用里的总额应视为估算值，而不是正式账单。未知模型会优先使用数据源自带的上游费用；如果源数据没有费用，费用可能会显示为零，直到价格数据被更新。

## 贡献

欢迎提交 issue 和 pull request。请尽量保持改动聚焦；如果涉及 parser、价格、聚合或 UI 行为，请补充相应测试。

本仓库的本地 agent 协作规则见 [AGENT_GUIDE.md](./AGENT_GUIDE.md)。

## 许可证

TokenWatch 使用 GNU General Public License v3.0 or later 授权。详见 [LICENSE](./LICENSE)。
