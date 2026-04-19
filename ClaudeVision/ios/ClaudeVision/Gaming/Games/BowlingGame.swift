import Foundation

@MainActor
final class BowlingGame: ObservableObject, Game {
    let id = "bowling"
    let title = "Meta Bowling"
    let howToPlay = "Flick your chin up to roll. Harder flick = more power."

    @Published private(set) var score: Int = 0
    @Published private(set) var frame: Int = 1
    @Published private(set) var ballInFrame: Int = 1
    @Published private(set) var pinsRemaining: Int = 10
    @Published private(set) var lastRoll: Int = 0
    @Published private(set) var statusLine: String = "Frame 1 · Ready to bowl"
    @Published private(set) var isFinished: Bool = false

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
        score += knocked
        lastRoll = knocked

        let strike = ballInFrame == 1 && knocked == 10
        let spare = ballInFrame == 2 && pinsRemaining == 0

        if strike {
            statusLine = "STRIKE! \(knocked) pins · total \(score)"
            advanceFrame()
        } else if ballInFrame == 2 || spare {
            statusLine = (spare ? "Spare! " : "") + "Rolled \(knocked) · total \(score)"
            advanceFrame()
        } else {
            ballInFrame = 2
            statusLine = "Rolled \(knocked) · \(pinsRemaining) left — flick again"
        }
    }

    private func advanceFrame() {
        if frame >= totalFrames {
            isFinished = true
            statusLine = "Game over · final score \(score)"
            return
        }
        frame += 1
        ballInFrame = 1
        pinsRemaining = 10
        statusLine = "Frame \(frame) · Flick chin up to bowl"
    }

    /// Soft physics: low power rolls gutter, mid hits 4-7 pins, high flick is
    /// a strike candidate. Adds a small random jitter so every roll feels
    /// different without being unfair.
    private func pinsKnocked(power: Float, remaining: Int) -> Int {
        let clamped = max(0, min(1, power))
        let base = Float(remaining) * clamped
        let jitter = Float.random(in: -1.5...1.5)
        let raw = Int((base + jitter).rounded())
        return max(0, min(remaining, raw))
    }
}
