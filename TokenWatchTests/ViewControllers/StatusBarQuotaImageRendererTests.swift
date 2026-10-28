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
            windowKinds: StatusBarQuotaWindowsOption.both.windowKinds,
            ringDiameter: 22
        )
        #expect(both.groups.map(\.provider) == [.claude, .codex])
        #expect(both.groups[0].rings.map(\.shortLabel) == ["5H", "7D"])
        #expect(both.groups[0].rings.map(\.valueText) == ["68%", "86%"])
        #expect(both.groups[0].rings[0].remainingFraction == 0.68)

        let weekOnly = StatusBarQuotaModel.make(
            presentations: presentations,
            windowKinds: StatusBarQuotaWindowsOption.sevenDay.windowKinds,
            ringDiameter: 22
        )
        #expect(weekOnly.groups.map { $0.rings.map(\.shortLabel) } == [["7D"], ["7D"]])
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
            windowKinds: [.fiveHour, .sevenDay],
            ringDiameter: 22
        )

        #expect(model.groups[0].rings.map(\.shortLabel) == ["5H", "7D"])
        #expect(model.groups[0].rings.allSatisfy { $0.remainingFraction == nil && $0.valueText == "—" })
        #expect(!model.groups[0].isDimmed)
        #expect(model.groups[1].isDimmed)
        // 旧记录不再用强调色提示低额度。
        #expect(model.groups[1].rings[0].severity == .normal)
    }

    @Test("图像宽度只取决于窗口数量，数值变化不引起状态栏抖动")
    func imageWidthIsIndependentOfValues() {
        let full = StatusBarQuotaModel.make(
            presentations: makePresentations(claudeUsed: (0, 0), codexUsed: (0, 0)),
            windowKinds: [.fiveHour, .sevenDay],
            ringDiameter: 22
        )
        let low = StatusBarQuotaModel.make(
            presentations: makePresentations(claudeUsed: (99.5, 91), codexUsed: (100, 45)),
            windowKinds: [.fiveHour, .sevenDay],
            ringDiameter: 22
        )

        #expect(low.groups[0].rings.map(\.valueText) == ["<1%", "9%"])
        #expect(low.groups[1].rings.map(\.valueText) == ["0%", "55%"])
        #expect(StatusBarQuotaLayout.imageSize(for: full) == StatusBarQuotaLayout.imageSize(for: low))

        let size = StatusBarQuotaLayout.imageSize(for: full)
        #expect(size.height == 22)
        // 设计预估 240–260pt；以原生字体实测，保持在合理区间。
        #expect(size.width > 200 && size.width < 270)

        let image = StatusBarQuotaImageRenderer.makeImage(for: low)
        #expect(image.size == size)
        #expect(!image.isTemplate)
    }

    @Test("组合图像依次绘制原有仪表盘图标、今日 token 文本与额度圆环")
    func combinedImagePutsTodayTokensBeforeQuota() throws {
        let model = StatusBarQuotaModel.make(
            presentations: makePresentations(claudeUsed: (32, 14), codexUsed: (12, 2)),
            windowKinds: [.fiveHour, .sevenDay],
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

        #expect(image.size.width == ceil(
            symbol.size.width
                + StatusBarIconLayout.imageTitleSpacing
                + titleWidth
                + StatusBarQuotaLayout.todayTokensToQuotaSpacing
                + quotaSize.width
        ))
        #expect(image.size.height >= quotaSize.height)
        #expect(!image.isTemplate)
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
            windowKinds: [.fiveHour],
            ringDiameter: 22
        )
        let image = StatusBarQuotaImageRenderer.makeImage(for: model)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(image.size.width * 2),
            pixelsHigh: Int(image.size.height * 2),
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

        // 第一个圆环内圈（2x 像素坐标）应绘制出图标，而不只有圆弧。
        var iconPixels = 0
        for x in 12..<32 {
            for y in 12..<32 where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                iconPixels += 1
            }
        }
        #expect(iconPixels > 50)
    }

    // MARK: - Helpers

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
