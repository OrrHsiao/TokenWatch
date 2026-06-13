# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TokenWatch is a macOS desktop application (Cocoa/AppKit) for monitoring token usage. The app is categorized as a developer tool (`public.app-category.developer-tools`).

## Build & Test Commands

优先使用 Xcode MCP 进行构建、测试和调试。

### Build
```bash
# Build the app (Debug)
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build

# Build the app (Release)
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Release build
```

### Test
```bash
# Run all tests (unit + UI)
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' test

# Run only unit tests
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test

# Run only UI tests
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchUITests test

# Run a single unit test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TokenWatchTests/testMethodName test
```

## Architecture

### Target Structure
- **TokenWatch** (macOS app) — Main application target
- **TokenWatchTests** (unit test bundle) — Uses Swift Testing framework (`import Testing`)
- **TokenWatchUITests** (UI test bundle) — Uses XCTest

### Key Configuration Details
- **Language**: Swift 6.0
- **Minimum deployment**: macOS 15.0
- **Bundle ID**: `com.xiaoao.TokenWatch`
- **Storyboard**: `Base.lproj/Main.storyboard`
- **Sandbox**: App sandbox enabled with readonly user-selected file access
- **Concurrency**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — all code is `@MainActor` by default unless explicitly opted out
- **App groups**: Registered (`REGISTER_APP_GROUPS = YES`)

### Source Layout
```
TokenWatch/
├── AppDelegate.swift          # NSApplicationDelegate — app lifecycle
├── ViewController.swift       # NSViewController — main content
├── Assets.xcassets/           # AppIcon, AccentColor
└── Base.lproj/
    └── Main.storyboard        # Main interface
TokenWatchTests/
└── TokenWatchTests.swift      # Swift Testing unit tests
TokenWatchUITests/
├── TokenWatchUITests.swift          # XCTest UI tests
└── TokenWatchUITestsLaunchTests.swift  # Launch performance tests
```

### Test Framework Notes
- Unit tests use the **Swift Testing** framework (`import Testing`, `@Test` macro, `#expect(...)`) — not XCTest
- UI tests use **XCTest** (`XCTestCase` subclass, `XCTAssert`, `XCUIApplication`)
- The unit test bundle has `TEST_HOST` set to the main app, so `@testable import TokenWatch` works

## Commit Style

使用 [Conventional Commits](https://www.conventionalcommits.org/) 规范：

```
<type>(<scope>): <description>
```

**Type 类型：**
- `feat` — 新功能
- `fix` — 修复 bug
- `refactor` — 重构（不改变行为）
- `test` — 新增或修改测试
- `docs` — 文件更新
- `chore` — 构建、CI、依赖更新等杂项
- `style` — 格式、空白、分号等（不影响逻辑）

**规则：**
- 描述使用简体中文，不超过 72 字符
- 不强制句尾句号
- commit message 简洁描述「做了什么」而非「怎么做的」

## Agent Working Rules

- 修改代码前先阅读相关文件
- 优先修改已有代码，不要无意义重构
- 不要删除注释，除非确认无用
- 保持现有代码风格
- 一个 PR 只解决一个问题
- 不要引入新的第三方库，除非明确要求
- 不要修改无关文件
- 与用户交流、分析说明、代码解释、总结等默认使用简体中文；仅在用户明确要求或涉及代码、协议、API 等需要保留原文时使用其他语言

## Code Quality Rules

- 核心公共方法必须添加注释，说明其作用、参数和返回值（如适用）。
- 复杂业务逻辑、特殊实现方式或容易产生歧义的代码，必须添加注释说明设计原因，而不仅仅描述代码做了什么。
- 关键业务流程、重要状态变更、异常分支等关键步骤应添加适当的日志（log），便于排查问题。
- 日志内容应简洁、明确，能够体现当前执行阶段和关键信息，避免无意义或过于频繁的日志输出。
- 不要为了满足规则而添加无价值的注释或日志，保持代码整洁。
