import Foundation

@MainActor
final class BowlingGame: ObservableObject, Game {
  /// Drives the strict roll-flow state machine. The view watches `phase`
  /// to know when to animate the ball, when to fall pins, and whether to
  /// accept further input.
  enum RollPhase: Equatable {
    case countingDown  // arcade 3-2-1 before each turn — input ignored
    case idle  // ready for a flick
    case rolling  // ball traveling toward pins (~1.5s)
    case knocking  // pins falling (~0.8s)
    case resetting  // pin sweep + new rack (~0.6s)
    case finalScoring  // game over
  }

  /// Which gutter, if any, the current roll is heading into. nil means
  /// straight down the middle. The view reads this during `.rolling` to
  /// curve the ball animation toward the appropriate side.
  enum GutterSide: Equatable { case left, right }

  let id = "bowling"
  let title = "Meta Bowling"
  let howToPlay =
    "Tilt your head LEFT or RIGHT to aim. When you've lined up the shot, chin UP (or DOWN) to release the ball."
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
  /// Set when the released roll heads into a gutter (extreme aim).
  /// Drives the ball-curve animation; cleared when phase returns to idle.
  @Published private(set) var gutter: GutterSide? = nil
  /// Current value of the 3-2-1 arcade countdown ("Go!" when 0). nil
  /// when not counting down. The view animates a big number overlay.
  @Published private(set) var countdownValue: Int? = nil
  /// Where the ball is aimed on the lane: -1 = full left gutter, 0 = center,
  /// +1 = full right gutter. Tracks live head position during the aim
  /// window and is committed when the player chin-flicks UP/DOWN.
  @Published private(set) var aimPosition: Float = 0
  /// Released ball intent — read by the SceneKit scene the moment phase
  /// flips to `.rolling`. Power 0..1 maps to the forward impulse; hook
  /// -1..+1 maps to lateral angular velocity (curve).
  @Published private(set) var pendingPower: Float = 0
  @Published private(set) var pendingHook: Float = 0
  /// Wall-clock timestamp of the most recent .rolling transition. The
  /// scene uses this as a synchronization point — the same value firing
  /// twice would mean a duplicate launch, which would be a bug.
  @Published private(set) var rollLaunchedAt: Date? = nil

  /// Sensitivity for integrating live head motion into aim. Tuned by
  /// feel — too low = no movement, too high = jumpy.
  private let aimSensitivity: Float = 0.12
  /// Deadzone below which live motion is ignored as noise.
  private let aimDeadzone: Float = 0.08
  /// Safety timer for the .rolling phase. Cancels itself the moment the
  /// scene reports a settle; if it actually fires, the roll is treated
  /// as a no-show gutter so the state machine never deadlocks.
  private var physicsWatchdogTask: Task<Void, Never>? = nil
  /// How long to wait for the SceneKit scene to report a roll outcome
  /// before assuming the scene didn't run.
  private let physicsTimeout: TimeInterval = 6.0

  /// Outcome of the most recent roll. The view watches this to trigger
  /// arcade-style celebrations (particle burst, pop-up, screen shake)
  /// when a strike or spare lands.
  enum RollOutcome: Equatable { case strike, spare, open, gutter }
  @Published private(set) var lastOutcome: RollOutcome? = nil

  /// Themed ball skins the player can pick before rolling.
  enum BallSkin: String, CaseIterable, Identifiable {
    case classic
    case skull
    case superhero
    case eightBall
    case basketball
    case soccer
    case fire  // unlocked automatically during a turkey streak

    var id: String { rawValue }
    var displayName: String {
      switch self {
      case .classic: return "Classic"
      case .skull: return "Sugar Skull"
      case .superhero: return "Caped"
      case .eightBall: return "8-Ball"
      case .basketball: return "Hoops"
      case .soccer: return "Football"
      case .fire: return "On Fire"
      }
    }
  }
  @Published var selectedSkin: BallSkin = .classic
  /// The skin actually used for rendering — `.fire` overrides the
  /// player's pick when a turkey (3+ consecutive strikes) is active.
  var activeSkin: BallSkin { isOnFire ? .fire : selectedSkin }

  /// How many strikes in a row the player has thrown. Bonus points kick
  /// in once the streak reaches 3 (a "turkey"); the ball goes on fire.
  @Published private(set) var consecutiveStrikes: Int = 0
  var isOnFire: Bool { consecutiveStrikes >= 3 }
  @Published private(set) var statusLine: String = "Frame 1 · Ready to bowl"
  @Published private(set) var isFinished: Bool = false
  var activeModifier: VenueModifier = .default

  private let totalFrames = 10
  /// Flat history of every ball's pin count, in roll order. Real bowling
  /// scoring uses this for strike/spare bonus lookahead. Published so the
  /// scoreboard view can render frame-by-frame breakdowns.
  @Published private(set) var rollHistory: [Int] = []

  /// One per frame, computed from rollHistory. Drives the scoreboard.
  struct FrameDisplay: Equatable {
    let number: Int  // 1...10
    let rolls: [String]  // "X" / "/" / "-" / "0".."9"
    let cumulative: Int?  // nil if not finalized yet (waiting on bonus)
    let isCurrent: Bool
  }

  var frameDisplays: [FrameDisplay] {
    var displays: [FrameDisplay] = []
    var idx = 0
    var running = 0

    for f in 0..<totalFrames {
      let isCurrent = (frame - 1) == f && !isFinished
      guard idx < rollHistory.count else {
        displays.append(
          FrameDisplay(number: f + 1, rolls: [], cumulative: nil, isCurrent: isCurrent))
        continue
      }

      if f == totalFrames - 1 {
        // 10th frame: up to 3 balls, no bonus lookahead.
        let rolls = Array(rollHistory.suffix(rollHistory.count - idx))
        running += rolls.reduce(0, +)
        let labels = renderTenthFrameLabels(rolls)
        let total: Int? = isFrame10Complete(rolls) ? running : nil
        displays.append(
          FrameDisplay(number: 10, rolls: labels, cumulative: total, isCurrent: isCurrent))
        break
      }

      let r1 = rollHistory[idx]
      if r1 == 10 {
        // Strike — pending bonus from next 2 rolls.
        let bonus1: Int? = idx + 1 < rollHistory.count ? rollHistory[idx + 1] : nil
        let bonus2: Int? = idx + 2 < rollHistory.count ? rollHistory[idx + 2] : nil
        let total: Int? = (bonus1 != nil && bonus2 != nil) ? running + 10 + bonus1! + bonus2! : nil
        if total != nil { running = total! }
        displays.append(
          FrameDisplay(
            number: f + 1, rolls: ["", "X"], cumulative: total, isCurrent: isCurrent))
        idx += 1
      } else if idx + 1 < rollHistory.count {
        let r2 = rollHistory[idx + 1]
        let isSpare = r1 + r2 == 10
        let r1Label = r1 == 0 ? "-" : "\(r1)"
        let r2Label = isSpare ? "/" : (r2 == 0 ? "-" : "\(r2)")
        if isSpare {
          let bonus: Int? = idx + 2 < rollHistory.count ? rollHistory[idx + 2] : nil
          let total: Int? = bonus != nil ? running + 10 + bonus! : nil
          if total != nil { running = total! }
          displays.append(
            FrameDisplay(
              number: f + 1, rolls: [r1Label, r2Label], cumulative: total, isCurrent: isCurrent))
        } else {
          running += r1 + r2
          displays.append(
            FrameDisplay(
              number: f + 1, rolls: [r1Label, r2Label], cumulative: running, isCurrent: isCurrent))
        }
        idx += 2
      } else {
        // Just ball 1 of an open frame so far — partial display, no total.
        let r1Label = r1 == 0 ? "-" : "\(r1)"
        displays.append(
          FrameDisplay(
            number: f + 1, rolls: [r1Label], cumulative: nil, isCurrent: isCurrent))
        break
      }
    }

    // Pad empty frames so the scoreboard always has 10 cells.
    while displays.count < totalFrames {
      let n = displays.count + 1
      displays.append(
        FrameDisplay(
          number: n, rolls: [], cumulative: nil, isCurrent: (frame == n) && !isFinished))
    }
    return displays
  }

  private func renderTenthFrameLabels(_ rolls: [Int]) -> [String] {
    var out: [String] = []
    for (i, r) in rolls.enumerated() {
      if r == 10 {
        out.append("X")
      } else if i == 1 && (rolls[0] != 10) && rolls[0] + r == 10 {
        out.append("/")
      } else if i == 2 && rolls[1] != 10 && rolls[0] != 10 && rolls[1] + r == 10 {
        // Spare on balls 2+3 of 10th (won't happen with current logic but
        // handle it for safety).
        out.append("/")
      } else if r == 0 {
        out.append("-")
      } else {
        out.append("\(r)")
      }
    }
    return out
  }

  private func isFrame10Complete(_ rolls: [Int]) -> Bool {
    if rolls.count >= 3 { return true }
    if rolls.count == 2 {
      return rolls[0] != 10 && rolls[0] + rolls[1] != 10
    }
    return false
  }

  // Phase timing — kept here so the view can stay in sync. The roll
  // duration is no longer game-controlled (the SceneKit physics runs at
  // its own pace and reports back via physicsDidSettle); knockDuration
  // is now the celebration/outcome display window after settle.
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
    gutter = nil
    aimPosition = 0
    consecutiveStrikes = 0
    lastOutcome = nil
    rollHistory.removeAll()
    isFinished = false
    statusLine = "Frame 1 · get ready…"
    countdownValue = nil
    startCountdown()
  }

  func handle(_ event: GestureEvent) {
    guard !isFinished else { return }
    // Strict lockout — no spam-flicking. The phase only returns to
    // .idle after the ball animates, pins fall, and (between frames)
    // the rack resets.
    guard phase == .idle else { return }
    guard event.kind == .flick else { return }

    // Horizontal flicks are ignored — aim is now driven by live head
    // motion (handleMotion). Only chin UP/DOWN releases. Curvature in
    // the chin-flick path becomes the ball's hook.
    switch event.direction {
    case .up, .down:
      releaseRoll(power: event.magnitude, hook: event.lateralCurvature)
    case .left, .right, .none, .rollLeft, .rollRight, .forward, .backward:
      return
    }
  }

  /// Live head motion → aim integration. Fires at frame rate from the
  /// engine, but only does work while the player is in the `.idle`
  /// phase (aiming) so motion outside of that window (countdown, ball
  /// rolling, pin fall, reset) doesn't leak into next turn's aim.
  func handleMotion(_ vector: SIMD2<Float>) {
    guard phase == .idle else { return }
    let lateral = vector.x
    guard abs(lateral) > aimDeadzone else { return }
    aimPosition = max(-1, min(1, aimPosition + lateral * aimSensitivity))
    statusLine = aimLineLabel()
  }

  /// Commits the current aim into a real ball release. The actual pin
  /// outcome is decided by the SceneKit scene's physics — this method
  /// only stores the launch intent (power + hook + aim) and transitions
  /// to `.rolling`. The scene observes the phase transition, applies an
  /// impulse to its physics ball, and reports back via
  /// `physicsDidSettle(knockedThisRoll:wasGutter:)`.
  ///
  /// A watchdog auto-resolves the roll as a gutter ball if the scene
  /// fails to report back within `physicsTimeout` (e.g. the SceneKit
  /// view never mounted), so the game can never get stuck in `.rolling`.
  private func releaseRoll(power: Float, hook: Float = 0) {
    physicsWatchdogTask?.cancel()

    let absAim = abs(aimPosition)
    let gutterSide: GutterSide? =
      absAim > 0.7 ? (aimPosition < 0 ? .left : .right) : nil

    gutter = gutterSide
    rollNumber += 1
    pendingPower = max(0, min(1, power))
    pendingHook = max(-1, min(1, hook))
    rollLaunchedAt = Date()
    phase = .rolling
    statusLine = gutterSide == nil ? "Rolling…" : "Heading for the gutter!"

    physicsWatchdogTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: nanos(physicsTimeout))
      guard !Task.isCancelled else { return }
      // Scene never reported — treat the roll as a no-show gutter so
      // the state machine keeps moving.
      self.physicsDidSettle(knockedThisRoll: 0, wasGutter: true)
    }
  }

  /// Called by the SceneKit scene once the ball comes to rest and any
  /// chain-reaction pin falls have stopped. `knockedThisRoll` is the
  /// number of pins that newly toppled on this roll (NOT cumulative for
  /// the frame). Safe to call at most once per `.rolling` phase — the
  /// watchdog cancels itself on entry.
  func physicsDidSettle(knockedThisRoll: Int, wasGutter: Bool = false) {
    // Ignore stale callbacks that might arrive after we've already
    // moved on (e.g. watchdog fires AND scene reports).
    guard phase == .rolling else { return }
    physicsWatchdogTask?.cancel()
    physicsWatchdogTask = nil
    if wasGutter, gutter == nil {
      gutter = aimPosition < 0 ? .left : .right
    }
    let clamped = max(0, min(pinsRemaining, knockedThisRoll))
    applyImpact(knocked: clamped)
  }

  private func aimLineLabel() -> String {
    let pct = Int((aimPosition * 100).rounded())
    if pct == 0 { return "Aim: center" }
    return pct < 0 ? "Aim: \(abs(pct))% left" : "Aim: \(pct)% right"
  }

  // MARK: - Impact

  private func applyImpact(knocked: Int) {
    // Apply pin damage — this is what the view uses to animate pins
    // toppling, since pinsRemaining is @Published.
    pinsRemaining -= knocked
    rollHistory.append(knocked)
    lastRoll = knocked
    score = computeScore()
    // Turkey bonus: once the player is on a 3+ strike streak, every
    // pin knocked is worth +5 extra. Surfaces in the displayed total
    // (added on top of the canonical bowling score so the scoreboard
    // running totals still make sense).
    if isOnFire {
      score += knocked * 5
    }
    phase = .knocking

    // A strike means knocking all 10 pins on a fresh rack — true on
    // ball 1 of any frame, and also on the 10th-frame fill balls when
    // the rack was just refreshed by a prior strike/spare.
    let isStrike = knocked == 10 && pinsBeforeWasFull()
    let isSpare = !isStrike && pinsRemaining == 0

    // Update the consecutive-strike counter BEFORE building the callout
    // so the callout can announce a turkey or fire-mode message.
    if isStrike {
      consecutiveStrikes += 1
    } else {
      consecutiveStrikes = 0
    }

    let baseCallout: String
    if gutter != nil {
      statusLine = "Gutter ball! 0 pins · total \(score)"
      baseCallout = "Gutter ball. Total \(score)."
      lastOutcome = .gutter
    } else if isStrike {
      switch consecutiveStrikes {
      case 1:
        statusLine = "STRIKE! · total \(score)"
        baseCallout = "Strike! Total \(score)."
      case 2:
        statusLine = "DOUBLE! 2 in a row · total \(score)"
        baseCallout = "Double! Two in a row. Total \(score)."
      case 3:
        statusLine = "TURKEY! Ball on fire · total \(score)"
        baseCallout = "Turkey! Ball on fire. Total \(score)."
      default:
        statusLine = "FIRE STRIKE \(consecutiveStrikes)! · total \(score)"
        baseCallout =
          "Fire strike! \(consecutiveStrikes) in a row. Total \(score)."
      }
      lastOutcome = .strike
    } else if isSpare {
      statusLine = "Spare! \(knocked) pins · total \(score)"
      baseCallout = "Spare! Total \(score)."
      lastOutcome = .spare
    } else {
      statusLine = "\(knocked) pins · total \(score)"
      baseCallout = "\(knocked) pins. Total \(score)."
      lastOutcome = .open
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
      gutter = nil
      startCountdown()
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
        gutter = nil
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
          gutter = nil
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
      self.gutter = nil
      self.startCountdown()
    }
  }

  private func resetRackThenAdvanceTenth(toBall ball: Int, label: String) {
    phase = .resetting
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: nanos(resetDuration))
      self.pinsRemaining = 10
      self.ballInFrame = ball
      self.statusLine = "\(label)"
      self.gutter = nil
      self.startCountdown()
    }
  }

  private func endGame() {
    isFinished = true
    statusLine = "Game over · final score \(score)"
    countdownValue = nil
    phase = .finalScoring
  }

  /// 3-2-1 arcade countdown gating each turn. Phase stays `.countingDown`
  /// until the count finishes, so handle() can't accept flicks during
  /// it. Aim resets to center as part of the countdown — every turn
  /// starts aimed straight down the middle. Once the countdown ends,
  /// phase enters `.idle` and stays there indefinitely until the player
  /// commits with a chin-flick UP/DOWN. There is no auto-release — the
  /// gesture is the only way the ball moves.
  private func startCountdown() {
    phase = .countingDown
    aimPosition = 0
    countdownValue = 3
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: nanos(0.6))
      self.countdownValue = 2
      try? await Task.sleep(nanoseconds: nanos(0.6))
      self.countdownValue = 1
      try? await Task.sleep(nanoseconds: nanos(0.6))
      self.countdownValue = nil
      self.phase = .idle
      self.statusLine = "Move your head to aim · chin UP to roll"
    }
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

  private func nanos(_ s: TimeInterval) -> UInt64 {
    UInt64(s * 1_000_000_000)
  }
}
