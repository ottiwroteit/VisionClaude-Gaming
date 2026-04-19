import Foundation
import UIKit

/// Thin wrapper around UIApplication.setAlternateIconName. The names here
/// must match the keys declared under CFBundleAlternateIcons in Info.plist.
///
/// Calls fail silently if the PNG files aren't bundled — that's fine for
/// scaffolding. Drop AppIcon-<Name>@2x.png (120pt) and @3x.png (180pt) at
/// the bundle root and the icon shows up without code changes.
enum AppIconManager {
    enum Variant: String, CaseIterable, Identifiable {
        case `default`
        case bowling = "Bowling"
        case tennis = "Tennis"
        case pingpong = "PingPong"
        case boxing = "Boxing"
        case archery = "Archery"
        case fruitslash = "FruitSlash"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .default:    return "Default"
            case .bowling:    return "Bowling"
            case .tennis:     return "Tennis"
            case .pingpong:   return "Ping Pong"
            case .boxing:     return "Boxing"
            case .archery:    return "Archery"
            case .fruitslash: return "Fruit Slash"
            }
        }

        var iconName: String? {
            self == .default ? nil : rawValue
        }
    }

    static var isSupported: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    static var current: Variant {
        let name = UIApplication.shared.alternateIconName
        return Variant.allCases.first(where: { $0.iconName == name }) ?? .default
    }

    @MainActor
    static func set(_ variant: Variant) async throws {
        try await UIApplication.shared.setAlternateIconName(variant.iconName)
    }
}
