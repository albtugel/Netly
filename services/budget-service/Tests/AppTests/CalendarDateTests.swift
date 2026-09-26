import Foundation
import Testing

@testable import App

@Suite struct CalendarDateTests {
    @Test func parsesStrictFormat() {
        #expect(CalendarDate("2026-09-26")?.description == "2026-09-26")
        #expect(CalendarDate("2026-9-26") == nil)
        #expect(CalendarDate("2026-02-29") == nil)
        #expect(CalendarDate("2028-02-29") != nil)
        #expect(CalendarDate("26-09-2026") == nil)
    }

    @Test(arguments: [
        ("2026-09-26", "2026-10-26", 1),
        ("2026-09-26", "2026-10-27", 2),
        ("2026-09-26", "2026-09-30", 1),
        ("2026-09-26", "2027-09-26", 12),
    ])
    func countsStartedMonths(from: String, to: String, expected: Int) {
        #expect(CalendarDate(from)!.monthsUntil(CalendarDate(to)!) == expected)
    }
}
