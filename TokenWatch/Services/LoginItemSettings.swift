import Foundation
import ServiceManagement

/// 登录项设置抽象,便于设置页测试时注入 fake,避免测试改动真实系统登录项。
@MainActor
protocol LoginItemSettingsControlling: AnyObject {
    var isEnabled: Bool { get }

    /// 开启或关闭 TokenWatch 的系统登录项注册。
    func setEnabled(_ enabled: Bool) throws
}

/// 基于 `SMAppService.mainApp` 管理主应用的开机自启动状态。
@MainActor
final class LoginItemSettings: LoginItemSettingsControlling {
    static let shared = LoginItemSettings()

    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var isEnabled: Bool {
        service.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard !isEnabled else { return }
            try service.register()
        } else {
            guard isEnabled else { return }
            try service.unregister()
        }
    }
}
