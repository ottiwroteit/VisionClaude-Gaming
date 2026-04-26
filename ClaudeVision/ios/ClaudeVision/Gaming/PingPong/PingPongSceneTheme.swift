import SceneKit
import UIKit

/// Per-venue appearance overrides for the SceneKit ping-pong scene.
struct PingPongSceneTheme {
  let tableColor: UIColor
  let tableLineColor: UIColor
  let netColor: UIColor
  let ballColor: UIColor
  let playerPaddleColor: UIColor
  let cpuPaddleColor: UIColor
  let keyLightColor: UIColor
  let ambientColor: UIColor
  let fogColor: UIColor
  let fogStartDistance: CGFloat
  let fogEndDistance: CGFloat

  static func theme(forVenueID id: String) -> PingPongSceneTheme {
    switch id {
    case "basement": return .basement
    case "tokyo-alley": return .tokyoAlley
    case "cyber-arena": return .cyberArena
    default: return .basement
    }
  }
}

extension PingPongSceneTheme {
  static let basement = PingPongSceneTheme(
    tableColor: UIColor(red: 0.20, green: 0.40, blue: 0.55, alpha: 1),
    tableLineColor: UIColor.white,
    netColor: UIColor(white: 0.85, alpha: 1),
    ballColor: UIColor.white,
    playerPaddleColor: UIColor(red: 0.85, green: 0.18, blue: 0.18, alpha: 1),
    cpuPaddleColor: UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.95, blue: 0.85, alpha: 1),
    ambientColor: UIColor(red: 0.35, green: 0.40, blue: 0.45, alpha: 1),
    fogColor: UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1),
    fogStartDistance: 8,
    fogEndDistance: 24
  )

  static let tokyoAlley = PingPongSceneTheme(
    tableColor: UIColor(red: 0.10, green: 0.30, blue: 0.45, alpha: 1),
    tableLineColor: UIColor(red: 0.95, green: 0.85, blue: 0.30, alpha: 1),
    netColor: UIColor(white: 0.95, alpha: 1),
    ballColor: UIColor(red: 1.00, green: 0.55, blue: 0.20, alpha: 1),
    playerPaddleColor: UIColor(red: 0.95, green: 0.20, blue: 0.45, alpha: 1),
    cpuPaddleColor: UIColor(red: 0.20, green: 0.20, blue: 0.40, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.55, blue: 0.40, alpha: 1),
    ambientColor: UIColor(red: 0.40, green: 0.20, blue: 0.45, alpha: 1),
    fogColor: UIColor(red: 0.18, green: 0.10, blue: 0.30, alpha: 1),
    fogStartDistance: 10,
    fogEndDistance: 28
  )

  static let cyberArena = PingPongSceneTheme(
    tableColor: UIColor(red: 0.05, green: 0.05, blue: 0.18, alpha: 1),
    tableLineColor: UIColor(red: 0.30, green: 0.95, blue: 1.00, alpha: 1),
    netColor: UIColor(red: 0.65, green: 0.20, blue: 0.95, alpha: 1),
    ballColor: UIColor(red: 0.85, green: 1.00, blue: 0.30, alpha: 1),
    playerPaddleColor: UIColor(red: 0.30, green: 0.95, blue: 1.00, alpha: 1),
    cpuPaddleColor: UIColor(red: 0.95, green: 0.20, blue: 0.85, alpha: 1),
    keyLightColor: UIColor(red: 0.85, green: 0.55, blue: 1.00, alpha: 1),
    ambientColor: UIColor(red: 0.20, green: 0.10, blue: 0.40, alpha: 1),
    fogColor: UIColor(red: 0.05, green: 0.02, blue: 0.20, alpha: 1),
    fogStartDistance: 12,
    fogEndDistance: 32
  )
}
