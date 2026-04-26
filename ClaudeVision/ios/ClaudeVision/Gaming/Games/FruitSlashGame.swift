import Foundation
import simd

/// AI Slasher (kept on the `fruitslash` game id for backward
/// compatibility with the existing venue + dispatcher wiring).
///
/// The original spawn-one-fruit-and-flick model was redesigned per
/// user feedback: now the player wields a samurai sword that tracks
/// head movement, and stylized AI/LLM company logos (ChatGPT, Claude,
/// Gemini, Llama, Mistral, Grok, …) fall from the top of the screen.
/// Move the sword through them to slice. A few are "rogue AGI" bombs —
/// slicing those costs a life.
///
/// All gameplay rendering lives in the SpriteKit scene; this object
/// publishes the swordCommand (head-tilt) the scene reads each frame
/// plus score / lives / event callbacks the scene fires on slices.
@MainActor
final class FruitSlashGame: ObservableObject, Game {
  let id = "fruitslash"
  let title = "AI Slasher"
  let howToPlay =
    "Move your head to swing the sword. Slice every AI logo. Don't slice the AGI bombs."
  let tint: GameTint = .berry

  /// Sword tracking wants smooth continuous motion, not flicks. Lower
  /// activeThreshold keeps small intentional moves registering, but
  /// the game itself doesn't gate on flicks — head-tilt drives the
  /// sword directly via handleMotion.
  var preferredThresholds: MotionClassifier.Thresholds? {
    var t = MotionClassifier.Thresholds()
    t.activeThreshold = 0.008
    t.flickMaxDuration = 0.30
    t.maxGestureDuration = 0.55
    return t
  }

  // MARK: Published state

  @Published private(set) var score: Int = 0
  @Published private(set) var lives: Int = 3
  @Published private(set) var slices: Int = 0
  @Published private(set) var statusLine: String = "Move your head to swing the sword"
  @Published private(set) var isFinished: Bool = false

  /// Live head-tilt command in [-1, +1] for each axis. The scene
  /// reads this every frame to position the sword tip on screen.
  @Published private(set) var swordCommand: SIMD2<Float> = .zero
  /// Bumped on each slice so chrome can pop a +N badge.
  @Published private(set) var sliceEventID: Int = 0
  @Published private(set) var lastSliceWasBomb: Bool = false

  var activeModifier: VenueModifier = .default

  // MARK: Tunables

  let pointsPerLogo: Int = 15

  // MARK: Game protocol

  func start() { reset() }

  func reset() {
    score = 0
    lives = 3
    slices = 0
    isFinished = false
    statusLine = "Slash every logo. Avoid the AGI bombs."
    swordCommand = .zero
    lastSliceWasBomb = false
  }

  /// Discrete flicks are unused here — sword swing is continuous from
  /// head-tilt — but we keep the protocol method as a no-op so the
  /// engine plumbing stays uniform.
  func handle(_ event: GestureEvent) {
    // Intentionally empty.
  }

  func handleMotion(_ vector: SIMD2<Float>) {
    guard !isFinished else { return }
    // Pass-through with a small deadzone so a still head leaves the
    // sword centred. Scene clamps and maps to screen-space.
    let deadzone: Float = 0.03
    let x = abs(vector.x) < deadzone ? 0 : vector.x
    let y = abs(vector.y) < deadzone ? 0 : vector.y
    swordCommand = SIMD2<Float>(x, y)
  }

  // MARK: Scene → game callbacks

  /// Player sliced a normal AI logo.
  func didSliceLogo() {
    let bonus = max(1, Int(activeModifier.scoreMultiplier.rounded()))
    score += pointsPerLogo * bonus
    slices += 1
    sliceEventID += 1
    lastSliceWasBomb = false
    statusLine = "Sliced! \(slices) logos · \(score) pts"
  }

  /// Player sliced a rogue-AGI bomb (penalty).
  func didSliceBomb() {
    lives -= 1
    sliceEventID += 1
    lastSliceWasBomb = true
    if lives <= 0 {
      isFinished = true
      statusLine = "Sliced one too many bombs · final \(score)"
    } else {
      statusLine = "Bomb sliced! · \(lives) lives left"
    }
  }

  /// A logo escaped off the bottom of the screen without being sliced.
  func didMissLogo() {
    lives -= 1
    if lives <= 0 {
      isFinished = true
      statusLine = "Too many escaped · final \(score)"
    } else {
      statusLine = "Missed one · \(lives) lives left"
    }
  }
}
