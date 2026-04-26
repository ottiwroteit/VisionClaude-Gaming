import Foundation

@MainActor
final class BowlingGame: ObservableObject, Game {
  let id = "bowling"
  let title = "Meta Bowling"
  let howToPlay = "Flick your chin up to roll. Harder flick = more power."
  let tint: GameTint = .accent

  /// Bowling should feel gentle on the neck — drop the activeThreshold
  /// well below the default (0.012) so a soft chin-tilt registers, and
  /// keep flickMaxDuration long enough that even a slow, deliberate
  /// motion still classifies as a flick rather than a swing.
  var preferredThresholds: MotionClassifier.Thresholds? {
    var t = MotionClassifier.Thresholds()
    t.activeThreshold = 0.005
    t.flickMaxDuration = 0.5
    return t
  }

  @Published private(set) var score: Int = 0
  @Published private(set) var frame: Int = 1
  @Published private(set) var ballInFrame: Int = 1
  @Published private(set) var pinsRemaining: Int = 10
  @Published private(set) var lastRoll: Int = 0
  @Published private(set) var statusLine: String = "Frame 1 · Ready to bowl"
  @Published private(set) var isFinished: Bool = false
  var activeModifier: VenueModifier = .default

  private let totalFrames = 10

  func start() { reset() }

  func reset() {
    score = 0
    frame = 1
    ballInFrame = 1
    pinsRemaining = 10
    lastRoll = 0
    isFinished = false
    statusLine = "Frame 1 · Flick chin up to bowl"
  }

  func handle(_ event: GestureEvent) {
    guard !isFinished else { return }
    guard event.kind == .flick, event.direction == .up else { return }

    let power = event.magnitude
    let knocked = pinsKnocked(power: power, remaining: pinsRemaining)
    pinsRemaining -= knocked
    let points = Int((Double(knocked) * activeModifier.scoreMultiplier).rounded())
    score += points
    lastRoll = knocked

    let strike = ballInFrame == 1 && knocked == 10
    let spare = ballInFrame == 2 && pinsRemaining == 0

    if strike {
      statusLine = "STRIKE! \(knocked) pins · total \(score)"
      GameAudio.shared.speak("Strike! Total \(score).")
      advanceFrame()
    } else if ballInFrame == 2 || spare {
      statusLine = (spare ? "Spare! " : "") + "Rolled \(knocked) · total \(score)"
      GameAudio.shared.speak(
        (spare ? "Spare. " : "") + "\(knocked) pins. Total \(score)."
      )
      advanceFrame()
    } else {
      ballInFrame = 2
      statusLine = "Rolled \(knocked) · \(pinsRemaining) left — flick again"
      GameAudio.shared.speak("\(knocked) pins. \(pinsRemaining) left.")
    }
  }

  private func advanceFrame() {
    if frame >= totalFrames {
      isFinished = true
      statusLine = "Game over · final score \(score)"
      GameAudio.shared.speak("Game over. Final score \(score).")
      return
    }
    frame += 1
    ballInFrame = 1
    pinsRemaining = 10
    statusLine = "Frame \(frame) · Flick chin up to bowl"
  }

  /// Soft physics: low power rolls gutter, mid hits 4-7 pins, high flick is
  /// a strike candidate. Adds a small random jitter so every roll feels
  /// different without being unfair. Venue modifiers adjust the curve:
  /// stickyLane forgives weak rolls; higher difficulty = less generous jitter.
  private func pinsKnocked(power: Float, remaining: Int) -> Int {
    let clamped = max(0, min(1, power))
    let sticky = activeModifier.effect == .stickyLane ? Float(0.15) : 0
    let adjusted = min(1, clamped + sticky)
    let base = Float(remaining) * adjusted
    let jitterRange = Float(1.5 / activeModifier.difficultyMultiplier)
    let jitter = Float.random(in: -jitterRange...jitterRange)
    let raw = Int((base + jitter).rounded())
    return max(0, min(remaining, raw))
  }
}
