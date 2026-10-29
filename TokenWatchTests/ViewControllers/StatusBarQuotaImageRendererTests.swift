import AppKit
import Testing
@testable import TokenWatch

@MainActor
@Suite("StatusBarQuotaImageRenderer")
struct StatusBarQuotaImageRendererTests {
    private let now = Date(timeIntervalSince1970: 1_793_170_000)

    @Test("状态栏模型按 Claude、Codex 固定顺序与设置中的窗口生成")
    func modelFollowsProviderOrderAndWindowOption() {
        let presentations = makePresentations(claudeUsed: (32, 14), codexUsed: (12, 2))

        let both = StatusBarQuotaModel.make(
            presentations: presentations,
            configuration: Self.allDetailed,
            ringDiameter: 22
        )
        #expect(both.groups.map(\.provider) == [.claude, .codex])
        #expect(both.groups[0].rings.map(\.shortLabel) == ["5H", "7D"])
        #expect(both.groups[0].rings.map(\.valueText) == ["68%", "86%"])
        #expect(both.groups[0].rings[0].remainingFraction == 0.68)
        #expect(both.groups.allSatisfy { $0.rings.allSatisfy(\.showsValue) })

        let weekOnly = StatusBarQuotaModel.make(
            presentations: presentations,
            configuration: { _, kind in .init(isVisible: kind == .sevenDay, style: .detailed) },
            ringDiameter: 22
        )
        #expect(weekOnly.groups.map { $0.rings.map(\.shortLabel) } == [["7D"], ["7D"]])
    }

    @Test("Claude 与 Codex 按各自配置展示周期；周期全部关闭的 Agent 整组省略")
    func modelFollowsPerProviderConfiguration() {
        let presentations = makePresentations(claudeUsed: (32, 14), codexUsed: (12, 2))

        let model = StatusBarQuotaModel.make(
            presentations: presentations,
            configuration: { provider, kind in
                switch (provider, kind) {
                case (.claude, .fiveHour):
                    return .init(isVisible: true, style: .compact)
                case (.claude, .sevenDay):
                    return .init(isVisible: true, style: .detailed)
                case (.codex, _):
                    return .init(isVisible: false, style: .detailed)
                }
            },
            ringDiameter: 22
        )

        #expect(model.groups.map(\.provider) == [.claude])
        #expect(model.groups[0].rings.map(\.shortLabel) == ["5H", "7D"])
        #expect(model.groups[0].rings.map(\.showsValue) == [false, true])

        let empty = StatusBarQuotaModel.make(
            presentations: presentations,
            configuration: { _, _ in .init(isVisible: false, style: .detailed) },
            ringDiameter: 22
        )
        #expect(empty.groups.isEmpty)
        #expect(StatusBarQuotaLayout.imageSize(for: empty).width == 0)
    }

    @Test("简洁模式只绘制圆环，不占用百分比宽度，图像更窄")
    func compactStyleOmitsValueSlot() {
        let presentations = makePresentations(claudeUsed: (32, 14), codexUsed: (12, 2))
        let detailed = StatusBarQuotaModel.make(
            presentations: presentations,
            configuration: Self.allDetailed,
            ringDiameter: 22
        )
        let compact = StatusBarQuotaModel.make(
            presentations: presentations,
            configuration: { _, _ in .init(isVisible: true, style: .compact) },
            ringDiameter: 22
        )

        // 每个 Agent：圆环到首段文本间距 + 两段文本之间的窗口间距 + 两段文本宽度。
        let valueWidths = detailed.groups.flatMap(\.rings).reduce(0) {
            $0 + StatusBarQuotaLayout.valueSize(for: $1).width
        } + CGFloat(detailed.groups.count) * (StatusBarQuotaLayout.ringToValueSpacing + StatusBarQuotaLayout.windowSpacing)
        let detailedWidth = StatusBarQuotaLayout.imageSize(for: detailed).width
        let compactWidth = StatusBarQuotaLayout.imageSize(for: compact).width
        #expect(abs(detailedWidth - compactWidth - valueWidths) <= 1)
        // 每个 Agent 一个同心双环 + 1 个分组间距。
        #expect(compactWidth == ceil(2 * 22 + StatusBarQuotaLayout.providerSpacing))
        #expect(StatusBarQuotaImageRenderer.makeImage(for: compact).size.width == compactWidth)
    }

    @Test("详细模式周期移到百分比下方，圈内只保留 Agent 图标；简洁模式周期仍叠加在图标中心")
    func detailedStyleMovesPeriodBelowValue() throws {
        let presentations = makePresentations(claudeUsed: (32, 14), codexUsed: (12, 2))
        let detailed = StatusBarQuotaModel.make(
            presentations: presentations,
            configuration: { provider, kind in
                .init(isVisible: provider == .claude && kind == .fiveHour, style: .detailed)
            },
            ringDiameter: 22
        )
        let compact = StatusBarQuotaModel.make(
            presentations: presentations,
            configuration: { provider, kind in
                .init(isVisible: provider == .claude && kind == .fiveHour, style: .compact)
            },
            ringDiameter: 22
        )

        let ring = try #require(detailed.groups.first?.rings.first)
        #expect(StatusBarQuotaLayout.valueText(for: ring).string == "68%\n5H")

        // 简洁模式的周期从图标中镂空，圈内不透明像素应少于详细模式。
        let ringRect = NSRect(x: 0, y: 0, width: 22, height: 22)
        let detailedPixels = try opaquePixelCount(in: StatusBarQuotaImageRenderer.makeImage(for: detailed), rect: ringRect)
        let compactPixels = try opaquePixelCount(in: StatusBarQuotaImageRenderer.makeImage(for: compact), rect: ringRect)
        #expect(detailedPixels > compactPixels)
    }

    @Test("同一 Agent 同时展示 5H、7D 时合并为同心双环：外环 5H、内环 7D，环外文本仍按周期左右排列")
    func bothWindowsMergeIntoConcentricRings() throws {
        let presentations = makePresentations(claudeUsed: (32, 14), codexUsed: (12, 2))
        func claudeGroup(style: StatusBarQuotaWindowStyle) throws -> StatusBarQuotaGroup {
            let model = StatusBarQuotaModel.make(
                presentations: presentations,
                configuration: { provider, _ in .init(isVisible: provider == .claude, style: style) },
                ringDiameter: 22
            )
            return try #require(model.groups.first)
        }

        // 详细模式每个周期仍是“百分比 / 周期”两行，两段从左到右排在圆环右侧。
        let detailed = try claudeGroup(style: .detailed)
        #expect(detailed.rings.map { StatusBarQuotaLayout.valueText(for: $0).string } == ["68%\n5H", "86%\n7D"])
        #expect(StatusBarQuotaLayout.groupWidth(for: detailed, diameter: 22) == 22
            + StatusBarQuotaLayout.ringToValueSpacing
            + StatusBarQuotaLayout.valueSize(for: detailed.rings[0]).width
            + StatusBarQuotaLayout.windowSpacing
            + StatusBarQuotaLayout.valueSize(for: detailed.rings[1]).width)

        let compact = try claudeGroup(style: .compact)
        #expect(StatusBarQuotaLayout.groupWidth(for: compact, diameter: 22) == 22)

        // 沿圆心竖线取样：外环与内环之间（半径 8.5–9.5pt）留空，内环（半径 7–8.5pt）绘制出剩余额度圆弧。
        let image = StatusBarQuotaImageRenderer.makeImage(
            for: StatusBarQuotaModel(groups: [compact], ringDiameter: 22)
        )
        let outerInnerEdge = 11 - StatusBarQuotaLayout.nestedRingLineWidth
        let innerRingCenter = outerInnerEdge - StatusBarQuotaLayout.nestedRingGap
            - StatusBarQuotaLayout.nestedRingLineWidth / 2
        let gapPixels = try opaquePixelCount(
            in: image,
            rect: NSRect(
                x: 11,
                y: 11 + outerInnerEdge - StatusBarQuotaLayout.nestedRingGap,
                width: 0.5,
                height: StatusBarQuotaLayout.nestedRingGap
            )
        )
        let innerArcPixels = try opaquePixelCount(
            in: image,
            rect: NSRect(x: 11, y: 11 + innerRingCenter - 0.25, width: 0.5, height: 0.5)
        )
        #expect(gapPixels == 0)
        #expect(innerArcPixels > 0)
        #expect(StatusBarQuotaLayout.iconSide(ringCount: 2, diameter: 22) == 11)
    }

    @Test("无数据保留周期标签并使用虚线灰环与 —；旧记录整体弱化")
    func unknownAndStaleRings() {
        let presentations = [
            SubscriptionQuotaPresenter.make(
                provider: .claude,
                state: SubscriptionQuotaProviderState(result: .notAuthorized, lastReadFailed: false),
                now: now,
                language: .zhHans
            ),
            SubscriptionQuotaPresenter.make(
                provider: .codex,
                state: SubscriptionQuotaProviderState(
                    result: .snapshot(snapshot(provider: .codex, used: (90, 50), recordedSecondsAgo: 3 * 3_600)),
                    lastReadFailed: false
                ),
                now: now,
                language: .zhHans
            ),
        ]
        let model = StatusBarQuotaModel.make(
            presentations: presentations,
            configuration: Self.allDetailed,
            ringDiameter: 22
        )

        #expect(model.groups[0].rings.map(\.shortLabel) == ["5H", "7D"])
        #expect(model.groups[0].rings.allSatisfy { $0.remainingFraction == nil && $0.valueText == "—" })
        #expect(!model.groups[0].isDimmed)
        #expect(model.groups[1].isDimmed)
        // 旧记录不再用强调色提示低额度。
        #expect(model.groups[1].rings[0].severity == .normal)
    }

    @Test("百分比按实际宽度占位：同位数数值变化宽度不变，只有字符数变化才改变宽度")
    func imageWidthFollowsValueCharacterCount() {
        let twoDigits = StatusBarQuotaModel.make(
            presentations: makePresentations(claudeUsed: (32, 14), codexUsed: (12, 2)),
            configuration: Self.allDetailed,
            ringDiameter: 22
        )
        let otherTwoDigits = StatusBarQuotaModel.make(
            presentations: makePresentations(claudeUsed: (45, 20), codexUsed: (30, 10)),
            configuration: Self.allDetailed,
            ringDiameter: 22
        )
        let full = StatusBarQuotaModel.make(
            presentations: makePresentations(claudeUsed: (0, 0), codexUsed: (0, 0)),
            configuration: Self.allDetailed,
            ringDiameter: 22
        )
        let low = StatusBarQuotaModel.make(
            presentations: makePresentations(claudeUsed: (99.5, 91), codexUsed: (100, 45)),
            configuration: Self.allDetailed,
            ringDiameter: 22
        )

        #expect(low.groups[0].rings.map(\.valueText) == ["<1%", "9%"])
        #expect(low.groups[1].rings.map(\.valueText) == ["0%", "55%"])
        // 数字为等宽字体，同位数变化不引起状态栏宽度变化。
        #expect(StatusBarQuotaLayout.imageSize(for: twoDigits) == StatusBarQuotaLayout.imageSize(for: otherTwoDigits))
        // 不再为 100% 预留空白：两位数比满额窄，一位数更窄。
        #expect(StatusBarQuotaLayout.imageSize(for: twoDigits).width < StatusBarQuotaLayout.imageSize(for: full).width)
        #expect(StatusBarQuotaLayout.imageSize(for: low).width < StatusBarQuotaLayout.imageSize(for: twoDigits).width)

        let size = StatusBarQuotaLayout.imageSize(for: full)
        #expect(size.height == 22)
        #expect(size.width > 140 && size.width < 190)

        let image = StatusBarQuotaImageRenderer.makeImage(for: low)
        #expect(image.size == StatusBarQuotaLayout.imageSize(for: low))
        #expect(!image.isTemplate)
    }

    @Test("组合图像依次绘制原有仪表盘图标、今日 token 文本与额度圆环")
    func combinedImagePutsTodayTokensBeforeQuota() throws {
        let model = StatusBarQuotaModel.make(
            presentations: makePresentations(claudeUsed: (32, 14), codexUsed: (12, 2)),
            configuration: Self.allDetailed,
            ringDiameter: 22
        )
        let symbol = try #require(NSImage(
            systemSymbolName: "gauge.with.dots.needle.33percent",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: StatusBarIconLayout.pointSize, weight: .regular)))
        let title = NSAttributedString(
            string: "1.2M\nTokens",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 9)]
        )
        let titleWidth = ceil(title.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        ).width)

        let image = StatusBarQuotaImageRenderer.makeImage(
            for: model,
            leadingSymbol: symbol,
            leadingTitle: title
        )
        let quotaSize = StatusBarQuotaLayout.imageSize(for: model)

        // 仪表盘可见外圈按圆环直径占位，图像高度不超过圆环，避免状态栏整体缩放。
        #expect(image.size.width == ceil(
            model.ringDiameter
                + StatusBarQuotaLayout.todayTokensSymbolToTitleSpacing
                + titleWidth
                + StatusBarQuotaLayout.todayTokensToQuotaSpacing
                + quotaSize.width
        ))
        #expect(image.size.height == quotaSize.height)
        #expect(!image.isTemplate)
    }

    @Test("组合模式仪表盘可见外圈与额度圆环直径一致")
    func combinedImageGaugeMatchesRingDiameter() throws {
        for diameter in [StatusBarQuotaLayout.minimumRingDiameter, StatusBarQuotaLayout.defaultRingDiameter] {
            let model = StatusBarQuotaModel.make(
                presentations: makePresentations(claudeUsed: (32, 14), codexUsed: (12, 2)),
                configuration: Self.allDetailed,
                ringDiameter: diameter
            )
            let symbol = try #require(NSImage(
                systemSymbolName: "gauge.with.dots.needle.33percent",
                accessibilityDescription: nil
            )?.withSymbolConfiguration(.init(pointSize: StatusBarIconLayout.pointSize, weight: .regular)))
            let image = StatusBarQuotaImageRenderer.makeImage(
                for: model,
                leadingSymbol: symbol,
                leadingTitle: NSAttributedString(string: "1.2M\nTokens", attributes: [.font: NSFont.boldSystemFont(ofSize: 9)])
            )

            let ink = try inkBounds(in: image, columns: 0..<Int(diameter + 2))
            // 允许 1pt 抗锯齿与字形取整误差。
            #expect(abs(ink.width - diameter) <= 1)
            #expect(abs(ink.height - diameter) <= 1)
        }
    }

    @Test("圆环内图标与圆弧之间保留约 2pt 间隙")
    func agentIconKeepsGapFromRing() {
        let diameter = StatusBarQuotaLayout.defaultRingDiameter
        let ringInnerRadius = diameter / 2 - StatusBarQuotaLayout.ringLineWidth
        let iconRadius = diameter * StatusBarQuotaLayout.iconDiameterRatio / 2
        #expect(ringInnerRadius - iconRadius >= 2)
    }

    @Test("圆环直径在 20–22pt 候选范围内跟随状态栏高度")
    func ringDiameterFollowsStatusBarThickness() {
        #expect(StatusBarQuotaLayout.ringDiameter(forStatusBarThickness: 24) == 22)
        #expect(StatusBarQuotaLayout.ringDiameter(forStatusBarThickness: 22) == 20)
        #expect(StatusBarQuotaLayout.ringDiameter(forStatusBarThickness: 37) == 22)
        #expect(StatusBarQuotaLayout.ringDiameter(forStatusBarThickness: 16) == 20)
    }

    @Test("Agent 图标资源可用，图像实际绘制出内容")
    func rendersAgentIcons() throws {
        #expect(NSImage(named: StatusBarQuotaImageRenderer.claudeIconName) != nil)
        #expect(NSImage(named: StatusBarQuotaImageRenderer.codexIconName) != nil)

        let model = StatusBarQuotaModel.make(
            presentations: makePresentations(claudeUsed: (32, 14), codexUsed: (85, 95)),
            configuration: { _, kind in .init(isVisible: kind == .fiveHour, style: .detailed) },
            ringDiameter: 22
        )
        let image = StatusBarQuotaImageRenderer.makeImage(for: model)

        // 第一个圆环内圈应绘制出图标，而不只有圆弧。
        let iconPixels = try opaquePixelCount(in: image, rect: NSRect(x: 6, y: 6, width: 10, height: 10))
        #expect(iconPixels > 50)
    }

    // MARK: - Helpers

    /// 以浅色外观按指定倍率渲染图像。
    private func rasterize(_ image: NSImage, scale: CGFloat) throws -> NSBitmapImageRep {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(image.size.width * scale),
            pixelsHigh: Int(image.size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            image.draw(in: NSRect(origin: .zero, size: image.size))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// 指定列范围（点坐标）内可见像素的外接尺寸（点）。
    private func inkBounds(in image: NSImage, columns: Range<Int>) throws -> NSSize {
        let scale: CGFloat = 4
        let rep = try rasterize(image, scale: scale)
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for x in Int(CGFloat(columns.lowerBound) * scale)..<Int(CGFloat(columns.upperBound) * scale) {
            for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.15 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return .zero }
        return NSSize(width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }

    /// 以 2x 浅色外观渲染图像，统计指定区域（点坐标）内不透明像素数。
    private func opaquePixelCount(in image: NSImage, rect: NSRect) throws -> Int {
        let rep = try rasterize(image, scale: 2)
        var count = 0
        for x in Int(rect.minX * 2)..<Int(rect.maxX * 2) {
            for y in Int(rect.minY * 2)..<Int(rect.maxY * 2) where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                count += 1
            }
        }
        return count
    }

    private static let allDetailed: (SubscriptionQuotaProvider, SubscriptionQuotaWindowKind)
        -> StatusBarQuotaWindowConfiguration = { _, _ in .defaultConfiguration }

    private func makePresentations(
        claudeUsed: (Double, Double),
        codexUsed: (Double, Double)
    ) -> [SubscriptionQuotaProviderPresentation] {
        [
            SubscriptionQuotaPresenter.make(
                provider: .claude,
                state: SubscriptionQuotaProviderState(
                    result: .snapshot(snapshot(provider: .claude, used: claudeUsed)),
                    lastReadFailed: false
                ),
                now: now,
                language: .zhHans
            ),
            SubscriptionQuotaPresenter.make(
                provider: .codex,
                state: SubscriptionQuotaProviderState(
                    result: .snapshot(snapshot(provider: .codex, used: codexUsed)),
                    lastReadFailed: false
                ),
                now: now,
                language: .zhHans
            ),
        ]
    }

    private func snapshot(
        provider: SubscriptionQuotaProvider,
        used: (Double, Double),
        recordedSecondsAgo: TimeInterval = 60
    ) -> SubscriptionQuotaSnapshot {
        var windows: [SubscriptionQuotaWindowKind: SubscriptionQuotaWindow] = [:]
        windows[.fiveHour] = SubscriptionQuotaWindow(usedPercent: used.0, resetsAt: now.addingTimeInterval(3_600))
        windows[.sevenDay] = SubscriptionQuotaWindow(usedPercent: used.1, resetsAt: now.addingTimeInterval(86_400))
        return SubscriptionQuotaSnapshot(
            provider: provider,
            accountID: nil,
            bucketID: nil,
            recordedAt: now.addingTimeInterval(-recordedSecondsAgo),
            windows: windows
        )
    }
}
