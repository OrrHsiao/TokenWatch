# 文件选择器取消预设用户目录设计

## 背景

App Review 根据 Guideline 2.4.5(i) 指出 TokenWatch 将 Home Folder 作为预设位置。当前授权流程虽然使用标准 `NSOpenPanel`，但会主动将 `directoryURL` 设置为 provider 的默认目录；现有 provider 的默认目录均为当前用户主目录。

## 目标

保留现有 App Sandbox、只读 User Selected Files 和 security-scoped bookmark 流程，仅取消系统目录选择器的初始目录预设，让用户在标准 `NSOpenPanel` 中主动导航并选择授权目录。

## 设计

- `SecurityScopedBookmarkManager` 创建 `NSOpenPanel` 时不再读取 provider 的默认目录，也不再设置 `panel.directoryURL`。
- 保留目录单选、显示隐藏文件、授权提示、bookmark 创建与持久化等现有行为。
- 本次不改变共享 Home Folder bookmark 的数据模型，不拆分各 provider 的授权，也不修改首次启动授权时机或界面文案。
- 删除因本次变更失去用途的 `UsageProvider.defaultDirectoryPath` 及其 provider 实现，避免继续表达“预设目录”语义。

## 测试与验收

- 以可独立测试的面板配置方法验证新创建的 `NSOpenPanel.directoryURL` 未被 TokenWatch 设置。
- 现有授权提示、本地化和 bookmark 测试继续通过。
- Debug/Release 至少完成一次项目构建验证；完整单元测试在环境允许时运行。
- 最终代码中授权流程不存在对 `NSOpenPanel.directoryURL` 的赋值，也不存在 provider 默认目录配置。

## 非目标

- 不改为分别授权 `.claude`、`.codex` 或 OpenCode 数据目录。
- 不改变数据扫描路径、bookmark key 或历史 bookmark 的兼容性。
- 不调整应用内其他设置和首次启动流程。
