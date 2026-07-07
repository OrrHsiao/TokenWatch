import AppKit

/// 构建 AI Token Watch 的精简主菜单,只暴露当前应用实际支持的命令。
@MainActor
enum AppMainMenuBuilder {
    private static let appName = "AI Token Watch"

    /// 创建主菜单。调用方负责把返回值安装到 `NSApp.mainMenu`。
    static func build(actionTarget: AppDelegate, language: AppLanguage = .en) -> NSMenu {
        let mainMenu = NSMenu(title: "Main Menu")
        mainMenu.addItem(makeApplicationMenuItem(actionTarget: actionTarget, language: language))
        mainMenu.addItem(makeWindowMenuItem(language: language))
        return mainMenu
    }

    private static func makeApplicationMenuItem(actionTarget: AppDelegate, language: AppLanguage) -> NSMenuItem {
        let appMenu = NSMenu(title: appName)
        appMenu.addItem(makeApplicationItem(
            title: text(.mainMenuAbout, language: language),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            target: NSApp
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(makeApplicationItem(
            title: text(.statusMenuOpen, language: language),
            action: #selector(AppDelegate.openMainWindow(_:)),
            keyEquivalent: "0",
            target: actionTarget
        ))
        appMenu.addItem(makeApplicationItem(
            title: text(.mainMenuSettings, language: language),
            action: #selector(AppDelegate.showSettings(_:)),
            keyEquivalent: ",",
            target: actionTarget
        ))
        appMenu.addItem(makeApplicationItem(
            title: text(.refreshNow, language: language),
            action: #selector(AppDelegate.refreshNow(_:)),
            keyEquivalent: "r",
            target: actionTarget
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(makeApplicationItem(
            title: text(.mainMenuHide, language: language),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h",
            target: NSApp
        ))
        appMenu.addItem(makeApplicationItem(
            title: text(.mainMenuHideOthers, language: language),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
            modifierMask: [.command, .option],
            target: NSApp
        ))
        appMenu.addItem(makeApplicationItem(
            title: text(.mainMenuShowAll, language: language),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            target: NSApp
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(makeApplicationItem(
            title: text(.statusMenuQuit, language: language),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q",
            target: NSApp
        ))

        let item = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        item.submenu = appMenu
        return item
    }

    private static func makeWindowMenuItem(language: AppLanguage) -> NSMenuItem {
        let windowMenuTitle = text(.mainMenuWindow, language: language)
        let windowMenu = NSMenu(title: windowMenuTitle)
        windowMenu.addItem(makeApplicationItem(
            title: text(.mainMenuMinimize, language: language),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))
        windowMenu.addItem(makeApplicationItem(
            title: text(.mainMenuZoom, language: language),
            action: #selector(NSWindow.performZoom(_:))
        ))
        windowMenu.addItem(.separator())
        windowMenu.addItem(makeApplicationItem(
            title: text(.mainMenuBringAllToFront, language: language),
            action: #selector(NSApplication.arrangeInFront(_:)),
            target: NSApp
        ))

        let item = NSMenuItem(title: windowMenuTitle, action: nil, keyEquivalent: "")
        item.submenu = windowMenu
        return item
    }

    private static func text(_ key: AppStringKey, language: AppLanguage) -> String {
        AppStrings.text(key, language: language)
    }

    private static func makeApplicationItem(
        title: String,
        action: Selector?,
        keyEquivalent: String = "",
        modifierMask: NSEvent.ModifierFlags = .command,
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = keyEquivalent.isEmpty ? [] : modifierMask
        item.target = target
        return item
    }
}

/// 安装并维护主菜单,让菜单文案跟随应用语言设置变化。
@MainActor
final class AppMainMenuController {
    private let actionTarget: AppDelegate
    private let languageSettings: AppLanguageSettings
    private var languageSettingsObserverToken: AppLanguageSettings.ObservationToken?

    init(actionTarget: AppDelegate, languageSettings: AppLanguageSettings = .shared) {
        self.actionTarget = actionTarget
        self.languageSettings = languageSettings
    }

    /// 安装主菜单并开始监听语言设置变化。
    func start() {
        installMainMenu()
        guard languageSettingsObserverToken == nil else { return }
        languageSettingsObserverToken = languageSettings.observe { [weak self] in
            self?.installMainMenu()
        }
    }

    /// 停止监听语言设置变化。
    func stop() {
        if let token = languageSettingsObserverToken {
            languageSettings.removeObserver(token)
            languageSettingsObserverToken = nil
        }
    }

    private func installMainMenu() {
        let mainMenu = AppMainMenuBuilder.build(
            actionTarget: actionTarget,
            language: languageSettings.resolvedLanguage
        )
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = mainMenu.items.last?.submenu
    }
}
