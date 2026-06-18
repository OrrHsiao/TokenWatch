import AppKit
import Testing
@testable import TokenWatch

@MainActor
@Suite("StatusPopoverViewController")
struct StatusPopoverViewControllerTests {

    @Test("加载后创建二十二列热力图 collection view")
    func loadViewCreatesTwentyTwoColumnCollectionView() {
        let viewModel = TokenStatsViewModel()
        let controller = StatusPopoverViewController(
            viewModel: viewModel,
            nowProvider: { fixedDate() },
            calendar: fixedCalendar()
        )

        controller.loadViewIfNeeded()

        #expect(controller.debugMonthTitle == "最近 22 周")
        #expect(controller.debugCollectionView != nil)
        #expect(controller.debugWeekdayLabelCount == 0)
        #expect(controller.debugCollectionItemCount == 154)
    }

    @Test("根视图使用动态窗口背景")
    func rootViewUsesDynamicWindowBackground() {
        let controller = makeController()

        controller.loadViewIfNeeded()

        #expect(controller.view is StatusPopoverRootView)
    }

    @Test("collection view 使用固定 7 行网格高度")
    func collectionViewUsesFixedGridHeight() {
        let controller = makeController()

        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        #expect(controller.debugCollectionHeight == StatusPopoverViewController.debugExpectedCollectionHeight)
        #expect(controller.debugCollectionView?.frame.height == StatusPopoverViewController.debugExpectedCollectionHeight)
    }

    @Test("collection view 宽度完整容纳二十二周列")
    func collectionViewWidthFitsTwentyTwoWeekColumns() {
        let controller = makeController()

        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        #expect(controller.debugCollectionView?.frame.width == 327)
    }

    @Test("collection view 使用 GitHub 风格小方格布局")
    func collectionViewUsesGitHubStyleGridLayout() throws {
        let controller = makeController()

        controller.loadViewIfNeeded()

        let collectionView = try #require(controller.debugCollectionView)
        let layout = try #require(collectionView.collectionViewLayout as? NSCollectionViewFlowLayout)

        #expect(layout.itemSize == NSSize(width: 12, height: 12))
        #expect(layout.minimumInteritemSpacing == 3)
        #expect(layout.minimumLineSpacing == 3)
        #expect(layout.scrollDirection == .horizontal)
    }

    @Test("collection view 底部保留弹窗边距")
    func collectionViewBottomStaysInsidePopoverBounds() {
        let controller = makeController()

        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        #expect(controller.debugCollectionViewBottomFitsInRootBounds)
    }

    @Test("data source 返回快照数量")
    func dataSourceReturnsSnapshotCount() throws {
        let controller = makeController()

        controller.loadViewIfNeeded()

        let collectionView = try #require(controller.debugCollectionView)
        #expect(controller.collectionView(collectionView, numberOfItemsInSection: 0) == 154)
    }

    @Test("hover token 文案展示在热力图右上角并可恢复")
    func hoverTextAppearsAtHeatmapTopTrailingCorner() throws {
        let controller = makeController()

        controller.loadViewIfNeeded()
        let defaultText = controller.debugTotalText
        controller.view.layoutSubtreeIfNeeded()
        controller.debugUpdateHoverText("2026-06-10 · 12,345 tokens")
        controller.view.layoutSubtreeIfNeeded()

        #expect(controller.debugTotalText == defaultText)
        #expect(controller.debugHoverText == "2026-06-10 · 12,345 tokens")
        #expect(controller.debugHoverLabelTrailingAlignsWithCollectionView)
        #expect(controller.debugHoverLabelLeadingAlignsWithCollectionView)
        #expect(controller.debugHoverLabelSitsJustAboveCollectionView)
        #expect(try label(named: "hoverLabel", in: controller).textColor == label(named: "totalLabel", in: controller).textColor)

        controller.debugUpdateHoverText(nil)
        controller.view.layoutSubtreeIfNeeded()

        #expect(controller.debugTotalText == defaultText)
        #expect(controller.debugHoverText == "")
    }

    @Test("cell 访问对越界索引做保护")
    func cellAccessChecksItemBounds() {
        let controller = makeController()

        controller.loadViewIfNeeded()

        #expect(controller.debugHasCell(at: 0))
        #expect(!controller.debugHasCell(at: 999))
    }

    private func makeController() -> StatusPopoverViewController {
        StatusPopoverViewController(
            viewModel: TokenStatsViewModel(),
            nowProvider: { fixedDate() },
            calendar: fixedCalendar()
        )
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func fixedDate() -> Date {
        fixedCalendar().date(from: DateComponents(year: 2026, month: 6, day: 17))!
    }

    private func label(named name: String, in controller: StatusPopoverViewController) throws -> NSTextField {
        let child = Mirror(reflecting: controller).children.first { $0.label == name }
        return try #require(child?.value as? NSTextField)
    }
}
