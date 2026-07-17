import Foundation
import Testing
@testable import TokenWatch

@MainActor
@Suite("InitialDirectoryAuthorizationGuide")
struct InitialDirectoryAuthorizationGuideTests {
    @Test("首次且所有数据源均未授权时展示引导")
    func freshInstallationWithoutBookmarksShowsGuide() {
        withTemporaryGuideDefaults { defaults in
            let guide = makeGuide(defaults: defaults, authorizedKeys: [])

            #expect(guide.shouldPresent())
        }
    }

    @Test("任一数据源已有授权时不展示首次引导")
    func existingBookmarkSuppressesGuide() {
        withTemporaryGuideDefaults { defaults in
            let guide = makeGuide(
                defaults: defaults,
                authorizedKeys: ["CodexDataDirectoryBookmark"]
            )

            #expect(!guide.shouldPresent())
        }
    }

    @Test("展示记录会让稍后和重启后均不再重复提示")
    func markingGuideAsPresentedSuppressesFuturePrompts() {
        withTemporaryGuideDefaults { defaults in
            let guide = makeGuide(defaults: defaults, authorizedKeys: [])
            #expect(guide.shouldPresent())

            guide.markPresented()

            #expect(defaults.bool(forKey: InitialDirectoryAuthorizationGuide.storageKey))
            #expect(!guide.shouldPresent())
        }
    }

    @Test("没有数据源时不展示引导")
    func noProvidersDoesNotShowGuide() {
        withTemporaryGuideDefaults { defaults in
            let guide = InitialDirectoryAuthorizationGuide(
                defaults: defaults,
                bookmarkKeys: [],
                hasBookmark: { _ in false },
                isDebugPresentationForced: { true }
            )

            #expect(!guide.shouldPresent())
        }
    }

    @Test("调试强制参数可在保留授权状态时验证引导")
    func debugForcePresentationOverridesExistingState() {
        withTemporaryGuideDefaults { defaults in
            defaults.set(true, forKey: InitialDirectoryAuthorizationGuide.storageKey)
            let persistedGuide = makeGuide(
                defaults: defaults,
                authorizedKeys: ["CodexDataDirectoryBookmark"],
                isDebugPresentationForced: { true }
            )

            #expect(persistedGuide.shouldPresent())

            defaults.removeObject(forKey: InitialDirectoryAuthorizationGuide.storageKey)
            let unpersistedGuide = makeGuide(
                defaults: defaults,
                authorizedKeys: ["CodexDataDirectoryBookmark"],
                isDebugPresentationForced: { true }
            )
            unpersistedGuide.markPresented()
            #expect(!defaults.bool(forKey: InitialDirectoryAuthorizationGuide.storageKey))
        }
    }

    @Test("自动化环境可跳过首次引导")
    func automationCanSuppressInitialGuide() {
        withTemporaryGuideDefaults { defaults in
            let guide = makeGuide(
                defaults: defaults,
                authorizedKeys: [],
                isPresentationSuppressedForAutomation: { true }
            )

            #expect(!guide.shouldPresent())
        }
    }

    @Test("调试强制展示优先于自动化跳过")
    func debugForcePresentationOverridesAutomationSuppression() {
        withTemporaryGuideDefaults { defaults in
            let guide = makeGuide(
                defaults: defaults,
                authorizedKeys: [],
                isDebugPresentationForced: { true },
                isPresentationSuppressedForAutomation: { true }
            )

            #expect(guide.shouldPresent())
        }
    }

    private func makeGuide(
        defaults: UserDefaults,
        authorizedKeys: Set<String>,
        isDebugPresentationForced: @escaping () -> Bool = { false },
        isPresentationSuppressedForAutomation: @escaping () -> Bool = { false }
    ) -> InitialDirectoryAuthorizationGuide {
        InitialDirectoryAuthorizationGuide(
            defaults: defaults,
            bookmarkKeys: [
                "ClaudeDataDirectoryBookmark",
                "CodexDataDirectoryBookmark",
                "OpenCodeDataDirectoryBookmark",
            ],
            hasBookmark: { authorizedKeys.contains($0) },
            isDebugPresentationForced: isDebugPresentationForced,
            isPresentationSuppressedForAutomation: isPresentationSuppressedForAutomation
        )
    }
}

private func withTemporaryGuideDefaults(_ body: (UserDefaults) -> Void) {
    let suiteName = "InitialDirectoryAuthorizationGuideTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    body(defaults)
}
