import SceneKit
import UIKit

/// Per-venue appearance overrides for the SceneKit boxing scene. Same
/// structure as the bowling/archery themes — colours that the controller
/// re-binds onto the bag, chains, lighting, and fog when the venue
/// changes.
struct BoxingSceneTheme {
  /// Main bag body colour.
  let bagColor: UIColor
  /// Accent stripe / branding colour wrapped around the bag mid-section.
  let bagAccentColor: UIColor
  /// Hanging chain / strap colour above the bag.
  let chainColor: UIColor
  /// Floor / mat colour beneath the bag.
  let floorColor: UIColor
  /// Tint of the directional key light.
  let keyLightColor: UIColor
  /// Ambient fill colour.
  let ambientColor: UIColor
  /// Distance fog colour — should match the venue's far horizon.
  let fogColor: UIColor
  let fogStartDistance: CGFloat
  let fogEndDistance: CGFloat

  static func theme(forVenueID id: String) -> BoxingSceneTheme {
    switch id {
    case "back-alley": return .backAlley
    case "underground": return .underground
    case "title-fight": return .titleFight
    default: return .backAlley
    }
  }
}

extension BoxingSceneTheme {
  static let backAlley = BoxingSceneTheme(
    bagColor: UIColor(red: 0.55, green: 0.30, blue: 0.20, alpha: 1),
    bagAccentColor: UIColor(red: 0.85, green: 0.30, blue: 0.20, alpha: 1),
    chainColor: UIColor(red: 0.40, green: 0.40, blue: 0.42, alpha: 1),
    floorColor: UIColor(red: 0.18, green: 0.16, blue: 0.14, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.85, blue: 0.55, alpha: 1),
    ambientColor: UIColor(red: 0.30, green: 0.22, blue: 0.18, alpha: 1),
    fogColor: UIColor(red: 0.12, green: 0.10, blue: 0.10, alpha: 1),
    fogStartDistance: 8,
    fogEndDistance: 22
  )

  static let underground = BoxingSceneTheme(
    bagColor: UIColor(red: 0.35, green: 0.10, blue: 0.10, alpha: 1),
    bagAccentColor: UIColor(red: 1.00, green: 0.20, blue: 0.20, alpha: 1),
    chainColor: UIColor(red: 0.30, green: 0.30, blue: 0.32, alpha: 1),
    floorColor: UIColor(red: 0.10, green: 0.08, blue: 0.10, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.30, blue: 0.30, alpha: 1),
    ambientColor: UIColor(red: 0.25, green: 0.10, blue: 0.15, alpha: 1),
    fogColor: UIColor(red: 0.08, green: 0.04, blue: 0.06, alpha: 1),
    fogStartDistance: 6,
    fogEndDistance: 18
  )

  static let titleFight = BoxingSceneTheme(
    bagColor: UIColor(red: 0.10, green: 0.10, blue: 0.18, alpha: 1),
    bagAccentColor: UIColor(red: 1.00, green: 0.85, blue: 0.30, alpha: 1),
    chainColor: UIColor(red: 0.85, green: 0.85, blue: 0.88, alpha: 1),
    floorColor: UIColor(red: 0.20, green: 0.18, blue: 0.30, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.95, blue: 0.85, alpha: 1),
    ambientColor: UIColor(red: 0.45, green: 0.40, blue: 0.55, alpha: 1),
    fogColor: UIColor(red: 0.10, green: 0.08, blue: 0.18, alpha: 1),
    fogStartDistance: 10,
    fogEndDistance: 28
  )
}
