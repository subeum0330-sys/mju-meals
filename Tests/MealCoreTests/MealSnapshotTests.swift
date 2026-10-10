import Foundation
import Testing
@testable import MealCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct MealSnapshotTests {
    private let library = Cafeteria.all.first { $0.id == "science-library" }!
    private func date(_ value: String) -> Date {
        SchoolCalendar.parseDate(value.replacingOccurrences(of: "-", with: "."))!
    }

    private var fixture: Data {
        Data(#"""
        {"schemaVersion":1,"weeks":[{
          "cafeteriaID":"science-library","monday":"2026-10-05",
          "username":"mju_lounge",
          "postURL":"https://www.instagram.com/mju_lounge/p/ReviewedFixture/",
          "verifiedAt":"2026-10-08T05:15:00Z","scope":"B코너 백반",
          "location":"명진당 지하","operatingHours":"중식 11:30~14:00",
          "entries":[
            {"date":"2026-10-05","category":"중식","title":null,"items":["공휴일"],"note":null},
            {"date":"2026-10-08","category":"중식","title":"백반","items":["테스트 메뉴","쌀밥"],"note":null},
            {"date":"2026-10-08","category":"중식","title":"별도 코너","items":["테스트 선택 메뉴"],"note":null}
          ]
        }]}
        """#.utf8)
    }

    @Test func snapshotMatchesExactWeekAndCafeteria() throws {
        let store = try MealSnapshotStore.parse(data: fixture)
        let week = try #require(store.week(for: library, date: date("2026-10-08")))
        #expect(SchoolCalendar.dayKey(week.monday) == "2026-10-05")
        #expect(week.entries.map { SchoolCalendar.dayKey($0.date) } == ["2026-10-05", "2026-10-08", "2026-10-08"])
        #expect(Set(week.entries.map(\.id)).count == week.entries.count)
        #expect(store.week(for: library, date: date("2026-10-11")) != nil)
        #expect(store.week(for: library, date: date("2026-10-12")) == nil)
        #expect(store.week(for: library, date: date("2026-09-28")) == nil)
        for cafeteria in Cafeteria.all where cafeteria != library {
            #expect(store.week(for: cafeteria, date: date("2026-10-08")) == nil)
        }
        let wrongCampus = Cafeteria(id: library.id, name: library.name, campus: .humanities,
                                    sourceURL: library.sourceURL, dietID: library.dietID)
        #expect(store.week(for: wrongCampus, date: date("2026-10-08")) == nil)
    }

    @Test func reviewedProvenanceAndTimeArePreserved() throws {
        let week = try #require(MealSnapshotStore.parse(data: fixture).week(for: library, date: date("2026-10-08")))
        let source = try #require(week.snapshotSource)
        #expect(source.username == "mju_lounge")
        #expect(source.postURL.absoluteString == "https://www.instagram.com/mju_lounge/p/ReviewedFixture/")
        #expect(source.scope == "B코너 백반")
        #expect(source.verifiedAt == ISO8601DateFormatter().date(from: "2026-10-08T05:15:00Z"))
        #expect(week.fetchedAt == source.verifiedAt)
        #expect(week.entries.allSatisfy { $0.isPublished })
        #expect(week.entries.first?.items == ["공휴일"])
        let cached = try JSONDecoder().decode(MealWeek.self, from: JSONEncoder().encode(week))
        #expect(cached.snapshotSource?.postURL == source.postURL)
        #expect(cached.snapshotSource?.verifiedAt == source.verifiedAt)
        #expect(cached.fetchedAt == source.verifiedAt)
    }

    @Test func accountsBelongOnlyToTheirKnownScienceCafeterias() {
        let expected = ["science-library": "mju_lounge", "science-student": "mjhs_yongin",
                        "science-staff": "mj_bangmok_foodist", "science-dormitory": "mj_bokji_foodist"]
        for cafeteria in Cafeteria.all {
            #expect(cafeteria.instagramUsername == expected[cafeteria.id])
            if let username = expected[cafeteria.id] {
                #expect(cafeteria.instagramURL?.absoluteString == "https://www.instagram.com/\(username)/")
            } else {
                #expect(cafeteria.instagramURL == nil)
            }
        }
    }

    @Test func rejectsWrongDatesSourcesAndEmptyContent() throws {
        let json = String(decoding: fixture, as: UTF8.self)
        let substitutions = [
            (#""schemaVersion":1"#, #""schemaVersion":2"#),
            (#""monday":"2026-10-05""#, #""monday":"2026-10-06""#),
            (#""date":"2026-10-08""#, #""date":"2026-10-12""#),
            (#""date":"2026-10-08""#, #""date":"2026-02-30""#),
            (#""cafeteriaID":"science-library""#, #""cafeteriaID":"humanities-student""#),
            (#""username":"mju_lounge""#, #""username":"mjhs_yongin""#),
            ("https://www.instagram.com/mju_lounge/p/ReviewedFixture/", "https://www.instagram.com/mjhs_yongin/p/ReviewedFixture/"),
            ("https://www.instagram.com/mju_lounge/p/ReviewedFixture/", "https://www.instagram.com.evil.example/mju_lounge/p/ReviewedFixture/"),
            ("https://www.instagram.com/mju_lounge/p/ReviewedFixture/", "http://www.instagram.com/mju_lounge/p/ReviewedFixture/"),
            (#""scope":"B코너 백반""#, #""scope":" ""#),
            (#""verifiedAt":"2026-10-08T05:15:00Z""#, #""verifiedAt":"yesterday""#),
            (#""category":"중식""#, #""category":" ""#),
            (#""items":["공휴일"]"#, #""items":[]"#),
            (#""items":["공휴일"]"#, #""items":[" "]"#)
        ]
        for (before, after) in substitutions {
            let data = Data(json.replacingOccurrences(of: before, with: after).utf8)
            #expect(throws: MealServiceError.invalidSnapshot) { try MealSnapshotStore.parse(data: data) }
        }
    }

    @Test func rejectsDuplicateRestaurantWeeks() throws {
        var document = try #require(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
        let weeks = try #require(document["weeks"] as? [[String: Any]])
        document["weeks"] = weeks + weeks
        let data = try JSONSerialization.data(withJSONObject: document)
        #expect(throws: MealServiceError.invalidSnapshot) { try MealSnapshotStore.parse(data: data) }
    }

    @Test func oldCachedMealWeekDecodesWithoutSnapshotMetadata() throws {
        let original = MealWeek(cafeteria: library, monday: date("2026-10-05"), entries: [])
        let encoded = try JSONEncoder().encode(original)
        var document = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        document.removeValue(forKey: "snapshotSource")
        let decoded = try JSONDecoder().decode(MealWeek.self, from: JSONSerialization.data(withJSONObject: document))
        #expect(decoded.snapshotSource == nil)
        #expect(decoded.cafeteria == library)
        #expect(decoded.monday == original.monday)
    }

    @Test func serviceUsesReviewedWeekThenFallsBackToSchoolForFollowingWeek() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SnapshotFailureURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = try MealService(session: session, snapshotData: fixture)
        let reviewed = try await service.fetchWeek(for: library, date: date("2026-10-08"))
        #expect(reviewed.snapshotSource?.username == "mju_lounge")
        #expect(reviewed.entries[1].items.first == "테스트 메뉴")
        do {
            _ = try await service.fetchWeek(for: library, date: date("2026-10-15"))
            Issue.record("The following week must use the school request, not a shifted snapshot")
        } catch {
            #expect(error as? MealServiceError == .httpStatus(503))
        }
        do {
            _ = try await service.fetchUniversityWeek(for: library, date: date("2026-10-08"))
            Issue.record("The school-only method must not return a reviewed snapshot")
        } catch {
            #expect(error as? MealServiceError == .httpStatus(503))
        }
    }

    @Test func bundledOctoberWeekContainsReviewedMealsAndHolidayClosures() async throws {
        let expectedLunch = [
            "science-library": "제육생채비빔밥",
            "science-student": "마늘크림목살덮밥",
            "science-dormitory": "얼큰고기짬뽕",
            "science-staff": "꽁보리 열무비빔밥"
        ]
        let store = try MealSnapshotStore.bundled()
        var totalEntries = 0
        for cafeteria in Cafeteria.all.filter({ $0.campus == .science }) {
            let week = try await MealService().fetchWeek(for: cafeteria, date: date("2026-10-08"))
            let lunch = try #require(week.entries.first {
                SchoolCalendar.dayKey($0.date) == "2026-10-08" && $0.category == "중식"
            })
            #expect(lunch.items.first == expectedLunch[cafeteria.id])
            #expect(week.snapshotSource?.username == cafeteria.instagramUsername)
            #expect(week.fetchedAt == ISO8601DateFormatter().date(from: "2026-10-09T02:22:46Z"))
            #expect(week.fetchedAt == week.snapshotSource?.verifiedAt)
            #expect(week.entries.allSatisfy { SchoolCalendar.startOfWeek(containing: $0.date) == week.monday })
            let holidayEntries = week.entries.filter { SchoolCalendar.dayKey($0.date) == "2026-10-09" }
            #expect(!holidayEntries.isEmpty)
            #expect(holidayEntries.allSatisfy { $0.isPublished && $0.items == ["공휴일"] })
            #expect(store.week(for: cafeteria, date: date("2026-10-12")) == nil)
            totalEntries += week.entries.count
        }
        #expect(totalEntries == 35)
        let humanities = try #require(Cafeteria.all.first { $0.campus == .humanities })
        #expect(store.week(for: humanities, date: date("2026-10-08")) == nil)
    }
}

private final class SnapshotFailureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 503,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
