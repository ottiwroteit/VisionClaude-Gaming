import SwiftUI

/// The gaming home screen. Shows live glasses status at top and a grid of
/// motion-controlled games below. Selecting a game pushes into GameSessionView.
struct HomeView: View {
    @ObservedObject var rayBan: RayBanManager
    @ObservedObject var coordinator: GameCoordinator
    @Binding var selectedGameID: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 20) {
                header
                connectionCard
                motionMeter
                gamesHeader
                gamesGrid
                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VisionClaude")
                    .font(.caption).foregroundColor(Theme.textSecondary)
                Text("Gaming")
                    .font(.largeTitle.bold()).foregroundColor(Theme.textPrimary)
            }
            Spacer()
            Image(systemName: "eyeglasses")
                .font(.title2)
                .foregroundColor(Theme.accent)
        }
    }

    // MARK: - Connection Card

    private var connectionCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.surfaceStrong).frame(width: 44, height: 44)
                Image(systemName: rayBan.isRunning ? "dot.radiowaves.left.and.right" : "eyeglasses.slash")
                    .foregroundColor(rayBan.isRunning ? Theme.success : Theme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(rayBan.isRunning ? "Glasses streaming" : rayBan.glassesName)
                    .font(.subheadline.bold()).foregroundColor(Theme.textPrimary)
                Text(subtitle)
                    .font(.caption).foregroundColor(Theme.textSecondary)
            }
            Spacer()
            if rayBan.isRunning {
                Button("Stop") { rayBan.stop() }
                    .font(.caption.bold())
                    .foregroundColor(Theme.danger)
            } else {
                Button("Start") { try? rayBan.start() }
                    .font(.caption.bold())
                    .foregroundColor(Theme.accent)
            }
        }
        .cardStyle()
    }

    private var subtitle: String {
        if rayBan.isRunning { return "\(rayBan.frameCount) frames captured" }
        if rayBan.isRegistered { return "Ready to stream" }
        return "Not connected"
    }

    // MARK: - Motion Meter

    private var motionMeter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Motion")
                    .font(.caption.bold()).foregroundColor(Theme.textSecondary)
                Spacer()
                Text(coordinator.lastEventLabel.isEmpty ? "idle" : coordinator.lastEventLabel)
                    .font(.caption2).foregroundColor(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: min(proxy.size.width, CGFloat(coordinator.engine.liveMagnitude) * proxy.size.width))
                }
            }
            .frame(height: 6)
        }
        .cardStyle()
    }

    // MARK: - Games

    private var gamesHeader: some View {
        HStack {
            Text("Pick a game")
                .font(.title3.bold()).foregroundColor(Theme.textPrimary)
            Spacer()
            Text("\(coordinator.allGames.count)")
                .font(.caption).foregroundColor(Theme.textSecondary)
        }
    }

    private var gamesGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(coordinator.allGames, id: \.id) { game in
                    Button {
                        coordinator.activate(gameID: game.id)
                        selectedGameID = game.id
                    } label: {
                        GameCard(game: game, ready: rayBan.isRunning)
                    }
                    .buttonStyle(.plain)
                    .disabled(!rayBan.isRunning)
                    .opacity(rayBan.isRunning ? 1.0 : 0.55)
                }
            }
        }
    }
}

// MARK: - GameCard

struct GameCard: View {
    let game: any Game
    let ready: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.surfaceStrong))
            VStack(alignment: .leading, spacing: 4) {
                Text(game.title)
                    .font(.headline).foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Text(game.howToPlay)
                    .font(.caption2).foregroundColor(Theme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: ready ? "play.fill" : "lock.fill")
                Text(ready ? "Play" : "Needs feed")
            }
            .font(.caption2.bold())
            .foregroundColor(ready ? Theme.accent : Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .cardStyle()
    }

    private var icon: String {
        switch game.id {
        case "bowling":    return "figure.bowling"
        case "tennis":     return "figure.tennis"
        case "pingpong":   return "figure.table.tennis"
        case "boxing":     return "figure.boxing"
        case "archery":    return "scope"
        case "fruitslash": return "scissors"
        default:           return "gamecontroller.fill"
        }
    }
}
