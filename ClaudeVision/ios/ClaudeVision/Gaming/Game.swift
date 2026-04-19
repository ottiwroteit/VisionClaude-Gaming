import Foundation
import Combine

/// Every motion-controlled game conforms to this. Games are state machines
/// that consume GestureEvents from GestureEngine and publish their own
/// view-facing state (score, phase, feedback text, etc.) via @Published.
@MainActor
protocol Game: AnyObject, ObservableObject {
    var id: String { get }
    var title: String { get }
    /// Short, one-sentence description of how to play with head motion.
    var howToPlay: String { get }
    /// Human-readable current state, e.g. "Frame 3 · Ready to bowl".
    var statusLine: String { get }
    /// Current score / points.
    var score: Int { get }
    /// True when the game has finished and should show a summary.
    var isFinished: Bool { get }

    func start()
    func reset()
    func handle(_ event: GestureEvent)
}
