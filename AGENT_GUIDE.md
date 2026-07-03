## 基础规则
### 1. 编码前思考

**不要假设，不要掩盖困惑，要明确权衡取舍。**

- **明确说明假设** — 如果不确定，询问而不是猜测
- **呈现多种解释** — 当存在歧义时，不要默默选择
- **适时提出异议** — 如果存在更简单的方法，说出来
- **困惑时停下来** — 指出不清楚的地方并要求澄清

### 2. 简洁优先

**用最少的代码解决问题。不要过度推测。**

对抗过度工程化的倾向：

- 不要添加要求之外的功能
- 不要为一次性代码创建抽象
- 不要添加未要求的"灵活性"或"可配置性"
- 不要为不可能发生的场景做错误处理
- 如果 200 行代码可以写成 50 行，就重写它

**检验标准：** 资深工程师会觉得这过于复杂吗？如果是，简化。

### 3. 精准修改

**只修改必要部分。只清理自己引入的问题。**

编辑现有代码时：

- 不要"顺手优化"相邻的代码、注释或格式
- 不要重构没有问题的部分
- 匹配现有风格，即使你更倾向于不同的写法
- 如果注意到无关的死代码，指出一下，但不要删除

当你的改动产生孤儿代码时：

- 删除因你的改动而变得无用的导入/变量/函数
- 不要删除预先存在的死代码，除非被要求

**检验标准：** 每一行修改都应该能直接追溯到用户的请求。

### 4. 目标驱动执行

**定义成功标准。循环验证直到达成。**

将指令式任务转化为可验证的目标：

| 不要这样做... | 转化为... |
|--------------|-----------------|
| "添加校验" | "为无效输入编写测试，并让测试通过" |
| "修复 bug" | "编写能重现 bug 的测试，然后让它通过" |
| "重构 X" | "确保重构前后测试都能通过" |

对于多步骤任务，说明一个简短的计划：

```
1. [步骤] → 验证: [检查]
2. [步骤] → 验证: [检查]
3. [步骤] → 验证: [检查]
```

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

### Build
```bash
# Build the app (Debug)
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build

# Build the app (Release)
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Release build
```

### Test
```bash
# Run all tests (unit + UI)
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' test

# Run only unit tests
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test

# Run only UI tests
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchUITests test

# Run a single unit test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TokenWatchTests/testMethodName test
```