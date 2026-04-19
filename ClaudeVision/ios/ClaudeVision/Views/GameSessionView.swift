import SwiftUI
import Combine

/// The active gameplay screen. Chrome is shared across all games; the hero
/// area dispatches to a game-specific visualization based on game.id.
struct GameSessionView: View {
    @ObservedObject var coordinator: GameCoordinator
    @ObservedObject var rayBan: RayBanManager
    @Binding var selectedGameID: String?

    // Flash state — set by the last gesture event and fades within 500ms so
    // every flick/swing gets an anime-style "POW" confirmation.
    @State private var flashText: String = ""
    @State private var flashKey: UUID = UUID()
    @State private var flashOpacity: Double = 0
    @State private var eventSub: AnyCancellable?

    var body: some View {
        guard let game = activeGame else {
            return AnyView(EmptyView())
        }
        return AnyView(
            ZStack {
                Theme.background.ignoresSafeArea()
                Halftone().ignoresSafeArea()
                VStack(spacing: 16) {
                    topBar(for: game)
                    scoreRow(for: game)
                    heroContainer(for: game)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    coachingPanel(for: game)
                    liveMotionBar(for: game)
                }
                .padding(20)

                if flashOpacity > 0 {
                    BurstBadge(text: flashText, tint: tint(for: game), size: 180)
                        .opacity(flashOpacity)
                        .scaleEffect(0.7 + flashOpacity * 0.4)
                        .allowsHitTesting(false)
                        .id(flashKey)
                }

                if game.isFinished {
                    finishedOverlay(for: game)
                }
            }
            .onAppear { subscribeToEvents() }
            .onDisappear { eventSub = nil }
        )
    }

    private func subscribeToEvents() {
        eventSub = coordinator.engine.events
            .filter { $0.kind != .hold }
            .sink { event in
                flashText = "\(event.kind.rawValue.uppercased()) \(event.direction.rawValue.uppercased())!"
                flashKey = UUID()
                withAnimation(.easeOut(duration: 0.08)) { flashOpacity = 1 }
                withAnimation(.easeIn(duration: 0.45).delay(0.1)) { flashOpacity = 0 }
            }
    }

    private func heroContainer(for game: any Game) -> some View {
        ZStack {
            SpeedLines(tint: tint(for: game), intensity: CGFloat(min(1, coordinator.engine.liveMagnitude)))
            heroArt(for: game)
        }
    }

    private var activeGame: (any Game)? {
        coordinator.allGames.first(where: { $0.id == coordinator.activeGameID })
    }

    private func tint(for game: any Game) -> Color {
        Theme.color(for: game.tint)
    }

    // MARK: - Chrome

    private func topBar(for game: any Game) -> some View {
        HStack {
            Button {
                coordinator.stop()
                selectedGameID = nil
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("EXIT").tracking(2)
                }
                .font(.hype(14))
                .foregroundColor(.black)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(tint(for: game))
                .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
                .rotationEffect(.degrees(-3))
            }
            Spacer()
            Text(game.title.uppercased())
                .font(.hype(22))
                .foregroundColor(Theme.textPrimary)
                .shadow(color: tint(for: game), radius: 0, x: 2, y: 2)
            Spacer()
            Button {
                coordinator.activate(gameID: game.id)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.black)
                    .padding(8)
                    .background(Theme.textPrimary)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
                    .rotationEffect(.degrees(3))
            }
        }
    }

    private func scoreRow(for game: any Game) -> some View {
        HStack(spacing: 12) {
            BurstBadge(text: "\(game.score)", tint: tint(for: game), size: 88)
            VStack(alignment: .leading, spacing: 2) {
                Text("STATUS")
                    .font(.hype(12)).tracking(3)
                    .foregroundColor(tint(for: game))
                Text(game.statusLine)
                    .font(.hype(17))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .celBorder(tint: tint(for: game))
        }
    }

    private func coachingPanel(for game: any Game) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.black)
                .padding(6)
                .background(tint(for: game))
                .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
            Text(game.howToPlay)
                .font(.footnote.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .celBorder(tint: tint(for: game), strokeWidth: 2)
    }

    private func liveMotionBar(for game: any Game) -> some View {
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
                        .fill(tint(for: game))
                        .frame(width: min(proxy.size.width, CGFloat(coordinator.engine.liveMagnitude) * proxy.size.width))
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - Finished overlay

    private func finishedOverlay(for game: any Game) -> some View {
        VStack(spacing: 20) {
            Text("GAME\nOVER")
                .font(.hype(56))
                .foregroundColor(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .shadow(color: tint(for: game), radius: 0, x: 4, y: 4)
            BurstBadge(text: "\(game.score)", tint: tint(for: game), size: 140)
            Text("FINAL SCORE")
                .font(.hype(14)).tracking(4)
                .foregroundColor(Theme.textSecondary)
            HStack(spacing: 12) {
                Button {
                    coordinator.activate(gameID: game.id)
                } label: {
                    Text("REMATCH").tracking(3)
                        .font(.hype(16))
                        .foregroundColor(.black)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(tint(for: game))
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
                        .rotationEffect(.degrees(-2))
                }
                .buttonStyle(.plain)
                Button {
                    coordinator.stop()
                    selectedGameID = nil
                } label: {
                    Text("EXIT").tracking(3)
                        .font(.hype(16))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .overlay(Rectangle().stroke(.white, lineWidth: 2))
                        .rotationEffect(.degrees(2))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(32)
        .background(Theme.background)
        .overlay(Rectangle().stroke(tint(for: game), lineWidth: 4))
        .shadow(color: .black, radius: 0, x: 6, y: 8)
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
    private var tint: Color { Theme.color(for: game.tint) }
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(0..<10, id: \.self) { i in
                    Capsule()
                        .fill(i < game.pinsRemaining ? tint : Theme.surface)
                        .frame(width: 14, height: 40)
                }
            }
            .frame(maxWidth: .infinity)
            Rectangle()
                .fill(LinearGradient(colors: [Theme.surface, Theme.surfaceStrong], startPoint: .top, endPoint: .bottom))
                .frame(height: 140)
                .overlay(
                    Circle().fill(tint)
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
    private var tint: Color { Theme.color(for: game.tint) }
    var body: some View {
        VStack(spacing: 12) {
            Text("You \(game.score) · \(phaseLabel)")
                .font(.subheadline).foregroundColor(Theme.textSecondary)
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(tint.opacity(0.5), lineWidth: 2)
                VStack {
                    Rectangle().fill(Theme.stroke).frame(height: 1)
                }
                Circle().fill(tint)
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
    private var tint: Color { Theme.color(for: game.tint) }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                scoreTile(label: "You", value: game.score, highlight: true)
                Spacer()
                scoreTile(label: "CPU", value: game.cpuScore)
            }
            RoundedRectangle(cornerRadius: 10)
                .fill(tint.opacity(0.3))
                .frame(height: 140)
                .overlay(
                    HStack {
                        Rectangle().fill(tint).frame(width: 4, height: 60)
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
                .foregroundColor(highlight ? tint : Theme.textPrimary)
        }
    }
}

private struct BoxingArt: View {
    @ObservedObject var game: BoxingGame
    private var tint: Color { Theme.color(for: game.tint) }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                healthBar(label: "You", value: game.playerHealth, color: Theme.success)
                healthBar(label: "CPU", value: game.cpuHealth, color: tint)
            }
            ZStack {
                Circle().fill(tint.opacity(0.25)).frame(width: 140, height: 140)
                Image(systemName: "figure.boxing")
                    .font(.system(size: 60))
                    .foregroundColor(tint)
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
    private var tint: Color { Theme.color(for: game.tint) }
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                ForEach([50, 40, 30, 20, 10], id: \.self) { r in
                    Circle()
                        .stroke(tint.opacity(0.35), lineWidth: 1)
                        .frame(width: CGFloat(r) * 3, height: CGFloat(r) * 3)
                }
                Circle().fill(tint).frame(width: 12, height: 12)
            }
            .frame(height: 180)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Draw").font(.caption).foregroundColor(Theme.textSecondary)
                    Spacer()
                    Text("\(Int(game.drawStrength * 100))%")
                        .font(.caption.monospaced()).foregroundColor(tint)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surface)
                        Capsule().fill(tint)
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
    private var tint: Color { Theme.color(for: game.tint) }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i < game.lives ? "heart.fill" : "heart")
                        .foregroundColor(tint)
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.2))
                if let fruit = game.currentFruit {
                    Image(systemName: fruit.isBomb ? "bolt.fill" : "leaf.fill")
                        .font(.system(size: 70))
                        .foregroundColor(fruit.isBomb ? Theme.danger : tint)
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
                .foregroundColor(Theme.color(for: game.tint))
        }
    }
}
