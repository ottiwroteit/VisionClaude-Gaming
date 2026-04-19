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
    @Published private(set) var playerHealth: Int = 100
    @Published private(set) var cpuHealth: Int = 100
    @Published private(set) var round: Int = 1
    @Published private(set) var incomingAttack: IncomingAttack = .none
    @Published private(set) var statusLine: String = "Round 1 — defend and counter"
    @Published private(set) var isFinished: Bool = false

    enum IncomingAttack: String { case none, jab, hookLeft, hookRight, uppercut }

    private var attackTimer: Timer?

    func start() {
        reset()
        scheduleNextAttack()
    }

    func reset() {
        score = 0
        playerHealth = 100
        cpuHealth = 100
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
            landPunch(damage: Int(10 + event.magnitude * 15), label: "Jab")
        } else if event.kind == .swing, event.direction == .left || event.direction == .right {
            landPunch(damage: Int(15 + event.magnitude * 20), label: "Hook \(event.direction.rawValue)")
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

    private func landPunch(damage: Int, label: String) {
        cpuHealth = max(0, cpuHealth - damage)
        score += damage
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
                        self.playerHealth = max(0, self.playerHealth - 12)
                        self.statusLine = "Took the \(self.incomingAttack.rawValue) · \(self.playerHealth) HP"
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
