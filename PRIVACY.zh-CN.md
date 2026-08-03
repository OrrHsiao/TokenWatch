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
