import SwiftUI

/// Root router. Four states:
///   - glasses not registered / not streaming → GlassesSetupView
///   - streaming, no game picked              → HomeView
///   - game picked, no venue confirmed        → VenueSelectView
///   - venue confirmed, session active        → GameSessionView
struct ContentView: View {
    @StateObject private var rayBan = RayBanManager()
    @StateObject private var coordinator = GameCoordinator()
    @StateObject private var progress = ProgressStore.shared
    @State private var pickedGameID: String?
    @State private var sessionGameID: String?
    @State private var hasBootstrapped = false

    var body: some View {
        Group {
            if !rayBan.isRegistered || !rayBan.isRunning {
                GlassesSetupView(rayBan: rayBan)
            } else if let id = sessionGameID {
                GameSessionView(
                    coordinator: coordinator,
                    rayBan: rayBan,
                    progress: progress,
                    onExit: {
                        coordinator.stop()
                        sessionGameID = nil
                        pickedGameID = nil
                    }
                )
                .id(id) // Force a fresh session view when game changes.
            } else if let id = pickedGameID,
                      let game = coordinator.allGames.first(where: { $0.id == id }) {
                VenueSelectView(
                    progress: progress,
                    game: game,
                    onStart: { _ in
                        coordinator.activate(gameID: id)
                        sessionGameID = id
                    },
                    onCancel: { pickedGameID = nil }
                )
            } else {
                HomeView(
                    rayBan: rayBan,
                    coordinator: coordinator,
                    progress: progress,
                    onPickGame: { pickedGameID = $0 }
                )
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: bootstrap)
        .onDisappear {
            rayBan.cleanup()
            coordinator.stop()
        }
    }

    private func bootstrap() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        rayBan.configure(frameInterval: 1.0, jpegQuality: 0.5)
        rayBan.startMonitoringRegistration()
        coordinator.register(BowlingGame())
        coordinator.register(TennisGame())
        coordinator.register(PingPongGame())
        coordinator.register(BoxingGame())
        coordinator.register(ArcheryGame())
        coordinator.register(FruitSlashGame())
        coordinator.attach(frames: rayBan.$latestImage)
    }
}
