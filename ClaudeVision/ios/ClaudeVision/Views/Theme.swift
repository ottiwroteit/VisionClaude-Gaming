import SwiftUI

/// Shared visual language for the whole gaming app. Dark, high-contrast,
/// with a single warm accent color so game-specific art can use the rest of
/// the palette freely.
enum Theme {
    static let accent = Color(red: 232/255, green: 123/255, blue: 53/255)
    static let background = Color(red: 12/255, green: 12/255, blue: 14/255)
    static let surface = Color.white.opacity(0.06)
    static let surfaceStrong = Color.white.opacity(0.12)
    static let stroke = Color.white.opacity(0.08)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let success = Color(red: 74/255, green: 222/255, blue: 128/255)
    static let danger = Color(red: 248/255, green: 113/255, blue: 113/255)

    /// Per-game tint palette. Picked so each color is distinct at a glance
    /// in the game grid and carries into the game's hero art.
    static func color(for tint: GameTint) -> Color {
        switch tint {
        case .accent: return accent
        case .court:  return Color(red:  76/255, green: 187/255, blue: 110/255) // tennis green
        case .table:  return Color(red:  78/255, green: 140/255, blue: 220/255) // table blue
        case .ring:   return Color(red: 232/255, green:  80/255, blue:  92/255) // boxing red
        case .gold:   return Color(red: 234/255, green: 187/255, blue:  80/255) // archery gold
        case .berry:  return Color(red: 226/255, green: 102/255, blue: 168/255) // fruit magenta
        }
    }

    enum Radius {
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
    }
}

struct CardStyle: ViewModifier {
    var strong: Bool = false
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(strong ? Theme.surfaceStrong : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle(strong: Bool = false) -> some View {
        modifier(CardStyle(strong: strong))
    }
}
