# Bundle 原生本地化设计

**日期**: 2026-07-22
**作者**: TokenWatch
**状态**: 已确认，待实现

## 背景与目标

TokenWatch 的应用内界面已经通过 `AppLanguage` 和 `AppStrings` 支持简体中文、繁体中文、英文、日文、韩文、西班牙文、德文、法文、葡萄牙文（巴西）、意大利文、荷兰文和波兰文。但 Xcode 工程仅声明 `en` 与 `Base`，目标不含任何本地化资源，生成的应用 Bundle 也没有 `CFBundleLocalizations`。

本次目标是在不迁移或复制现有 154 条运行时 UI 文案的前提下，让 macOS 能从应用 Bundle 识别全部 12 种支持语言，并为生成的 `Info.plist` 提供原生本地化资源。

## 范围

### 本次包含

1. 为应用目标新增 `InfoPlist.xcstrings`，声明 12 种已支持的本地化语言。
2. 本地化 `CFBundleDisplayName` 与 `CFBundleName`，品牌名称在各语言中保持 `AI Token Watch`。
3. 在 Debug 与 Release 的生成式 `Info.plist` 配置中显式写入 `CFBundleLocalizations` 数组。
4. 将 Xcode 项目的 `knownRegions` 扩展为相同的 12 种语言和 `Base`。
5. 新增回归测试，验证应用 Bundle 的语言声明与本地化资源集合完整。

### 本次不包含

- 将 `AppStrings` 的 154 条 UI 文案迁移到 `Localizable.xcstrings`。
- 修改应用内语言切换、`AppLanguage` 的系统语言解析或 UI 重绘逻辑。
- 本地化日志、测试名称、provider 或模型名称、token 数和美元金额格式。
- 更改产品名称或品牌文案。

## 设计

### 双层本地化职责

`AppStrings` 继续作为用户可见 UI 文案的唯一运行时来源。它支持应用内独立于系统的语言偏好，不能由 Bundle 的系统语言回退机制替代。

新增的 `InfoPlist.xcstrings` 只负责 Bundle 层的原生资源，例如 Finder、Launch Services 和系统读取的应用显示名。该目录包含与 `AppLanguage.allCases` 一致的 12 种语言，不存放 UI 文案 key，避免两套 154 键词典发生漂移。

### 项目与产物配置

工程使用 `PBXFileSystemSynchronizedRootGroup`，因此把字符串目录放入 `TokenWatch/` 后由目标自动纳入资源。项目文件仍需更新 `knownRegions`，以便 Xcode 的工程元数据与实际资源一致。

应用目标的 Debug 和 Release 配置都显式生成 `CFBundleLocalizations`。其语言代码为：

```text
zh-Hans, zh-Hant, en, ja, ko, es, de, fr, pt-BR, it, nl, pl
```

`CFBundleDevelopmentRegion` 继续使用 `en`，因为英文是现有生成式 `Info.plist` 的开发语言；它不等同于支持语言列表。

### 回归测试

新增 Bundle 本地化测试，使用应用宿主 Bundle 验证：

1. `CFBundleLocalizations` 是包含全部 12 个语言代码的数组。
2. Bundle 的 `localizations` 包含全部 12 个语言代码。
3. 每种语言都有 `InfoPlist.strings` 编译资源，且可读取 `CFBundleDisplayName`。

测试的期望语言集合以单一常量定义，与 `AppLanguage.allCases.map(\.rawValue)` 比较，防止新增应用语言时忘记扩展 Bundle 配置。

## 错误处理与兼容性

没有新的运行时分支或用户可见错误。缺少某个 Bundle 语言资源时，系统仍会使用开发语言回退；新增测试会在开发阶段阻止这种不完整产物进入发布流程。

## 验证

1. 运行 Bundle 本地化单元测试。
2. 构建 Debug 应用后，使用 `plutil` 验证 `CFBundleLocalizations` 为 12 项数组。
3. 检查应用 `Contents/Resources` 中的 12 个 `.lproj/InfoPlist.strings` 资源。
4. 运行现有应用语言测试，确认运行时词典与系统语言解析未回归。

## 影响面

| 文件 | 改动 |
|---|---|
| `TokenWatch/InfoPlist.xcstrings` | 新增 Bundle 层本地化目录 |
| `TokenWatch.xcodeproj/project.pbxproj` | 扩展区域声明并生成支持语言数组 |
| `TokenWatchTests/Localization/BundleLocalizationTests.swift` | 新增 Bundle 本地化回归测试 |
