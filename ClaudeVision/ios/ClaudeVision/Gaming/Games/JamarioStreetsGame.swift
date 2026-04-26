import Foundation

/// Jamario: Streets — a side-scrolling beat-em-up in the spirit of
/// Streets of Rage. Player controls Jamario in a fixed arena. Enemies
/// spawn in waves and walk toward him; he punches and kicks them
/// down. Defeat all enemies in a wave to advance.
///
/// Input mapping (head-tracked):
/// - Head tilt LEFT/RIGHT — walk Jamario along the street.
/// - Chin UP flick — PUNCH (short range, fast).
/// - Chin DOWN flick — KICK (longer reach, more damage, slower recovery).
///
/// All combat resolution lives in this model so audio + chrome can
/// react to the same events the SpriteKit scene does.
@MainActor
final class JamarioStreetsGame: ObservableObject, Game {
  let id = "jamariostreets"
  let title = "Jamario: Streets"
  let howToPlay = "Tilt LEFT/RIGHT to walk. Chin UP = punch. Chin DOWN = kick."
  let tint: GameTint = .ring  // street brawler — ring red feels right

  /// Streets needs both directions of chin-flick AND continuous head-tilt
  /// for movement. Borrows the bowling latency cutoff so attacks fire
  /// fast, but with a slightly higher activeThreshold so the constant
  /// head-tilt-for-movement doesn't accidentally trigger flicks.
  var preferredThresholds: MotionClassifier.Thresholds? {
    var t = MotionClassifier.Thresholds()
    t.activeThreshold = 0.011
    t.flickMaxDuration = 0.30
    t.maxGestureDuration = 0.55
    return t
  }

  // MARK: Published state

  @Published private(set) var score: Int = 0
  @Published private(set) var wave: Int = 1
  @Published private(set) var playerHP: Int = 100
  @Published private(set) var enemiesDefeatedThisWave: Int = 0
  @Published private(set) var enemiesPerWave: Int = 3
  @Published private(set) var statusLine: String = "Wave 1 — clean up the street"
  @Published private(set) var isFinished: Bool = false

  /// Continuous walk velocity command in [-1, +1]. Updated from
  /// handleMotion (head-tilt) and read by the scene each frame to
  /// drive Jamario's horizontal velocity.
  @Published private(set) var walkAxis: Float = 0
  /// Bumped each time the player commits to a punch. Scene applies
  /// the punch animation + hit detection.
  @Published private(set) var punchEventID: Int = 0
  /// Bumped each time the player commits to a kick.
  @Published private(set) var kickEventID: Int = 0
  /// Bumped each time the player TAKES damage from an enemy contact.
  /// Drives the chrome's red-flash + camera shake in the scene.
  @Published private(set) var hitEventID: Int = 0
  /// Bumped each time an enemy is defeated.
  @Published private(set) var enemyDownEventID: Int = 0

  var activeModifier: VenueModifier = .default

  // MARK: Tunables

  /// Damage values published so the scene's hit-resolution math agrees
  /// with the model's bookkeeping.
  let punchDamage: Int = 18
  let kickDamage: Int = 28
  /// Damage Jamario takes per enemy contact.
  let enemyContactDamage: Int = 8
  /// Cooldown the scene should respect between consecutive enemy hits
  /// on the player (so a single touching enemy doesn't drain HP every
  /// frame).
  let perEnemyHitCooldown: TimeInterval = 0.7

  // MARK: Lifecycle

  func start() { reset() }

  func reset() {
    score = 0
    wave = 1
    playerHP = 100
    enemiesDefeatedThisWave = 0
    enemiesPerWave = 3
    walkAxis = 0
    isFinished = false
    statusLine = "Wave 1 — clean up the street"
  }

  // MARK: Game protocol — input

  func handle(_ event: GestureEvent) {
    guard !isFinished, event.kind == .flick else { return }
    switch event.direction {
    case .up:
      punchEventID += 1
    case .down:
      kickEventID += 1
    default:
      break
    }
  }

  func handleMotion(_ vector: SIMD2<Float>) {
    guard !isFinished else { return }
    // Head-tilt X drives walk command. Apply a deadzone so a still
    // head doesn't drift, and clamp to [-1, +1].
    let deadzone: Float = 0.05
    let lateral = vector.x
    if abs(lateral) < deadzone {
      walkAxis = 0
    } else {
      let scaled = (lateral - (lateral > 0 ? deadzone : -deadzone)) * 2.5
      walkAxis = max(-1, min(1, scaled))
    }
  }

  // MARK: Scene → game callbacks

  /// Scene reports a punch landed on an enemy.
  func didLandPunch() {
    let bonus = max(1, Int(activeModifier.scoreMultiplier.rounded()))
    score += 5 * bonus
  }

  /// Scene reports a kick landed on an enemy.
  func didLandKick() {
    let bonus = max(1, Int(activeModifier.scoreMultiplier.rounded()))
    score += 8 * bonus
  }

  /// Scene reports an enemy was defeated (HP fell to 0).
  func didDefeatEnemy() {
    let bonus = max(1, Int(activeModifier.scoreMultiplier.rounded()))
    score += 25 * bonus
    enemiesDefeatedThisWave += 1
    enemyDownEventID += 1
    statusLine = "\(enemiesDefeatedThisWave)/\(enemiesPerWave) down · score \(score)"
    if enemiesDefeatedThisWave >= enemiesPerWave {
      advanceWave()
    }
  }

  /// Scene reports the player took damage.
  func didTakeDamage() {
    let dmg = Int(Double(enemyContactDamage) * activeModifier.difficultyMultiplier)
    playerHP = max(0, playerHP - dmg)
    hitEventID += 1
    if playerHP == 0 {
      isFinished = true
      statusLine = "Down for the count · final score \(score)"
    } else {
      statusLine = "Took a hit · \(playerHP) HP"
    }
  }

  // MARK: Wave progression

  private func advanceWave() {
    wave += 1
    enemiesDefeatedThisWave = 0
    // Each wave gets 1 more enemy, capping at 6 so the screen doesn't
    // turn into a swarm.
    enemiesPerWave = min(6, 3 + wave - 1)
    // Small HP heal between waves so the run can keep going without
    // becoming impossible.
    playerHP = min(100, playerHP + 15)
    statusLine = "Wave \(wave) — \(enemiesPerWave) incoming"
  }
}
