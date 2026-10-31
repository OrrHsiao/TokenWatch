# 本地订阅额度设计文件

- 打开 [preview.html](preview.html) 查看设计。
- [preview.fragment.html](preview.fragment.html) 为可编辑源；HTML 预览内嵌两枚 Agent 图标及原界面截图。
- 以 [设计与开发约束](../../superpowers/specs/2026-10-28-subscription-quota-ui-design.md) 和 [Claude 开发交接](../../superpowers/plans/2026-10-28-subscription-quota-ui-handoff.md) 为开发依据。

## 原界面保持

弹窗下方使用 `existing-popover.png` 展示项目原有界面，文件取自加入订阅额度之前的 `snapshots/raw/zh-Hans/01-menu-bar-popover.png`，当前商店截图已包含订阅剩余区。该图是深色演示截图，作为已有样式参照，不随预览主题改变。

开发时复用当前 AppKit 原生视图，不把图片用于应用。只在原区域上方新增订阅区，并增加总高度；原区域的文案、刷新按钮、摘要、热力图、趋势图、字体、颜色、尺寸、间距、材质及交互保持。

## 图标来源

`claude.svg` 与 `codex.svg` 来自 [LobeHub Icons](https://github.com/lobehub/lobe-icons/tree/master/packages/static-svg/icons)，按 MIT 许可使用，见 [ICONS-LICENSE.txt](ICONS-LICENSE.txt)。

预览是设计参考，全部额度均为示例数据。当前未接入本地数据读取，也未修改应用实现。
