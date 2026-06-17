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
