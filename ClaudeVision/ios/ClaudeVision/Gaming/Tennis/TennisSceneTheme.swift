import SceneKit
import UIKit

/// Per-venue appearance overrides for the SceneKit tennis scene.
struct TennisSceneTheme {
  let courtColor: UIColor
  let courtLineColor: UIColor
  let netColor: UIColor
  let ballColor: UIColor
  let opponentColor: UIColor
  let keyLightColor: UIColor
  let ambientColor: UIColor
  let fogColor: UIColor
  let fogStartDistance: CGFloat
  let fogEndDistance: CGFloat

  static func theme(forVenueID id: String) -> TennisSceneTheme {
    switch id {
    case "rooftop": return .rooftop
    case "cherry-park": return .cherry
    case "grand-arena": return .grandArena
    default: return .rooftop
    }
  }
}

extension TennisSceneTheme {
  static let rooftop = TennisSceneTheme(
    courtColor: UIColor(red: 0.20, green: 0.55, blue: 0.30, alpha: 1),
    courtLineColor: UIColor.white,
    netColor: UIColor(white: 0.92, alpha: 1),
    ballColor: UIColor(red: 0.85, green: 1.00, blue: 0.30, alpha: 1),
    opponentColor: UIColor(red: 0.15, green: 0.20, blue: 0.55, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.95, blue: 0.85, alpha: 1),
    ambientColor: UIColor(red: 0.45, green: 0.55, blue: 0.55, alpha: 1),
    fogColor: UIColor(red: 0.25, green: 0.35, blue: 0.40, alpha: 1),
    fogStartDistance: 14,
    fogEndDistance: 36
  )

  static let cherry = TennisSceneTheme(
    courtColor: UIColor(red: 0.65, green: 0.35, blue: 0.45, alpha: 1),
    courtLineColor: UIColor(white: 0.95, alpha: 1),
    netColor: UIColor(white: 0.95, alpha: 1),
    ballColor: UIColor(red: 1.00, green: 0.85, blue: 0.30, alpha: 1),
    opponentColor: UIColor(red: 0.45, green: 0.25, blue: 0.55, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.85, blue: 0.85, alpha: 1),
    ambientColor: UIColor(red: 0.85, green: 0.60, blue: 0.70, alpha: 1),
    fogColor: UIColor(red: 0.95, green: 0.78, blue: 0.85, alpha: 1),
    fogStartDistance: 16,
    fogEndDistance: 40
  )

  static let grandArena = TennisSceneTheme(
    courtColor: UIColor(red: 0.10, green: 0.30, blue: 0.55, alpha: 1),
    courtLineColor: UIColor.white,
    netColor: UIColor(white: 0.95, alpha: 1),
    ballColor: UIColor(red: 0.85, green: 1.00, blue: 0.20, alpha: 1),
    opponentColor: UIColor(red: 0.95, green: 0.20, blue: 0.20, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.95, blue: 1.00, alpha: 1),
    ambientColor: UIColor(red: 0.55, green: 0.55, blue: 0.65, alpha: 1),
    fogColor: UIColor(red: 0.18, green: 0.20, blue: 0.30, alpha: 1),
    fogStartDistance: 18,
    fogEndDistance: 48
  )
}
