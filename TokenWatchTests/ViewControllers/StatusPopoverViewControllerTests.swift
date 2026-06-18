import AppKit
import Testing
@testable import TokenWatch

@MainActor
@Suite("StatusPopoverViewController")
struct StatusPopoverViewControllerTests {

    @Test("加载后创建最近五个月 collection view")
    func loadViewCreatesRecentFiveMonthCollectionView() {
        let viewModel = TokenStatsViewModel()
        let controller = StatusPopoverViewController(
            viewModel: viewModel,
            nowProvider: { fixedDate() },
            calendar: fixedCalendar()
        )

        controller.loadViewIfNeeded()

        #expect(controller.debugMonthTitle == "最近 5 个月")
        #expect(controller.debugCollectionView != nil)
        #expect(controller.debugWeekdayLabelCount == 0)
        #expect(controller.debugCollectionItemCount == 161)
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

    @Test("collection view 宽度完整容纳最近五个月周列")
    func collectionViewWidthFitsAllFiveMonthWeekColumns() {
        let controller = makeController()

        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        #expect(controller.debugCollectionView?.frame.width == 342)
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
        #expect(controller.collectionView(collectionView, numberOfItemsInSection: 0) == 161)
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
