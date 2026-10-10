import Foundation
import Testing
@testable import MealCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct MealCoreTests {
    private func cafeteria(_ dietID: Int) -> Cafeteria { Cafeteria.all.first { $0.dietID == dietID }! }
    private func date(_ value: String) -> Date { SchoolCalendar.parseDate(value)! }
    private func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }
    private func parse(_ name: String, dietID: Int, monday: String) throws -> MealWeek {
        try MealHTMLParser.parse(fixture(name), cafeteria: cafeteria(dietID), expectedMonday: date(monday))
    }

    @Test func testSeoulWeekBoundaryAndNewYear() {
        let sundayUTC = ISO8601DateFormatter().date(from: "2026-10-04T15:01:00Z")!
        #expect(SchoolCalendar.dayKey(sundayUTC) == "2026-10-05")
        #expect(SchoolCalendar.dayKey(SchoolCalendar.startOfWeek(containing: sundayUTC)) == "2026-10-05")
        #expect(SchoolCalendar.dayKey(SchoolCalendar.startOfWeek(containing: date("2027.01.01"))) == "2026-12-28")
        #expect(SchoolCalendar.weekDates(containing: date("2027.01.01")).map(SchoolCalendar.dayKey) ==
                       ["2026-12-28", "2026-12-29", "2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02", "2027-01-03"])
        #expect(SchoolCalendar.parseDate("2026.02.30") == nil)
    }

    @Test func testAllFourScienceRestaurantsAgainstOfficialFixtures() throws {
        for (name, id, expectedCount) in [("science-library", 4, 5), ("science-student", 5, 10),
                                          ("science-dormitory", 6, 10), ("science-staff", 7, 10)] {
            let week = try parse(name, dietID: id, monday: "2026.09.07")
            #expect(week.entries.count == expectedCount, "\(name)")
            #expect(Set(week.entries.map(\.id)).count == expectedCount, "\(name)")
            #expect(week.entries.allSatisfy { $0.isPublished }, "\(name)")
            #expect(week.entries.allSatisfy { SchoolCalendar.startOfWeek(containing: $0.date) == week.monday }, "\(name)")
            #expect(week.operatingHours != nil, "\(name)")
            #expect(week.location != nil, "\(name)")
        }
        let library = try parse("science-library", dietID: 4, monday: "2026.09.07")
        #expect(library.entries[1].items.first == "얼큰차돌짬뽕")
        #expect(library.entries[1].items.count == 7)
        #expect(library.entries[0].title == "개교기념일 미운영")
        #expect(library.entries[0].isPublished, "Published closure must not be called unpublished")
        let student = try parse("science-student", dietID: 5, monday: "2026.09.07")
        #expect(student.entries[7].items == ["반달돈까스&냉모밀"])
        #expect(SchoolCalendar.dayKey(student.entries[7].date) == "2026-09-10")
        let staff = try parse("science-staff", dietID: 7, monday: "2026.09.07")
        #expect(staff.entries[0].category == "중식")
        #expect(staff.entries[1].category == "석식")
        #expect(staff.entries[0].title == "개교기념일 미운영")
        #expect(staff.entries[0].items.isEmpty)
        #expect(staff.entries[0].isPublished)
    }

    @Test func testUnpublishedIsNotAnErrorOrInventedMenu() throws {
        let week = try parse("science-unpublished", dietID: 4, monday: "2026.10.05")
        #expect(week.entries.count == 5)
        #expect(week.entries.allSatisfy { !$0.isPublished && $0.items.isEmpty && $0.title == nil })
        #expect(week.entries[3].note == "등록된 식단내용이(가) 없습니다.")
        #expect(SchoolCalendar.dayKey(week.entries[3].date) == "2026-10-08")
    }

    @Test func testMultipleMenusUnderOneDateAndMealRowspan() throws {
        let week = try parse("humanities-multiple", dietID: 10, monday: "2026.10.05")
        let lunches = week.entries.filter { SchoolCalendar.dayKey($0.date) == "2026-10-07" && $0.category == "중식" }
        try #require(lunches.count == 2)
        #expect(lunches[0].items.first == "고추잡채덮밥")
        #expect(lunches[1].items == ["[일품DAY]", "제육야채덮밥", "맛김치", "요구르트"])
        #expect(lunches[0].id != lunches[1].id)
        #expect(week.entries.count == 16)
    }

    @Test func testEntitiesAndInlineMarkup() throws {
        let html = try fixture("science-library").replacingOccurrences(of: "얼큰차돌짬뽕", with: "<b>밥&amp;국</b>&nbsp;&#x1F35A;&#32;&#128077;&lt;선택&gt;&quot;맛&quot;&apos;")
        let result = try MealHTMLParser.parse(html, cafeteria: cafeteria(4), expectedMonday: date("2026.09.07"))
        #expect(result.entries[1].items.first == "밥&국 🍚 👍<선택>\"맛\"'")
    }

    @Test func testWrongWeekAndWrongRestaurantAreRejected() throws {
        let html = try fixture("science-library")
        #expect(throws: MealServiceError.mismatchedWeek) {
            try MealHTMLParser.parse(html, cafeteria: cafeteria(4), expectedMonday: date("2026.10.05"))
        }
        #expect(throws: MealServiceError.unexpectedPage) {
            try MealHTMLParser.parse(html, cafeteria: cafeteria(5), expectedMonday: date("2026.09.07"))
        }
    }

    @Test func testBrokenTableAndOutOfWeekDateAreRejected() throws {
        let html = try fixture("science-library")
        for broken in [html.replacingOccurrences(of: "09.08 (화)", with: "10.08 (화)"),
                       html.replacingOccurrences(of: "<td rowspan=\"1\">중식</td>", with: ""),
                       html.replacingOccurrences(of: "rowspan=\"1\"", with: "rowspan=\"100\"")] {
            #expect(throws: MealServiceError.self) {
                try MealHTMLParser.parse(broken, cafeteria: cafeteria(4), expectedMonday: date("2026.09.07"))
            }
        }
        #expect(throws: MealServiceError.unexpectedPage) {
            try MealHTMLParser.parse("<html>점검 중</html>", cafeteria: cafeteria(4), expectedMonday: date("2026.09.07"))
        }
    }

    @Test func testCrossYearTableDateUsesRequestedWeek() throws {
        var html = try fixture("science-unpublished")
        html = html.replacingOccurrences(of: "2026.10.05", with: "2026.12.28")
        for (old, new) in [("10.05", "12.28"), ("10.06", "12.29"), ("10.07", "12.30"), ("10.08", "12.31"), ("10.09", "01.01")] {
            html = html.replacingOccurrences(of: old, with: new)
        }
        let week = try MealHTMLParser.parse(html, cafeteria: cafeteria(4), expectedMonday: date("2026.12.28"))
        #expect(SchoolCalendar.dayKey(week.entries.last!.date) == "2027-01-01")
    }

    @Test func testHTTPFailureAndInvalidEncoding() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MealMockURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = MealService(session: session)
        for id in [9998, 9999] {
            let custom = Cafeteria(id: "mock", name: "mock", campus: .science, sourceURL: cafeteria(4).sourceURL, dietID: id)
            do {
                _ = try await service.fetchWeek(for: custom, date: date("2026.10.08"))
                Issue.record("Expected request failure")
            } catch MealServiceError.httpStatus(let status) {
                #expect(id == 9999)
                #expect(status == 503)
            } catch MealServiceError.invalidEncoding {
                #expect(id == 9998)
            } catch { Issue.record("Unexpected error: \(error)") }
        }
    }

}

struct LiveMealServiceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MJU_LIVE_TEST"] == "1"))
    func testLiveScienceMenusWhenExplicitlyEnabled() async throws {
        let now = Date()
        let monday = SchoolCalendar.startOfWeek(containing: now)
        for cafeteria in Cafeteria.all.filter({ $0.campus == .science }) {
            let week = try await MealService().fetchUniversityWeek(for: cafeteria, date: now)
            #expect(week.cafeteria == cafeteria)
            #expect(week.monday == monday)
            #expect(!week.entries.isEmpty)
            #expect(week.entries.allSatisfy { SchoolCalendar.startOfWeek(containing: $0.date) == monday })
        }
    }
}

private final class MealMockURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let status = request.url!.path.contains("9999") ? 503 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([0xff, 0xfe, 0xfd]))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
