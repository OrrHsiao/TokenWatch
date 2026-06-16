# 状态栏刷新仪表盘动画 — 设计稿

- 日期:2026-06-16
- 关联:`StatusBarController`、`StatusBarTitleBuilder`、`TokenStatsViewModel`

## 1. 范围与目标

每次 TokenWatch 触发刷新时,菜单栏左侧的 SF Symbol 仪表盘图标进入加载动画。动画使用现有的 `gauge.with.dots.needle.*percent` 系列图标帧,让用户能看出正在刷新;状态栏文本继续展示上一次 token 数,避免刷新过程中闪烁或跳动。

本次只改菜单栏状态图标:

- 覆盖启动时自动刷新、30 秒定时刷新、菜单「立即刷新」。
- 不改主窗口各 provider 的 loading 文案。
- 不改 token 总数计算、图标分档阈值、刷新间隔。
- 不引入第三方依赖。

## 2. 设计决策

采用 `StatusBarController` 内部图标帧动画:

1. `StatusBarTitleBuilder` 继续只负责纯计算:文本、当日 token 总数、静态图标分档。
2. 新增纯函数暴露刷新动画帧顺序,便于单测覆盖:

   ```swift
   static let loadingSymbolNames = [
       "gauge.with.dots.needle.0percent",
       "gauge.with.dots.needle.33percent",
       "gauge.with.dots.needle.50percent",
       "gauge.with.dots.needle.67percent",
       "gauge.with.dots.needle.100percent",
   ]
   ```

3. `StatusBarController` 根据 ViewModel loading 状态启动或停止动画:
   - 任一 provider `isLoading == true` 时启动动画 timer。
   - 所有 provider `isLoading == false` 时停止动画并调用现有 `renderTitle()` 恢复真实分档图标。
4. 动画 timer 只替换 `iconView.image`,不修改 `titleLabel`,所以刷新期间文字保持稳定。

## 3. 状态流

```
viewModel.loadAllStats()
        │
        ▼
某 provider isLoading = true
        │
        ▼
StatusBarController.startLoadingAnimation()
        │
        ▼
循环替换 gauge.with.dots.needle.*percent 图标
        │
        ▼
全部 provider isLoading = false
        │
        ▼
StatusBarController.stopLoadingAnimation()
        │
        ▼
renderTitle() 恢复按今日 token 总量分档的静态图标
```

现有 observer 曾刻意等待所有 provider 完成后才重绘标题,避免数字中途跳动。本次保留这个约束,只在 loading 期间额外更新图标帧。

## 4. 测试策略

- `StatusBarTitleBuilderTests` 新增动画帧顺序测试,确保帧只使用 `gauge.with.dots.needle.*percent` 系列并按 0 → 100 的方向排列。
- 保留现有 `symbolNameTiers` 测试,确认静态图标分档不受动画影响。
- 运行 `TokenWatchTests` 目标验证状态栏文本、ViewModel observer、provider 解析等现有单测仍通过。

UI timer 与 `NSStatusItem` 的实际动画播放不做自动化 UI 测试;核心可测行为是帧定义和 loading 状态触发路径,最终通过构建与人工运行验收确认。

## 5. 风险与处理

- **重复刷新重入**:动画启动时若 timer 已存在则直接复用,避免叠加多个 timer。
- **刷新失败或未授权**:只要 ViewModel 结束 loading,动画就停止;错误和未授权仍走现有静态显示逻辑。
- **低功耗影响**:动画 timer 仅在刷新期间存在,刷新结束立即释放。
- **布局稳定性**:所有帧共用相同 SF Symbol 配置和 `NSImageView` 尺寸约束,不会改变状态栏宽度。
