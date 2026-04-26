import Foundation

@MainActor
final class BowlingGame: ObservableObject, Game {
  /// Drives the strict roll-flow state machine. The view watches `phase`
  /// to know when to animate the ball, when to fall pins, and whether to
  /// accept further input.
  enum RollPhase: Equatable {
    case idle  // ready for a flick
    case rolling  // ball traveling toward pins (~1.5s)
    case knocking  // pins falling (~0.8s)
    case resetting  // pin sweep + new rack (~0.6s)
    case finalScoring  // game over
  }

  let id = "bowling"
  let title = "Meta Bowling"
  let howToPlay = "Flick your chin up to roll. Wait for the pins to settle before your next throw."
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
  /// Bumps every accepted flick. The view triggers the ball animation
  /// off `phase`, but rollNumber stays useful for any consumer that wants
  /// a "fired this many times" counter.
  @Published private(set) var rollNumber: Int = 0
  @Published private(set) var phase: RollPhase = .idle
  @Published private(set) var statusLine: String = "Frame 1 · Ready to bowl"
  @Published private(set) var isFinished: Bool = false
  var activeModifier: VenueModifier = .default

  private let totalFrames = 10
  /// Flat history of every ball's pin count, in roll order. Real bowling
  /// scoring uses this for strike/spare bonus lookahead.
  private var rollHistory: [Int] = []

  // Phase timing — kept here so the view can stay in sync.
  private let rollDuration: TimeInterval = 1.5
  private let knockDuration: TimeInterval = 0.8
  private let resetDuration: TimeInterval = 0.6

  func start() { reset() }

  func reset() {
    score = 0
    frame = 1
    ballInFrame = 1
    pinsRemaining = 10
    lastRoll = 0
    rollNumber = 0
    phase = .idle
    rollHistory.removeAll()
    isFinished = false
    statusLine = "Frame 1 · Flick chin up to bowl"
  }

  func handle(_ event: GestureEvent) {
    guard !isFinished else { return }
    // Strict lockout — no spam-flicking. The phase only returns to
    // .idle after the ball animates, pins fall, and (between frames)
    // the rack resets.
    guard phase == .idle else { return }
    guard event.kind == .flick, event.direction == .up else { return }

    let pendingKnock = pinsKnocked(power: event.magnitude, remaining: pinsRemaining)
    rollNumber += 1
    phase = .rolling
    statusLine = "Rolling…"

    // Pins drop AFTER the ball arrives.
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: nanos(rollDuration))
      self.applyImpact(knocked: pendingKnock)
    }
  }

  // MARK: - Impact

  private func applyImpact(knocked: Int) {
    // Apply pin damage — this is what the view uses to animate pins
    // toppling, since pinsRemaining is @Published.
    pinsRemaining -= knocked
    rollHistory.append(knocked)
    lastRoll = knocked
    score = computeScore()
    phase = .knocking

    // A strike means knocking all 10 pins on a fresh rack — true on
    // ball 1 of any frame, and also on the 10th-frame fill balls when
    // the rack was just refreshed by a prior strike/spare.
    let isStrike = knocked == 10 && pinsBeforeWasFull()
    let isSpare = !isStrike && pinsRemaining == 0

    let baseCallout: String
    if isStrike {
      statusLine = "STRIKE! · total \(score)"
      baseCallout = "Strike! Total \(score)."
    } else if isSpare {
      statusLine = "Spare! \(knocked) pins · total \(score)"
      baseCallout = "Spare! Total \(score)."
    } else {
      statusLine = "\(knocked) pins · total \(score)"
      baseCallout = "\(knocked) pins. Total \(score)."
    }

    let willEndGame = isFinalRoll()
    let callout =
      willEndGame ? "\(baseCallout) Game over. Final score \(score)." : baseCallout
    GameAudio.shared.playBowlSequence(scoreCallout: callout)

    // Advance after the pin-fall animation has had time to finish.
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: nanos(knockDuration))
      self.transitionAfterKnock()
    }
  }

  /// True if the rack going into this roll was a full 10. Used to detect
  /// strikes correctly in the 10th frame even on ball 2 / ball 3 (when
  /// the rack was just refreshed by a previous strike).
  private func pinsBeforeWasFull() -> Bool {
    // pinsRemaining BEFORE applyImpact = pinsRemaining + lastRoll (now).
    // We've already mutated, so back-calculate.
    return (pinsRemaining + lastRoll) == 10
  }

  // MARK: - Phase progression

  private func transitionAfterKnock() {
    if frame < totalFrames {
      transitionFramesOneToNine()
    } else {
      transitionTenthFrame()
    }
  }

  private func transitionFramesOneToNine() {
    let strikeOnBall1 = ballInFrame == 1 && lastRoll == 10
    let frameOver = strikeOnBall1 || ballInFrame == 2
    if frameOver {
      advanceFrameWithReset()
    } else {
      ballInFrame = 2
      statusLine = "\(pinsRemaining) left · flick for ball 2"
      phase = .idle
    }
  }

  private func transitionTenthFrame() {
    let frameRolls = tenthFrameRolls()
    switch frameRolls.count {
    case 1:
      // After ball 1: reset rack if it was a strike, else continue.
      if frameRolls[0] == 10 {
        resetRackThenAdvanceTenth(toBall: 2, label: "STRIKE! Roll again")
      } else {
        ballInFrame = 2
        statusLine = "\(pinsRemaining) left · flick for ball 2"
        phase = .idle
      }
    case 2:
      let r1 = frameRolls[0]
      let r2 = frameRolls[1]
      if r1 == 10 {
        // Ball 1 was a strike. Ball 2 played on a fresh rack.
        if r2 == 10 {
          // Double — fill ball on a fresh rack again.
          resetRackThenAdvanceTenth(toBall: 3, label: "DOUBLE! Fill ball")
        } else {
          // Continue with whatever's standing.
          ballInFrame = 3
          statusLine = "\(pinsRemaining) left · flick for fill ball"
          phase = .idle
        }
      } else if r1 + r2 == 10 {
        // Spare on ball 2 → fill ball on fresh rack.
        resetRackThenAdvanceTenth(toBall: 3, label: "SPARE! Fill ball")
      } else {
        // Open frame → game over.
        endGame()
      }
    default:
      // 3 rolls done in 10th → game over.
      endGame()
    }
  }

  private func advanceFrameWithReset() {
    if frame >= totalFrames {
      endGame()
      return
    }
    phase = .resetting
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: nanos(resetDuration))
      self.frame += 1
      self.ballInFrame = 1
      self.pinsRemaining = 10
      self.statusLine = "Frame \(self.frame) · flick chin up to bowl"
      self.phase = .idle
    }
  }

  private func resetRackThenAdvanceTenth(toBall ball: Int, label: String) {
    phase = .resetting
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: nanos(resetDuration))
      self.pinsRemaining = 10
      self.ballInFrame = ball
      self.statusLine = "\(label)"
      self.phase = .idle
    }
  }

  private func endGame() {
    isFinished = true
    statusLine = "Game over · final score \(score)"
    phase = .finalScoring
  }

  // MARK: - Real bowling scoring (strike + spare bonuses)

  /// Bowling-correct cumulative score: strike scores 10 + next 2 rolls,
  /// spare scores 10 + next 1 roll, open frame just sums. The 10th frame
  /// gets up to 3 rolls and no further bonus lookahead.
  private func computeScore() -> Int {
    var total = 0
    var idx = 0
    var f = 0
    while f < totalFrames && idx < rollHistory.count {
      if f == totalFrames - 1 {
        total += rollHistory[idx...].reduce(0, +)
        break
      }
      let r1 = rollHistory[idx]
      if r1 == 10 {
        total += 10
        if idx + 1 < rollHistory.count { total += rollHistory[idx + 1] }
        if idx + 2 < rollHistory.count { total += rollHistory[idx + 2] }
        idx += 1
      } else if idx + 1 < rollHistory.count {
        let r2 = rollHistory[idx + 1]
        total += r1 + r2
        if r1 + r2 == 10, idx + 2 < rollHistory.count {
          total += rollHistory[idx + 2]
        }
        idx += 2
      } else {
        total += r1
        break
      }
      f += 1
    }
    return total
  }

  /// Returns just the rolls belonging to frame 10 (in order).
  private func tenthFrameRolls() -> [Int] {
    var idx = 0
    var f = 0
    while f < totalFrames - 1 && idx < rollHistory.count {
      if rollHistory[idx] == 10 {
        idx += 1  // strike — single roll
      } else if idx + 1 < rollHistory.count {
        idx += 2  // open or spare — two rolls
      } else {
        return []  // game still in earlier frame
      }
      f += 1
    }
    guard idx <= rollHistory.count else { return [] }
    return Array(rollHistory.suffix(rollHistory.count - idx))
  }

  /// True if the just-completed roll was the last one of the game.
  private func isFinalRoll() -> Bool {
    guard frame == totalFrames else { return false }
    let rolls = tenthFrameRolls()
    if rolls.count >= 3 { return true }
    if rolls.count == 2 {
      // No fill ball coming if ball 1 wasn't a strike and the two
      // didn't make a spare.
      return rolls[0] != 10 && rolls[0] + rolls[1] != 10
    }
    return false
  }

  // MARK: - Pin physics

  /// Soft physics: low power rolls gutter, mid hits 4-7 pins, high flick
  /// is a strike candidate. Sticky-lane modifier forgives weak rolls.
  /// Higher venue difficulty = less generous random jitter.
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

  private func nanos(_ s: TimeInterval) -> UInt64 {
    UInt64(s * 1_000_000_000)
  }
}
