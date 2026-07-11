import Foundation
import ServiceManagement

enum LoginItemSettingsState: Sendable, Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable
}

/// 登录项设置抽象；设置页只消费稳定领域状态，不直接依赖 ServiceManagement。
@MainActor
protocol LoginItemSettingsControlling: AnyObject {
    var state: LoginItemSettingsState { get }

    /// 按当前状态开启或关闭 TokenWatch 登录项。
    func setEnabled(_ enabled: Bool) throws

    /// 打开系统设置的登录项面板，不更改注册状态。
    func openSystemSettings()
}

/// 对 `SMAppService` 的最小测试 seam；生产和测试共享同一动作矩阵。
@MainActor
protocol LoginItemServiceControlling: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemServiceControlling {}

/// 基于 `SMAppService.mainApp` 管理主应用的开机自启动状态。
@MainActor
final class LoginItemSettings: LoginItemSettingsControlling {
    static let shared = LoginItemSettings()

    private let service: any LoginItemServiceControlling
    private let openSystemSettingsAction: @MainActor () -> Void

    init(
        service: any LoginItemServiceControlling = SMAppService.mainApp,
        openSystemSettingsAction: @escaping @MainActor () -> Void = {
            SMAppService.openSystemSettingsLoginItems()
        }
    ) {
        self.service = service
        self.openSystemSettingsAction = openSystemSettingsAction
    }

    var state: LoginItemSettingsState {
        switch service.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        switch (state, enabled) {
        case (.notRegistered, true):
            try service.register()
        case (.enabled, false), (.requiresApproval, false):
            try service.unregister()
        default:
            return
        }
    }

    func openSystemSettings() {
        openSystemSettingsAction()
    }
}
