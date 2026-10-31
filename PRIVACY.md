# AI Token Watch Privacy Policy

[简体中文](https://orrhsiao.github.io/TokenWatch/privacy/zh-CN/)

Effective Date: October 31, 2026

AI Token Watch is a local-only macOS app for summarizing token usage from coding-agent records on your Mac.

## Data Collection

AI Token Watch does not collect, transmit, sell, share, or upload user data.

AI Token Watch does not require an account or login. It does not include analytics, advertising, telemetry, tracking, or third-party SDKs.

## Local File Access

AI Token Watch does not display a file picker automatically when it launches. In Settings, you may separately choose a data folder for Claude Code, Codex, opencode, Antigravity, or DeepSeek Harness. The app uses each selected folder directly as that provider's data root and reads it with read-only access granted through the standard macOS file picker.

If you use the subscription quota feature, you may also choose the Claude Code configuration file `~/.claude.json` in Settings. The app reads it with read-only access and decodes only the cached subscription quota and the current account identifier, which is used to confirm that the cached quota belongs to the signed-in account. Other contents of the file are ignored. Codex quota is read from the session logs in the Codex data folder you already selected.

All parsing, aggregation, and cost estimation happen locally on your device. An unselected provider does not prevent the app from using data from providers you selected.

The app may display local information derived from those files, such as token counts, model names, session identifiers, project paths, and remaining subscription quota. This information remains on your device.

## Local Storage

AI Token Watch stores app preferences in local UserDefaults, along with an independent security-scoped bookmark for each provider folder you select and for the Claude Code configuration file if you choose it. This lets the app remember settings and restore only the access you granted.

To power desktop widgets, the app also writes an aggregated usage summary (such as token totals, model names, and project names) and your purchase status to a shared App Group container on your Mac, which only AI Token Watch's widgets read. This data is stored only on your device and is not transmitted anywhere.

## Network Access

AI Token Watch itself does not access the network. The Privacy Policy and Support entries open public webpages in your default browser. In-app purchases are processed by Apple through the App Store; AI Token Watch does not receive your payment information.

## Contact

For privacy questions or app support, visit the [AI Token Watch Support page](https://orrhsiao.github.io/TokenWatch/support/) or email [orrhsiao@126.com](mailto:orrhsiao@126.com). A GitHub account is not required to contact support by email.
