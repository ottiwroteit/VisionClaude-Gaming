import SwiftUI
import Combine

/// Standalone SwiftUI screen that hosts the GameCoordinator. Present from
/// anywhere in the app once the Ray-Ban glasses are streaming:
///
///     GamingView(rayBan: rayBanManager)
///
/// The view wires the glasses camera frame publisher into the GestureEngine and
/// lets the user pick any registered Game.
struct GamingView: View {
    @ObservedObject var rayBan: RayBanManager
    @StateObject private var coordinator = GameCoordinator()
    @State private var hasRegisteredGames = false

    var body: some View {
        VStack(spacing: 16) {
            header

            if let activeID = coordinator.activeGameID,
               let game = coordinator.allGames.first(where: { $0.id == activeID }) {
                gameSurface(for: game)
            } else {
                gamePicker
            }

            liveMotionReadout
        }
        .padding()
        .background(Color.black.ignoresSafeArea())
        .foregroundColor(.white)
        .onAppear(perform: setupIfNeeded)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text("VisionClaude Gaming")
                .font(.title2).bold()
            Spacer()
            Image(systemName: rayBan.isRunning ? "eyeglasses" : "eyeglasses.slash")
                .foregroundColor(rayBan.isRunning ? .green : .gray)
        }
    }

    private var gamePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick a game").font(.headline)
            ForEach(coordinator.allGames, id: \.id) { game in
                Button {
                    coordinator.activate(gameID: game.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(game.title).font(.title3).bold()
                        Text(game.howToPlay).font(.caption).foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func gameSurface(for game: any Game) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("← Back") { coordinator.stop() }
                    .foregroundColor(.orange)
                Spacer()
                Text(game.title).font(.title3).bold()
            }
            Text(game.howToPlay).font(.caption).foregroundColor(.gray)

            Text(game.statusLine)
                .font(.title2).bold()
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)

            HStack {
                Text("Score").foregroundColor(.gray)
                Spacer()
                Text("\(game.score)").font(.title).bold()
            }

            if game.isFinished {
                Button("Play again") {
                    coordinator.activate(gameID: game.id)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            Spacer()
        }
    }

    private var liveMotionReadout: some View {
        VStack(spacing: 4) {
            ProgressView(value: Double(coordinator.engine.liveMagnitude), total: 2.0)
                .tint(.orange)
            Text(coordinator.lastEventLabel.isEmpty ? "waiting for motion…" : coordinator.lastEventLabel)
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }

    // MARK: - Setup

    private func setupIfNeeded() {
        guard !hasRegisteredGames else { return }
        coordinator.register(BowlingGame())
        coordinator.register(TennisGame())
        coordinator.register(PingPongGame())
        coordinator.register(BoxingGame())
        coordinator.register(ArcheryGame())
        coordinator.register(FruitSlashGame())
        coordinator.attach(frames: rayBan.$latestImage)
        hasRegisteredGames = true
    }
}
