import Foundation
import Testing
@testable import MealCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct MealRemoteFeedTests {
    private let library = Cafeteria.all.first { $0.id == "science-library" }!
    private func date(_ value: String) -> Date { SchoolCalendar.parseDate(value)! }
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteFeedURLProtocol.self]
        return URLSession(configuration: configuration)
    }
    private func url(_ name: String) -> URL { URL(string: "https://menus.example/\(name).json")! }

    @Test func remoteWeekWinsOverBundledCopyAndPreservesCollectionTime() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let service = try MealService(session: session, feedURL: url("automatic"), snapshotData: RemoteFeedFixture.manual)
        let week = try await service.fetchWeek(for: library, date: date("2026.10.08"))
        let source = try #require(week.snapshotSource)
        #expect(week.entries.first?.items == ["자동 수집 메뉴"])
        #expect(source.isAutomatic)
        #expect(source.processingMethod == "automatic")
        #expect(source.sourceUpdatedAt == ISO8601DateFormatter().date(from: "2026-10-09T02:00:00Z"))
        #expect(week.fetchedAt == source.collectedAt)
        #expect(week.feedWarning == nil)
        let cached = try JSONDecoder().decode(MealWeek.self, from: JSONEncoder().encode(week))
        #expect(cached.snapshotSource?.isAutomatic == true)
        #expect(cached.snapshotSource?.sourceUpdatedAt == source.sourceUpdatedAt)
    }

    @Test func newlyPublishedWeekLoadsWithoutShiftingPreviousWeek() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let service = try MealService(session: session, feedURL: url("following"), snapshotData: RemoteFeedFixture.manual)
        let next = try await service.fetchWeek(for: library, date: date("2026.10.15"))
        #expect(SchoolCalendar.dayKey(next.monday) == "2026-10-12")
        #expect(next.entries.map { SchoolCalendar.dayKey($0.date) } == ["2026-10-15"])
        #expect(next.snapshotSource?.isAutomatic == true)
        let previous = try await service.fetchWeek(for: library, date: date("2026.10.08"))
        #expect(previous.snapshotSource?.isAutomatic == false)
        #expect(previous.entries.first?.items == ["검토한 메뉴"])
        #expect(previous.feedWarning == nil)

        let oldFeed = try MealService(session: session, feedURL: url("automatic"), snapshotData: RemoteFeedFixture.manual)
        do {
            _ = try await oldFeed.fetchWeek(for: library, date: date("2026.10.15"))
            Issue.record("A previous-week remote or local record must not become next week's menu")
        } catch {
            #expect(error as? MealServiceError == .httpStatus(503))
        }
    }

    @Test func failedFeedKeepsExactWeekManualFallbackAndItsOriginalTime() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        for endpoint in ["unavailable", "empty", "malformed", "large", "length"] {
            let service = try MealService(session: session, feedURL: url(endpoint), snapshotData: RemoteFeedFixture.manual)
            let week = try await service.fetchWeek(for: library, date: date("2026.10.08"))
            #expect(week.entries.first?.items == ["검토한 메뉴"], "\(endpoint)")
            #expect(week.snapshotSource?.isAutomatic == false)
            #expect(week.fetchedAt == ISO8601DateFormatter().date(from: "2026-10-08T01:00:00Z"))
            #expect(week.feedWarning?.contains("자동 갱신 서버") == true, "\(endpoint)")
        }
    }

    @Test func invalidConfigurationIsExplicitAndDoesNotDiscardAvailableMenu() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        for address in ["http://menus.example/automatic.json", "https://secret@menus.example/automatic.json",
                        "https://menus.example/automatic.json?token=secret", "https://menus.example/automatic.json#secret"] {
            let service = try MealService(session: session, feedURL: URL(string: address)!, snapshotData: RemoteFeedFixture.manual)
            let week = try await service.fetchWeek(for: library, date: date("2026.10.08"))
            #expect(week.snapshotSource?.isAutomatic == false)
            #expect(week.feedWarning?.contains("주소가 올바르지") == true)
            #expect(week.feedWarning?.contains("secret") == false)
        }
    }

    @Test func schoolFallbackExplainsFeedFailureWhileEmptyValidFeedIsNotFailure() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let failed = try MealService(session: session, feedURL: url("empty"))
        let week = try await failed.fetchWeek(for: library, date: date("2026.10.08"))
        #expect(week.snapshotSource == nil)
        #expect(week.feedWarning != nil)
        #expect(week.entries.allSatisfy { !$0.isPublished })

        let pending = try MealService(session: session, feedURL: url("missing"))
        let pendingWeek = try await pending.fetchWeek(for: library, date: date("2026.10.08"))
        #expect(pendingWeek.snapshotSource == nil)
        #expect(pendingWeek.feedWarning == nil)

        do {
            _ = try await failed.fetchWeek(for: library, date: date("2026.10.15"))
            Issue.record("Both sources failed, so the error must name both")
        } catch MealServiceError.allSourcesUnavailable(let feed, let school) {
            #expect(feed.contains("자동 갱신 서버"))
            #expect(school.contains("503"))
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func cancelledRefreshDoesNotReturnFallback() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let service = try MealService(session: session, feedURL: url("cancelled"), snapshotData: RemoteFeedFixture.manual)
        do {
            _ = try await service.fetchWeek(for: library, date: date("2026.10.08"))
            Issue.record("Cancellation must propagate")
        } catch {
            #expect(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
    }

    @Test func processingMetadataIsValidatedAndOldManualCacheStillDecodes() throws {
        let automatic = String(decoding: RemoteFeedFixture.automatic, as: UTF8.self)
        for invalid in [automatic.replacingOccurrences(of: "\"automatic\"", with: "\"human-ish\""),
                        automatic.replacingOccurrences(of: "\"collectedAt\":\"2026-10-09T02:00:00Z\",", with: ""),
                        automatic.replacingOccurrences(of: "2026-10-09T02:00:00Z", with: "tomorrow")] {
            #expect(throws: MealServiceError.invalidSnapshot) {
                try MealSnapshotStore.parse(data: Data(invalid.utf8))
            }
        }
        let manual = try #require(MealSnapshotStore.parse(data: RemoteFeedFixture.manual)
            .week(for: library, date: date("2026.10.08")))
        #expect(manual.snapshotSource?.processingMethod == nil)
        #expect(manual.snapshotSource?.collectedAt == nil)
        #expect(manual.snapshotSource?.sourceUpdatedAt == manual.snapshotSource?.verifiedAt)
        let oldCache = try JSONDecoder().decode(MealWeek.self, from: JSONEncoder().encode(manual))
        #expect(oldCache.feedWarning == nil)
        #expect(oldCache.snapshotSource?.isAutomatic == false)
    }
}

private enum RemoteFeedFixture {
    static let automatic = Data(#"""
    {"schemaVersion":1,"weeks":[{
      "cafeteriaID":"science-library","monday":"2026-10-05",
      "username":"mju_lounge","postURL":"https://www.instagram.com/mju_lounge/p/AutomaticFixture/",
      "verifiedAt":"2026-10-08T01:00:00Z","scope":"B코너 백반",
      "processingMethod":"automatic","collectedAt":"2026-10-09T02:00:00Z",
      "entries":[{"date":"2026-10-08","category":"중식","items":["자동 수집 메뉴"]}]
    }]}
    """#.utf8)
    static let manual = Data(String(decoding: automatic, as: UTF8.self)
        .replacingOccurrences(of: "\"processingMethod\":\"automatic\",\"collectedAt\":\"2026-10-09T02:00:00Z\",", with: "")
        .replacingOccurrences(of: "자동 수집 메뉴", with: "검토한 메뉴").utf8)
    static let following = Data(String(decoding: automatic, as: UTF8.self)
        .replacingOccurrences(of: "2026-10-05", with: "2026-10-12")
        .replacingOccurrences(of: "\"date\":\"2026-10-08\"", with: "\"date\":\"2026-10-15\"").utf8)
}

private final class RemoteFeedURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        var status = 200
        var headers = ["Content-Type": "application/json"]
        let data: Data
        if url.host == "www.mju.ac.kr" {
            if url.query == "monday=2026.10.05",
               let file = Bundle.module.url(forResource: "science-unpublished", withExtension: "html", subdirectory: "Fixtures"),
               let fixture = try? Data(contentsOf: file) {
                data = fixture
                headers["Content-Type"] = "text/html"
            } else { status = 503; data = Data() }
        } else {
            switch url.lastPathComponent {
            case "automatic.json": data = RemoteFeedFixture.automatic
            case "following.json": data = RemoteFeedFixture.following
            case "missing.json": data = Data(#"{"schemaVersion":1,"weeks":[]}"#.utf8)
            case "empty.json": data = Data()
            case "malformed.json":
                data = Data(String(decoding: RemoteFeedFixture.automatic, as: UTF8.self)
                    .replacingOccurrences(of: "\"date\":\"2026-10-08\"", with: "\"date\":\"2026-10-15\"").utf8)
            case "large.json": data = Data(repeating: 32, count: MealService.maximumFeedBytes + 1)
            case "length.json": headers["Content-Length"] = String(MealService.maximumFeedBytes + 1); data = Data()
            case "cancelled.json":
                client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
                return
            default: status = 503; data = Data()
            }
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
