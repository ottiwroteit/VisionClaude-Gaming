import Foundation

@MainActor
final class TennisGame: ObservableObject, Game {
    let id = "tennis"
    let title = "Meta Tennis"
    let howToPlay = "Turn head right = forehand, left = backhand, chin up = serve."

    enum Phase: String { case serve, rally, pointOver }

    @Published private(set) var score: Int = 0
    @Published private(set) var playerGames: Int = 0
    @Published private(set) var cpuGames: Int = 0
    @Published private(set) var phase: Phase = .serve
    @Published private(set) var statusLine: String = "Chin up to serve"
    @Published private(set) var isFinished: Bool = false
    @Published private(set) var rallyCount: Int = 0

    func start() { reset() }

    func reset() {
        score = 0
        playerGames = 0
        cpuGames = 0
        phase = .serve
        rallyCount = 0
        isFinished = false
        statusLine = "Chin up to serve"
    }

    func handle(_ event: GestureEvent) {
        guard !isFinished, event.kind == .flick || event.kind == .swing else { return }
        switch phase {
        case .serve:
            guard event.direction == .up else {
                statusLine = "Fault — flick chin up to serve"
                return
            }
            phase = .rally
            rallyCount = 1
            statusLine = "Serve in · incoming return"
        case .rally:
            guard event.direction == .left || event.direction == .right else {
                statusLine = "Mishit — turn head to return"
                phase = .pointOver
                awardPoint(toPlayer: false)
                return
            }
            rallyCount += 1
            // Probability of winning the point scales with power and alternates returns.
            let winChance = 0.35 + Double(event.magnitude) * 0.5
            if Double.random(in: 0...1) < winChance {
                if rallyCount >= Int.random(in: 3...6) {
                    awardPoint(toPlayer: true)
                } else {
                    statusLine = "Deep \(event.direction.rawValue) — CPU returns"
                }
            } else {
                awardPoint(toPlayer: false)
            }
        case .pointOver:
            phase = .serve
            statusLine = "Chin up to serve"
        }
    }

    private func awardPoint(toPlayer: Bool) {
        if toPlayer {
            score += 1
            statusLine = "Winner! (\(score))"
        } else {
            statusLine = "CPU wins the point"
        }
        phase = .pointOver
        if score >= 4 {
            playerGames += 1
            score = 0
            if playerGames >= 3 {
                isFinished = true
                statusLine = "Game, set, match · you win!"
            }
        }
    }
}
