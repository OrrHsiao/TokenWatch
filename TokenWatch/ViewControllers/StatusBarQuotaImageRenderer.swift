import AppKit

/// 状态栏中单个额度窗口：Agent 圆环单元中的一层圆环；详细模式环外另有百分比与周期两行文本。
struct StatusBarQuotaRing: Equatable {
    let shortLabel: String
    /// 0...1 的剩余比例；nil 表示没有可展示的值，绘制虚线灰环。
    let remainingFraction: Double?
    let valueText: String
    let severity: SubscriptionQuotaSeverity
    /// 详细模式在圆环右侧绘制剩余百分比（上）与周期（下）；简洁模式只绘制圆环，周期叠加在图标中心。
    let showsValue: Bool
}

/// 同一个 Agent 的额度窗口，共用一个圆环单元：
/// 只展示一个周期时为单环；同时展示 5H、7D 时为同心双环，外环 5H、内环 7D。
struct StatusBarQuotaGroup: Equatable {
    let provider: SubscriptionQuotaProvider
    /// 按 5H、7D 顺序排列：圆环由外向内绘制，环外文本从左到右排列。
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
    /// 单环图标与圆弧之间保留约 2pt 间隙（22pt 圆环内图标约 14pt）。
    static let iconDiameterRatio: CGFloat = 0.64
    /// 同心双环在单环外径内容纳两层圆弧，线宽收细到 1.5pt（Retina 下 3px）；
    /// 层间留 1pt（2px），避免两层圆弧在抗锯齿后连成一片。
    static let nestedRingLineWidth: CGFloat = 1.5
    static let nestedRingGap: CGFloat = 1
    /// 同心双环图标与内环之间的间隙；22pt 圆环内图标约 11pt，20pt 时约 9pt。
    static let nestedIconGap: CGFloat = 1.5
    /// 简洁模式叠加在图标中心的周期字号，尽量小以少遮挡 Agent 图标；
    /// Retina 下 5pt 镂空笔画约 2px 仍可辨认，4.5pt 起笔画只剩 1px、开始糊成一片。
    static let periodFontSize: CGFloat = 5
    /// 周期字形外沿描边宽度（pt）；随字号收细，避免描边填满字形内部。
    static let periodOutlineWidth: CGFloat = 0.5
    /// 详细模式环外两行文本，字号与行高沿用今日 token 标题（数字 9pt 粗体 / 单位 7pt）。
    static let valueFontSize: CGFloat = 9
    static let valueLineHeight: CGFloat = 10
    static let valuePeriodFontSize: CGFloat = 7
    static let valuePeriodLineHeight: CGFloat = 8
    /// 数字左侧字形留白约 0.25pt，可见间隔约 4.25pt，与仪表盘图标到今日 token 文本一致。
    static let ringToValueSpacing: CGFloat = 4
    /// 同一 Agent 相邻两段环外文本（5H、7D）之间的间距。
    static let windowSpacing: CGFloat = 6
    /// 环外文本宽度向上取整并含字形右侧留白，可见间隔约比该值多 0.75pt；
    /// 取 6.5 使分组间可见间隔与今日 token 文本到首个圆环一致（约 7.25pt）。
    static let providerSpacing: CGFloat = 6.5
    /// 组合模式中今日 token 文本与第一个额度圆环之间的间距。
    static let todayTokensToQuotaSpacing: CGFloat = 6
    /// 仪表盘 SF Symbol 画布四周自带透明边：18pt 字号时画布 21pt、可见外圈约 18pt。
    /// 组合模式据此放大绘制，使仪表盘可见外圈与额度圆环直径一致。
    static let todayTokensSymbolVisibleRatio: CGFloat = 18.0 / 21.0
    /// 组合模式中仪表盘可见外圈到今日 token 文本的间距；加上文本左侧字形留白，
    /// 可见间隔约 4.25pt，与圆环到百分比一致。
    static let todayTokensSymbolToTitleSpacing: CGFloat = 3.25
    static let dimmedAlpha: CGFloat = 0.55
    /// 已用额度轨道相对 labelColor 的透明度：0.22 在浅色状态栏上几乎看不见已用部分，
    /// 提高到 0.4 使已用段清晰可辨，同时仍明显弱于剩余额度圆弧。
    static let usedTrackAlpha: CGFloat = 0.4
    /// 无数据虚线灰环的透明度与线段 / 间隔。
    static let unknownTrackAlpha: CGFloat = 0.45
    static let unknownTrackDash: [CGFloat] = [2, 2]

    /// 圆环直径跟随系统状态栏高度，在 20–22pt 候选范围内取值，并为上下留出 1pt。
    static func ringDiameter(forStatusBarThickness thickness: CGFloat) -> CGFloat {
        min(defaultRingDiameter, max(minimumRingDiameter, thickness - 2))
    }

    static var valueFont: NSFont {
        .monospacedDigitSystemFont(ofSize: valueFontSize, weight: .bold)
    }

    static var valuePeriodFont: NSFont {
        .systemFont(ofSize: valuePeriodFontSize)
    }

    static var periodFont: NSFont {
        .systemFont(ofSize: periodFontSize, weight: .bold)
    }

    /// 圈内 Agent 图标边长：单环按 `iconDiameterRatio`；同心环从直径中扣除各层线宽、层间距与图标间隙。
    /// - Parameters:
    ///   - ringCount: 圆环层数。
    ///   - diameter: 最外层圆环直径。
    static func iconSide(ringCount: Int, diameter: CGFloat) -> CGFloat {
        guard ringCount > 1 else { return diameter * iconDiameterRatio }
        let ringsThickness = CGFloat(ringCount) * nestedRingLineWidth + CGFloat(ringCount - 1) * nestedRingGap
        return diameter - 2 * (ringsThickness + nestedIconGap)
    }

    /// 详细模式环外文本：剩余百分比在上、周期在下，与今日 token 的“数字 / 单位”排布一致。
    /// 周期移出圆环，避免压住圈内 Agent 图标。
    static func valueText(for ring: StatusBarQuotaRing) -> NSAttributedString {
        func paragraph(lineHeight: CGFloat) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.minimumLineHeight = lineHeight
            style.maximumLineHeight = lineHeight
            return style
        }
        let text = NSMutableAttributedString(
            string: ring.valueText,
            attributes: [
                .font: valueFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph(lineHeight: valueLineHeight),
            ]
        )
        text.append(NSAttributedString(
            string: "\n\(ring.shortLabel)",
            attributes: [
                .font: valuePeriodFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph(lineHeight: valuePeriodLineHeight),
            ]
        ))
        return text
    }

    /// 环外文本按实际宽度占位，不为 `100%` 预留空白，使各段间隔保持一致、整体更窄。
    /// 数字为等宽字体，宽度只在字符数变化（如 `100%`→`99%`、`10%`→`9%`）时改变，不会持续抖动。
    static func valueSize(for ring: StatusBarQuotaRing) -> NSSize {
        let bounds = valueText(for: ring).boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        )
        return NSSize(width: ceil(bounds.width), height: ceil(bounds.height))
    }

    /// 单个 Agent 占用的宽度：一个圆环单元，详细模式的周期依次在右侧追加环外文本。
    static func groupWidth(for group: StatusBarQuotaGroup, diameter: CGFloat) -> CGFloat {
        group.rings.filter(\.showsValue).enumerated().reduce(diameter) { width, item in
            width + (item.offset == 0 ? ringToValueSpacing : windowSpacing) + valueSize(for: item.element).width
        }
    }

    /// 图像尺寸由分组、窗口、简洁 / 详细样式、圆环直径与百分比字符数决定。
    static func imageSize(for model: StatusBarQuotaModel) -> NSSize {
        let groupsWidth = model.groups.reduce(0) { $0 + groupWidth(for: $1, diameter: model.ringDiameter) }
        let spacing = CGFloat(max(0, model.groups.count - 1)) * providerSpacing
        return NSSize(width: ceil(groupsWidth + spacing), height: model.ringDiameter)
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
    /// - Returns: 非 template 图像；尺寸由窗口、样式与百分比字符数决定，绘制时才解析外观颜色。
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
    /// 仪表盘可见外圈按圆环直径绘制，使两者一样大；图像高度不超过圆环，避免状态栏整体缩放。
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
        // 可见外圈占据 ringDiameter 见方；按透明边比例放大后的绘制区超出部分只是透明边，被图像边界裁掉。
        let symbolSide = model.ringDiameter
        let symbolScale = symbolSide / (leadingSymbol.size.width * StatusBarQuotaLayout.todayTokensSymbolVisibleRatio)
        let symbolDrawSize = NSSize(
            width: leadingSymbol.size.width * symbolScale,
            height: leadingSymbol.size.height * symbolScale
        )
        let titleBounds = leadingTitle.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        )
        let titleSize = NSSize(width: ceil(titleBounds.width), height: ceil(titleBounds.height))
        let height = max(quotaSize.height, symbolSide, titleSize.height)
        let titleOriginX = symbolSide + StatusBarQuotaLayout.todayTokensSymbolToTitleSpacing
        let quotaOriginX = titleOriginX + titleSize.width + StatusBarQuotaLayout.todayTokensToQuotaSpacing
        let size = NSSize(width: ceil(quotaOriginX + quotaSize.width), height: height)
        let icons = agentIcons()

        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let symbolRect = NSRect(
                x: (symbolSide - symbolDrawSize.width) / 2,
                y: (height - symbolDrawSize.height) / 2,
                width: symbolDrawSize.width,
                height: symbolDrawSize.height
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
            let ringRect = NSRect(x: x, y: (height - diameter) / 2, width: diameter, height: diameter)
            drawRings(group.rings, icon: icons[group.provider], in: ringRect, context: context)
            x += diameter
            for (valueIndex, ring) in group.rings.filter(\.showsValue).enumerated() {
                x += valueIndex == 0 ? StatusBarQuotaLayout.ringToValueSpacing : StatusBarQuotaLayout.windowSpacing
                let valueSize = StatusBarQuotaLayout.valueSize(for: ring)
                StatusBarQuotaLayout.valueText(for: ring).draw(
                    with: NSRect(
                        x: x,
                        y: (height - valueSize.height) / 2,
                        width: valueSize.width,
                        height: valueSize.height
                    ),
                    options: [.usesLineFragmentOrigin]
                )
                x += valueSize.width
            }
            context.endTransparencyLayer()
            context.restoreGState()
        }
    }

    /// 绘制一个 Agent 的圆环单元：单个周期为一层圆环；多个周期为同心环，
    /// `rings[0]` 在最外层，其余依次向内收一层线宽与层间距，图标居中。
    private static func drawRings(
        _ rings: [StatusBarQuotaRing],
        icon: NSImage?,
        in rect: NSRect,
        context: CGContext
    ) {
        let isNested = rings.count > 1
        let lineWidth = isNested ? StatusBarQuotaLayout.nestedRingLineWidth : StatusBarQuotaLayout.ringLineWidth
        let labelColor = NSColor.labelColor
        for (index, ring) in rings.enumerated() {
            let inset = CGFloat(index) * (lineWidth + StatusBarQuotaLayout.nestedRingGap)
            drawRing(ring, in: rect.insetBy(dx: inset, dy: inset), lineWidth: lineWidth)
        }

        let iconSide = StatusBarQuotaLayout.iconSide(ringCount: rings.count, diameter: rect.width)
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
        // 详细模式的周期已在环外第二行；简洁模式没有环外文本，单环时周期仍叠加在图标中心。
        // 同心环的两个周期无法同时叠加，且图标更小，改由内外层区分周期。
        if !isNested, let ring = rings.first, !ring.showsValue {
            drawPeriodLabel(ring.shortLabel, centeredIn: iconRect, color: labelColor, context: context)
        }
        context.endTransparencyLayer()
    }

    /// 绘制一层额度圆环：已用额度轨道（无数据时为虚线灰环）与剩余额度圆弧。
    private static func drawRing(_ ring: StatusBarQuotaRing, in rect: NSRect, lineWidth: CGFloat) {
        let labelColor = NSColor.labelColor

        let track = NSBezierPath(ovalIn: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        track.lineWidth = lineWidth
        if ring.remainingFraction == nil {
            let dash = StatusBarQuotaLayout.unknownTrackDash
            track.setLineDash(dash, count: dash.count, phase: 0)
            labelColor.withAlphaComponent(StatusBarQuotaLayout.unknownTrackAlpha).setStroke()
        } else {
            labelColor.withAlphaComponent(StatusBarQuotaLayout.usedTrackAlpha).setStroke()
        }
        track.stroke()

        guard let fraction = ring.remainingFraction, fraction > 0 else { return }
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
