import Foundation

@MainActor
final class BoxingGame: ObservableObject, Game {
  let id = "boxing"
  let title = "Meta Boxing"
  let howToPlay = "Bob down to duck, tilt left/right to slip, flick forward (chin down) to jab."
  let tint: GameTint = .ring

  /// Boxing needs fast reflex detection — lower activeThreshold so small
  /// slips register, and short flickMaxDuration so punches stay snappy.
  var preferredThresholds: MotionClassifier.Thresholds? {
    var t = MotionClassifier.Thresholds()
    t.activeThreshold = 0.010
    t.flickMaxDuration = 0.22
    return t
  }

  @Published private(set) var score: Int = 0
  /// Both fighters get 400 HP so a typical fight (player throws ~1
  /// hook per 1-2 s at ~25 dmg avg) lasts 30-60 s instead of ending
  /// in the first 5-10 s. Health bars in the chrome read this against
  /// `maxHealth` so the percentage display stays correct.
  @Published private(set) var playerHealth: Int = 400
  @Published private(set) var cpuHealth: Int = 400
  let maxHealth: Int = 400
  @Published private(set) var round: Int = 1
  @Published private(set) var incomingAttack: IncomingAttack = .none
  @Published private(set) var statusLine: String = "Round 1 — defend and counter"
  @Published private(set) var isFinished: Bool = false
  /// Bumps every time the player lands a punch on the heavy bag.
  /// SceneKit observes this to trigger the recoil animation.
  @Published private(set) var lastPunchEventID: Int = 0
  /// Direction the most recent landed punch came from. The scene
  /// uses this to bias the bag's recoil axis (center jab vs side hook).
  @Published private(set) var lastPunchSide: PunchSide = .center
  /// Bumps when the player TAKES damage (CPU's incoming attack lands
  /// because the player didn't dodge). Drives the screen-flash overlay.
  @Published private(set) var lastHitEventID: Int = 0
  var activeModifier: VenueModifier = .default

  enum IncomingAttack: String { case none, jab, hookLeft, hookRight, uppercut }
  enum PunchSide { case center, left, right }

  private var attackTimer: Timer?

  func start() {
    reset()
    scheduleNextAttack()
  }

  func reset() {
    score = 0
    playerHealth = maxHealth
    cpuHealth = maxHealth
    round = 1
    incomingAttack = .none
    isFinished = false
    statusLine = "Round 1 — defend and counter"
    attackTimer?.invalidate()
    attackTimer = nil
  }

  func handle(_ event: GestureEvent) {
    guard !isFinished else { return }

    // Defense mapping: dodge the incoming attack by matching head motion.
    if event.kind == .flick || event.kind == .swing {
      let dodged = matchDodge(event: event, attack: incomingAttack)
      if dodged && incomingAttack != .none {
        statusLine = "Dodged \(incomingAttack.rawValue)!"
        incomingAttack = .none
        scheduleNextAttack(delay: 0.8)
        return
      }
    }

    // Offense: chin-down flick = jab, left/right swing = hook.
    if event.kind == .flick, event.direction == .down {
      landPunch(damage: Int(10 + event.magnitude * 15), label: "Jab", side: .center)
    } else if event.kind == .swing, event.direction == .left {
      landPunch(damage: Int(15 + event.magnitude * 20), label: "Hook left", side: .left)
    } else if event.kind == .swing, event.direction == .right {
      landPunch(damage: Int(15 + event.magnitude * 20), label: "Hook right", side: .right)
    }
  }

  private func matchDodge(event: GestureEvent, attack: IncomingAttack) -> Bool {
    switch attack {
    case .jab, .uppercut: return event.direction == .down
    case .hookLeft: return event.direction == .right
    case .hookRight: return event.direction == .left
    case .none: return false
    }
  }

  private func landPunch(damage: Int, label: String, side: PunchSide) {
    // Crowd pressure venues boost hooks specifically.
    let crowdBonus =
      activeModifier.effect == .crowdPressure && label.contains("Hook")
      ? Int(Double(damage) * 0.4) : 0
    let boosted = Int(Double(damage + crowdBonus) * activeModifier.scoreMultiplier)
    cpuHealth = max(0, cpuHealth - boosted)
    score += boosted
    // Publish the punch BEFORE the status update so the SceneKit
    // scene's onChange observer fires with the correct side context.
    lastPunchSide = side
    lastPunchEventID += 1
    statusLine = "\(label) lands · CPU \(cpuHealth) HP"
    if cpuHealth == 0 {
      isFinished = true
      statusLine = "KO! You win round \(round)"
      attackTimer?.invalidate()
    }
  }

  private func scheduleNextAttack(delay: TimeInterval = 1.5) {
    attackTimer?.invalidate()
    attackTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, !self.isFinished else { return }
        let attacks: [IncomingAttack] = [.jab, .hookLeft, .hookRight, .uppercut]
        self.incomingAttack = attacks.randomElement() ?? .jab
        self.statusLine = "Incoming \(self.incomingAttack.rawValue)!"
        // Give the player a short window before damage resolves.
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
          Task { @MainActor [weak self] in
            guard let self, self.incomingAttack != .none, !self.isFinished else { return }
            // CPU hits harder at higher difficulty.
            // CPU damage scaled up alongside the new 400 HP pool so a
            // missed dodge actually costs the player meaningful HP and
            // both fighters die in roughly the same number of hits
            // (~15-25). Keeps fights at the 30-60 s the user asked for.
            let dmg = Int(Double(28) * self.activeModifier.difficultyMultiplier)
            self.playerHealth = max(0, self.playerHealth - dmg)
            self.statusLine = "Took the \(self.incomingAttack.rawValue) · \(self.playerHealth) HP"
            self.lastHitEventID += 1
            self.incomingAttack = .none
            if self.playerHealth == 0 {
              self.isFinished = true
              self.statusLine = "Down for the count. CPU wins."
            } else {
              self.scheduleNextAttack()
            }
          }
        }
      }
    }
  }
}
