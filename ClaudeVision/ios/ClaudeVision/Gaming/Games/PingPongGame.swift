import Foundation

@MainActor
final class PingPongGame: ObservableObject, Game {
    let id = "pingpong"
    let title = "Meta Ping Pong"
    let howToPlay = "Quick chin nods + side tilts. Timing matters more than power."

    @Published private(set) var score: Int = 0
    @Published private(set) var cpuScore: Int = 0
    @Published private(set) var rally: Int = 0
    @Published private(set) var statusLine: String = "Rally starts — flick to return"
    @Published private(set) var isFinished: Bool = false

    /// Ping pong is twitch-reflex: we require flicks only, and each return
    /// has a short time window before the CPU scores.
    private var lastReturn: Date = .distantPast
    private let returnWindow: TimeInterval = 1.5

    func start() { reset() }

    func reset() {
        score = 0
        cpuScore = 0
        rally = 0
        isFinished = false
        lastReturn = Date()
        statusLine = "Rally starts — flick to return"
    }

    func handle(_ event: GestureEvent) {
        guard !isFinished else { return }
        let elapsed = Date().timeIntervalSince(lastReturn)
        if elapsed > returnWindow {
            cpuScore += 1
            rally = 0
            lastReturn = Date()
            statusLine = "Too slow! CPU \(cpuScore) – \(score)"
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
        } else {
            cpuScore += 1
            rally = 0
            statusLine = "Missed. CPU \(cpuScore) – \(score)"
            finishIfNeeded()
        }

        if rally >= 6 {
            score += 1
            rally = 0
            statusLine = "Point! \(score) – \(cpuScore)"
            finishIfNeeded()
        }
    }

    private func finishIfNeeded() {
        if score >= 11 || cpuScore >= 11 {
            isFinished = true
            statusLine = score > cpuScore
                ? "You win \(score)-\(cpuScore)"
                : "CPU wins \(cpuScore)-\(score)"
        }
    }
}
