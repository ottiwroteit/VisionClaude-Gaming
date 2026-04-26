import SceneKit
import UIKit

/// Per-venue appearance overrides for the SceneKit fruit-slash scene.
struct FruitSlashSceneTheme {
  /// Tint applied to fruit colour selection (multiplier on the fruit
  /// palette). nil = no tint, fruits render their base colour.
  let fruitTint: UIColor?
  /// Bomb body colour.
  let bombColor: UIColor
  /// Slash particle / accent colour.
  let slashAccentColor: UIColor
  /// Tint of the directional key light.
  let keyLightColor: UIColor
  /// Ambient fill colour.
  let ambientColor: UIColor
  /// Distance fog colour.
  let fogColor: UIColor
  let fogStartDistance: CGFloat
  let fogEndDistance: CGFloat

  static func theme(forVenueID id: String) -> FruitSlashSceneTheme {
    switch id {
    case "kitchen": return .kitchen
    case "orchard": return .orchard
    case "heavens-garden": return .heaven
    default: return .kitchen
    }
  }
}

extension FruitSlashSceneTheme {
  static let kitchen = FruitSlashSceneTheme(
    fruitTint: nil,
    bombColor: UIColor(white: 0.10, alpha: 1),
    slashAccentColor: UIColor(red: 1.00, green: 0.85, blue: 0.30, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.95, blue: 0.85, alpha: 1),
    ambientColor: UIColor(red: 0.55, green: 0.55, blue: 0.60, alpha: 1),
    fogColor: UIColor(white: 0.18, alpha: 1),
    fogStartDistance: 8,
    fogEndDistance: 24
  )

  static let orchard = FruitSlashSceneTheme(
    fruitTint: UIColor(red: 1.05, green: 1.00, blue: 0.85, alpha: 1),
    bombColor: UIColor(red: 0.20, green: 0.10, blue: 0.05, alpha: 1),
    slashAccentColor: UIColor(red: 0.95, green: 0.55, blue: 0.20, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.80, blue: 0.55, alpha: 1),
    ambientColor: UIColor(red: 0.45, green: 0.55, blue: 0.40, alpha: 1),
    fogColor: UIColor(red: 0.55, green: 0.55, blue: 0.40, alpha: 1),
    fogStartDistance: 10,
    fogEndDistance: 28
  )

  static let heaven = FruitSlashSceneTheme(
    fruitTint: UIColor(red: 1.10, green: 1.05, blue: 0.95, alpha: 1),
    bombColor: UIColor(red: 0.30, green: 0.20, blue: 0.45, alpha: 1),
    slashAccentColor: UIColor(red: 0.95, green: 0.85, blue: 1.00, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.95, blue: 1.00, alpha: 1),
    ambientColor: UIColor(red: 0.78, green: 0.78, blue: 0.95, alpha: 1),
    fogColor: UIColor(red: 0.85, green: 0.85, blue: 0.95, alpha: 1),
    fogStartDistance: 14,
    fogEndDistance: 36
  )
}
