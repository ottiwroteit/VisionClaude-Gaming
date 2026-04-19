import Foundation

@MainActor
final class ArcheryGame: ObservableObject, Game {
    let id = "archery"
    let title = "Meta Archery"
    let howToPlay = "Hold still to draw and aim. Flick chin up to release. Longer draw = more power."
    let tint: GameTint = .gold

    /// Archery lives on the hold channel — relax stillThreshold so natural
    /// micro-tremor doesn't cancel the draw, and shorten minHoldDuration so
    /// the drawStrength UI updates quickly as the player holds.
    var preferredThresholds: MotionClassifier.Thresholds? {
        var t = MotionClassifier.Thresholds()
        t.stillThreshold = 0.006
        t.minHoldDuration = 0.15
        t.activeThreshold = 0.018
        return t
    }

    @Published private(set) var score: Int = 0
    @Published private(set) var arrowsLeft: Int = 5
    @Published private(set) var drawStrength: Float = 0   // 0...1
    @Published private(set) var statusLine: String = "Hold still to draw"
    @Published private(set) var isFinished: Bool = false
    var activeModifier: VenueModifier = .default

    private var drawStart: Date?
    private let maxDraw: TimeInterval = 2.5

    func start() { reset() }

    func reset() {
        score = 0
        arrowsLeft = 5
        drawStrength = 0
        drawStart = nil
        isFinished = false
        statusLine = "Hold still to draw"
    }

    func handle(_ event: GestureEvent) {
        guard !isFinished else { return }

        if event.kind == .hold {
            if drawStart == nil { drawStart = event.timestamp }
            let held = event.timestamp.timeIntervalSince(drawStart ?? event.timestamp)
            drawStrength = Float(min(1, held / maxDraw))
            statusLine = "Drawing… \(Int(drawStrength * 100))%"
            return
        }

        if event.kind == .flick, event.direction == .up {
            fire()
        } else {
            // Any other motion cancels the draw.
            drawStart = nil
            drawStrength = 0
            statusLine = "Steady — hold still to draw"
        }
    }

    private func fire() {
        guard arrowsLeft > 0 else { return }
        var strength = drawStrength
        // Wind drift: randomly nudges perceived strength so the sweet spot
        // jitters even when the player nailed the draw.
        if activeModifier.effect == .windDrift {
            strength += Float.random(in: -0.12...0.12)
            strength = max(0, min(1, strength))
        }
        // High altitude: widens the bullseye band so near-misses still count big.
        let sweetRadius: Float = activeModifier.effect == .highAltitude ? 0.18 : 0.10
        let delta = abs(strength - 0.75)
        let rawPoints: Int
        switch delta {
        case ..<sweetRadius:         rawPoints = 10
        case ..<(sweetRadius + 0.10): rawPoints = 7
        case ..<(sweetRadius + 0.25): rawPoints = 4
        default:                      rawPoints = 1
        }
        let points = Int(Double(rawPoints) * activeModifier.scoreMultiplier)
        score += points
        arrowsLeft -= 1
        drawStrength = 0
        drawStart = nil
        statusLine = "Hit \(points) · \(arrowsLeft) arrows left"
        if arrowsLeft == 0 {
            isFinished = true
            statusLine = "Round complete · \(score) points"
        }
    }
}
