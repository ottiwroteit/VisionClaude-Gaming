import SwiftUI

/// The gaming home screen. Shows live glasses status at top and a grid of
/// motion-controlled games below. Selecting a game pushes into GameSessionView.
struct HomeView: View {
  @ObservedObject var rayBan: RayBanManager
  @ObservedObject var coordinator: GameCoordinator
  @ObservedObject var progress: ProgressStore
  var onPickGame: (String) -> Void
  var onRunScenario: (GestureRecorder.Script) -> Void

  @State private var showDebug = false

  var body: some View {
    ZStack {
      Theme.background.ignoresSafeArea()
      Halftone().ignoresSafeArea()

      ScrollView(.vertical) {
        VStack(spacing: 16) {
          header
          connectionCard
          dailyChallenge
          motionMeter
          gamesHeader
          gamesCarousel
        }
        .padding(20)
      }

      if let celebration = progress.pendingCelebration {
        UnlockCelebration(venue: celebration) {
          progress.acknowledgeCelebration(celebration)
        }
      }
    }
    .sheet(isPresented: $showDebug) {
      DebugPanelView(
        progress: progress,
        onRunScenario: { script in
          showDebug = false
          onRunScenario(script)
        },
        onDismiss: { showDebug = false }
      )
      .preferredColorScheme(.dark)
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
          .onLongPressGesture(minimumDuration: 0.8) {
            showDebug = true
          }
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

  private var dailyChallenge: some View {
    let challenge = progress.todaysChallenge
    let record = progress.challengeRecord(for: challenge)
    return DailyChallengeCard(challenge: challenge, record: record) {
      onPickGame(challenge.gameID)
    }
  }

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

  /// Horizontal carousel of game cards. Each card snaps to the viewport
  /// so one game is fully on-screen at a time with a hint of the next.
  /// The whole HomeView already scrolls vertically, so this section just
  /// scrolls sideways within its row.
  private var gamesCarousel: some View {
    GeometryReader { geo in
      let cardWidth = max(220, geo.size.width * 0.86)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 14) {
          ForEach(coordinator.allGames, id: \.id) { game in
            Button {
              onPickGame(game.id)
            } label: {
              GameCard(
                game: game,
                ready: rayBan.isRunning,
                venueName: progress.currentVenue(for: game.id).name,
                total: progress.total(for: game.id),
                nextUnlock: progress.progressToNextUnlock(for: game.id)?.next
              )
              .frame(width: cardWidth)
            }
            .buttonStyle(.plain)
            .disabled(!rayBan.isRunning)
          }
        }
        .padding(.horizontal, 4)
        .scrollTargetLayoutCompat()
      }
      .scrollTargetBehaviorViewAlignedCompat()
    }
    .frame(height: 280)
  }
}

// MARK: - iOS 17 scroll-snap shims
// `scrollTargetLayout()` and `scrollTargetBehavior(.viewAligned)` are
// iOS 17+. Wrap them in no-op shims so the file compiles on older
// SDKs while still snapping on iOS 17+.

extension View {
  @ViewBuilder
  fileprivate func scrollTargetLayoutCompat() -> some View {
    if #available(iOS 17.0, *) {
      self.scrollTargetLayout()
    } else {
      self
    }
  }

  @ViewBuilder
  fileprivate func scrollTargetBehaviorViewAlignedCompat() -> some View {
    if #available(iOS 17.0, *) {
      self.scrollTargetBehavior(.viewAligned)
    } else {
      self
    }
  }
}

// MARK: - GameCard

struct GameCard: View {
  let game: any Game
  let ready: Bool
  let venueName: String
  let total: Int
  let nextUnlock: Int?

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
          .font(.hype(20))
          .foregroundColor(Theme.textPrimary)
          .lineLimit(2)
          .shadow(color: tintColor, radius: 0, x: 2, y: 2)
        HStack(spacing: 4) {
          Image(systemName: "mappin.circle.fill")
            .font(.caption2)
          Text(venueName)
            .lineLimit(1)
        }
        .font(.caption2.weight(.bold))
        .foregroundColor(tintColor)
      }
      Spacer(minLength: 0)
      progressBar
      HStack(spacing: 6) {
        Image(systemName: ready ? "play.fill" : "lock.fill")
        Text(ready ? "READY" : "LOCKED")
          .tracking(2)
      }
      .font(.hype(11))
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

  @ViewBuilder
  private var progressBar: some View {
    if let next = nextUnlock {
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text("\(total)").font(.hype(11)).foregroundColor(tintColor)
          Text("/ \(next)").font(.hype(11)).foregroundColor(Theme.textSecondary)
        }
        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Rectangle().fill(Theme.surface).frame(height: 4)
            Rectangle()
              .fill(tintColor)
              .frame(width: proxy.size.width * progressFraction(next: next), height: 4)
          }
        }
        .frame(height: 4)
      }
    } else if total > 0 {
      Text("ALL UNLOCKED · \(total) PTS")
        .font(.hype(10)).tracking(2)
        .foregroundColor(Theme.success)
    }
  }

  private func progressFraction(next: Int) -> CGFloat {
    guard next > 0 else { return 1 }
    return min(1, max(0, CGFloat(total) / CGFloat(next)))
  }

  private var icon: String {
    switch game.id {
    case "bowling": return "figure.bowling"
    case "tennis": return "figure.tennis"
    case "pingpong": return "figure.table.tennis"
    case "boxing": return "figure.boxing"
    case "archery": return "scope"
    case "fruitslash": return "scissors"
    default: return "gamecontroller.fill"
    }
  }
}
