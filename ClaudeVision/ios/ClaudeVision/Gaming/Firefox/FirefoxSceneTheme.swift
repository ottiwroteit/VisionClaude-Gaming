import SceneKit
import UIKit

/// Per-venue palette for the Firefox flight scene. Drives sky, ground
/// plane, enemy fighter colour, missile colour, lighting, fog.
struct FirefoxSceneTheme {
  let skyColor: UIColor
  let horizonColor: UIColor
  let groundColor: UIColor
  let cloudColor: UIColor
  let enemyColor: UIColor
  let missileColor: UIColor
  let keyLightColor: UIColor
  let ambientColor: UIColor
  let fogColor: UIColor
  let fogStartDistance: CGFloat
  let fogEndDistance: CGFloat

  static func theme(forVenueID id: String) -> FirefoxSceneTheme {
    switch id {
    case "arctic-run": return .arctic
    case "midnight-strike": return .midnight
    case "desert-dogfight": return .desert
    default: return .arctic
    }
  }
}

extension FirefoxSceneTheme {
  /// Default cold-sky palette for the starter "Arctic Run" venue.
  static let arctic = FirefoxSceneTheme(
    skyColor: UIColor(red: 0.55, green: 0.78, blue: 0.95, alpha: 1),
    horizonColor: UIColor(red: 0.85, green: 0.92, blue: 0.98, alpha: 1),
    groundColor: UIColor(red: 0.92, green: 0.95, blue: 0.98, alpha: 1),
    cloudColor: UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),
    enemyColor: UIColor(red: 0.30, green: 0.30, blue: 0.40, alpha: 1),
    missileColor: UIColor(red: 1.00, green: 0.85, blue: 0.30, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.95, blue: 0.95, alpha: 1),
    ambientColor: UIColor(red: 0.65, green: 0.75, blue: 0.85, alpha: 1),
    fogColor: UIColor(red: 0.78, green: 0.88, blue: 0.95, alpha: 1),
    fogStartDistance: 30,
    fogEndDistance: 140
  )

  static let midnight = FirefoxSceneTheme(
    skyColor: UIColor(red: 0.05, green: 0.08, blue: 0.18, alpha: 1),
    horizonColor: UIColor(red: 0.10, green: 0.12, blue: 0.30, alpha: 1),
    groundColor: UIColor(red: 0.05, green: 0.05, blue: 0.10, alpha: 1),
    cloudColor: UIColor(red: 0.30, green: 0.30, blue: 0.45, alpha: 0.85),
    enemyColor: UIColor(red: 0.60, green: 0.10, blue: 0.10, alpha: 1),
    missileColor: UIColor(red: 0.30, green: 0.95, blue: 1.00, alpha: 1),
    keyLightColor: UIColor(red: 0.55, green: 0.60, blue: 0.85, alpha: 1),
    ambientColor: UIColor(red: 0.15, green: 0.18, blue: 0.30, alpha: 1),
    fogColor: UIColor(red: 0.04, green: 0.05, blue: 0.15, alpha: 1),
    fogStartDistance: 25,
    fogEndDistance: 110
  )

  static let desert = FirefoxSceneTheme(
    skyColor: UIColor(red: 0.95, green: 0.65, blue: 0.30, alpha: 1),
    horizonColor: UIColor(red: 1.00, green: 0.85, blue: 0.55, alpha: 1),
    groundColor: UIColor(red: 0.85, green: 0.55, blue: 0.30, alpha: 1),
    cloudColor: UIColor(red: 1.00, green: 0.95, blue: 0.85, alpha: 0.85),
    enemyColor: UIColor(red: 0.25, green: 0.25, blue: 0.30, alpha: 1),
    missileColor: UIColor(red: 1.00, green: 0.30, blue: 0.30, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.85, blue: 0.65, alpha: 1),
    ambientColor: UIColor(red: 0.65, green: 0.50, blue: 0.40, alpha: 1),
    fogColor: UIColor(red: 0.85, green: 0.65, blue: 0.40, alpha: 1),
    fogStartDistance: 35,
    fogEndDistance: 150
  )
}
