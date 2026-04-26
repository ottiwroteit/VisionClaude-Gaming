import Foundation

@MainActor
final class FruitSlashGame: ObservableObject, Game {
  let id = "fruitslash"
  let title = "Meta Fruit Slash"
  let howToPlay = "Flick your head in the direction of each flying fruit to slice it."
  let tint: GameTint = .berry

  /// Fruit slash wants fast, directional flicks. Low activeThreshold so
  /// snaps register, tight flick window, and strong axis dominance so a
  /// flick toward "up" doesn't get mis-labeled as "up-left".
  var preferredThresholds: MotionClassifier.Thresholds? {
    var t = MotionClassifier.Thresholds()
    t.activeThreshold = 0.010
    t.flickMaxDuration = 0.22
    t.axisDominance = 2.0
    return t
  }

  struct Fruit: Identifiable {
    let id = UUID()
    let direction: GestureDirection
    let expiresAt: Date
    let isBomb: Bool
  }

  @Published private(set) var score: Int = 0
  @Published private(set) var lives: Int = 3
  @Published private(set) var currentFruit: Fruit?
  @Published private(set) var statusLine: String = "Flick toward the fruit!"
  @Published private(set) var isFinished: Bool = false
  /// Last outcome from a resolved fruit (sliced cleanly, missed,
  /// bomb-sliced, bomb-dodged, expired). The SceneKit scene reads
  /// this to pick the right departure animation for the active
  /// fruit node when it goes away.
  @Published private(set) var lastOutcome: FruitOutcome? = nil
  /// Bumps on every resolved fruit so the scene's onChange observer
  /// fires even when consecutive outcomes match.
  @Published private(set) var outcomeEventID: Int = 0
  var activeModifier: VenueModifier = .default

  struct FruitOutcome {
    let direction: GestureDirection
    let isBomb: Bool
    let kind: Kind
    enum Kind { case sliced, missed, bombSliced, bombDodged, expired }
  }

  private var spawnTimer: Timer?
  private var difficulty: Double = 1.0

  func start() {
    reset()
    scheduleSpawn()
  }

  func reset() {
    score = 0
    lives = 3
    currentFruit = nil
    difficulty = 1.0
    isFinished = false
    statusLine = "Flick toward the fruit!"
    spawnTimer?.invalidate()
    spawnTimer = nil
  }

  func handle(_ event: GestureEvent) {
    guard !isFinished, event.kind == .flick else { return }
    guard let fruit = currentFruit else { return }

    let matched = event.direction == fruit.direction
    let kind: FruitOutcome.Kind
    if fruit.isBomb {
      if matched {
        lives -= 1
        statusLine = "Sliced a bomb! -1 life"
        kind = .bombSliced
        loseIfNeeded()
      } else {
        statusLine = "Good — you dodged the bomb"
        score += 2
        kind = .bombDodged
      }
    } else if matched {
      let base = Int(1 + event.magnitude * 4)
      score += Int(Double(base) * activeModifier.scoreMultiplier)
      statusLine = "Slice! \(score)"
      kind = .sliced
    } else {
      lives -= 1
      statusLine = "Missed \(fruit.direction.rawValue) — \(lives) lives left"
      kind = .missed
      loseIfNeeded()
    }
    publishOutcome(direction: fruit.direction, isBomb: fruit.isBomb, kind: kind)
    currentFruit = nil
  }

  private func publishOutcome(direction: GestureDirection, isBomb: Bool, kind: FruitOutcome.Kind) {
    lastOutcome = FruitOutcome(direction: direction, isBomb: isBomb, kind: kind)
    outcomeEventID += 1
  }

  private func loseIfNeeded() {
    if lives <= 0 {
      isFinished = true
      statusLine = "Game over · score \(score)"
      spawnTimer?.invalidate()
    }
  }

  private func scheduleSpawn() {
    let interval = max(0.6, 2.0 / difficulty)
    spawnTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, !self.isFinished else { return }
        // If previous fruit wasn't sliced in time, lose a life.
        if let previous = self.currentFruit, Date() > previous.expiresAt {
          if !previous.isBomb {
            self.lives -= 1
            self.statusLine = "Fruit escaped! \(self.lives) lives left"
            self.loseIfNeeded()
          }
          self.publishOutcome(
            direction: previous.direction, isBomb: previous.isBomb, kind: .expired)
          self.currentFruit = nil
        }
        let dirs: [GestureDirection] = [.up, .down, .left, .right]
        let dir = dirs.randomElement() ?? .up
        let isBomb = Double.random(in: 0...1) < 0.15
        self.currentFruit = Fruit(
          direction: dir,
          expiresAt: Date().addingTimeInterval(1.4),
          isBomb: isBomb
        )
        self.statusLine =
          isBomb
          ? "BOMB from \(dir.rawValue) — do NOT flick!"
          : "Fruit from \(dir.rawValue) — flick!"
        self.difficulty += 0.05
      }
    }
  }
}
