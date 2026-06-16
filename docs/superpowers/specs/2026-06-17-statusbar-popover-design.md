# 状态栏左键 Popover — 设计稿

- 日期:2026-06-17
- 关联:`StatusBarController`

## 1. 范围与目标

点击 TokenWatch 菜单栏状态项时,左键弹出一个空的 `NSPopover` 视图。视图暂不承载业务内容,只提供后续扩展的容器。原有状态栏菜单仍保留,改为通过右键或 Control-click 打开,继续提供「打开 TokenWatch」「立即刷新」「退出 TokenWatch」入口。

本次只改状态栏交互:

- 左键:显示或隐藏空 `NSPopover`。
- 右键 / Control-click:显示原有菜单。
- 不改状态栏 token 文本、图标分档、刷新动画、刷新间隔。
- 不引入第三方依赖。

## 2. 设计决策

采用 `NSStatusBarButton` 的 `target/action` 接管鼠标事件,不再把 `NSMenu` 直接挂到 `statusItem.menu`。原因是 `statusItem.menu` 会让系统优先按默认菜单行为处理点击,无法在左键上稳定展示 `NSPopover`。

具体结构:

1. `StatusBarController` 继续持有 `NSStatusItem`。
2. `StatusBarController` 新增一个 `NSPopover`,内容控制器使用空 `NSViewController`。
3. 空视图固定一个基础尺寸,背景使用 `NSColor.windowBackgroundColor`,由 AppKit 自动适配浅色和暗黑模式。
4. 原菜单保留为 `NSMenu` 属性,但不直接赋给 `statusItem.menu`。
5. 状态栏按钮设置 `sendAction(on: [.leftMouseUp, .rightMouseUp])`:
   - 普通左键切换 popover。
   - 右键或 Control-click 弹出原菜单。

## 3. 事件流

```
NSStatusBarButton mouseUp
        │
        ▼
StatusBarController.handleStatusItemClick()
        │
        ├─ leftMouseUp + control modifier → showMenu()
        ├─ rightMouseUp                  → showMenu()
        └─ leftMouseUp                   → togglePopover()
```

`togglePopover()` 以状态栏按钮为锚点调用 `popover.show(relativeTo:of:preferredEdge:)`。如果 popover 已显示,再次左键点击则关闭。

## 4. 测试策略

新增一个纯逻辑枚举,将 AppKit 鼠标事件归类为状态栏交互意图:

- 左键 → `.togglePopover`
- 右键 → `.showMenu`
- Control-click → `.showMenu`

单元测试覆盖上述分流规则。`NSPopover` 与 `NSStatusItem` 的实际展示由 AppKit 负责,通过构建验证 API 调用合法,并在运行应用时人工确认左键和右键行为。

## 5. 风险与处理

- **原菜单入口丢失**:菜单不再挂到 `statusItem.menu`,但作为属性保留,右键 / Control-click 通过 `popUpStatusItemMenu(_:)` 打开。
- **暗黑模式显示异常**:空视图使用 `NSColor.windowBackgroundColor`,不写死颜色。
- **点击状态判断耦合 AppKit**:把事件分流抽为纯函数,单测覆盖规则;控制器只负责调用对应 UI 行为。
