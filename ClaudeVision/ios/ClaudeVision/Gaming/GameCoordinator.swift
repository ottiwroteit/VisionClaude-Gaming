import Foundation
import Combine
import UIKit

/// Wires the Ray-Ban frame stream into GestureEngine and routes gesture events
/// into the currently selected Game. One coordinator per session; swap games
/// at runtime without restarting the camera.
@MainActor
final class GameCoordinator: ObservableObject {

    @Published private(set) var activeGameID: String?
    @Published private(set) var lastEventLabel: String = ""

    let engine = GestureEngine()
    private var games: [String: any Game] = [:]
    private var activeGame: (any Game)?
    private var eventSubscription: AnyCancellable?
    private var frameSubscription: AnyCancellable?
    private var activeGameSubscription: AnyCancellable?

    init() {
        eventSubscription = engine.events.sink { [weak self] event in
            guard let self else { return }
            self.lastEventLabel = "\(event.kind.rawValue) \(event.direction.rawValue) m=\(String(format: "%.2f", event.magnitude))"
            self.activeGame?.handle(event)
        }
    }

    func register(_ game: any Game) {
        games[game.id] = game
    }

    var allGames: [any Game] {
        games.values.sorted { $0.title < $1.title }
    }

    func activate(gameID: String) {
        activeGame?.reset()
        activeGameSubscription = nil
        activeGame = games[gameID]
        activeGameID = gameID
        if let game = activeGame {
            // Forward the game's state changes so SwiftUI views observing the
            // coordinator re-render when score/statusLine/isFinished change.
            activeGameSubscription = game.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            game.start()
        }
        engine.start()
    }

    func stop() {
        engine.stop()
        activeGame?.reset()
        activeGame = nil
        activeGameID = nil
    }

    /// Subscribe to a FrameSource's latest-image publisher and pipe frames in.
    func attach<P: Publisher>(frames: P) where P.Output == UIImage?, P.Failure == Never {
        frameSubscription = frames
            .compactMap { $0 }
            .throttle(for: .milliseconds(33), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] image in
                self?.engine.ingest(image: image)
            }
    }
}
