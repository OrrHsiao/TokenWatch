# 小组件方案 2 设计验收

日期：2026-08-05

## 对照材料

- 视觉参考：`/Users/orrhsiao/.codex/generated_images/019fcd44-b429-73f3-bbcb-01359cf2a01c/exec-6727b540-7dfe-4bf9-93c5-2130361c774a.png`
- 实现截图（顶部）：`/Users/orrhsiao/.codex/visualizations/2026/08/04/019fcd44-b429-73f3-bbcb-01359cf2a01c/widget-option-2-qa/implementation-top-final.jpeg`
- 实现截图（下部）：`/Users/orrhsiao/.codex/visualizations/2026/08/04/019fcd44-b429-73f3-bbcb-01359cf2a01c/widget-option-2-qa/implementation-lower-final.jpeg`
- 合并对照图：`/Users/orrhsiao/.codex/visualizations/2026/08/04/019fcd44-b429-73f3-bbcb-01359cf2a01c/widget-option-2-qa/comparison-final.png`

参考图是概念排版，应用内 Gallery 继续使用项目既有的纵向分区与真实 WidgetKit small/medium 参考尺寸；本次以每张小组件卡片的内容层级、间距、颜色和状态语义作为对照面。

## 验收结论

- 热力图与趋势图：实现未修改，截图与改造前保持一致。
- 最近 7 天：small 使用主数值优先布局；medium 增加本地化星期标签和当日强调；两种尺寸均无截断或拥挤。
- 今日用量：small/medium 均明确展示今日总量、相对 7 日均值的变化和日均基线；medium 的均值虚线清晰可见。非真实告警使用品牌蓝，达到保守异常判定时才使用红色。
- 本月预算：实际进度保持品牌蓝；月底预测使用独立琥珀色虚线刻度和预测文案，不再把预测风险误表达为当前支出进度。
- 项目消耗与主模型：主名称、总量、来源占比的层级清晰；分别使用紫色和青色占比条。
- 字体与布局：核心数值使用圆角粗体和等宽数字，辅助文案保持次级对比；155×155 与 329×155 预览均未出现裁切、重叠或异常换行。
- 明暗与方向适配：指标色在浅色和深色外观下分别使用高对比色值；预算预测刻度会随 RTL 布局镜像。
- 可访问性：保留聚合 VoiceOver 标签，并把冻结语言的星期标题、日均标题、变化百分比、预测位置和来源占比纳入展示数据。

## 迭代记录

1. 首轮截图发现 medium 今日用量的日均虚线在系统材质上对比不足。
2. 将参考线绑定到 Charts 绘图区和展示层的同一日均值，并同步真实 Widget 与 Gallery 预览。
3. 复核浅色对比度、极端变化百分比、应用语言与系统语言不一致、RTL 预算刻度和过期数据提示等边界状态。
4. 最终实机截图确认预算主数值与预测刻度完整显示，项目/模型使用独立紫色与青色，占比及时间范围无裁切。
5. Xcode 完整构建成功，13 项小组件定向测试全部通过；合并对照图复核通过。

final result: passed
