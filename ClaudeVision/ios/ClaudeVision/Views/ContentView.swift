import SwiftUI

/// Root router.
///   - Dev scenario active              → GameSessionView in replay mode
///   - Glasses not registered / streaming → GlassesSetupView
///   - Game picked, no venue confirmed    → VenueSelectView
///   - Venue confirmed, session active    → GameSessionView
///   - Otherwise                          → HomeView
struct ContentView: View {
  @StateObject private var rayBan = RayBanManager()
  @StateObject private var coordinator = GameCoordinator()
  @StateObject private var progress = ProgressStore.shared
  @StateObject private var recorder = GestureRecorder()
  @State private var pickedGameID: String?
  @State private var sessionGameID: String?
  @State private var devScript: GestureRecorder.Script?
  @State private var hasBootstrapped = false
  @State private var showingSplash = true
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Group {
      if showingSplash {
        LaunchSplashView { showingSplash = false }
      } else if let script = devScript {
        // Replay mode: glasses aren't required, scenario drives the game.
        GameSessionView(
          coordinator: coordinator,
          rayBan: rayBan,
          progress: progress,
          onExit: exitSession
        )
        .id("dev-\(script.id)")
        .onAppear { runDevScript(script) }
      } else if !rayBan.isRegistered || !rayBan.isRunning {
        GlassesSetupView(rayBan: rayBan)
      } else if let id = sessionGameID {
        GameSessionView(
          coordinator: coordinator,
          rayBan: rayBan,
          progress: progress,
          onExit: exitSession
        )
        .id(id)  // Force a fresh session view when game changes.
      } else if let id = pickedGameID,
        let game = coordinator.allGames.first(where: { $0.id == id })
      {
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
          onPickGame: { pickedGameID = $0 },
          onRunScenario: { devScript = $0 }
        )
      }
    }
    .preferredColorScheme(.dark)
    .onAppear(perform: bootstrap)
    .onDisappear {
      rayBan.cleanup()
      coordinator.stop()
    }
    .onChange(of: scenePhase) { _, newPhase in
      // Background/inactive transitions are the only reliable hook for
      // cleanup before the app is killed. Without this, an Xcode kill
      // can leave the MWDAT DeviceSession alive cross-process and the
      // next launch errors with `sessionAlreadyExists`.
      if newPhase == .background {
        rayBan.cleanup()
      }
    }
  }

  private func exitSession() {
    recorder.stopReplay()
    coordinator.stop()
    sessionGameID = nil
    pickedGameID = nil
    devScript = nil
  }

  private func runDevScript(_ script: GestureRecorder.Script) {
    coordinator.activate(gameID: script.gameID)
    recorder.replay(script, into: coordinator.engine)
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
    coordinator.register(JamarioGame())
    coordinator.register(JamarioStreetsGame())
    coordinator.register(FirefoxGame())
    coordinator.attach(frames: rayBan.$latestImage)
  }
}
