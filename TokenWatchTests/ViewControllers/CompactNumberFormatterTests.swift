import Testing
@testable import TokenWatch

struct CompactNumberFormatterTests {

    @Test func zeroAndSmallIntegers() {
        #expect(CompactNumberFormatter.format(0) == "0")
        #expect(CompactNumberFormatter.format(1) == "1")
        #expect(CompactNumberFormatter.format(823) == "823")
        #expect(CompactNumberFormatter.format(999) == "999")
    }

    @Test func thousandsRangeKeepsOneDecimal() {
        #expect(CompactNumberFormatter.format(1_000) == "1.0k")
        #expect(CompactNumberFormatter.format(1_234) == "1.2k")
        #expect(CompactNumberFormatter.format(99_949) == "99.9k")
        #expect(CompactNumberFormatter.format(99_999) == "99.9k")
    }

    @Test func hundredThousandsKeepsOneDecimal() {
        #expect(CompactNumberFormatter.format(100_000) == "100.0k")
        #expect(CompactNumberFormatter.format(823_456) == "823.4k")
        #expect(CompactNumberFormatter.format(999_999) == "999.9k")
    }

    @Test func millionsRangeKeepsOneDecimal() {
        #expect(CompactNumberFormatter.format(1_000_000) == "1.0M")
        #expect(CompactNumberFormatter.format(1_234_567) == "1.2M")
        #expect(CompactNumberFormatter.format(9_949_000) == "9.9M")
        #expect(CompactNumberFormatter.format(9_999_999) == "9.9M")
    }

    @Test func tenMillionsKeepsOneDecimal() {
        #expect(CompactNumberFormatter.format(10_000_000) == "10.0M")
        #expect(CompactNumberFormatter.format(12_345_678) == "12.3M")
        #expect(CompactNumberFormatter.format(123_456_789) == "123.4M")
    }

    @Test func negativesTreatedAsZero() {
        #expect(CompactNumberFormatter.format(-1) == "0")
        #expect(CompactNumberFormatter.format(-1_000_000) == "0")
    }

    @Test func hoverTokensUseMillionsWithKFallback() {
        #expect(CompactNumberFormatter.formatHoverTokens(-1) == "0.0M")
        #expect(CompactNumberFormatter.formatHoverTokens(0) == "0.0M")
        #expect(CompactNumberFormatter.formatHoverTokens(12_345) == "12.3k")
        #expect(CompactNumberFormatter.formatHoverTokens(99_999) == "99.9k")
        #expect(CompactNumberFormatter.formatHoverTokens(100_000) == "0.1M")
        #expect(CompactNumberFormatter.formatHoverTokens(1_234_567) == "1.2M")
    }
}
