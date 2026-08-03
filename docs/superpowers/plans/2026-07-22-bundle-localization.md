# Bundle 原生本地化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the shipped macOS app Bundle explicitly declare and package all 12 languages already supported by `AppLanguage`, while preserving `AppStrings` as the runtime UI-copy source.

**Architecture:** Add a version-controlled `Info.plist` because Xcode's generated Info settings cannot reliably emit the array-valued `CFBundleLocalizations` key. Add an `InfoPlist.xcstrings` catalog for native localized Info resources; the file-system-synchronized target automatically compiles it into per-language `InfoPlist.strings` files. A Swift Testing regression test reads the app host bundle and prevents the project settings, catalog, and `AppLanguage` cases from drifting apart.

**Tech Stack:** Swift 6, Foundation, AppKit, Swift Testing, Xcode 26 string catalogs, macOS app bundle resources.

---

## File Structure

- Create `TokenWatch/Info.plist`
  - Owns the static application Info dictionary, including the complete `CFBundleLocalizations` array and existing build-setting placeholders.
- Create `TokenWatch/InfoPlist.xcstrings`
  - Owns native `Info.plist` localization values for `CFBundleDisplayName` and `CFBundleName` in all 12 supported languages.
- Create `TokenWatchTests/Localization/BundleLocalizationTests.swift`
  - Owns the regression test for the declared language array and compiled `InfoPlist.strings` resources.
- Modify `TokenWatch.xcodeproj/project.pbxproj`
  - Switch only the application target's Debug and Release configurations to the static Info file; retain generated Info files for both test targets.
  - Add every supported language to `knownRegions`.

The project uses `PBXFileSystemSynchronizedRootGroup`, so do not add file-reference or build-phase entries for the three new files. New files below `TokenWatch/` and `TokenWatchTests/` acquire target membership automatically.

### Task 1: Add the failing Bundle-localization regression test

**Files:**
- Create: `TokenWatchTests/Localization/BundleLocalizationTests.swift`
- Test: `TokenWatchTests/Localization/BundleLocalizationTests.swift`

- [ ] **Step 1: Write the failing test**

Create `TokenWatchTests/Localization/BundleLocalizationTests.swift` with the following source:

```swift
import Foundation
import Testing
@testable import TokenWatch

@MainActor
@Suite("BundleLocalization")
struct BundleLocalizationTests {
    private static let expectedLocalizationCodes = Set(AppLanguage.allCases.map(\.rawValue))

    @Test("应用 Bundle 声明全部支持语言")
    func bundleDeclaresAllSupportedLanguages() throws {
        let bundle = Bundle(for: AppDelegate.self)
        let expected = Self.expectedLocalizationCodes
        let declaredCodes = try #require(
            bundle.object(forInfoDictionaryKey: "CFBundleLocalizations") as? [String]
        )

        #expect(Set(declaredCodes) == expected)
        #expect(Set(bundle.localizations).isSuperset(of: expected))

        for language in expected {
            let resourcePath = try #require(
                bundle.path(
                    forResource: "InfoPlist",
                    ofType: "strings",
                    inDirectory: nil,
                    forLocalization: language
                )
            )
            let values = try #require(
                NSDictionary(contentsOfFile: resourcePath) as? [String: String]
            )

            #expect(values["CFBundleDisplayName"] == "AI Token Watch")
            #expect(values["CFBundleName"] == "AI Token Watch")
        }
    }
}
```

- [ ] **Step 2: Run the test and confirm the pre-fix failure**

Run outside the sandbox because app-hosted macOS tests require `testmanagerd`:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchTests/BundleLocalizationTests/bundleDeclaresAllSupportedLanguages()' \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test
```

Expected: the test fails at `#require` because the current app Info dictionary has no `CFBundleLocalizations` array.

### Task 2: Add native Bundle localization resources and static Info configuration

**Files:**
- Create: `TokenWatch/Info.plist`
- Create: `TokenWatch/InfoPlist.xcstrings`
- Modify: `TokenWatch.xcodeproj/project.pbxproj:190-197`
- Modify: `TokenWatch.xcodeproj/project.pbxproj:413-417`
- Modify: `TokenWatch.xcodeproj/project.pbxproj:460-464`

- [ ] **Step 1: Create the static application Info dictionary**

Create `TokenWatch/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>AI Token Watch</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>zh-Hans</string>
        <string>zh-Hant</string>
        <string>en</string>
        <string>ja</string>
        <string>ko</string>
        <string>es</string>
        <string>de</string>
        <string>fr</string>
        <string>pt-BR</string>
        <string>it</string>
        <string>nl</string>
        <string>pl</string>
    </array>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
    <key>CFBundleShortVersionString</key>
    <string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key>
    <string>$(CURRENT_PROJECT_VERSION)</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key>
    <string></string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
```

- [ ] **Step 2: Create the Info string catalog**

Create `TokenWatch/InfoPlist.xcstrings` with both Info keys and all 12 translated catalog entries. The product name is a brand and deliberately remains identical in every locale.

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "CFBundleDisplayName" : {
      "comment" : "Bundle display name",
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "nl" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "pl" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } }
      }
    },
    "CFBundleName" : {
      "comment" : "Bundle name",
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "nl" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "pl" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "AI Token Watch" } }
      }
    }
  },
  "version" : "1.0"
}
```

- [ ] **Step 3: Update Xcode project metadata and application build settings**

In the `PBXProject` `knownRegions` list, preserve `en` and `Base`, then add:

```text
"zh-Hans",
"zh-Hant",
ja,
ko,
es,
de,
fr,
"pt-BR",
it,
nl,
pl,
```

For only the app target's Debug and Release `XCBuildConfiguration` blocks, replace these generated-Info settings:

```text
GENERATE_INFOPLIST_FILE = YES;
INFOPLIST_KEY_CFBundleDisplayName = "AI Token Watch";
INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.developer-tools";
INFOPLIST_KEY_NSHumanReadableCopyright = "";
INFOPLIST_KEY_NSPrincipalClass = NSApplication;
```

with:

```text
GENERATE_INFOPLIST_FILE = NO;
INFOPLIST_FILE = TokenWatch/Info.plist;
```

Do not change the corresponding generated-Info settings in `TokenWatchTests` or `TokenWatchUITests` configurations.

### Task 3: Verify the native resources and prevent regressions

**Files:**
- Test: `TokenWatchTests/Localization/BundleLocalizationTests.swift`
- Test: `TokenWatchTests/Localization/AppLanguageSettingsTests.swift`

- [ ] **Step 1: Run the new regression test**

Run outside the sandbox:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchTests/BundleLocalizationTests/bundleDeclaresAllSupportedLanguages()' \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test
```

Expected: `TEST SUCCEEDED` and the test confirms all 12 language codes, all 12 `InfoPlist.strings` files, and both localized Info keys.

- [ ] **Step 2: Build the app and inspect the emitted Bundle**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -configuration Debug \
  -derivedDataPath .build/DerivedData build
```

Then inspect the output:

```bash
plutil -extract CFBundleLocalizations xml1 -o - \
  '.build/DerivedData/Build/Products/Debug/AI Token Watch.app/Contents/Info.plist'
find '.build/DerivedData/Build/Products/Debug/AI Token Watch.app/Contents/Resources' \
  -maxdepth 2 -name InfoPlist.strings -print | sort
```

Expected: the plist extraction prints exactly 12 strings (`zh-Hans`, `zh-Hant`, `en`, `ja`, `ko`, `es`, `de`, `fr`, `pt-BR`, `it`, `nl`, `pl`), and `find` prints one `InfoPlist.strings` path below each matching `.lproj` directory.

- [ ] **Step 3: Run the existing application-language completeness test**

Run outside the sandbox:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchTests/AppLanguageSettingsTests/allStringKeysResolveToNonEmptyText()' \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test
```

Expected: `TEST SUCCEEDED`; the static Bundle configuration does not affect the existing 154-key runtime UI table.

### Task 4: Commit the implementation as one focused change

**Files:**
- Create: `TokenWatch/Info.plist`
- Create: `TokenWatch/InfoPlist.xcstrings`
- Create: `TokenWatchTests/Localization/BundleLocalizationTests.swift`
- Modify: `TokenWatch.xcodeproj/project.pbxproj`

- [ ] **Step 1: Review exactly the intended implementation files**

Run:

```bash
git status --short
git diff --check
git diff -- TokenWatch/Info.plist TokenWatch/InfoPlist.xcstrings \
  TokenWatchTests/Localization/BundleLocalizationTests.swift \
  TokenWatch.xcodeproj/project.pbxproj
```

Expected: no whitespace errors and no staged or unstaged changes to the user's pre-existing scheme, settings-view, or unrelated test modifications.

- [ ] **Step 2: Stage and commit only the implementation files**

Run:

```bash
git add TokenWatch/Info.plist TokenWatch/InfoPlist.xcstrings \
  TokenWatchTests/Localization/BundleLocalizationTests.swift \
  TokenWatch.xcodeproj/project.pbxproj
git diff --cached --check
git commit -m 'fix(i18n): 补齐 Bundle 原生本地化'
```

Expected: one focused commit containing only the native Bundle localization fix and its regression test.
