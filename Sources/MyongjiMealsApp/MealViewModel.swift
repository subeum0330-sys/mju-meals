import Foundation
import Combine
import MealCore

@MainActor
final class MealViewModel: ObservableObject {
    @Published private(set) var campus: Campus
    @Published private(set) var cafeteria: Cafeteria
    @Published private(set) var selectedDate: Date
    @Published private(set) var week: MealWeek?
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?

    private let preferences: UserDefaults
    private let service: MealService
    private var cachedWeeks: [String: MealWeek] = [:]
    private var activeRequest: UUID?
    private var requestTask: Task<MealWeek, Error>?
    private var lastActiveDay = Date()

    init(preferences: UserDefaults = .standard,
         service: MealService = MealService(feedURL: MealFeedConfiguration.url)) {
        self.preferences = preferences
        self.service = service
        let savedCampus = preferences.string(forKey: "preferredCampus").flatMap(Campus.init(rawValue:)) ?? .science
        let savedCafeteria = preferences.string(forKey: "preferredCafeteria.\(savedCampus.rawValue)")
        let available = Cafeteria.all.filter { $0.campus == savedCampus }
        let selectedCafeteria = available.first { $0.id == savedCafeteria } ?? available.first ?? Cafeteria.all[0]
        campus = selectedCafeteria.campus
        cafeteria = selectedCafeteria
        selectedDate = Date()
        if let data = preferences.data(forKey: "cachedMealWeeks"),
           let saved = try? JSONDecoder().decode([String: MealWeek].self, from: data) {
            cachedWeeks = saved.filter { key, value in
                key == "\(value.cafeteria.id):\(SchoolCalendar.dayKey(value.monday))"
                && abs(value.monday.timeIntervalSinceNow) < 60 * 60 * 24 * 60
            }
        }
    }

    var cafeterias: [Cafeteria] { Cafeteria.all.filter { $0.campus == campus } }
    var dates: [Date] { SchoolCalendar.weekDates(containing: selectedDate) }
    var entries: [MealEntry] {
        week?.entries.filter { SchoolCalendar.calendar.isDate($0.date, inSameDayAs: selectedDate) } ?? []
    }
    var isToday: Bool { SchoolCalendar.calendar.isDate(selectedDate, inSameDayAs: Date()) }
    var isPastDate: Bool {
        SchoolCalendar.calendar.startOfDay(for: selectedDate) < SchoolCalendar.calendar.startOfDay(for: Date())
    }
    var hasPublishedEntries: Bool { entries.contains(where: \.isPublished) }
    var sourceLabel: String {
        guard let source = week?.snapshotSource else { return "학교 홈페이지" }
        return source.isAutomatic ? "인스타 자동 수집" : "인스타 확인본"
    }
    var isAutomaticRefreshConfigured: Bool { MealFeedConfiguration.isConfigured }
    var needsSourceFollowUp: Bool {
        !isLoading && (errorMessage != nil || !hasPublishedEntries)
    }
    var isShowingSavedResult: Bool { week != nil && errorMessage != nil }
    var campusCity: String { campus == .science ? "용인" : "서울" }

    func selectCampus(_ newCampus: Campus) {
        guard newCampus != campus else { return }
        let available = Cafeteria.all.filter { $0.campus == newCampus }
        let savedID = preferences.string(forKey: "preferredCafeteria.\(newCampus.rawValue)")
        guard let selection = available.first(where: { $0.id == savedID }) ?? available.first else { return }
        campus = newCampus
        cafeteria = selection
        preferences.set(newCampus.rawValue, forKey: "preferredCampus")
        loadSelection()
    }

    func selectCafeteria(_ selection: Cafeteria) {
        guard selection.campus == campus, selection.id != cafeteria.id else { return }
        cafeteria = selection
        preferences.set(selection.id, forKey: "preferredCafeteria.\(campus.rawValue)")
        loadSelection()
    }

    func selectDate(_ date: Date) {
        let oldMonday = SchoolCalendar.startOfWeek(containing: selectedDate)
        selectedDate = date
        if oldMonday != SchoolCalendar.startOfWeek(containing: date) {
            loadSelection()
        }
    }

    func moveWeek(by offset: Int) {
        guard let date = SchoolCalendar.calendar.date(byAdding: .day, value: offset * 7, to: selectedDate) else { return }
        selectDate(date)
    }

    func goToToday() { selectDate(Date()) }

    func resume() async {
        // Roll the selected day forward only if the user was viewing today.
        if SchoolCalendar.calendar.isDate(selectedDate, inSameDayAs: lastActiveDay) {
            selectedDate = Date()
        }
        lastActiveDay = Date()
        await refresh()
    }

    func refresh() async {
        requestTask?.cancel()
        let requestID = UUID()
        activeRequest = requestID
        defer {
            if activeRequest == requestID {
                isLoading = false
                requestTask = nil
            }
        }
        let selectedCafeteria = cafeteria
        let requestedDate = selectedDate
        let monday = SchoolCalendar.startOfWeek(containing: requestedDate)
        let key = cacheKey(for: selectedCafeteria, date: requestedDate)
        week = cachedWeeks[key]
        errorMessage = nil
        isLoading = true
        if let message = MealFeedConfiguration.errorMessage {
            errorMessage = message
            return
        }

        let service = service
        let task = Task { try await service.fetchWeek(for: selectedCafeteria, date: requestedDate) }
        requestTask = task

        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard activeRequest == requestID, !Task.isCancelled else { return }
            // A returned week must belong to exactly the requested restaurant and week.
            guard result.cafeteria.id == selectedCafeteria.id,
                  SchoolCalendar.startOfWeek(containing: result.monday) == monday else {
                errorMessage = "선택한 주의 식단을 확인하지 못했어요. 식단 원문을 확인해 주세요."
                isLoading = false
                requestTask = nil
                return
            }
            if let warning = result.feedWarning {
                errorMessage = warning
                // A failed feed request must not overwrite a newer same-week
                // server copy with the bundled fallback or school HTML.
                if let saved = cachedWeeks[key], saved.snapshotSource?.isAutomatic == true {
                    week = saved
                } else {
                    week = result
                }
            } else {
                cachedWeeks[key] = result
                week = result
                saveCache()
            }
        } catch {
            guard activeRequest == requestID else { return }
            if !Task.isCancelled && !(error is CancellationError) {
                errorMessage = (error as? MealServiceError)?.errorDescription
                    ?? "식단을 불러오지 못했어요. 인터넷 연결을 확인한 뒤 다시 시도해 주세요."
            }
        }
        guard activeRequest == requestID else { return }
        isLoading = false
        requestTask = nil
    }

    func formattedDate(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = SchoolCalendar.calendar
        formatter.timeZone = SchoolCalendar.calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private func loadSelection() {
        // Clear immediately, before an asynchronous task can run, to prevent a flash
        // of another cafeteria's menu under the newly selected heading.
        requestTask?.cancel()
        activeRequest = nil
        week = cachedWeeks[cacheKey(for: cafeteria, date: selectedDate)]
        errorMessage = nil
        isLoading = true
        Task { await refresh() }
    }

    private func cacheKey(for cafeteria: Cafeteria, date: Date) -> String {
        "\(cafeteria.id):\(SchoolCalendar.dayKey(SchoolCalendar.startOfWeek(containing: date)))"
    }

    private func saveCache() {
        cachedWeeks = cachedWeeks.filter { abs($0.value.monday.timeIntervalSinceNow) < 60 * 60 * 24 * 60 }
        if let data = try? JSONEncoder().encode(cachedWeeks) {
            preferences.set(data, forKey: "cachedMealWeeks")
        }
    }
}
