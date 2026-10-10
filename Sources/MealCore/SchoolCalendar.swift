import Foundation

public enum SchoolCalendar {
    public static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        value.locale = Locale(identifier: "ko_KR")
        value.firstWeekday = 2
        value.minimumDaysInFirstWeek = 4
        return value
    }

    public static func startOfWeek(containing date: Date) -> Date {
        let cal = calendar
        let day = cal.startOfDay(for: date)
        let offset = (cal.component(.weekday, from: day) + 5) % 7
        return cal.date(byAdding: .day, value: -offset, to: day)!
    }

    public static func weekDates(containing date: Date) -> [Date] {
        let monday = startOfWeek(containing: date)
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: monday)! }
    }

    public static func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    static func parseDate(_ value: String) -> Date? {
        let parts = value.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              dayKey(date) == String(format: "%04d-%02d-%02d", parts[0], parts[1], parts[2]) else { return nil }
        return date
    }
}
