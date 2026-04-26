import SceneKit
import UIKit

/// Per-venue appearance overrides for the SceneKit archery scene.
/// Same structure as the bowling theme — colours that the controller
/// re-binds onto its key materials and lights when the venue changes.
struct ArcherySceneTheme {
  /// Wood / shaft colour of the arrow.
  let arrowShaftColor: UIColor
  /// Tip + fletching accent colour.
  let arrowAccentColor: UIColor
  /// Outer target ring colour (the "1-point" band).
  let targetOuterColor: UIColor
  /// Mid-ring colour (the "4-point" band).
  let targetMidColor: UIColor
  /// Inner-ring colour (the "7-point" band).
  let targetInnerColor: UIColor
  /// Bullseye colour (the "10-point" centre).
  let targetBullseyeColor: UIColor
  /// Tint of the directional key light.
  let keyLightColor: UIColor
  /// Ambient fill colour.
  let ambientColor: UIColor
  /// Distance fog colour — should match the venue's far horizon so the
  /// 3D target recedes naturally into the SwiftUI venue background.
  let fogColor: UIColor
  let fogStartDistance: CGFloat
  let fogEndDistance: CGFloat

  static func theme(forVenueID id: String) -> ArcherySceneTheme {
    switch id {
    case "tundra-range": return .tundra
    case "canyon-range": return .canyon
    case "rooftop-range": return .rooftop
    case "moonlit-range": return .moonlit
    default: return .canyon
    }
  }
}

extension ArcherySceneTheme {
  /// Default canyon palette — warm golds and earth tones.
  static let canyon = ArcherySceneTheme(
    arrowShaftColor: UIColor(red: 0.65, green: 0.45, blue: 0.25, alpha: 1),
    arrowAccentColor: UIColor(red: 1.00, green: 0.85, blue: 0.30, alpha: 1),
    targetOuterColor: UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1),
    targetMidColor: UIColor(red: 0.20, green: 0.55, blue: 0.95, alpha: 1),
    targetInnerColor: UIColor(red: 1.00, green: 0.20, blue: 0.20, alpha: 1),
    targetBullseyeColor: UIColor(red: 1.00, green: 0.85, blue: 0.20, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.90, blue: 0.75, alpha: 1),
    ambientColor: UIColor(red: 0.55, green: 0.45, blue: 0.35, alpha: 1),
    fogColor: UIColor(red: 0.70, green: 0.55, blue: 0.40, alpha: 1),
    fogStartDistance: 14,
    fogEndDistance: 36
  )

  static let tundra = ArcherySceneTheme(
    arrowShaftColor: UIColor(red: 0.35, green: 0.30, blue: 0.25, alpha: 1),
    arrowAccentColor: UIColor(red: 0.65, green: 0.85, blue: 1.00, alpha: 1),
    targetOuterColor: UIColor(red: 0.92, green: 0.95, blue: 1.00, alpha: 1),
    targetMidColor: UIColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 1),
    targetInnerColor: UIColor(red: 0.85, green: 0.20, blue: 0.30, alpha: 1),
    targetBullseyeColor: UIColor(red: 1.00, green: 0.85, blue: 0.30, alpha: 1),
    keyLightColor: UIColor(red: 0.85, green: 0.95, blue: 1.00, alpha: 1),
    ambientColor: UIColor(red: 0.55, green: 0.65, blue: 0.78, alpha: 1),
    fogColor: UIColor(red: 0.78, green: 0.85, blue: 0.92, alpha: 1),
    fogStartDistance: 12,
    fogEndDistance: 32
  )

  static let rooftop = ArcherySceneTheme(
    arrowShaftColor: UIColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1),
    arrowAccentColor: UIColor(red: 1.00, green: 0.65, blue: 0.10, alpha: 1),
    targetOuterColor: UIColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1),
    targetMidColor: UIColor(red: 0.30, green: 0.55, blue: 0.85, alpha: 1),
    targetInnerColor: UIColor(red: 0.95, green: 0.25, blue: 0.30, alpha: 1),
    targetBullseyeColor: UIColor(red: 1.00, green: 0.80, blue: 0.20, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.55, blue: 0.30, alpha: 1),
    ambientColor: UIColor(red: 0.30, green: 0.25, blue: 0.40, alpha: 1),
    fogColor: UIColor(red: 0.25, green: 0.20, blue: 0.35, alpha: 1),
    fogStartDistance: 14,
    fogEndDistance: 36
  )

  static let moonlit = ArcherySceneTheme(
    arrowShaftColor: UIColor(red: 0.28, green: 0.30, blue: 0.40, alpha: 1),
    arrowAccentColor: UIColor(red: 0.55, green: 0.75, blue: 1.00, alpha: 1),
    targetOuterColor: UIColor(red: 0.85, green: 0.88, blue: 0.95, alpha: 1),
    targetMidColor: UIColor(red: 0.15, green: 0.30, blue: 0.65, alpha: 1),
    targetInnerColor: UIColor(red: 0.85, green: 0.20, blue: 0.45, alpha: 1),
    targetBullseyeColor: UIColor(red: 0.95, green: 0.85, blue: 0.55, alpha: 1),
    keyLightColor: UIColor(red: 0.65, green: 0.75, blue: 1.00, alpha: 1),
    ambientColor: UIColor(red: 0.20, green: 0.25, blue: 0.45, alpha: 1),
    fogColor: UIColor(red: 0.10, green: 0.12, blue: 0.25, alpha: 1),
    fogStartDistance: 10,
    fogEndDistance: 28
  )
}
