import Foundation

/// A day without time or time zone, encoded in JSON as `YYYY-MM-DD`.
struct CalendarDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    init?(year: Int, month: Int, day: Int) {
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: Self.utcCalendar) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    init(_ date: Date) {
        let components = Self.utcCalendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year!
        self.month = components.month!
        self.day = components.day!
    }

    static func today(now: Date = .now) -> CalendarDate {
        CalendarDate(now)
    }

    /// Whole calendar months from `self` until `other`, counting a started month as a full one.
    func monthsUntil(_ other: CalendarDate) -> Int {
        var months = (other.year - year) * 12 + (other.month - month)
        if other.day > day { months += 1 }
        return months
    }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension CalendarDate: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let date = CalendarDate(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Must be a valid date in YYYY-MM-DD format"
            )
        }
        self = date
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
