import SwiftUI

@main
struct MyongjiMealsApp: App {
    var body: some Scene {
        WindowGroup {
            MealsView()
                .tint(MealTheme.pine)
                #if os(macOS)
                .frame(minWidth: 420, minHeight: 720)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 430, height: 860)
        #endif
    }
}
