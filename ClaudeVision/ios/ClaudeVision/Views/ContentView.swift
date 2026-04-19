import SwiftUI

/// Root router. Three states:
///   - glasses not registered / not streaming → GlassesSetupView
///   - streaming + active game selected       → GameSessionView
///   - streaming + no game selected           → HomeView
struct ContentView: View {
    @StateObject private var rayBan = RayBanManager()
    @StateObject private var coordinator = GameCoordinator()
    @State private var selectedGameID: String?
    @State private var hasBootstrapped = false

    var body: some View {
        Group {
            if !rayBan.isRegistered || !rayBan.isRunning {
                GlassesSetupView(rayBan: rayBan)
            } else if selectedGameID != nil {
                GameSessionView(
                    coordinator: coordinator,
                    rayBan: rayBan,
                    selectedGameID: $selectedGameID
                )
            } else {
                HomeView(
                    rayBan: rayBan,
                    coordinator: coordinator,
                    selectedGameID: $selectedGameID
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
