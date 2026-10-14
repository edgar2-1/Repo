import Foundation

/// A calendar day with no time or time zone, stored as "yyyy-MM-dd".
/// All arithmetic happens in UTC so daylight-saving changes never shift a day.
public struct Day: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), (1...31).contains(day), year > 1900 else { return nil }
        let comps = DateComponents(year: year, month: month, day: day)
        guard let date = Day.utc.date(from: comps) else { return nil }
        let back = Day.utc.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        self.year = year; self.month = month; self.day = day
    }

    /// Parses "yyyy-MM-dd".
    public init?(_ string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// The day `date` falls on in `calendar` (the user's calendar by default).
    public init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = c.year!; self.month = c.month!; self.day = c.day!
    }

    public static func today(calendar: Calendar = .current) -> Day { Day(date: Date(), calendar: calendar) }

    /// Midnight UTC on this day.
    public var utcDate: Date { Day.utc.date(from: DateComponents(year: year, month: month, day: day))! }

    /// This day at `hour:minute` in `calendar`'s time zone.
    public func date(hour: Int, minute: Int = 0, calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
    }

    public func adding(days n: Int) -> Day {
        Day(date: Day.utc.date(byAdding: .day, value: n, to: utcDate)!, calendar: Day.utc)
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    public func days(until other: Day) -> Int {
        Day.utc.dateComponents([.day], from: utcDate, to: other.utcDate).day!
    }

    /// 0 = Sunday … 6 = Saturday.
    public var weekday: Int { Day.utc.component(.weekday, from: utcDate) - 1 }

    public var monthKey: String { String(format: "%04d-%02d", year, month) }
    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public static func < (a: Day, b: Day) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let d = Day(s) else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a yyyy-MM-dd day: \(s)")) }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}
