import Foundation

public enum Campus: String, CaseIterable, Codable, Sendable {
    case humanities, science

    public var displayName: String {
        switch self {
        case .humanities: "인문캠퍼스"
        case .science: "자연캠퍼스"
        }
    }
}

public struct Cafeteria: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let campus: Campus
    public let sourceURL: URL
    public let dietID: Int

    public init(id: String, name: String, campus: Campus, sourceURL: URL, dietID: Int) {
        self.id = id
        self.name = name
        self.campus = campus
        self.sourceURL = sourceURL
        self.dietID = dietID
    }

    public var instagramUsername: String? {
        guard campus == .science else { return nil }
        switch id {
        case "science-library": return "mju_lounge"
        case "science-student": return "mjhs_yongin"
        case "science-staff": return "mj_bangmok_foodist"
        case "science-dormitory": return "mj_bokji_foodist"
        default: return nil
        }
    }

    public var instagramURL: URL? {
        instagramUsername.flatMap { URL(string: "https://www.instagram.com/\($0)/") }
    }

    public static let all: [Cafeteria] = [
        .init(id: "science-library", name: "명진당", campus: .science,
              sourceURL: URL(string: "https://www.mju.ac.kr/mjukr/485/subview.do")!, dietID: 4),
        .init(id: "science-student", name: "학생회관", campus: .science,
              sourceURL: URL(string: "https://www.mju.ac.kr/mjukr/486/subview.do")!, dietID: 5),
        .init(id: "science-dormitory", name: "생활관식당", campus: .science,
              sourceURL: URL(string: "https://www.mju.ac.kr/mjukr/487/subview.do")!, dietID: 6),
        .init(id: "science-staff", name: "교직원식당", campus: .science,
              sourceURL: URL(string: "https://www.mju.ac.kr/mjukr/488/subview.do")!, dietID: 7),
        .init(id: "humanities-student", name: "학생회관식당", campus: .humanities,
              sourceURL: URL(string: "https://www.mju.ac.kr/mjukr/8595/subview.do")!, dietID: 10)
    ]
}

public struct MealEntry: Identifiable, Codable, Sendable {
    public let id: String
    public let date: Date
    /// School labels 점심 and 저녁 are normalized to 중식 and 석식.
    public let category: String
    public let title: String?
    public let items: [String]
    public let note: String?
    /// True means the school published content, including an explicit closure notice.
    public let isPublished: Bool

    public init(id: String, date: Date, category: String, title: String? = nil,
                items: [String], note: String? = nil, isPublished: Bool) {
        self.id = id
        self.date = date
        self.category = category
        self.title = title
        self.items = items
        self.note = note
        self.isPublished = isPublished
    }
}

/// Provenance for a dated copy of an Instagram menu post.
/// Older, manually reviewed copies omit `processingMethod` and `collectedAt`.
public struct MealSnapshotSource: Codable, Sendable {
    public let username: String
    public let postURL: URL
    public let verifiedAt: Date
    public let scope: String
    public let processingMethod: String?
    public let collectedAt: Date?

    public var isAutomatic: Bool { processingMethod == "automatic" }
    /// Automatic collection is not a human review, even when the legacy
    /// `verifiedAt` field is present for schema compatibility.
    public var sourceUpdatedAt: Date { isAutomatic ? (collectedAt ?? verifiedAt) : verifiedAt }

    public init(username: String, postURL: URL, verifiedAt: Date, scope: String,
                processingMethod: String? = nil, collectedAt: Date? = nil) {
        self.username = username
        self.postURL = postURL
        self.verifiedAt = verifiedAt
        self.scope = scope
        self.processingMethod = processingMethod
        self.collectedAt = collectedAt
    }
}

public struct MealWeek: Codable, Sendable {
    public let cafeteria: Cafeteria
    public let monday: Date
    public let entries: [MealEntry]
    public let location: String?
    public let operatingHours: String?
    public let fetchedAt: Date
    public let snapshotSource: MealSnapshotSource?
    /// A configured remote feed failed to refresh. The displayed data is an
    /// exact-week fallback; its own source timestamp has not been advanced.
    public let feedWarning: String?

    public init(cafeteria: Cafeteria, monday: Date, entries: [MealEntry],
                location: String? = nil, operatingHours: String? = nil, fetchedAt: Date = Date(),
                snapshotSource: MealSnapshotSource? = nil, feedWarning: String? = nil) {
        self.cafeteria = cafeteria
        self.monday = monday
        self.entries = entries
        self.location = location
        self.operatingHours = operatingHours
        self.fetchedAt = fetchedAt
        self.snapshotSource = snapshotSource
        self.feedWarning = feedWarning
    }

    func withFeedWarning(_ warning: String?) -> MealWeek {
        MealWeek(cafeteria: cafeteria, monday: monday, entries: entries, location: location,
                 operatingHours: operatingHours, fetchedAt: fetchedAt,
                 snapshotSource: snapshotSource, feedWarning: warning)
    }
}
