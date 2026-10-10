import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum MealTheme {
    static let pine = adaptive(light: 0x195C46, dark: 0x87CEAD)
    static let pineFill = adaptive(light: 0x195C46, dark: 0x245F4C)
    static let canvas = adaptive(light: 0xF6F6EF, dark: 0x151C18)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x222C25)
    static let softGreen = adaptive(light: 0xE7EFE7, dark: 0x2A3B30)
    static let ink = adaptive(light: 0x172D24, dark: 0xF2F3E9)
    static let secondary = adaptive(light: 0x64716A, dark: 0xADB9AF)
    static let border = adaptive(light: 0xE4E8DF, dark: 0x354438)
    static let warning = adaptive(light: 0x8F5E13, dark: 0xE6BE79)
    static let warningFill = adaptive(light: 0xFFF4DB, dark: 0x3B3020)

    private static func adaptive(light: UInt, dark: UInt) -> Color {
        #if os(iOS)
        return Color(uiColor: UIColor { traits in
            nativeColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
        #elseif os(macOS)
        return Color(nsColor: NSColor(name: nil) { appearance in
            nativeColor(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        })
        #endif
    }

    #if os(iOS)
    private static func nativeColor(_ hex: UInt) -> UIColor {
        UIColor(red: Double((hex >> 16) & 255) / 255,
                green: Double((hex >> 8) & 255) / 255,
                blue: Double(hex & 255) / 255, alpha: 1)
    }
    #elseif os(macOS)
    private static func nativeColor(_ hex: UInt) -> NSColor {
        NSColor(red: Double((hex >> 16) & 255) / 255,
                green: Double((hex >> 8) & 255) / 255,
                blue: Double(hex & 255) / 255, alpha: 1)
    }
    #endif
}

struct MealCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(MealTheme.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(MealTheme.border.opacity(0.65), lineWidth: 1)
            }
    }
}

extension View {
    func mealCard() -> some View { modifier(MealCard()) }
}
