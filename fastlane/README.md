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
rbenv exec bundle exec fastlane mac validate_app_store_release app_version:1.0.4
```

只在本地校验 App Store 版本、元数据和截图

### mac upload_app_store_metadata

```sh
rbenv exec bundle exec fastlane mac upload_app_store_metadata app_version:1.0.4
```

上传商店元数据与截图，但不提交审核

### mac submit_xcode_cloud_build

```sh
rbenv exec bundle exec fastlane mac submit_xcode_cloud_build app_version:1.0.4 build_number:42
```

等待指定 Xcode Cloud 构建，上传资料并提交 App Review

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
