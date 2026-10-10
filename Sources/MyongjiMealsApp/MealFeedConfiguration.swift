import Foundation

/// The public data URL is configured when building the app. API keys stay on the server.
enum MealFeedConfiguration {
    static var rawURL: String {
        (ProcessInfo.processInfo.environment["MJU_MEAL_FEED_URL"]
         ?? Bundle.main.object(forInfoDictionaryKey: "MJUMealFeedURL") as? String
         ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var url: URL? { rawURL.isEmpty ? nil : URL(string: rawURL) }
    static var isConfigured: Bool { !rawURL.isEmpty }
    static var errorMessage: String? {
        guard isConfigured else { return nil }
        guard let url, url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.port == nil || url.port == 443 else {
            return "자동 갱신 주소를 확인하지 못했어요. 앱의 데이터 연결 설정을 확인해 주세요."
        }
        return nil
    }
}
