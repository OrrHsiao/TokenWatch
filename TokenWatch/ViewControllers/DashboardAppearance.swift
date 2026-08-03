import AppKit

/// 保持 macOS 15/Xcode 16.4 可编译时，通过 KVC 设置 macOS 26 玻璃样式的枚举值。
private enum NativeGlassEffectStyle {
    static let regular = 0
    static let clear = 1
}

enum DashboardPalette {
    static let appBackground = dynamicColor(light: 0xF4F6FA, dark: 0x0B0F14)
    static let translucentAppBackground = dynamicColor(
        light: 0xF4F6FA,
        dark: 0x0B0F14,
        lightAlpha: 0.1,
        darkAlpha: 0.1
    )
    static let sidebarBackground = dynamicColor(light: 0xFFFFFF, dark: 0x05070A)
    static let panelBackground = dynamicColor(light: 0xFFFFFF, dark: 0x151B23)
    static let deepPanelBackground = dynamicColor(light: 0xFFFFFF, dark: 0x05070A)
    static let scanCardBackground = dynamicColor(light: 0xF8FAFC, dark: 0x0D1117)
    static let border = dynamicColor(light: 0xD8DEE8, dark: 0x2B3440)
    static let subtleBorder = dynamicColor(light: 0xE5E7EB, dark: 0x223041)
    static let primaryText = dynamicColor(light: 0x111827, dark: 0xF5F7FA)
    static let secondaryText = dynamicColor(light: 0x6B7280, dark: 0x9CA3AF)
    static let mutedText = dynamicColor(light: 0x94A3B8, dark: 0x6B7280)
    static let accent = dynamicColor(light: 0x2563EB, dark: 0x5AA2FF)
    static let green = dynamicColor(light: 0x16A34A, dark: 0x5FE3A1)
    static let costLine = dynamicColor(light: 0x16A34A, dark: 0x39D353)
    static let statusInactive = dynamicColor(light: 0xDC2626, dark: 0x4B5563)
    static let yellow = dynamicColor(light: 0xF59E0B, dark: 0xF5C451)
    static let purple = dynamicColor(light: 0x8B5CF6, dark: 0xA78BFA)
    static let glassControlBorder = dynamicColor(
        light: 0x64748B,
        dark: 0xFFFFFF,
        lightAlpha: 0.32,
        darkAlpha: 0.28
    )
    static let glassDivider = dynamicColor(
        light: 0x94A3B8,
        dark: 0xFFFFFF,
        lightAlpha: 0.28,
        darkAlpha: 0.16
    )
    static let navigationSelectedBackground = dynamicColor(
        light: 0x2563EB,
        dark: 0x5AA2FF,
        lightAlpha: 0.16,
        darkAlpha: 0.24
    )
    static let navigationSelectedText = dynamicColor(light: 0x2563EB, dark: 0xF5F7FA)
    static let rangeSelectedBackground = dynamicColor(
        light: 0x2563EB,
        dark: 0x5AA2FF,
        lightAlpha: 0.58,
        darkAlpha: 0.32
    )
    static let rangeSelectedText = dynamicColor(light: 0x1E3A8A, dark: 0xF5F7FA)
    static let rangeSelectedBorder = dynamicColor(
        light: 0x2563EB,
        dark: 0x5AA2FF,
        lightAlpha: 0.62,
        darkAlpha: 0.5
    )
    static let sessionTableHeaderBackground = dynamicColor(
        light: 0x2563EB,
        dark: 0xFFFFFF,
        lightAlpha: 0.10,
        darkAlpha: 0.14
    )
    static let sessionTableAlternateRowBackground = dynamicColor(
        light: 0xFFFFFF,
        dark: 0xFFFFFF,
        lightAlpha: 0.28,
        darkAlpha: 0.08
    )
    static let sessionDateBackground = dynamicColor(light: 0xFFFFFF, dark: 0x111827)
    static let sessionDateBorder = dynamicColor(light: 0xD8DEE8, dark: 0x263244)
    static let sessionDateIcon = dynamicColor(light: 0x64748B, dark: 0x9CA3AF)
    static let chartBlue = dynamicColor(light: 0x5AA2FF, dark: 0x5AA2FF)
    static let chartGreen = dynamicColor(light: 0x4ADE80, dark: 0x4ADE80)
    static let chartAmber = dynamicColor(light: 0xFBBF24, dark: 0xFBBF24)
    static let chartCyan = dynamicColor(light: 0x36C6D9, dark: 0x36C6D9)
    static let chartRed = dynamicColor(light: 0xF87171, dark: 0xF87171)
    static let chartPurple = dynamicColor(light: 0xA78BFA, dark: 0xA78BFA)

    private static func dynamicColor(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }

    private static func dynamicColor(
        light: Int,
        dark: Int,
        lightAlpha: CGFloat,
        darkAlpha: CGFloat
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light).withAlphaComponent(isDark ? darkAlpha : lightAlpha)
        }
    }
}

enum DashboardLayerColor {
    @MainActor
    static func cgColor(_ color: NSColor, for view: NSView) -> CGColor {
        guard usesEffectiveAppearance(for: view) else {
            return color.cgColor
        }

        var resolvedColor = color.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolvedColor = color.cgColor
        }
        return resolvedColor
    }

    @MainActor
    static func applyBackground(_ color: NSColor, to view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = cgColor(color, for: view)
    }

    @MainActor
    static func nsColor(_ color: NSColor, for view: NSView) -> NSColor {
        guard usesEffectiveAppearance(for: view) else {
            return color
        }

        var resolvedColor = color
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolvedColor = color.usingColorSpace(.sRGB) ?? color
        }
        return resolvedColor
    }

    @MainActor
    private static func usesEffectiveAppearance(for view: NSView) -> Bool {
        if view.window != nil {
            return true
        }

        var currentView: NSView? = view
        while let view = currentView {
            if view.appearance != nil {
                return true
            }
            currentView = view.superview
        }
        return false
    }
}

@MainActor
protocol DashboardAppearanceRefreshable: AnyObject {
    func refreshDashboardAppearance()
}

final class DashboardBackgroundView: NSView, DashboardAppearanceRefreshable {
    private let backgroundColor: NSColor
    private let allowsFirstResponder: Bool

    init(
        frame frameRect: NSRect = .zero,
        backgroundColor: NSColor,
        acceptsFirstResponder: Bool = false
    ) {
        self.backgroundColor = backgroundColor
        self.allowsFirstResponder = acceptsFirstResponder
        super.init(frame: frameRect)
        wantsLayer = true
        updateLayerColors()
    }

    required init?(coder: NSCoder) {
        fatalError("DashboardBackgroundView 必须用 init(frame:backgroundColor:) 构造")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshDashboardAppearance()
    }

    override var acceptsFirstResponder: Bool {
        allowsFirstResponder
    }

    func refreshDashboardAppearance() {
        updateLayerColors()
    }

    private func updateLayerColors() {
        layer?.backgroundColor = DashboardLayerColor.cgColor(backgroundColor, for: self)
    }
}

/// 主窗口的大面积背景，在 macOS 26 使用原生 Liquid Glass，并为旧系统保留系统材质回退。
final class DashboardGlassBackgroundView: NSView {
    private let allowsFirstResponder: Bool
    private let contentContainer = NSView()
    private var usesNativeLiquidGlass = false

    var debugUsesNativeLiquidGlass: Bool { usesNativeLiquidGlass }

    init(
        frame frameRect: NSRect = .zero,
        acceptsFirstResponder: Bool = false
    ) {
        self.allowsFirstResponder = acceptsFirstResponder
        super.init(frame: frameRect)
        installGlassEffect()
    }

    required init?(coder: NSCoder) {
        fatalError("DashboardGlassBackgroundView 必须用 init(frame:material:) 构造")
    }

    override var acceptsFirstResponder: Bool {
        allowsFirstResponder
    }

    /// 将界面内容放入玻璃容器，确保 AppKit 按原生玻璃层级绘制。
    func addContentSubview(_ view: NSView) {
        contentContainer.addSubview(view)
    }

    private func installGlassEffect() {
        if #available(macOS 26.0, *), let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glassView = glassClass.init(frame: .zero)
            glassView.setValue(NativeGlassEffectStyle.clear, forKey: "style")
            glassView.setValue(CGFloat(0), forKey: "cornerRadius")
            glassView.translatesAutoresizingMaskIntoConstraints = false
            glassView.setValue(contentContainer, forKey: "contentView")
            addSubview(glassView)
            NSLayoutConstraint.activate([
                glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
                glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
                glassView.topAnchor.constraint(equalTo: topAnchor),
                glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            usesNativeLiquidGlass = true
            return
        }

        let fallbackView = NSVisualEffectView()
        fallbackView.material = .underWindowBackground
        fallbackView.blendingMode = .behindWindow
        fallbackView.state = .active
        fallbackView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fallbackView)
        fallbackView.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            fallbackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fallbackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fallbackView.topAnchor.constraint(equalTo: topAnchor),
            fallbackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: fallbackView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: fallbackView.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: fallbackView.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: fallbackView.bottomAnchor),
        ])
    }
}

/// 主要信息卡在 macOS 26 使用常规 Liquid Glass，既保留背景透视也维持文字可读性。
class DashboardGlassCardView: NSView {
    private let contentContainer = NSView()
    private var nativeGlassView: NSView?
    private var usesNativeLiquidGlass = false
    private var usesClearGlassStyle = false

    var debugUsesNativeLiquidGlass: Bool { usesNativeLiquidGlass }
    var debugUsesClearGlassStyle: Bool { usesClearGlassStyle }

    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        installGlassEffect(cornerRadius: cornerRadius)
    }

    required init?(coder: NSCoder) {
        fatalError("DashboardGlassCardView 必须用 init(cornerRadius:) 构造")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateNativeGlassStyle()
    }

    /// 将内容放入系统玻璃的 contentView，避免覆盖原生折射与边缘高光。
    func addContentSubview(_ view: NSView) {
        contentContainer.addSubview(view)
    }

    private func installGlassEffect(cornerRadius: CGFloat) {
        if #available(macOS 26.0, *), let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glassView = glassClass.init(frame: .zero)
            glassView.setValue(cornerRadius, forKey: "cornerRadius")
            glassView.translatesAutoresizingMaskIntoConstraints = false
            glassView.setValue(contentContainer, forKey: "contentView")
            contentContainer.translatesAutoresizingMaskIntoConstraints = false
            addSubview(glassView)
            NSLayoutConstraint.activate([
                glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
                glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
                glassView.topAnchor.constraint(equalTo: topAnchor),
                glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
                contentContainer.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
                contentContainer.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
                contentContainer.topAnchor.constraint(equalTo: glassView.topAnchor),
                contentContainer.bottomAnchor.constraint(equalTo: glassView.bottomAnchor),
            ])
            nativeGlassView = glassView
            updateNativeGlassStyle()
            usesNativeLiquidGlass = true
            return
        }

        let fallbackView = NSVisualEffectView()
        fallbackView.material = .contentBackground
        fallbackView.blendingMode = .withinWindow
        fallbackView.state = .active
        fallbackView.wantsLayer = true
        fallbackView.layer?.cornerRadius = cornerRadius
        fallbackView.layer?.masksToBounds = true
        fallbackView.layer?.borderWidth = 1
        fallbackView.layer?.borderColor = DashboardLayerColor.cgColor(DashboardPalette.glassControlBorder, for: self)
        fallbackView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fallbackView)
        fallbackView.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            fallbackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fallbackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fallbackView.topAnchor.constraint(equalTo: topAnchor),
            fallbackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: fallbackView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: fallbackView.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: fallbackView.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: fallbackView.bottomAnchor),
        ])
    }

    /// 浅色环境让内容卡使用透明玻璃，避免系统常规材质叠加成厚重白卡；暗色继续使用常规玻璃维持对比度。
    private func updateNativeGlassStyle() {
        guard #available(macOS 26.0, *), let nativeGlassView = nativeGlassView else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        nativeGlassView.setValue(
            isDark ? NativeGlassEffectStyle.regular : NativeGlassEffectStyle.clear,
            forKey: "style"
        )
        usesClearGlassStyle = !isDark
    }
}

@MainActor
enum DashboardAppearanceRefresh {
    static func refresh(in view: NSView) {
        (view as? DashboardAppearanceRefreshable)?.refreshDashboardAppearance()
        view.subviews.forEach(refresh)
    }
}

@MainActor
enum AppLogoImage {
    static let identifier = "AppLogo"

    static func make() -> NSImage? {
        guard let source = NSImage(named: NSImage.Name("AppIcon")) ?? NSApp.applicationIconImage else {
            return nil
        }
        guard let image = source.copy() as? NSImage else { return nil }
        image.isTemplate = false
        return image
    }
}

enum DashboardColors {
    static let palette = [
        DashboardPalette.chartBlue,
        DashboardPalette.chartGreen,
        DashboardPalette.chartAmber,
        DashboardPalette.chartCyan,
        DashboardPalette.chartRed,
        DashboardPalette.chartPurple,
    ]

    static func modelColor(at index: Int) -> NSColor {
        palette[index % palette.count]
    }
}

class DashboardRoundedView: NSView, DashboardAppearanceRefreshable {
    private let backgroundColor: NSColor
    private let borderColor: NSColor?

    init(
        backgroundColor: NSColor,
        cornerRadius: CGFloat,
        borderColor: NSColor? = nil,
        borderWidth: CGFloat = 0
    ) {
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = borderWidth
        updateLayerColors()
    }

    required init?(coder: NSCoder) {
        fatalError("DashboardRoundedView 必须用 init(backgroundColor:cornerRadius:) 构造")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshDashboardAppearance()
    }

    func refreshDashboardAppearance() {
        updateLayerColors()
    }

    private func updateLayerColors() {
        layer?.backgroundColor = DashboardLayerColor.cgColor(backgroundColor, for: self)
        layer?.borderColor = borderColor.map { DashboardLayerColor.cgColor($0, for: self) }
    }
}

final class DashboardDotView: NSView, DashboardAppearanceRefreshable {
    private let color: NSColor

    init(color: NSColor, accessibilityIdentifier: String? = nil, accessibilityValue: String? = nil) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        updateLayerColors()
        if let accessibilityIdentifier {
            setAccessibilityIdentifier(accessibilityIdentifier)
        }
        if let accessibilityValue {
            setAccessibilityValue(accessibilityValue)
        }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 8),
            heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("DashboardDotView 必须用 init(color:) 构造")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshDashboardAppearance()
    }

    func refreshDashboardAppearance() {
        updateLayerColors()
    }

    private func updateLayerColors() {
        layer?.backgroundColor = DashboardLayerColor.cgColor(color, for: self)
    }
}

private extension NSColor {
    convenience init(hex: Int) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
