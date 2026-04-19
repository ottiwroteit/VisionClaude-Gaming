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
            Halftone().ignoresSafeArea()

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
            VStack(alignment: .leading, spacing: -4) {
                Text("VisionClaude")
                    .font(.hype(14))
                    .foregroundColor(Theme.accent)
                    .tracking(4)
                Text("GAMING")
                    .font(.hype(42))
                    .foregroundColor(Theme.textPrimary)
                    .shadow(color: Theme.accent, radius: 0, x: 3, y: 3)
            }
            Spacer()
            Image(systemName: "eyeglasses")
                .font(.title)
                .foregroundColor(Theme.accent)
                .padding(10)
                .background(Circle().stroke(Theme.accent, lineWidth: 2))
        }
    }

    // MARK: - Connection Card

    private var connectionCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(rayBan.isRunning ? Theme.success.opacity(0.2) : Theme.surfaceStrong)
                    .frame(width: 44, height: 44)
                Circle().stroke(rayBan.isRunning ? Theme.success : Theme.stroke, lineWidth: 2)
                    .frame(width: 44, height: 44)
                Image(systemName: rayBan.isRunning ? "dot.radiowaves.left.and.right" : "eyeglasses.slash")
                    .foregroundColor(rayBan.isRunning ? Theme.success : Theme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(rayBan.isRunning ? "LINKED" : "OFFLINE")
                    .font(.hype(16)).foregroundColor(Theme.textPrimary)
                    .tracking(2)
                Text(subtitle)
                    .font(.caption).foregroundColor(Theme.textSecondary)
            }
            Spacer()
            if rayBan.isRunning {
                actionChip(label: "STOP", tint: Theme.danger) { rayBan.stop() }
            } else {
                actionChip(label: "START", tint: Theme.accent) { try? rayBan.start() }
            }
        }
        .padding(14)
        .celBorder(tint: rayBan.isRunning ? Theme.success : Theme.accent)
    }

    private func actionChip(label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.hype(13))
                .tracking(2)
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(tint)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
                .rotationEffect(.degrees(-2))
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        if rayBan.isRunning { return "\(rayBan.frameCount) frames captured" }
        if rayBan.isRegistered { return "Ready to stream" }
        return "Not connected"
    }

    // MARK: - Motion Meter

    private var motionMeter: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MOTION")
                    .font(.hype(14)).tracking(3)
                    .foregroundColor(Theme.accent)
                Spacer()
                Text(coordinator.lastEventLabel.isEmpty ? "idle" : coordinator.lastEventLabel.uppercased())
                    .font(.caption2.bold()).foregroundColor(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.surface)
                    // Chunky segmented fill — reads as energy bar, not progress bar.
                    let segments = 18
                    let magnitude = min(1.0, CGFloat(coordinator.engine.liveMagnitude))
                    let filled = Int(magnitude * CGFloat(segments))
                    HStack(spacing: 2) {
                        ForEach(0..<segments, id: \.self) { i in
                            Rectangle()
                                .fill(i < filled ? segmentColor(index: i, filled: filled) : Theme.surface)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
            }
            .frame(height: 14)
        }
        .padding(14)
        .celBorder(tint: Theme.accent)
    }

    private func segmentColor(index: Int, filled: Int) -> Color {
        let ratio = Double(index) / 18.0
        if ratio < 0.5 { return Theme.accent }
        if ratio < 0.8 { return Theme.success }
        return Theme.danger
    }

    // MARK: - Games

    private var gamesHeader: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("CHOOSE")
                .font(.hype(26)).foregroundColor(Theme.textPrimary)
                .tracking(3)
            Text("YOUR BATTLE")
                .font(.hype(26)).foregroundColor(Theme.accent)
                .tracking(3)
            Spacer()
            Text("\(coordinator.allGames.count)")
                .font(.hype(24))
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Rectangle().fill(Theme.accent))
                .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
                .rotationEffect(.degrees(-4))
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
                }
            }
        }
    }
}

// MARK: - GameCard

struct GameCard: View {
    let game: any Game
    let ready: Bool

    private var tintColor: Color { Theme.color(for: game.tint) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Icon block — thick square with hard shadow behind.
            ZStack {
                Rectangle()
                    .fill(tintColor)
                    .frame(width: 54, height: 54)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(.black)
            }
            .rotationEffect(.degrees(-4))
            .shadow(color: .black, radius: 0, x: 3, y: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(game.title.uppercased())
                    .font(.hype(22))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)
                    .shadow(color: tintColor, radius: 0, x: 2, y: 2)
                Text(game.howToPlay)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: ready ? "play.fill" : "lock.fill")
                Text(ready ? "READY" : "LOCKED")
                    .tracking(2)
            }
            .font(.hype(12))
            .foregroundColor(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(ready ? tintColor : Theme.surface)
            .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .celBorder(tint: tintColor, strokeWidth: ready ? 3 : 1.5)
        .opacity(ready ? 1.0 : 0.7)
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
