## 代码质量

- 核心公共方法必须添加注释，说明其作用、参数和返回值（如适用）。
- 复杂业务逻辑、特殊实现方式或容易产生歧义的代码，必须添加注释说明设计原因，而不仅仅描述代码做了什么。
- 关键业务流程、重要状态变更、异常分支等关键步骤应添加适当的日志（log），便于排查问题。
- 日志内容应简洁、明确，能够体现当前执行阶段和关键信息，避免无意义或过于频繁的日志输出。
- 不要为了满足规则而添加无价值的注释或日志，保持代码整洁。

## 提交
1. Commit 基本原则

每次提交必须满足：

* Commit message 优先使用中文
* 单一职责（One Commit, One Purpose）
* 可回滚（Revertable）
* 可追踪（Traceable）
* 可审计（Auditable）

禁止：

* 混合多个不相关修改
* 提交临时代码
* 提交未使用代码
* 提交调试日志
* 提交破坏性变更且无说明

2. Commit Message格式
<type>(<scope>): <summary>

示例：
feat(agent): 新增 Maestro DSL 转 Appium 脚本能力
fix(parser): 修复 YAML 缩进解析异常
refactor(runtime): 重构任务调度流程
perf(core): 优化执行器并发性能
test(login): 增加登录流程冒烟测试
docs(readme): 补充安装说明
chore(deps): 升级 Appium 依赖版本
ci(actions): 优化构建缓存策略

## 项目规则
1. 设计文档优先使用中文。
2. 优先使用 Xcode MCP 进行构建、测试和调试。

### macOS 测试运行说明
- 在 Codex/agent 沙盒内，`xcodebuild` 默认写入 `~/Library/Developer/Xcode/DerivedData` 可能触发权限错误；运行构建或测试时优先指定 `-derivedDataPath .build/DerivedData`，必要时把 `.xcresult` 写到 `.build/TestResults/`。
- macOS app-hosted tests 需要连接系统测试服务 `com.apple.testmanagerd.control`。沙盒内执行 `xcodebuild test` 可能失败并出现 `Sandbox restriction`；完整测试应在沙盒外运行，或在 Codex 中对测试命令申请提升权限。
- 如果无法提升权限，`build-for-testing` 只能验证编译，不能替代真正的测试运行。
- `.build/` 已被 `.gitignore` 忽略，可作为本项目的本地 DerivedData 和测试结果目录。

### Build
```bash
# Build the app (Debug)
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug -derivedDataPath .build/DerivedData build

# Build the app (Release)
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Release -derivedDataPath .build/DerivedData build
```

### Test
```bash
# Run all tests (unit + UI)
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -derivedDataPath .build/DerivedData test

# Run only unit tests
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test

# Run only UI tests
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test

# Run a single Swift Testing test (the identifier must include trailing parentheses)
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/TokenWatchTests/testMethodName()' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test

# Compile tests without running them (usable inside sandbox when testmanagerd is unavailable)
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData build-for-testing
```
