import ServiceManagement
import Testing
@testable import TokenWatch

@MainActor
@Suite("LoginItemSettings")
struct LoginItemSettingsTests {
    @Test func mapsEveryServiceManagementStatus() {
        let cases: [(SMAppService.Status, LoginItemSettingsState)] = [
            (.notRegistered, .notRegistered),
            (.enabled, .enabled),
            (.requiresApproval, .requiresApproval),
            (.notFound, .unavailable),
        ]

        for item in cases {
            let service = FakeLoginItemService(status: item.0)
            let settings = LoginItemSettings(service: service)
            #expect(settings.state == item.1)
        }
    }

    @Test func registerAndUnregisterFollowTheFourStateMatrix() throws {
        let notRegistered = FakeLoginItemService(status: .notRegistered)
        let notRegisteredSettings = LoginItemSettings(service: notRegistered)
        try notRegisteredSettings.setEnabled(true)
        try notRegisteredSettings.setEnabled(false)
        #expect(notRegistered.registerCallCount == 1)
        #expect(notRegistered.unregisterCallCount == 0)

        let enabled = FakeLoginItemService(status: .enabled)
        let enabledSettings = LoginItemSettings(service: enabled)
        try enabledSettings.setEnabled(true)
        try enabledSettings.setEnabled(false)
        #expect(enabled.registerCallCount == 0)
        #expect(enabled.unregisterCallCount == 1)

        let requiresApproval = FakeLoginItemService(status: .requiresApproval)
        let requiresApprovalSettings = LoginItemSettings(service: requiresApproval)
        try requiresApprovalSettings.setEnabled(true)
        try requiresApprovalSettings.setEnabled(false)
        #expect(requiresApproval.registerCallCount == 0)
        #expect(requiresApproval.unregisterCallCount == 1)

        let unavailable = FakeLoginItemService(status: .notFound)
        let unavailableSettings = LoginItemSettings(service: unavailable)
        try unavailableSettings.setEnabled(true)
        try unavailableSettings.setEnabled(false)
        #expect(unavailable.registerCallCount == 0)
        #expect(unavailable.unregisterCallCount == 0)
    }

    @Test func opensSystemSettingsThroughAnIndependentAction() {
        let service = FakeLoginItemService(status: .requiresApproval)
        var openCallCount = 0
        let settings = LoginItemSettings(
            service: service,
            openSystemSettingsAction: { openCallCount += 1 }
        )

        settings.openSystemSettings()

        #expect(openCallCount == 1)
        #expect(service.registerCallCount == 0)
        #expect(service.unregisterCallCount == 0)
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemServiceControlling {
    let status: SMAppService.Status
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
    }

    func unregister() throws {
        unregisterCallCount += 1
    }
}
