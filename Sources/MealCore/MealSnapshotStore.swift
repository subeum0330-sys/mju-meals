import Foundation

/// A dated dataset with per-record provenance. This never scrapes Instagram.
struct MealSnapshotStore: Sendable {
    private let weeks: [MealWeek]

    static func bundled() throws -> MealSnapshotStore {
        guard let url = Bundle.module.url(forResource: "instagram-reviewed", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            throw MealServiceError.invalidSnapshot
        }
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> MealSnapshotStore {
        guard let document = try? JSONDecoder().decode(Document.self, from: data),
              document.schemaVersion == 1 else {
            throw MealServiceError.invalidSnapshot
        }
        var weeks: [MealWeek] = []
        var keys: Set<String> = []
        for record in document.weeks {
            guard let cafeteria = Cafeteria.all.first(where: { $0.id == record.cafeteriaID }),
                  cafeteria.instagramUsername == record.username,
                  validPostURL(record.postURL, username: record.username),
                  let monday = parseDay(record.monday),
                  monday == SchoolCalendar.startOfWeek(containing: monday),
                  let verifiedAt = parseTimestamp(record.verifiedAt),
                  [nil, "manual", "automatic"].contains(record.processingMethod),
                  !record.scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !record.entries.isEmpty,
                  keys.insert("\(record.cafeteriaID)|\(record.monday)").inserted else {
                throw MealServiceError.invalidSnapshot
            }
            let collectedAt = record.collectedAt.flatMap(parseTimestamp)
            guard (record.collectedAt == nil || collectedAt != nil),
                  record.processingMethod != "automatic" || collectedAt != nil else {
                throw MealServiceError.invalidSnapshot
            }
            var entries: [MealEntry] = []
            for (index, entry) in record.entries.enumerated() {
                guard let date = parseDay(entry.date),
                      SchoolCalendar.startOfWeek(containing: date) == monday,
                      !entry.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !entry.items.isEmpty,
                      entry.items.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                    throw MealServiceError.invalidSnapshot
                }
                entries.append(MealEntry(
                    id: "instagram-\(record.cafeteriaID)-\(entry.date)-\(entry.category)-\(index)",
                    date: date, category: entry.category, title: entry.title,
                    items: entry.items, note: entry.note, isPublished: true
                ))
            }
            let source = MealSnapshotSource(username: record.username, postURL: record.postURL,
                                            verifiedAt: verifiedAt, scope: record.scope,
                                            processingMethod: record.processingMethod, collectedAt: collectedAt)
            weeks.append(MealWeek(cafeteria: cafeteria, monday: monday, entries: entries,
                                  location: record.location, operatingHours: record.operatingHours,
                                  fetchedAt: source.sourceUpdatedAt, snapshotSource: source))
        }
        return MealSnapshotStore(weeks: weeks)
    }

    func week(for cafeteria: Cafeteria, date: Date) -> MealWeek? {
        let monday = SchoolCalendar.startOfWeek(containing: date)
        // Match the complete known cafeteria as well as the week: a same-name
        // restaurant on another campus must never inherit this menu.
        return weeks.first { $0.cafeteria == cafeteria && $0.monday == monday }
    }

    private static func parseDay(_ value: String) -> Date? {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let date = SchoolCalendar.parseDate(value.replacingOccurrences(of: "-", with: ".")),
              SchoolCalendar.dayKey(date) == value else { return nil }
        return date
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }

    private static func validPostURL(_ url: URL, username: String) -> Bool {
        guard url.scheme == "https",
              let host = url.host,
              ["instagram.com", "www.instagram.com"].contains(host),
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { return false }
        let components = url.path.split(separator: "/")
        return components.count == 3 && components[0] == username && components[1] == "p"
            && components[2].range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    private struct Document: Decodable {
        let schemaVersion: Int
        let weeks: [WeekRecord]
    }

    private struct WeekRecord: Decodable {
        let cafeteriaID: String
        let monday: String
        let username: String
        let postURL: URL
        let verifiedAt: String
        let processingMethod: String?
        let collectedAt: String?
        let scope: String
        let location: String?
        let operatingHours: String?
        let entries: [EntryRecord]
    }

    private struct EntryRecord: Decodable {
        let date: String
        let category: String
        let title: String?
        let items: [String]
        let note: String?
    }
}
