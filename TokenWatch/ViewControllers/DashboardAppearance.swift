import AppKit

enum DashboardPalette {
    static let appBackground = dynamicColor(light: 0xF4F6FA, dark: 0x0B0F14)
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
    static let navigationSelectedBackground = dynamicColor(light: 0xEAF2FF, dark: 0x182235)
    static let navigationSelectedText = dynamicColor(light: 0x2563EB, dark: 0xFFFFFF)
    static let rangeSelectedBackground = dynamicColor(light: 0x2563EB, dark: 0xF5F7FA)
    static let rangeSelectedText = dynamicColor(light: 0xFFFFFF, dark: 0x0B0F14)
    static let rangeSelectedBorder = dynamicColor(light: 0x2563EB, dark: 0x2B3440)
    static let sessionTableHeaderBackground = dynamicColor(light: 0xF1F5F9, dark: 0x202936)
    static let sessionTableAlternateRowBackground = dynamicColor(light: 0xF8FAFC, dark: 0x111820)
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
