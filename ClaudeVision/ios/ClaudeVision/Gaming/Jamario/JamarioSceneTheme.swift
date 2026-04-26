import SpriteKit
import UIKit

/// Per-venue palette for the SpriteKit Jamario scene. The level
/// generator + scene controller read these to colour the procedurally-
/// drawn ground, platforms, sky, mountains, clouds, player, enemies,
/// and coins. Same approach as the SceneKit themes — no asset files,
/// just colour tokens applied to primitive shapes.
struct JamarioSceneTheme {
  /// Sky gradient — top of frame.
  let skyTop: UIColor
  /// Sky gradient — bottom of frame (just above the horizon).
  let skyBottom: UIColor
  /// Distant mountain silhouette colour.
  let mountainColor: UIColor
  /// Mid-distance hill / brush colour behind the playfield.
  let hillColor: UIColor
  /// Cloud colour.
  let cloudColor: UIColor
  /// Top surface of the ground (grass / sand).
  let groundTopColor: UIColor
  /// Body of the ground beneath the top surface.
  let groundBodyColor: UIColor
  /// Floating platform body (stone / wood).
  let platformColor: UIColor
  /// Player body colour (Jamario himself).
  let playerColor: UIColor
  /// Player accent (overalls / cap stripe).
  let playerAccentColor: UIColor
  /// Goomba enemy colour.
  let enemyColor: UIColor
  /// Coin disc colour.
  let coinColor: UIColor
  /// Coin highlight glint colour.
  let coinGlintColor: UIColor

  static func theme(forVenueID id: String) -> JamarioSceneTheme {
    switch id {
    case "jamario-kingdom": return .jamarioKingdom
    case "shifting-sands": return .shiftingSands
    case "cloud-tops": return .cloudTops
    default: return .jamarioKingdom
    }
  }
}

extension JamarioSceneTheme {
  /// Starter palette — bright blue sky, green hills, red player,
  /// brown goombas. Classic side-scroller lookbook so it reads as a
  /// platformer immediately.
  static let jamarioKingdom = JamarioSceneTheme(
    skyTop: UIColor(red: 0.40, green: 0.70, blue: 1.00, alpha: 1),
    skyBottom: UIColor(red: 0.75, green: 0.92, blue: 1.00, alpha: 1),
    mountainColor: UIColor(red: 0.18, green: 0.40, blue: 0.20, alpha: 1),
    hillColor: UIColor(red: 0.30, green: 0.60, blue: 0.30, alpha: 1),
    cloudColor: UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.95),
    groundTopColor: UIColor(red: 0.40, green: 0.78, blue: 0.30, alpha: 1),
    groundBodyColor: UIColor(red: 0.62, green: 0.40, blue: 0.20, alpha: 1),
    platformColor: UIColor(red: 0.78, green: 0.55, blue: 0.32, alpha: 1),
    playerColor: UIColor(red: 0.95, green: 0.20, blue: 0.20, alpha: 1),
    playerAccentColor: UIColor(red: 0.20, green: 0.30, blue: 0.85, alpha: 1),
    enemyColor: UIColor(red: 0.55, green: 0.30, blue: 0.18, alpha: 1),
    coinColor: UIColor(red: 1.00, green: 0.85, blue: 0.20, alpha: 1),
    coinGlintColor: UIColor(red: 1.00, green: 1.00, blue: 0.85, alpha: 1)
  )

  static let shiftingSands = JamarioSceneTheme(
    skyTop: UIColor(red: 0.95, green: 0.65, blue: 0.30, alpha: 1),
    skyBottom: UIColor(red: 1.00, green: 0.85, blue: 0.55, alpha: 1),
    mountainColor: UIColor(red: 0.55, green: 0.30, blue: 0.18, alpha: 1),
    hillColor: UIColor(red: 0.85, green: 0.55, blue: 0.30, alpha: 1),
    cloudColor: UIColor(red: 1.00, green: 0.95, blue: 0.85, alpha: 0.85),
    groundTopColor: UIColor(red: 0.95, green: 0.78, blue: 0.45, alpha: 1),
    groundBodyColor: UIColor(red: 0.65, green: 0.40, blue: 0.20, alpha: 1),
    platformColor: UIColor(red: 0.85, green: 0.65, blue: 0.40, alpha: 1),
    playerColor: UIColor(red: 0.20, green: 0.35, blue: 0.85, alpha: 1),
    playerAccentColor: UIColor(red: 0.95, green: 0.20, blue: 0.20, alpha: 1),
    enemyColor: UIColor(red: 0.45, green: 0.25, blue: 0.18, alpha: 1),
    coinColor: UIColor(red: 1.00, green: 0.80, blue: 0.20, alpha: 1),
    coinGlintColor: UIColor(red: 1.00, green: 1.00, blue: 0.85, alpha: 1)
  )

  static let cloudTops = JamarioSceneTheme(
    skyTop: UIColor(red: 0.45, green: 0.30, blue: 0.65, alpha: 1),
    skyBottom: UIColor(red: 0.85, green: 0.65, blue: 0.95, alpha: 1),
    mountainColor: UIColor(red: 0.30, green: 0.20, blue: 0.55, alpha: 1),
    hillColor: UIColor(red: 0.65, green: 0.40, blue: 0.85, alpha: 1),
    cloudColor: UIColor(red: 1.00, green: 0.95, blue: 1.00, alpha: 0.95),
    groundTopColor: UIColor(red: 0.95, green: 0.95, blue: 1.00, alpha: 1),
    groundBodyColor: UIColor(red: 0.55, green: 0.55, blue: 0.85, alpha: 1),
    platformColor: UIColor(red: 0.85, green: 0.85, blue: 1.00, alpha: 1),
    playerColor: UIColor(red: 0.95, green: 0.30, blue: 0.55, alpha: 1),
    playerAccentColor: UIColor(red: 0.95, green: 0.85, blue: 0.30, alpha: 1),
    enemyColor: UIColor(red: 0.55, green: 0.30, blue: 0.55, alpha: 1),
    coinColor: UIColor(red: 1.00, green: 0.85, blue: 0.30, alpha: 1),
    coinGlintColor: UIColor(red: 1.00, green: 1.00, blue: 0.95, alpha: 1)
  )
}
