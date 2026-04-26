import Foundation
import simd

/// Firefox — first-person flight combat in the spirit of the 1984
/// Atari arcade game. Player pilots a fighter through the sky;
/// enemy aircraft spawn ahead and the player shoots them down with
/// missiles. Camera is locked to the cockpit POV; the world rotates
/// around it to convey banking and pitch.
///
/// Input:
/// - Continuous head-tilt LEFT/RIGHT  → bank (roll) the aircraft.
/// - Continuous head-tilt UP/DOWN     → pitch (climb / dive).
/// - Chin UP flick                    → fire missile.
@MainActor
final class FirefoxGame: ObservableObject, Game {
  let id = "firefox"
  let title = "Meta Firefox"
  let howToPlay = "Tilt to bank/pitch. Chin UP to fire. Shoot down enemy fighters."
  let tint: GameTint = .ring

  /// Firefox needs continuous tilt for steering AND fast flicks for
  /// firing — same threshold profile as the other flick-driven games
  /// with the latency cutoff that prevents post-flick settling lag.
  var preferredThresholds: MotionClassifier.Thresholds? {
    var t = MotionClassifier.Thresholds()
    t.activeThreshold = 0.012
    t.flickMaxDuration = 0.28
    t.maxGestureDuration = 0.55
    return t
  }

  // MARK: Published state

  @Published private(set) var score: Int = 0
  @Published private(set) var lives: Int = 3
  @Published private(set) var enemiesDowned: Int = 0
  @Published private(set) var statusLine: String = "Eyes up — fighters incoming"
  @Published private(set) var isFinished: Bool = false

  /// Steering command in [-1, +1] for each axis. X = bank (positive
  /// = bank right), Y = pitch (positive = nose up). Updated by
  /// handleMotion every frame from head-tilt.
  @Published private(set) var bankCommand: Float = 0
  @Published private(set) var pitchCommand: Float = 0
  /// Bumped each time the player commits a missile fire.
  @Published private(set) var fireEventID: Int = 0
  /// Bumped when the player TAKES damage (an enemy passed too close
  /// or hit the player). Drives chrome flash + camera shake.
  @Published private(set) var hitEventID: Int = 0

  var activeModifier: VenueModifier = .default

  // MARK: Tunables exposed to the scene

  /// Score per enemy downed; the scene tells us when one's destroyed.
  let scorePerKill: Int = 100

  // MARK: Game protocol

  func start() { reset() }

  func reset() {
    score = 0
    lives = 3
    enemiesDowned = 0
    bankCommand = 0
    pitchCommand = 0
    isFinished = false
    statusLine = "Eyes up — fighters incoming"
  }

  func handle(_ event: GestureEvent) {
    guard !isFinished, event.kind == .flick else { return }
    if event.direction == .up {
      fireEventID += 1
    }
  }

  func handleMotion(_ vector: SIMD2<Float>) {
    guard !isFinished else { return }
    let deadzone: Float = 0.04
    let lateral = vector.x
    let vertical = vector.y
    bankCommand = abs(lateral) < deadzone ? 0 : max(-1, min(1, lateral * 3.0))
    pitchCommand = abs(vertical) < deadzone ? 0 : max(-1, min(1, vertical * 3.0))
  }

  // MARK: Scene → game callbacks

  func didDownEnemy() {
    let bonus = max(1, Int(activeModifier.scoreMultiplier.rounded()))
    score += scorePerKill * bonus
    enemiesDowned += 1
    statusLine = "Splash one · \(enemiesDowned) downed · score \(score)"
  }

  func didTakeHit() {
    lives -= 1
    hitEventID += 1
    if lives <= 0 {
      isFinished = true
      statusLine = "Aircraft destroyed · final \(score)"
    } else {
      statusLine = "Took a hit · \(lives) lives left"
    }
  }
}
