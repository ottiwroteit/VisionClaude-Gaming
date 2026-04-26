import Foundation

@MainActor
final class PingPongGame: ObservableObject, Game {
  let id = "pingpong"
  let title = "Meta Ping Pong"
  let howToPlay = "Quick chin nods + side tilts. Timing matters more than power."
  let tint: GameTint = .table

  /// Ping pong is twitch-reflex — lower activeThreshold so tiny head jerks
  /// register, and clamp flickMaxDuration hard so anything longer than a
  /// real twitch gets thrown out as a swing (and ignored by this game).
  var preferredThresholds: MotionClassifier.Thresholds? {
    var t = MotionClassifier.Thresholds()
    t.stillThreshold = 0.003
    t.activeThreshold = 0.009
    t.flickMaxDuration = 0.18
    t.axisDominance = 1.4
    return t
  }

  @Published private(set) var score: Int = 0
  @Published private(set) var cpuScore: Int = 0
  @Published private(set) var rally: Int = 0
  @Published private(set) var statusLine: String = "Rally starts — flick to return"
  @Published private(set) var isFinished: Bool = false
  /// Last "ball changed state" event the SceneKit scene observes.
  /// .serve = CPU is serving (ball flies toward player).
  /// .playerReturn = player just returned (ball flies toward CPU,
  /// then CPU returns it back to player on the same beat).
  /// .miss = player failed to return in time (ball flies past).
  /// .point = a 6-rally point landed.
  @Published private(set) var lastShotKind: ShotKind = .serve
  /// Bumps on every shot event so the scene's onChange observer
  /// fires even when consecutive events match.
  @Published private(set) var shotEventID: Int = 0
  /// Window the scene should use to time its ball animations to
  /// match the model's reaction window. Read-only mirror of the
  /// internal `returnWindow`.
  var sceneReturnWindow: TimeInterval { returnWindow }
  var activeModifier: VenueModifier = .default

  enum ShotKind { case serve, playerReturn, miss, point }

  /// Ping pong is twitch-reflex: we require flicks only, and each return
  /// has a short time window before the CPU scores. The rainTempo venue
  /// effect shortens this window.
  private var lastReturn: Date = .distantPast
  private var returnWindow: TimeInterval {
    activeModifier.effect == .rainTempo ? 1.1 : 1.5
  }

  func start() { reset() }

  func reset() {
    score = 0
    cpuScore = 0
    rally = 0
    isFinished = false
    lastReturn = Date()
    statusLine = "Rally starts — flick to return"
    publishShot(.serve)
  }

  func handle(_ event: GestureEvent) {
    guard !isFinished else { return }
    let elapsed = Date().timeIntervalSince(lastReturn)
    if elapsed > returnWindow {
      cpuScore += 1
      rally = 0
      lastReturn = Date()
      statusLine = "Too slow! CPU \(cpuScore) – \(score)"
      publishShot(.miss)
      finishIfNeeded()
      return
    }
    guard event.kind == .flick else { return }
    guard [.up, .down, .left, .right].contains(event.direction) else { return }

    rally += 1
    lastReturn = Date()
    let timingBonus = 1.0 - elapsed / returnWindow
    let winChance = 0.4 + Double(event.magnitude) * 0.3 + timingBonus * 0.2
    if Double.random(in: 0...1) < winChance {
      statusLine = "Return \(rally)! (\(event.direction.rawValue))"
      publishShot(.playerReturn)
    } else {
      cpuScore += 1
      rally = 0
      statusLine = "Missed. CPU \(cpuScore) – \(score)"
      publishShot(.miss)
      finishIfNeeded()
    }

    if rally >= 6 {
      score += max(1, Int(activeModifier.scoreMultiplier.rounded()))
      rally = 0
      statusLine = "Point! \(score) – \(cpuScore)"
      publishShot(.point)
      finishIfNeeded()
    }
  }

  private func publishShot(_ kind: ShotKind) {
    lastShotKind = kind
    shotEventID += 1
  }

  private func finishIfNeeded() {
    if score >= 11 || cpuScore >= 11 {
      isFinished = true
      statusLine =
        score > cpuScore
        ? "You win \(score)-\(cpuScore)"
        : "CPU wins \(cpuScore)-\(score)"
    }
  }
}
