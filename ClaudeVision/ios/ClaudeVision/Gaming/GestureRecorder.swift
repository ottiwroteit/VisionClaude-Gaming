import Foundation
import Combine
import simd

/// Records GestureEvents emitted by GestureEngine into a timestamped script,
/// and replays scripts back into an active Game so we can iterate on game
/// mechanics and UI without wearing the glasses.
///
/// This deliberately operates at the *gesture* layer, not the raw flow
/// layer. It's a game-logic testing tool, not a classifier-tuning tool.
@MainActor
final class GestureRecorder: ObservableObject {

    struct Script: Codable, Identifiable {
        struct Step: Codable {
            let delay: TimeInterval       // seconds after previous step
            let kind: String              // GestureKind.rawValue
            let direction: String         // GestureDirection.rawValue
            let magnitude: Float
            let duration: TimeInterval
        }
        let id: String
        let label: String
        let gameID: String
        var steps: [Step]
    }

    @Published private(set) var isRecording = false
    @Published private(set) var recordedSteps: [Script.Step] = []

    private var captureStart: Date?
    private var lastStepAt: Date?
    private var engineSub: AnyCancellable?

    // MARK: - Recording

    func startRecording(source: GestureEngine) {
        recordedSteps = []
        captureStart = Date()
        lastStepAt = captureStart
        isRecording = true
        engineSub = source.events
            .filter { $0.kind != .hold }
            .sink { [weak self] event in
                self?.capture(event)
            }
    }

    func stopRecording(label: String, gameID: String) -> Script {
        isRecording = false
        engineSub = nil
        let script = Script(
            id: UUID().uuidString,
            label: label,
            gameID: gameID,
            steps: recordedSteps
        )
        return script
    }

    private func capture(_ event: GestureEvent) {
        let now = Date()
        let delay = now.timeIntervalSince(lastStepAt ?? now)
        lastStepAt = now
        recordedSteps.append(
            .init(
                delay: delay,
                kind: event.kind.rawValue,
                direction: event.direction.rawValue,
                magnitude: event.magnitude,
                duration: event.duration
            )
        )
    }

    // MARK: - Replay

    private var replayTask: Task<Void, Never>?

    /// Fires each step into the GestureEngine's event publisher directly,
    /// bypassing the classifier. Consumers (games) don't know the difference.
    func replay(_ script: Script, into engine: GestureEngine) {
        replayTask?.cancel()
        replayTask = Task { @MainActor [weak engine] in
            guard let engine else { return }
            for step in script.steps {
                let ns = UInt64(max(0, step.delay) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                if Task.isCancelled { return }
                guard let kind = GestureKind(rawValue: step.kind),
                      let direction = GestureDirection(rawValue: step.direction) else { continue }
                let event = GestureEvent(
                    kind: kind,
                    direction: direction,
                    magnitude: step.magnitude,
                    peakVelocity: 0,
                    duration: step.duration,
                    vector: .zero,
                    timestamp: Date()
                )
                engine.events.send(event)
            }
        }
    }

    func stopReplay() {
        replayTask?.cancel()
        replayTask = nil
    }
}
