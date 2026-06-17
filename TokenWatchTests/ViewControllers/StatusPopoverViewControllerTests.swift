import AppKit
import Testing
@testable import TokenWatch

@MainActor
@Suite("StatusPopoverViewController")
struct StatusPopoverViewControllerTests {

    @Test("加载后创建标题和 7 列 collection view")
    func loadViewCreatesCalendarCollectionView() {
        let viewModel = TokenStatsViewModel()
        let controller = StatusPopoverViewController(
            viewModel: viewModel,
            nowProvider: { fixedDate() },
            calendar: fixedCalendar()
        )

        controller.loadViewIfNeeded()

        #expect(controller.debugMonthTitle == "2026 年 6 月")
        #expect(controller.debugCollectionView != nil)
        #expect(controller.debugWeekdayLabelCount == 7)
        #expect(controller.debugCollectionItemCount == 30)
    }

    @Test("根视图使用动态窗口背景")
    func rootViewUsesDynamicWindowBackground() {
        let controller = makeController()

        controller.loadViewIfNeeded()

        #expect(controller.view is StatusPopoverRootView)
    }

    @Test("collection view 使用固定 6 行网格高度")
    func collectionViewUsesFixedGridHeight() {
        let controller = makeController()

        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        #expect(controller.debugCollectionHeight == StatusPopoverViewController.debugExpectedCollectionHeight)
        #expect(controller.debugCollectionView?.frame.height == StatusPopoverViewController.debugExpectedCollectionHeight)
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
        #expect(controller.collectionView(collectionView, numberOfItemsInSection: 0) == 30)
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
}
