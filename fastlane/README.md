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
rbenv exec bundle exec fastlane mac validate_app_store_release app_version:1.0.5
```

只在本地校验 App Store 版本、元数据和截图

### mac plan_widget_iap

```sh
rbenv exec bundle exec fastlane mac plan_widget_iap
```

只读检查桌面小组件永久解锁内购的创建计划

### mac create_widget_iap

```sh
rbenv exec bundle exec fastlane mac create_widget_iap confirm:true
```

创建并配置 $2.99 的桌面小组件永久解锁内购

### mac upload_app_store_metadata

```sh
rbenv exec bundle exec fastlane mac upload_app_store_metadata app_version:1.0.5
```

上传商店元数据与截图，但不提交审核

### mac upload_app_store_screenshots

```sh
rbenv exec bundle exec fastlane mac upload_app_store_screenshots app_version:1.0.5
```

只上传商店截图，不修改元数据或提交审核

### mac submit_xcode_cloud_build

```sh
rbenv exec bundle exec fastlane mac submit_xcode_cloud_build app_version:1.0.5 build_number:42
```

等待指定 Xcode Cloud 构建，上传资料并提交 App Review

----

This README is maintained manually so required release and IAP safety parameters remain visible.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
