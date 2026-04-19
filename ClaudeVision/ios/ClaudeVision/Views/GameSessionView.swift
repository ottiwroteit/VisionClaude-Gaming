import SwiftUI

/// The active gameplay screen. Chrome is shared across all games; the hero
/// area dispatches to a game-specific visualization based on game.id.
struct GameSessionView: View {
    @ObservedObject var coordinator: GameCoordinator
    @ObservedObject var rayBan: RayBanManager
    @Binding var selectedGameID: String?

    var body: some View {
        guard let game = activeGame else {
            return AnyView(EmptyView())
        }
        return AnyView(
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    topBar(for: game)
                    scoreRow(for: game)
                    heroArt(for: game)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    coachingPanel(for: game)
                    liveMotionBar
                }
                .padding(20)

                if game.isFinished {
                    finishedOverlay(for: game)
                }
            }
        )
    }

    private var activeGame: (any Game)? {
        coordinator.allGames.first(where: { $0.id == coordinator.activeGameID })
    }

    // MARK: - Chrome

    private func topBar(for game: any Game) -> some View {
        HStack {
            Button {
                coordinator.stop()
                selectedGameID = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Home")
                }
                .font(.subheadline.bold())
                .foregroundColor(Theme.accent)
            }
            Spacer()
            Text(game.title)
                .font(.headline)
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Button {
                coordinator.activate(gameID: game.id)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.subheadline.bold())
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }

    private func scoreRow(for game: any Game) -> some View {
        HStack(spacing: 16) {
            metric(label: "Score", value: "\(game.score)")
            Divider().frame(height: 32).overlay(Theme.stroke)
            metric(label: "Status", value: game.statusLine, wide: true)
        }
        .cardStyle()
    }

    private func metric(label: String, value: String, wide: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2).foregroundColor(Theme.textSecondary)
                .tracking(1.2)
            Text(value)
                .font(wide ? .subheadline.bold() : .title2.bold())
                .foregroundColor(Theme.textPrimary)
                .lineLimit(2)
        }
        .frame(maxWidth: wide ? .infinity : nil, alignment: .leading)
    }

    private func coachingPanel(for game: any Game) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(Theme.accent)
            Text(game.howToPlay)
                .font(.footnote)
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle()
    }

    private var liveMotionBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Live motion").font(.caption2).foregroundColor(Theme.textSecondary)
                Spacer()
                Text(coordinator.lastEventLabel.isEmpty ? "—" : coordinator.lastEventLabel)
                    .font(.caption2.monospaced())
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: min(proxy.size.width, CGFloat(coordinator.engine.liveMagnitude) * proxy.size.width))
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - Finished overlay

    private func finishedOverlay(for game: any Game) -> some View {
        VStack(spacing: 16) {
            Text("Game over")
                .font(.title.bold()).foregroundColor(Theme.textPrimary)
            Text("Final score \(game.score)")
                .font(.title2).foregroundColor(Theme.accent)
            HStack(spacing: 12) {
                Button("Play again") {
                    coordinator.activate(gameID: game.id)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
                Button("Home") {
                    coordinator.stop()
                    selectedGameID = nil
                }
                .buttonStyle(.bordered).tint(.white)
            }
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.large)
                .fill(Theme.background)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.large)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
        )
        .shadow(radius: 40)
    }

    // MARK: - Hero art dispatcher

    @ViewBuilder
    private func heroArt(for game: any Game) -> some View {
        switch game.id {
        case "bowling":    if let g = game as? BowlingGame    { BowlingArt(game: g) }
        case "tennis":     if let g = game as? TennisGame     { TennisArt(game: g) }
        case "pingpong":   if let g = game as? PingPongGame   { PingPongArt(game: g) }
        case "boxing":     if let g = game as? BoxingGame     { BoxingArt(game: g) }
        case "archery":    if let g = game as? ArcheryGame    { ArcheryArt(game: g) }
        case "fruitslash": if let g = game as? FruitSlashGame { FruitSlashArt(game: g) }
        default:           GenericArt(game: game)
        }
    }
}

// MARK: - Per-Game Hero Art
// Each of these is a lightweight SwiftUI visualization that reads published
// state directly from its game object. The look is intentionally minimal and
// symbolic — the goal is to communicate "what just happened" in a glance.

private struct BowlingArt: View {
    @ObservedObject var game: BowlingGame
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(0..<10, id: \.self) { i in
                    Capsule()
                        .fill(i < game.pinsRemaining ? Theme.accent : Theme.surface)
                        .frame(width: 14, height: 40)
                }
            }
            .frame(maxWidth: .infinity)
            Rectangle()
                .fill(LinearGradient(colors: [Theme.surface, Theme.surfaceStrong], startPoint: .top, endPoint: .bottom))
                .frame(height: 140)
                .overlay(
                    Circle().fill(Theme.accent)
                        .frame(width: 38, height: 38)
                        .offset(y: 46)
                )
                .cornerRadius(Theme.Radius.medium)
            Text("Frame \(game.frame) · Ball \(game.ballInFrame)")
                .font(.caption).foregroundColor(Theme.textSecondary)
        }
    }
}

private struct TennisArt: View {
    @ObservedObject var game: TennisGame
    var body: some View {
        VStack(spacing: 12) {
            Text("You \(game.score) · \(phaseLabel)")
                .font(.subheadline).foregroundColor(Theme.textSecondary)
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.accent.opacity(0.4), lineWidth: 2)
                VStack {
                    Rectangle().fill(Theme.stroke).frame(height: 1)
                }
                Circle().fill(Theme.accent)
                    .frame(width: 18, height: 18)
                    .offset(y: game.phase == .rally ? -40 : 40)
                    .animation(.easeInOut(duration: 0.4), value: game.phase)
            }
            .frame(height: 180)
            Text("Rally \(game.rallyCount)")
                .font(.caption).foregroundColor(Theme.textSecondary)
        }
    }
    private var phaseLabel: String {
        switch game.phase {
        case .serve:     return "Serve"
        case .rally:     return "Rally"
        case .pointOver: return "Point over"
        }
    }
}

private struct PingPongArt: View {
    @ObservedObject var game: PingPongGame
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                scoreTile(label: "You", value: game.score, highlight: true)
                Spacer()
                scoreTile(label: "CPU", value: game.cpuScore)
            }
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.surfaceStrong)
                .frame(height: 140)
                .overlay(
                    HStack {
                        Rectangle().fill(Theme.accent).frame(width: 4, height: 60)
                        Spacer()
                        Circle().fill(.white).frame(width: 12, height: 12)
                        Spacer()
                        Rectangle().fill(Theme.danger).frame(width: 4, height: 60)
                    }
                    .padding(12)
                )
            Text("Rally \(game.rally)")
                .font(.caption).foregroundColor(Theme.textSecondary)
        }
    }
    private func scoreTile(label: String, value: Int, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundColor(Theme.textSecondary)
            Text("\(value)").font(.title.bold())
                .foregroundColor(highlight ? Theme.accent : Theme.textPrimary)
        }
    }
}

private struct BoxingArt: View {
    @ObservedObject var game: BoxingGame
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                healthBar(label: "You", value: game.playerHealth, color: Theme.success)
                healthBar(label: "CPU", value: game.cpuHealth, color: Theme.danger)
            }
            ZStack {
                Circle().fill(Theme.surfaceStrong).frame(width: 140, height: 140)
                Image(systemName: "figure.boxing")
                    .font(.system(size: 60))
                    .foregroundColor(Theme.accent)
                if game.incomingAttack != .none {
                    Text("⚠ \(game.incomingAttack.rawValue)")
                        .font(.caption.bold())
                        .padding(6)
                        .background(Capsule().fill(Theme.danger))
                        .offset(y: -90)
                }
            }
            Text("Round \(game.round)")
                .font(.caption).foregroundColor(Theme.textSecondary)
        }
    }
    private func healthBar(label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundColor(Theme.textSecondary)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface)
                    Capsule().fill(color)
                        .frame(width: proxy.size.width * CGFloat(value) / 100)
                }
            }
            .frame(height: 8)
        }
    }
}

private struct ArcheryArt: View {
    @ObservedObject var game: ArcheryGame
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                ForEach([50, 40, 30, 20, 10], id: \.self) { r in
                    Circle()
                        .stroke(Theme.textSecondary.opacity(0.3), lineWidth: 1)
                        .frame(width: CGFloat(r) * 3, height: CGFloat(r) * 3)
                }
                Circle().fill(Theme.accent).frame(width: 12, height: 12)
            }
            .frame(height: 180)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Draw").font(.caption).foregroundColor(Theme.textSecondary)
                    Spacer()
                    Text("\(Int(game.drawStrength * 100))%")
                        .font(.caption.monospaced()).foregroundColor(Theme.accent)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surface)
                        Capsule().fill(Theme.accent)
                            .frame(width: proxy.size.width * CGFloat(game.drawStrength))
                    }
                }
                .frame(height: 6)
            }
            Text("\(game.arrowsLeft) arrows left")
                .font(.caption).foregroundColor(Theme.textSecondary)
        }
    }
}

private struct FruitSlashArt: View {
    @ObservedObject var game: FruitSlashGame
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i < game.lives ? "heart.fill" : "heart")
                        .foregroundColor(Theme.danger)
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceStrong)
                if let fruit = game.currentFruit {
                    Image(systemName: fruit.isBomb ? "bolt.fill" : "leaf.fill")
                        .font(.system(size: 70))
                        .foregroundColor(fruit.isBomb ? Theme.danger : Theme.accent)
                        .offset(fruitOffset(for: fruit.direction))
                        .transition(.scale)
                        .id(fruit.id)
                }
            }
            .frame(height: 180)
            .animation(.easeInOut(duration: 0.25), value: game.currentFruit?.id)
        }
    }
    private func fruitOffset(for direction: GestureDirection) -> CGSize {
        switch direction {
        case .up:    return CGSize(width: 0, height: -50)
        case .down:  return CGSize(width: 0, height: 50)
        case .left:  return CGSize(width: -80, height: 0)
        case .right: return CGSize(width: 80, height: 0)
        default:     return .zero
        }
    }
}

private struct GenericArt: View {
    let game: any Game
    var body: some View {
        VStack {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 80))
                .foregroundColor(Theme.accent)
        }
    }
}
