# AI Token Watch

[![CI](https://github.com/OrrHsiao/TokenWatch/actions/workflows/ci.yml/badge.svg)](https://github.com/OrrHsiao/TokenWatch/actions/workflows/ci.yml)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue)](./LICENSE)
![macOS 15+](https://img.shields.io/badge/macOS-15.0%2B-000000?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![AppKit](https://img.shields.io/badge/AppKit-native-0A84FF)
![Menu Bar App](https://img.shields.io/badge/menu%20bar-app-34C759)
![Privacy: local only](https://img.shields.io/badge/privacy-local--only-30D158)

[English](./README.md) | [简体中文](./README.zh-CN.md)

AI Token Watch is a native macOS app for tracking token usage and estimated cost from local coding-agent data. It reads local usage records from Claude Code, Codex, and opencode, then summarizes totals by day, month, model, project, and provider.

The app is built with Swift, AppKit, and the macOS App Sandbox. AI Token Watch does not send your usage data anywhere.

## Screenshots

<p align="center">
  <img src="./snapshots/appstore_snapshot/en-US/01-menu-bar-popover.png" alt="AI Token Watch menu bar popover showing month, week, today, and daily average token usage" width="820">
</p>

<p align="center">
  <img src="./snapshots/appstore_snapshot/en-US/02-overview.png" alt="AI Token Watch overview dashboard showing token totals, cost, trends, source share, model ranking, and project usage" width="820">
</p>

<p align="center">
  <img src="./snapshots/appstore_snapshot/en-US/03-sessions.png" alt="AI Token Watch sessions view showing session-level model, token, cost, and record counts" width="820">
</p>

## Features

- Native macOS menu bar and window experience
- Total usage, today, recent 30 days, and recent 12 months views
- Token and cost breakdowns by provider and model
- Calendar heatmap and chart views for trend scanning
- Session-level review with model, project, token, cost, and record counts
- Local parsing for Claude Code JSONL, Codex rollout JSONL, and opencode SQLite data
- Security-scoped bookmark access for sandbox-friendly local file permissions
- Embedded LiteLLM pricing snapshot with hand-tuned pricing overrides for common models

## Supported Sources

AI Token Watch never opens a file picker automatically at launch. In **Settings**, use the **Data Folders** section to choose only the providers you use.

| Source | Folder selected by the user | Data read inside that folder |
| --- | --- | --- |
| Claude Code | Claude Code data folder | `projects/**/*.jsonl` |
| Codex | Codex data folder | `sessions/**/rollout-*.jsonl`, `archived_sessions/**`, and optional `config.toml` |
| opencode | opencode data folder | `opencode.db` |

Each provider stores an independent read-only security-scoped bookmark. Leaving one provider unselected does not block selected providers.

## Privacy

AI Token Watch is designed as a local-only utility.

- It reads a provider folder only after you explicitly choose that folder in the standard macOS open panel.
- It stores one security-scoped bookmark per selected provider in `UserDefaults` so it can reopen that folder later.
- It does not upload usage records, project paths, prompts, responses, or pricing data.
- It does not include analytics or telemetry.

The app may display local project paths from the agent logs because those paths are part of the source data. See the [Privacy Policy](https://orrhsiao.github.io/TokenWatch/privacy/).

## Install

Download the latest packaged app from the [GitHub Releases page](https://github.com/OrrHsiao/TokenWatch/releases):

1. Download `AI-Token-Watch-macOS-universal.zip` from the latest release.
2. Unzip the archive.
3. Move `AI Token Watch.app` to `/Applications`.
4. Open AI Token Watch. Launch does not open a file picker.
5. Open **Settings** and, in **Data Folders**, choose the folder for each provider you use.

If macOS says `AI Token Watch.app is damaged and can't be opened. You should move it to the Trash.`, confirm that the app came from the official AI Token Watch release page, then go to **System Settings > Privacy & Security**. In the Security section, click **Open Anyway** for AI Token Watch, then open AI Token Watch again and choose **Open** when prompted.

To build from source instead:

1. Clone the repository.
2. Open `TokenWatch.xcodeproj` in Xcode.
3. Select the `TokenWatch` scheme.
4. Build and run on macOS.
5. Open **Settings** and choose provider folders in **Data Folders**.

## First Run

AI Token Watch does not request access at launch. Open **Settings**, find **Data Folders**, and choose each provider's data folder with the standard macOS folder picker. You can cancel without changing that provider's existing selection or data.

Selected providers load independently. An unselected provider shows that its folder has not been selected; an empty selected folder shows that no data was found. You can refresh manually from the window or menu bar popover, and change automatic refresh intervals in Settings.

## Build

Requirements:

- macOS 15.0+
- Xcode 16.4+
- Swift 6.0

Build the app:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build
```

Run unit tests:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

Run all tests:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' test
```

## Architecture

Each provider owns its scanner, parser, selected data-root contract, and read-only security-scoped bookmark, then emits shared `ParsedUsageEntry` values. `PricingEngine` and `UsageAggregator` turn those entries into summaries that are rendered by AppKit view controllers. Provider authorization and loading states remain independent in `TokenStatsViewModel`.

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

Key directories:

```text
TokenWatch/
  Analytics/       Aggregation logic
  Models/          Shared usage and pricing models
  Pricing/         Pricing table, LiteLLM catalog, cost engine
  Providers/       Claude Code, Codex, and opencode adapters
  Services/        Security-scoped bookmark management
  ViewControllers/ AppKit UI
  ViewModels/      Provider state coordination

TokenWatchTests/   Swift Testing unit tests
TokenWatchUITests/ XCTest UI tests
```

## Pricing Data

AI Token Watch estimates cost from embedded pricing data. Prices can drift from upstream provider billing, so treat app totals as an estimate rather than an invoice. Unknown models fall back to upstream cost when the source provides it; otherwise their cost may be shown as zero until pricing data is updated.

## Contributing

Issues and pull requests are welcome. Please keep changes focused and include tests for parser, pricing, aggregation, or UI behavior when relevant.

For local agent guidance, see [AGENT_GUIDE.md](./AGENT_GUIDE.md).

## License

AI Token Watch is licensed under the GNU General Public License v3.0 or later. See [LICENSE](./LICENSE).
