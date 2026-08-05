# Xcode Cloud + 本地 Fastlane App Store 发布设计

## 1. 方案概览

TokenWatch 采用适合个人项目的两段式发布流程：

```text
release 分支的新 commit
  -> Xcode Cloud 测试、签名、Archive、上传 App Store Connect
  -> 本机 Fastlane 校验并上传版本说明、URL 和截图
  -> 本机 Fastlane 选择精确 version/build 并提交 App Review
  -> 审核通过后在 App Store Connect 手动发布
```

在这条 App Store 发布链路中，GitHub 只作为 Xcode Cloud 读取源码和 `release` 分支的 Git 仓库，不运行 App Store 发布工作流，也不保存 Apple API Key。仓库原有的 GitHub Release workflow 与此流程相互独立。

## 2. 职责边界

### Xcode Cloud

- 构建 `TokenWatch` scheme，同时包含 Widget Extension。
- 使用 Apple 托管的证书和 provisioning profile 自动签名。
- Archive 并上传二进制到 App Store Connect。
- 分配实际 `build_number`。

### 本机 Fastlane

- 校验 App 与 Widget 的 `MARKETING_VERSION`。
- 校验中英文版本说明、Support/Privacy URL 和截图。
- 上传版本说明、URL 和商店截图。
- 等待指定 Xcode Cloud build 处理完成。
- 只选择输入的精确 version/build 提交 App Review。

### 人工确认

- 针对本次精确 build 确认 App Privacy、出口合规、Review 联系人、版权、价格和销售地区。
- 截图中的数据是否允许公开。
- 是否执行提审，以及审核通过后何时发布。

## 3. 当前工程基线

| Target | Bundle ID | Release Version / Build |
| --- | --- | --- |
| `TokenWatch` | `com.xiaoao.tokenwatch` | `1.0.4 (2)` |
| `TokenWatchWidgets` | `com.xiaoao.tokenwatch.widgets` | `1.0.4 (2)` |

主 App 与 Widget 使用 Team `8525Z2FVDF`、Automatic Signing 和 App Group `group.com.xiaoao.tokenwatch`。

历史审核资料显示 App Store 曾存在 `1.0 (8)`。macOS build number 必须持续递增，因此首次配置 Xcode Cloud 时，必须查询 App Store Connect 中的历史最大 build，并把 **Next Build Number** 设置为最大值加一，不能直接使用工程中的 `2`。[Apple：设置 Xcode Cloud 下一构建号](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds)

## 4. 仓库文件

```text
Gemfile
Gemfile.lock
.ruby-version
fastlane/
  Appfile
  Fastfile
  .env.example
  metadata/
    en-US/
      release_notes.txt
      support_url.txt
      privacy_url.txt
    zh-Hans/
      release_notes.txt
      support_url.txt
      privacy_url.txt
snapshots/appstore_snapshot/
  en-US/*.png
  zh-Hans/*.png
```

`.p8` 私钥和实际 `fastlane/.env` 不进入仓库。商店截图继续复用版本化的 `snapshots/appstore_snapshot`，不复制到被忽略的 `fastlane/screenshots`。

## 5. 一次性配置

### 5.1 安装 Ruby 依赖

项目固定使用 Ruby `3.4.9`、Fastlane `2.237.0` 和 `Gemfile.lock`。当前机器使用 rbenv，首次执行：

```bash
rbenv install -s 3.4.9
rbenv exec ruby -v
rbenv exec bundle install
```

所有 Fastlane 命令都通过 `rbenv exec bundle exec fastlane` 运行，避免系统 Ruby 版本不同。若终端已正确初始化 rbenv 并自动读取 `.ruby-version`，可以省略命令前的 `rbenv exec`。

### 5.2 配置本地 App Store Connect API Key

在 App Store Connect 的 **Users and Access > Integrations > App Store Connect API** 创建 Team Key：

- 角色使用 `App Manager`。
- 下载 `.p8` 后保存到仓库外，例如：
  `~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8`。
- 设置文件权限为仅当前用户可读：

  ```bash
  mkdir -p ~/.appstoreconnect/private_keys
  chmod 600 ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
  ```

复制本地配置模板：

```bash
cp fastlane/.env.example fastlane/.env
```

填写 `fastlane/.env`：

```dotenv
ASC_KEY_ID=XXXXXXXXXX
ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000
ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
```

Fastlane 会自动加载该文件。`.gitignore` 已忽略实际 `.env` 和 `AuthKey_*.p8`，但私钥仍必须保存在仓库外。

### 5.3 配置 Xcode Cloud

在 Xcode 中建立独立 workflow `App Store Release`：

1. Product 和 scheme 选择 `TokenWatch`。
2. 保留现有 Start Condition：`release` 分支发生 Branch Changes 时启动。
3. 添加 Test action，至少运行 `TokenWatchTests`；测试成功后才继续发布。
4. 添加 macOS Archive action，并让它依赖 Test action 成功。
5. Deployment Preparation 选择 **TestFlight and App Store**。
6. 启用 Clean Build 和 Restrict Editing。
7. 配置 Archive 后上传 App Store Connect。
8. 确认主 App、Widget Bundle ID 和 App Group capability 已注册。
9. 把 Next Build Number 设置为 App Store Connect 历史最大 build 加一。

## 6. Fastlane Lanes

### `mac validate_app_store_release`

只读本地校验，不需要 API Key，也不会访问 Apple：

```bash
rbenv exec bundle exec fastlane mac validate_app_store_release app_version:1.0.5
```

检查内容：

- App 与 Widget 的 Release `MARKETING_VERSION` 等于输入版本。
- `en-US`、`zh-Hans` 版本说明存在、非空且不超过 4000 字符。
- Support/Privacy URL 是完整 HTTPS URL。
- 每个 locale 有 1 至 10 张截图。
- Mac 截图尺寸符合规范且不含 alpha 通道。

### `mac upload_app_store_metadata`

上传商店资料，但不选择二进制、不提交审核：

```bash
rbenv exec bundle exec fastlane mac upload_app_store_metadata app_version:1.0.5
```

此步骤是可选预览。资料确认无误时，也可以直接运行提审 lane。

### `mac submit_xcode_cloud_build`

等待并选择 Xcode Cloud 上传的精确构建，然后提交审核：

```bash
rbenv exec bundle exec fastlane mac submit_xcode_cloud_build \
  app_version:1.0.5 \
  build_number:42
```

行为：

- 最多等待指定 build 处理 60 分钟，每 15 秒查询一次。
- 只接受 `VALID`，明确拒绝 `FAILED` 和 `INVALID`。
- 二进制始终由 Xcode Cloud 上传，Fastlane 设置 `skip_binary_upload: true`。
- 上传仓库中的双语 metadata 和截图。
- 提交 App Review。
- 固定 `automatic_release: false`，审核通过后不会自动上线。

## 7. 每次发版的最简流程

1. 同时更新 App 和 Widget 的 `MARKETING_VERSION`。
2. 更新中英文 `release_notes.txt`，确认截图数据可以公开。
3. 本地执行资料校验：

   ```bash
   rbenv exec bundle exec fastlane mac validate_app_store_release app_version:1.0.5
   ```

4. 将通过校验的发布提交合入 `release` 分支并推送，触发 Xcode Cloud：

   ```bash
   git switch release
   git push origin release
   git rev-parse HEAD
   ```

5. 等待 Xcode Cloud 完成 Archive 和上传；核对构建详情中的 source commit 与上一步 SHA 一致，并在 App Store Connect 记下实际 build number。
6. 针对本次精确 build，在提审 lane 前确认 App Privacy、出口合规、Review 联系人、版权、价格/地区和 Review Notes。
7. 确保工作区没有未提交修改，并切换到 Xcode Cloud 构建详情中的精确 source commit：

   ```bash
   git status --short
   git fetch origin release
   git switch --detach 0123456789abcdef0123456789abcdef01234567
   ```

   `git status --short` 必须没有输出，示例 SHA 要替换为实际 source commit。即使之后 `release` 分支继续前进，Fastlane 上传的 metadata 和截图仍与该构建来自同一个 commit。

8. 在本机执行提审：

   ```bash
   rbenv exec bundle exec fastlane mac submit_xcode_cloud_build \
     app_version:1.0.5 \
     build_number:42
   ```

9. 提审命令完成后使用 `git switch -` 返回原分支。
10. Apple 审核通过后，在 App Store Connect 手动发布。

如果希望先检查线上截图和文案，可在提审命令前运行一次 `upload_app_store_metadata`；否则无需增加额外步骤。

如需保留容易识别的版本历史，可以额外给同一 commit 创建 `v1.0.5` tag；tag 不再是 Xcode Cloud 触发或 Fastlane 提审的必要条件。

## 8. 失败与恢复

| 故障 | 行为 | 恢复方式 |
| --- | --- | --- |
| App/Widget 版本不一致 | 本地校验失败，不访问 Apple | 修正版本并向 `release` 推送新构建 |
| 截图尺寸或 alpha 不合规 | 本地校验失败 | 重新导出截图 |
| 本地 `.env` 或 `.p8` 缺失 | 在登录前失败 | 修正本地配置 |
| 指定 build 尚未出现 | 最多等待 60 分钟后失败 | 检查 Xcode Cloud/ASC 后重跑同一命令 |
| build 为 `FAILED` / `INVALID` | 明确失败，不提审 | 修复 binary 并产生新 build |
| metadata 上传中断 | 命令失败 | 使用同一输入重新运行 |
| App Store Connect 有冲突草稿 | Deliver 失败，不会自动取消 | 在网页核对并人工处理草稿 |

截图使用 `overwrite_screenshots: true`，会替换当前编辑版本的中英文截图。运行上传或提审命令后不要主动中断；如果网络中断，使用同一命令重跑即可恢复。

## 9. 安全边界

- `.p8` 永远保存在仓库外，不提交、不发送到 GitHub。
- `fastlane/.env` 被 Git 忽略，只保存 Key ID、Issuer ID 和本地私钥路径。
- Fastlane 不自动填写未经确认的出口合规、版权、Review 联系人或隐私法律结论。
- `automatic_release: false` 保证审核通过后仍由开发者决定上线时间。

## 10. 后续可选演进

如果以后需要多人协作、远程提审或审计审批，再增加 GitHub Actions/专用 CI。个人项目阶段不引入额外发布平台，也不增加 webhook 服务。
