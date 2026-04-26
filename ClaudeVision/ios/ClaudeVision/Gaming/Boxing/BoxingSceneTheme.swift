import SceneKit
import UIKit

/// Per-venue appearance overrides for the SceneKit boxing scene. The
/// scene is first-person — the player faces a 3D boxer opponent and
/// can see their own gloves at the bottom of the frame — so the theme
/// drives the opponent's body, trunks, gloves, and the player's own
/// gloves, plus the lighting that sells the venue.
struct BoxingSceneTheme {
  /// Opponent's torso/body colour.
  let bodyColor: UIColor
  /// Opponent's trunks colour (the wider band around the hips).
  let trunksColor: UIColor
  /// Opponent's boxing-glove colour.
  let opponentGloveColor: UIColor
  /// Player's own (first-person) glove colour, visible at the bottom
  /// of the frame.
  let playerGloveColor: UIColor
  /// Floor / mat colour beneath the action.
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
    bodyColor: UIColor(red: 0.78, green: 0.55, blue: 0.40, alpha: 1),
    trunksColor: UIColor(red: 0.30, green: 0.18, blue: 0.12, alpha: 1),
    opponentGloveColor: UIColor(red: 0.80, green: 0.20, blue: 0.18, alpha: 1),
    playerGloveColor: UIColor(red: 0.20, green: 0.30, blue: 0.95, alpha: 1),
    floorColor: UIColor(red: 0.18, green: 0.16, blue: 0.14, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.85, blue: 0.55, alpha: 1),
    ambientColor: UIColor(red: 0.30, green: 0.22, blue: 0.18, alpha: 1),
    fogColor: UIColor(red: 0.12, green: 0.10, blue: 0.10, alpha: 1),
    fogStartDistance: 8,
    fogEndDistance: 22
  )

  static let underground = BoxingSceneTheme(
    bodyColor: UIColor(red: 0.62, green: 0.45, blue: 0.32, alpha: 1),
    trunksColor: UIColor(red: 0.45, green: 0.05, blue: 0.10, alpha: 1),
    opponentGloveColor: UIColor(red: 1.00, green: 0.20, blue: 0.20, alpha: 1),
    playerGloveColor: UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1),
    floorColor: UIColor(red: 0.10, green: 0.08, blue: 0.10, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.30, blue: 0.30, alpha: 1),
    ambientColor: UIColor(red: 0.25, green: 0.10, blue: 0.15, alpha: 1),
    fogColor: UIColor(red: 0.08, green: 0.04, blue: 0.06, alpha: 1),
    fogStartDistance: 6,
    fogEndDistance: 18
  )

  static let titleFight = BoxingSceneTheme(
    bodyColor: UIColor(red: 0.70, green: 0.50, blue: 0.38, alpha: 1),
    trunksColor: UIColor(red: 0.10, green: 0.10, blue: 0.18, alpha: 1),
    opponentGloveColor: UIColor(red: 1.00, green: 0.85, blue: 0.30, alpha: 1),
    playerGloveColor: UIColor(red: 0.20, green: 0.30, blue: 0.95, alpha: 1),
    floorColor: UIColor(red: 0.22, green: 0.20, blue: 0.32, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.95, blue: 0.85, alpha: 1),
    ambientColor: UIColor(red: 0.45, green: 0.40, blue: 0.55, alpha: 1),
    fogColor: UIColor(red: 0.10, green: 0.08, blue: 0.18, alpha: 1),
    fogStartDistance: 10,
    fogEndDistance: 28
  )
}
