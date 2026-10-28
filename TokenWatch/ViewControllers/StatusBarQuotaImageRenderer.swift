import AppKit

/// 状态栏中单个额度窗口：圆环 + 圈内图标与周期 + 右侧剩余百分比（仅详细模式）。
struct StatusBarQuotaRing: Equatable {
    let shortLabel: String
    /// 0...1 的剩余比例；nil 表示没有可展示的值，绘制虚线灰环。
    let remainingFraction: Double?
    let valueText: String
    let severity: SubscriptionQuotaSeverity
    /// 详细模式在圆环右侧绘制剩余百分比；简洁模式只绘制圆环。
    let showsValue: Bool
}

/// 同一个 Agent 的相邻窗口。
struct StatusBarQuotaGroup: Equatable {
    let provider: SubscriptionQuotaProvider
    let rings: [StatusBarQuotaRing]
    /// 旧记录整体弱化。
    let isDimmed: Bool
}

/// 状态栏额度图像的完整输入；Equatable 用于跳过无变化的重绘与重新布局。
struct StatusBarQuotaModel: Equatable {
    let groups: [StatusBarQuotaGroup]
    let ringDiameter: CGFloat

    /// 按固定的 Claude、Codex 与 5H、7D 顺序，依设置页中每个周期的展示配置生成状态栏模型。
    /// - Parameters:
    ///   - presentations: 两个 Agent 的展示模型。
    ///   - configuration: 某个 Agent 某个周期是否展示及简洁 / 详细样式。
    ///   - ringDiameter: 圆环直径。
    /// - Returns: 只包含需展示周期的模型；某个 Agent 的周期全部关闭时整组省略。
    static func make(
        presentations: [SubscriptionQuotaProviderPresentation],
        configuration: (SubscriptionQuotaProvider, SubscriptionQuotaWindowKind) -> StatusBarQuotaWindowConfiguration,
        ringDiameter: CGFloat
    ) -> StatusBarQuotaModel {
        let groups = presentations.compactMap { presentation -> StatusBarQuotaGroup? in
            let rings = SubscriptionQuotaWindowKind.allCases.compactMap { kind -> StatusBarQuotaRing? in
                let windowConfiguration = configuration(presentation.provider, kind)
                guard windowConfiguration.isVisible,
                      let window = presentation.windows.first(where: { $0.kind == kind }) else {
                    return nil
                }
                return StatusBarQuotaRing(
                    shortLabel: window.shortLabel,
                    remainingFraction: window.remainingPercent.map { $0 / 100 },
                    valueText: window.valueText,
                    severity: window.severity,
                    showsValue: windowConfiguration.style.showsValue
                )
            }
            guard !rings.isEmpty else { return nil }
            return StatusBarQuotaGroup(
                provider: presentation.provider,
                rings: rings,
                isDimmed: presentation.isStale
            )
        }
        return StatusBarQuotaModel(groups: groups, ringDiameter: ringDiameter)
    }
}

/// 状态栏额度布局参数。
enum StatusBarQuotaLayout {
    static let defaultRingDiameter: CGFloat = 22
    static let minimumRingDiameter: CGFloat = 20
    static let ringLineWidth: CGFloat = 1.75
    /// 图标与圆弧之间保留约 2pt 间隙（22pt 圆环内图标约 14pt）。
    static let iconDiameterRatio: CGFloat = 0.64
    static let periodFontSize: CGFloat = 6.5
    /// 周期字形外沿描边宽度（pt）。
    static let periodOutlineWidth: CGFloat = 0.6
    static let valueFontSize: CGFloat = 11
    static let ringToValueSpacing: CGFloat = 3
    static let windowSpacing: CGFloat = 6
    static let providerSpacing: CGFloat = 14
    /// 组合模式中今日 token 文本与第一个额度圆环之间的间距。
    static let todayTokensToQuotaSpacing: CGFloat = 14
    static let dimmedAlpha: CGFloat = 0.55
    /// 虚线灰环的线段与间隔。
    static let unknownTrackDash: [CGFloat] = [2, 2]

    /// 圆环直径跟随系统状态栏高度，在 20–22pt 候选范围内取值，并为上下留出 1pt。
    static func ringDiameter(forStatusBarThickness thickness: CGFloat) -> CGFloat {
        min(defaultRingDiameter, max(minimumRingDiameter, thickness - 2))
    }

    static var valueFont: NSFont {
        .monospacedDigitSystemFont(ofSize: valueFontSize, weight: .regular)
    }

    static var periodFont: NSFont {
        .systemFont(ofSize: periodFontSize, weight: .bold)
    }

    /// 百分比槽位按 `100%` 预留，数值变化时状态栏宽度保持不变。
    static var valueSlotWidth: CGFloat {
        let font = valueFont
        return ["100%", "<1%", "—"]
            .map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }
            .max() ?? 0
    }

    /// 单个窗口占用的宽度：简洁模式只有圆环，详细模式追加固定宽度的百分比槽位。
    static func ringWidth(for ring: StatusBarQuotaRing, diameter: CGFloat) -> CGFloat {
        ring.showsValue ? diameter + ringToValueSpacing + valueSlotWidth : diameter
    }

    /// 图像尺寸只取决于分组、窗口、简洁 / 详细样式与圆环直径，与具体数值无关。
    static func imageSize(for model: StatusBarQuotaModel) -> NSSize {
        var width: CGFloat = 0
        for (groupIndex, group) in model.groups.enumerated() {
            if groupIndex > 0 {
                width += providerSpacing
            }
            width += group.rings.reduce(0) { $0 + ringWidth(for: $1, diameter: model.ringDiameter) }
            width += CGFloat(max(0, group.rings.count - 1)) * windowSpacing
        }
        return NSSize(width: ceil(width), height: model.ringDiameter)
    }
}

/// 将额度模型绘制为单张状态栏图像。
///
/// 继续交给原生 `NSStatusBarButton` 以 image-only 方式绘制，不添加自定义子视图，
/// 避免进入状态栏场景的持续布局失效。颜色在绘制时按按钮当前外观解析，
/// 因此图标、正常圆弧与数字始终使用系统单色，只有低额度圆弧使用强调色。
enum StatusBarQuotaImageRenderer {
    static let claudeIconName = "AgentClaude"
    static let codexIconName = "AgentCodex"

    /// 生成状态栏额度图像。
    /// - Parameter model: 分组、窗口与圆环直径。
    /// - Returns: 非 template 图像；尺寸只由窗口与简洁 / 详细样式决定，绘制时才解析外观颜色。
    static func makeImage(for model: StatusBarQuotaModel) -> NSImage {
        let size = StatusBarQuotaLayout.imageSize(for: model)
        let icons = agentIcons()

        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(model: model, icons: icons, height: size.height, in: context)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// 生成“今日 Tokens + 额度”组合图像：原有仪表盘图标与今日 token 文本在前，额度圆环在后。
    ///
    /// NSStatusBarButton 只能把 image 放在 title 一侧，无法让圆环排在原生标题之后，
    /// 因此组合模式把三部分绘制进同一张图；文本沿用原有标题的字体、字号与双行排布。
    /// - Parameters:
    ///   - model: 额度圆环模型。
    ///   - leadingSymbol: 原有今日 token 档位图标（template）。
    ///   - leadingTitle: 今日 token 双行文本，不含状态栏 cell 专用的 baseline 偏移。
    /// - Returns: 非 template 图像；图标与文本按绘制时外观着色。
    static func makeImage(
        for model: StatusBarQuotaModel,
        leadingSymbol: NSImage,
        leadingTitle: NSAttributedString
    ) -> NSImage {
        let quotaSize = StatusBarQuotaLayout.imageSize(for: model)
        let symbolSize = leadingSymbol.size
        let titleBounds = leadingTitle.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        )
        let titleSize = NSSize(width: ceil(titleBounds.width), height: ceil(titleBounds.height))
        let height = max(quotaSize.height, symbolSize.height, titleSize.height)
        let titleOriginX = symbolSize.width + StatusBarIconLayout.imageTitleSpacing
        let quotaOriginX = titleOriginX + titleSize.width + StatusBarQuotaLayout.todayTokensToQuotaSpacing
        let size = NSSize(width: ceil(quotaOriginX + quotaSize.width), height: height)
        let icons = agentIcons()

        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let symbolRect = NSRect(
                x: 0,
                y: (height - symbolSize.height) / 2,
                width: symbolSize.width,
                height: symbolSize.height
            )
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            leadingSymbol.draw(in: symbolRect)
            context.setBlendMode(.sourceIn)
            context.setFillColor(NSColor.labelColor.cgColor)
            context.fill(symbolRect)
            context.endTransparencyLayer()

            leadingTitle.draw(
                with: NSRect(
                    x: titleOriginX,
                    y: (height - titleSize.height) / 2,
                    width: titleSize.width,
                    height: titleSize.height
                ),
                options: [.usesLineFragmentOrigin]
            )

            context.saveGState()
            context.translateBy(x: quotaOriginX, y: 0)
            draw(model: model, icons: icons, height: height, in: context)
            context.restoreGState()
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func agentIcons() -> [SubscriptionQuotaProvider: NSImage] {
        [
            .claude: NSImage(named: claudeIconName),
            .codex: NSImage(named: codexIconName),
        ].compactMapValues { $0 }
    }

    private static func draw(
        model: StatusBarQuotaModel,
        icons: [SubscriptionQuotaProvider: NSImage],
        height: CGFloat,
        in context: CGContext
    ) {
        let diameter = model.ringDiameter
        let slotWidth = StatusBarQuotaLayout.valueSlotWidth
        var x: CGFloat = 0
        for (groupIndex, group) in model.groups.enumerated() {
            if groupIndex > 0 {
                x += StatusBarQuotaLayout.providerSpacing
            }
            context.saveGState()
            if group.isDimmed {
                context.setAlpha(StatusBarQuotaLayout.dimmedAlpha)
            }
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            for (ringIndex, ring) in group.rings.enumerated() {
                if ringIndex > 0 {
                    x += StatusBarQuotaLayout.windowSpacing
                }
                let ringRect = NSRect(x: x, y: (height - diameter) / 2, width: diameter, height: diameter)
                drawRing(ring, icon: icons[group.provider], in: ringRect, context: context)
                x += diameter
                guard ring.showsValue else { continue }
                x += StatusBarQuotaLayout.ringToValueSpacing
                drawValue(
                    ring.valueText,
                    in: NSRect(x: x, y: 0, width: slotWidth, height: height)
                )
                x += slotWidth
            }
            context.endTransparencyLayer()
            context.restoreGState()
        }
    }

    private static func drawRing(
        _ ring: StatusBarQuotaRing,
        icon: NSImage?,
        in rect: NSRect,
        context: CGContext
    ) {
        let lineWidth = StatusBarQuotaLayout.ringLineWidth
        let labelColor = NSColor.labelColor

        let track = NSBezierPath(ovalIn: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        track.lineWidth = lineWidth
        if ring.remainingFraction == nil {
            let dash = StatusBarQuotaLayout.unknownTrackDash
            track.setLineDash(dash, count: dash.count, phase: 0)
            labelColor.withAlphaComponent(0.45).setStroke()
        } else {
            labelColor.withAlphaComponent(0.22).setStroke()
        }
        track.stroke()

        if let fraction = ring.remainingFraction, fraction > 0 {
            // 12 点方向起顺时针填充剩余额度。
            let clampedFraction = min(fraction, 1)
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: NSPoint(x: rect.midX, y: rect.midY),
                radius: (rect.width - lineWidth) / 2,
                startAngle: 90,
                endAngle: 90 - 360 * clampedFraction,
                clockwise: true
            )
            arc.lineWidth = lineWidth
            arc.lineCapStyle = clampedFraction >= 1 ? .butt : .round
            arcColor(for: ring.severity).setStroke()
            arc.stroke()
        }

        let iconSide = rect.width * StatusBarQuotaLayout.iconDiameterRatio
        let iconRect = NSRect(
            x: rect.midX - iconSide / 2,
            y: rect.midY - iconSide / 2,
            width: iconSide,
            height: iconSide
        )
        // 图标与周期在独立透明层内合成，镂空只作用于图标本身，不会擦掉状态栏选中背景。
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        if let icon {
            icon.draw(in: iconRect)
            context.setBlendMode(.sourceIn)
            context.setFillColor(labelColor.cgColor)
            context.fill(iconRect)
            context.setBlendMode(.normal)
        }
        drawPeriodLabel(ring.shortLabel, centeredIn: iconRect, color: labelColor, context: context)
        context.endTransparencyLayer()
    }

    /// 周期与图标共享同一中心：先描一圈细外沿，再把字面从图标中镂空，
    /// 字面因此呈现相对图标的反色，且不需要独立底色块。
    private static func drawPeriodLabel(
        _ label: String,
        centeredIn rect: NSRect,
        color: NSColor,
        context: CGContext
    ) {
        let font = StatusBarQuotaLayout.periodFont
        let text = label as NSString
        let textSize = text.size(withAttributes: [.font: font])
        let origin = NSPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2
        )
        // NSAttributedString 描边宽度以字号百分比表示，正值表示只描边不填充。
        let outlineStrokePercent = StatusBarQuotaLayout.periodOutlineWidth * 2 / font.pointSize * 100
        text.draw(at: origin, withAttributes: [
            .font: font,
            .strokeColor: color,
            .strokeWidth: outlineStrokePercent,
        ])
        context.setBlendMode(.destinationOut)
        text.draw(at: origin, withAttributes: [
            .font: font,
            .foregroundColor: NSColor.black,
        ])
        context.setBlendMode(.normal)
    }

    private static func drawValue(_ value: String, in slot: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: StatusBarQuotaLayout.valueFont,
            .foregroundColor: NSColor.labelColor,
        ]
        let text = value as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: slot.maxX - size.width, y: slot.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private static func arcColor(for severity: SubscriptionQuotaSeverity) -> NSColor {
        switch severity {
        case .normal:
            return .labelColor
        case .warning:
            return .systemOrange
        case .danger:
            return .systemRed
        }
    }
}
