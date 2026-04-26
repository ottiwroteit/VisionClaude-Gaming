import Foundation

/// Jamario — a Mario-style auto-runner named after the player. The
/// world scrolls past Jamario at a constant pace; the player's only
/// input is "jump" (chin UP). Game state is the simple side-scroller
/// arcade kit: coins collected, distance run, lives remaining, score
/// derived from both.
///
/// All level geometry, enemy/coin spawning, collision detection, and
/// death conditions live in the SpriteKit scene controller — this
/// object is just the published-state and event-publishing surface
/// the scene reports back to.
@MainActor
final class JamarioGame: ObservableObject, Game {
  let id = "jamario"
  let title = "Meta Jamario"
  let howToPlay = "Chin UP to jump. Avoid pits, stomp goombas, grab coins."
  let tint: GameTint = .accent

  /// Jamario needs snappy single-tap-style jumps. Borrows the same
  /// "force-close gestures past 0.5 s" cutoff that fixed bowling's
  /// chin-flick latency so a well-timed jump fires immediately.
  var preferredThresholds: MotionClassifier.Thresholds? {
    var t = MotionClassifier.Thresholds()
    t.activeThreshold = 0.008
    t.flickMaxDuration = 0.30
    t.maxGestureDuration = 0.5
    return t
  }

  // MARK: Published state

  @Published private(set) var score: Int = 0
  @Published private(set) var coins: Int = 0
  @Published private(set) var lives: Int = 3
  @Published private(set) var distance: Int = 0  // meters traveled
  @Published private(set) var statusLine: String = "Chin UP to jump"
  @Published private(set) var isFinished: Bool = false
  /// Bumps every time the player commits a jump intent. The SpriteKit
  /// scene observes this to apply the jump impulse on its physics body.
  @Published private(set) var jumpEventID: Int = 0
  /// Bumps every time Jamario stomps an enemy or grabs a coin or dies.
  /// Drives short pop badges on the chrome.
  @Published private(set) var pickupEventID: Int = 0
  @Published private(set) var lastPickupKind: PickupKind = .none
  var activeModifier: VenueModifier = .default

  enum PickupKind { case none, coin, stomp, deathByPit, deathByEnemy }

  // MARK: Game protocol

  func start() { reset() }

  func reset() {
    score = 0
    coins = 0
    lives = 3
    distance = 0
    isFinished = false
    statusLine = "Chin UP to jump"
    lastPickupKind = .none
  }

  func handle(_ event: GestureEvent) {
    guard !isFinished, event.kind == .flick, event.direction == .up else { return }
    jumpEventID += 1
  }

  // MARK: Scene → game callbacks

  func didCollectCoin() {
    coins += 1
    let bonus = max(1, Int(activeModifier.scoreMultiplier.rounded()))
    score += 10 * bonus
    statusLine = "Coin! · \(coins) coins · \(distance)m"
    lastPickupKind = .coin
    pickupEventID += 1
  }

  func didStompEnemy() {
    let bonus = max(1, Int(activeModifier.scoreMultiplier.rounded()))
    score += 50 * bonus
    statusLine = "Stomp! · \(coins) coins · \(distance)m"
    lastPickupKind = .stomp
    pickupEventID += 1
  }

  func didAdvance(meters: Int) {
    distance = max(distance, meters)
    let bonus = max(1, Int(activeModifier.scoreMultiplier.rounded()))
    score = coins * 10 * bonus + distance
    if !isFinished {
      statusLine = "\(coins) coins · \(distance)m"
    }
  }

  func didDieFromPit() {
    applyDeath(kind: .deathByPit, message: "Fell into a pit!")
  }

  func didDieFromEnemy() {
    applyDeath(kind: .deathByEnemy, message: "Hit a goomba!")
  }

  private func applyDeath(kind: PickupKind, message: String) {
    lives -= 1
    lastPickupKind = kind
    pickupEventID += 1
    if lives <= 0 {
      isFinished = true
      statusLine = "Game over · final \(score)"
    } else {
      statusLine = "\(message) · \(lives) lives left"
    }
  }
}
