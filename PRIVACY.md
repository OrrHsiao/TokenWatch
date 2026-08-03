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
