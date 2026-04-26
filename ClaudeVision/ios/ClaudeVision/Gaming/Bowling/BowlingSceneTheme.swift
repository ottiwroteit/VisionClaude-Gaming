import SceneKit
import UIKit

/// Per-venue appearance overrides for the SceneKit bowling scene. Six
/// presets line up with the six bowling venues defined in
/// `BowlingVenues.swift`. Anything not listed here (pin geometry, ball
/// shape, lane dimensions) is venue-independent.
struct BowlingSceneTheme {
  /// Wood / surface colour of the lane plank.
  let laneColor: UIColor
  /// Subtle stripe colour overlaid on the lane (boards, oil pattern).
  let laneStripeColor: UIColor
  /// Side-channel gutter colour.
  let gutterColor: UIColor
  /// Pin body main colour (white in regulation; tinted in themed venues).
  let pinBodyColor: UIColor
  /// Pin neck stripe / accent — the red ring on a regulation pin.
  let pinAccentColor: UIColor
  /// Default ball colour (overridden when the player picks a skin).
  let ballColor: UIColor
  /// Tint of the directional key light. Drives mood more than geometry.
  let keyLightColor: UIColor
  /// Ambient fill — sets the floor of brightness in shadowed areas.
  let ambientColor: UIColor
  /// Distance fog colour. Should match the venue's far-horizon tone so
  /// the lane appears to recede into the background art behind the SCNView.
  let fogColor: UIColor
  /// Fog start distance in scene units. Increase for a clearer back wall,
  /// decrease for a more dreamy, out-of-focus pin deck.
  let fogStartDistance: CGFloat
  let fogEndDistance: CGFloat
  /// Particle accent for strike fireworks and ball trails.
  let accentParticleColor: UIColor

  /// Look up a theme by venue id. Falls back to the neon starter venue
  /// for unknown ids so a missing venue can never crash the scene.
  static func theme(forVenueID id: String) -> BowlingSceneTheme {
    switch id {
    case "neon-lanes": return .neon
    case "tropical-island": return .tropical
    case "sunset-strip": return .sunset
    case "desert-dunes": return .desert
    case "jungle-temple": return .jungle
    case "dragon-shrine": return .dragon
    default: return .neon
    }
  }
}

extension BowlingSceneTheme {
  static let neon = BowlingSceneTheme(
    laneColor: UIColor(red: 0.18, green: 0.10, blue: 0.30, alpha: 1),
    laneStripeColor: UIColor(red: 1.00, green: 0.30, blue: 0.85, alpha: 1),
    gutterColor: UIColor(red: 0.05, green: 0.02, blue: 0.18, alpha: 1),
    pinBodyColor: UIColor(red: 0.98, green: 0.95, blue: 1.00, alpha: 1),
    pinAccentColor: UIColor(red: 1.00, green: 0.20, blue: 0.55, alpha: 1),
    ballColor: UIColor(red: 0.10, green: 0.78, blue: 1.00, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.55, blue: 1.00, alpha: 1),
    ambientColor: UIColor(red: 0.30, green: 0.20, blue: 0.55, alpha: 1),
    fogColor: UIColor(red: 0.10, green: 0.04, blue: 0.25, alpha: 1),
    fogStartDistance: 12,
    fogEndDistance: 38,
    accentParticleColor: UIColor(red: 1.00, green: 0.30, blue: 0.85, alpha: 1)
  )

  static let tropical = BowlingSceneTheme(
    laneColor: UIColor(red: 0.92, green: 0.78, blue: 0.55, alpha: 1),
    laneStripeColor: UIColor(red: 0.78, green: 0.60, blue: 0.32, alpha: 1),
    gutterColor: UIColor(red: 0.12, green: 0.45, blue: 0.55, alpha: 1),
    pinBodyColor: UIColor(red: 1.00, green: 0.99, blue: 0.95, alpha: 1),
    pinAccentColor: UIColor(red: 0.95, green: 0.30, blue: 0.30, alpha: 1),
    ballColor: UIColor(red: 0.20, green: 0.55, blue: 0.85, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.96, blue: 0.85, alpha: 1),
    ambientColor: UIColor(red: 0.55, green: 0.78, blue: 0.85, alpha: 1),
    fogColor: UIColor(red: 0.55, green: 0.85, blue: 0.92, alpha: 1),
    fogStartDistance: 18,
    fogEndDistance: 48,
    accentParticleColor: UIColor(red: 1.00, green: 0.85, blue: 0.40, alpha: 1)
  )

  static let sunset = BowlingSceneTheme(
    laneColor: UIColor(red: 0.65, green: 0.20, blue: 0.45, alpha: 1),
    laneStripeColor: UIColor(red: 1.00, green: 0.50, blue: 0.40, alpha: 1),
    gutterColor: UIColor(red: 0.30, green: 0.05, blue: 0.30, alpha: 1),
    pinBodyColor: UIColor(red: 1.00, green: 0.92, blue: 0.85, alpha: 1),
    pinAccentColor: UIColor(red: 0.95, green: 0.20, blue: 0.45, alpha: 1),
    ballColor: UIColor(red: 0.95, green: 0.30, blue: 0.55, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.65, blue: 0.55, alpha: 1),
    ambientColor: UIColor(red: 0.55, green: 0.20, blue: 0.40, alpha: 1),
    fogColor: UIColor(red: 0.65, green: 0.18, blue: 0.40, alpha: 1),
    fogStartDistance: 12,
    fogEndDistance: 36,
    accentParticleColor: UIColor(red: 1.00, green: 0.78, blue: 0.30, alpha: 1)
  )

  static let desert = BowlingSceneTheme(
    laneColor: UIColor(red: 0.85, green: 0.65, blue: 0.34, alpha: 1),
    laneStripeColor: UIColor(red: 0.95, green: 0.78, blue: 0.50, alpha: 1),
    gutterColor: UIColor(red: 0.55, green: 0.35, blue: 0.18, alpha: 1),
    pinBodyColor: UIColor(red: 1.00, green: 0.96, blue: 0.88, alpha: 1),
    pinAccentColor: UIColor(red: 0.85, green: 0.30, blue: 0.20, alpha: 1),
    ballColor: UIColor(red: 0.55, green: 0.32, blue: 0.18, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.92, blue: 0.78, alpha: 1),
    ambientColor: UIColor(red: 0.85, green: 0.70, blue: 0.50, alpha: 1),
    fogColor: UIColor(red: 0.95, green: 0.78, blue: 0.50, alpha: 1),
    fogStartDistance: 16,
    fogEndDistance: 44,
    accentParticleColor: UIColor(red: 1.00, green: 0.85, blue: 0.45, alpha: 1)
  )

  static let jungle = BowlingSceneTheme(
    laneColor: UIColor(red: 0.20, green: 0.32, blue: 0.18, alpha: 1),
    laneStripeColor: UIColor(red: 0.45, green: 0.65, blue: 0.30, alpha: 1),
    gutterColor: UIColor(red: 0.05, green: 0.18, blue: 0.10, alpha: 1),
    pinBodyColor: UIColor(red: 0.92, green: 0.95, blue: 0.85, alpha: 1),
    pinAccentColor: UIColor(red: 0.85, green: 0.30, blue: 0.20, alpha: 1),
    ballColor: UIColor(red: 0.15, green: 0.40, blue: 0.25, alpha: 1),
    keyLightColor: UIColor(red: 0.85, green: 1.00, blue: 0.78, alpha: 1),
    ambientColor: UIColor(red: 0.25, green: 0.45, blue: 0.30, alpha: 1),
    fogColor: UIColor(red: 0.10, green: 0.30, blue: 0.18, alpha: 1),
    fogStartDistance: 12,
    fogEndDistance: 32,
    accentParticleColor: UIColor(red: 0.85, green: 1.00, blue: 0.35, alpha: 1)
  )

  static let dragon = BowlingSceneTheme(
    laneColor: UIColor(red: 0.40, green: 0.05, blue: 0.10, alpha: 1),
    laneStripeColor: UIColor(red: 1.00, green: 0.55, blue: 0.20, alpha: 1),
    gutterColor: UIColor(red: 0.10, green: 0.02, blue: 0.04, alpha: 1),
    pinBodyColor: UIColor(red: 1.00, green: 0.95, blue: 0.85, alpha: 1),
    pinAccentColor: UIColor(red: 0.95, green: 0.20, blue: 0.10, alpha: 1),
    ballColor: UIColor(red: 0.85, green: 0.10, blue: 0.10, alpha: 1),
    keyLightColor: UIColor(red: 1.00, green: 0.55, blue: 0.30, alpha: 1),
    ambientColor: UIColor(red: 0.55, green: 0.10, blue: 0.10, alpha: 1),
    fogColor: UIColor(red: 0.30, green: 0.05, blue: 0.08, alpha: 1),
    fogStartDistance: 10,
    fogEndDistance: 30,
    accentParticleColor: UIColor(red: 1.00, green: 0.55, blue: 0.15, alpha: 1)
  )
}

/// Maps a `BowlingGame.BallSkin` to a UIColor used for the SceneKit ball
/// material. Kept separate from the venue theme so per-roll skin choice
/// composes cleanly: the player's selected skin always wins over the
/// theme's default ball color.
extension BowlingGame.BallSkin {
  var sceneColor: UIColor {
    switch self {
    case .classic: return UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)
    case .skull: return UIColor(red: 0.95, green: 0.95, blue: 0.92, alpha: 1)
    case .superhero: return UIColor(red: 0.10, green: 0.20, blue: 0.65, alpha: 1)
    case .eightBall: return UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)
    case .basketball: return UIColor(red: 0.95, green: 0.45, blue: 0.15, alpha: 1)
    case .soccer: return UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)
    case .fire: return UIColor(red: 1.00, green: 0.40, blue: 0.10, alpha: 1)
    }
  }
}
