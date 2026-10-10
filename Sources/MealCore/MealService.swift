import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MealServiceError: LocalizedError, Equatable, Sendable {
    case invalidResponse
    case httpStatus(Int)
    case invalidEncoding
    case unexpectedPage
    case mismatchedWeek
    case malformedTable
    case invalidSnapshot
    case invalidFeedURL
    case invalidFeedResponse
    case feedHTTPStatus(Int)
    case feedTooLarge
    case allSourcesUnavailable(feed: String, school: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "학교 서버의 응답을 확인할 수 없어요."
        case .httpStatus(let status): "학교 서버에 연결하지 못했어요. (HTTP \(status))"
        case .invalidEncoding: "학교 식단의 글자를 읽지 못했어요."
        case .unexpectedPage: "학교 식단 페이지의 형식이 달라졌어요. 원문을 확인해 주세요."
        case .mismatchedWeek: "학교에서 다른 주의 식단을 응답했어요. 다시 시도해 주세요."
        case .malformedTable: "학교 식단표를 정확히 읽지 못했어요. 원문을 확인해 주세요."
        case .invalidSnapshot: "식단 데이터의 날짜나 출처를 검증하지 못했어요. 원문을 확인해 주세요."
        case .invalidFeedURL: "자동 갱신 서버 주소가 올바르지 않아요. 인증 정보가 없는 HTTPS 주소를 설정해 주세요."
        case .invalidFeedResponse: "자동 갱신 서버의 응답을 확인할 수 없어요."
        case .feedHTTPStatus(let status): "자동 갱신 서버에 연결하지 못했어요. (HTTP \(status))"
        case .feedTooLarge: "자동 갱신 서버의 식단 데이터가 허용 크기를 넘었어요."
        case .allSourcesUnavailable(let feed, let school): "자동 갱신 서버와 학교 홈페이지에서 식단을 가져오지 못했어요. \(feed) \(school)"
        }
    }
}

public struct MealService: Sendable {
    private let session: URLSession
    private let snapshots: SnapshotSelection
    private let feedURL: URL?
    static let maximumFeedBytes = 2 * 1_024 * 1_024

    private enum SnapshotSelection: Sendable {
        case bundled
        case provided(MealSnapshotStore)
        case none
    }

    public init(feedURL: URL? = nil) {
        self.session = .shared
        self.snapshots = .bundled
        self.feedURL = feedURL
    }

    init(session: URLSession) {
        self.session = session
        self.snapshots = .none
        self.feedURL = nil
    }

    init(session: URLSession, snapshotData: Data) throws {
        self.session = session
        self.snapshots = .provided(try MealSnapshotStore.parse(data: snapshotData))
        self.feedURL = nil
    }

    init(session: URLSession, feedURL: URL, snapshotData: Data? = nil) throws {
        self.session = session
        self.feedURL = feedURL
        self.snapshots = try snapshotData.map { .provided(try MealSnapshotStore.parse(data: $0)) } ?? .none
    }

    public func fetchWeek(for cafeteria: Cafeteria, date: Date) async throws -> MealWeek {
        try Task.checkCancellation()
        var feedWarning: String?
        if let feedURL, cafeteria.instagramUsername != nil {
            do {
                let remote = try await fetchFeed(at: feedURL)
                if let week = remote.week(for: cafeteria, date: date) { return week }
            } catch {
                try Task.checkCancellation()
                // Cancellation is never a reason to replace data with a fallback.
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                let detail = (error as? MealServiceError)?.localizedDescription
                    ?? "네트워크 연결을 확인하고 다시 시도해 주세요."
                feedWarning = "자동 갱신 서버의 최신 식단을 확인하지 못했어요. \(detail)"
            }
        }
        let snapshot: MealWeek?
        switch snapshots {
        case .bundled:
            snapshot = try MealSnapshotStore.bundled().week(for: cafeteria, date: date)
        case .provided(let store):
            snapshot = store.week(for: cafeteria, date: date)
        case .none:
            snapshot = nil
        }
        if let snapshot { return snapshot.withFeedWarning(feedWarning) }
        do {
            return try await fetchUniversityWeek(for: cafeteria, date: date).withFeedWarning(feedWarning)
        } catch {
            try Task.checkCancellation()
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            if let feedWarning {
                throw MealServiceError.allSourcesUnavailable(feed: feedWarning, school: error.localizedDescription)
            }
            throw error
        }
    }

    private func fetchFeed(at url: URL) async throws -> MealSnapshotStore {
        guard Self.validFeedURL(url) else { throw MealServiceError.invalidFeedURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse,
              let finalURL = response.url, Self.validFeedURL(finalURL) else {
            throw MealServiceError.invalidFeedResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw MealServiceError.feedHTTPStatus(response.statusCode)
        }
        guard response.expectedContentLength <= Int64(Self.maximumFeedBytes) else {
            throw MealServiceError.feedTooLarge
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < Self.maximumFeedBytes else { throw MealServiceError.feedTooLarge }
            data.append(byte)
            if data.count.isMultiple(of: 16_384) { try Task.checkCancellation() }
        }
        try Task.checkCancellation()
        return try MealSnapshotStore.parse(data: data)
    }

    private static func validFeedURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && !(url.host ?? "").isEmpty
            && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
    }

    /// Kept separate so a live school-source check cannot pass using a bundled copy.
    func fetchUniversityWeek(for cafeteria: Cafeteria, date: Date) async throws -> MealWeek {
        let monday = SchoolCalendar.startOfWeek(containing: date)
        var components = URLComponents(string: "https://www.mju.ac.kr/diet/mjukr/\(cafeteria.dietID)/view.do")!
        components.queryItems = [URLQueryItem(name: "monday", value: SchoolCalendar.dayKey(monday).replacingOccurrences(of: "-", with: "."))]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw MealServiceError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw MealServiceError.httpStatus(response.statusCode) }
        guard let html = String(data: data, encoding: .utf8) else { throw MealServiceError.invalidEncoding }
        return try MealHTMLParser.parse(html, cafeteria: cafeteria, expectedMonday: monday)
    }
}
