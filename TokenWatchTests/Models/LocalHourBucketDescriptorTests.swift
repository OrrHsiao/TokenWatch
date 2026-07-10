import Foundation
import Testing
@testable import TokenWatch

@Suite("LocalHourBucketDescriptor")
struct LocalHourBucketDescriptorTests {
    @Test("春季跳时日仍生成 00 到 23 的二十四个唯一墙上小时")
    func springForwardDayHasTwentyFourWallClockBuckets() throws {
        let calendar = losAngelesCalendar()
        let day = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 8, hour: 12
        )))

        let buckets = LocalHourBucketDescriptor.buckets(forDayContaining: day, calendar: calendar)

        #expect(buckets.count == 24)
        #expect(Set(buckets.map(\.key)).count == 24)
        #expect(buckets.map(\.key) == (0..<24).map {
            String(format: "2026-03-08T%02d", $0)
        })
    }

    @Test("秋季回拨日两个真实 01 点映射到同一个墙上 key")
    func repeatedRealHoursShareOneWallClockKey() throws {
        let calendar = losAngelesCalendar()
        let midnight = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 1, hour: 0
        )))
        let firstOne = try #require(calendar.date(byAdding: .hour, value: 1, to: midnight))
        let secondOne = firstOne.addingTimeInterval(3_600)
        let buckets = LocalHourBucketDescriptor.buckets(forDayContaining: midnight, calendar: calendar)

        #expect(LocalHourBucketDescriptor.key(for: firstOne, calendar: calendar) == "2026-11-01T01")
        #expect(LocalHourBucketDescriptor.key(for: secondOne, calendar: calendar) == "2026-11-01T01")
        #expect(buckets.count == 24)
        #expect(Set(buckets.map(\.key)).count == 24)
        #expect(buckets.last?.key == "2026-11-01T23")
    }

    private func losAngelesCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }
}
