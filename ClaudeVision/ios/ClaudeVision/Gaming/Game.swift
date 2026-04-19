import Foundation
import Combine

/// Every motion-controlled game conforms to this. Games are state machines
/// that consume GestureEvents from GestureEngine and publish their own
/// view-facing state (score, phase, feedback text, etc.) via @Published.
///
/// `changes` is an erased publisher the coordinator forwards so SwiftUI views
/// observing the coordinator re-render whenever the active game's state
/// advances. Each game implements it by mapping its own `objectWillChange`.
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

    var changes: AnyPublisher<Void, Never> { get }

    /// SwiftUI Color name used to tint the game card and hero art accents.
    /// Defaults to the global Theme.accent when nil.
    var tint: GameTint { get }

    /// Gesture classifier settings this game prefers. Returning nil keeps the
    /// engine's defaults. The coordinator applies these before `start()`.
    var preferredThresholds: MotionClassifier.Thresholds? { get }

    /// The venue modifier the game is currently playing under. Written by
    /// GameCoordinator during `activate()` so `handle()` can adjust scoring,
    /// difficulty, and behavior on a per-venue basis.
    var activeModifier: VenueModifier { get set }

    func start()
    func reset()
    func handle(_ event: GestureEvent)
}

extension Game where Self.ObjectWillChangePublisher == ObservableObjectPublisher {
    var changes: AnyPublisher<Void, Never> {
        objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }
}

extension Game {
    var tint: GameTint { .accent }
    var preferredThresholds: MotionClassifier.Thresholds? { nil }
}

/// Named tints so games can pick from a curated palette without each one
/// reaching for arbitrary colors. SwiftUI resolves these via Theme.color(for:).
enum GameTint: String {
    case accent     // default orange
    case court      // tennis green
    case table      // ping pong blue
    case ring       // boxing red
    case gold       // archery gold
    case berry      // fruit slash magenta
}
