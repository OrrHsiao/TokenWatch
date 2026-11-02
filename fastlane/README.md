fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac validate_app_store_release

```sh
rbenv exec bundle exec fastlane mac validate_app_store_release app_version:1.5.0
```

只在本地校验 App Store 版本、元数据和截图

### mac upload_app_store_metadata

```sh
rbenv exec bundle exec fastlane mac upload_app_store_metadata app_version:1.5.0
```

上传商店元数据与截图，但不提交审核

### mac upload_app_store_screenshots

```sh
rbenv exec bundle exec fastlane mac upload_app_store_screenshots app_version:1.5.0
```

只上传商店截图，不修改元数据或提交审核

### mac generate_app_store_screenshots

```sh
rbenv exec bundle exec fastlane mac generate_app_store_screenshots
# 或同时跑 UI 测试抓取最新界面：
rbenv exec bundle exec fastlane mac generate_app_store_screenshots run_ui_tests:true
```

自动重新装裱双语 App Store 宣传图并执行本地规范校验

### mac update_and_upload_screenshots

```sh
rbenv exec bundle exec fastlane mac update_and_upload_screenshots app_version:1.5.0
```

一键自动化：重新生成商店宣传图，并通过审核前校验后同步上传至 App Store Connect

### mac submit_xcode_cloud_build

```sh
rbenv exec bundle exec fastlane mac submit_xcode_cloud_build app_version:1.5.0 build_number:42
```

等待指定 Xcode Cloud 构建，上传资料并提交 App Review

----

This README is maintained manually so required release and IAP safety parameters remain visible.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
