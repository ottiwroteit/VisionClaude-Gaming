import Combine
import SwiftUI

/// The active gameplay screen. Chrome is shared across all games; the hero
/// area dispatches to a game-specific visualization based on game.id.
struct GameSessionView: View {
  @ObservedObject var coordinator: GameCoordinator
  @ObservedObject var rayBan: RayBanManager
  @ObservedObject var progress: ProgressStore
  var onExit: () -> Void

  // Flash state — set by the last gesture event and fades within 500ms so
  // every flick/swing gets an anime-style "POW" confirmation.
  @State private var flashText: String = ""
  @State private var flashKey: UUID = UUID()
  @State private var flashOpacity: Double = 0
  @State private var eventSub: AnyCancellable?

  @State private var shareImage: UIImage?
  @State private var showShareSheet = false

  var body: some View {
    guard let game = activeGame else {
      return AnyView(EmptyView())
    }
    let venue = progress.currentVenue(for: game.id)
    return AnyView(
      ZStack {
        // Venue sits at the very back — the whole session plays
        // inside the selected environment.
        venue.background
          .ignoresSafeArea()
        Color.black.opacity(0.35).ignoresSafeArea()
        Halftone().ignoresSafeArea()
        VStack(spacing: 16) {
          topBar(for: game, venue: venue)
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

        if let celebration = progress.pendingCelebration,
          celebration.gameID == game.id
        {
          UnlockCelebration(venue: celebration) {
            progress.acknowledgeCelebration(celebration)
          }
        }

        if game.isFinished {
          finishedOverlay(for: game)
        }
      }
      .onAppear {
        subscribeToEvents()
        // A flash from a prior session shouldn't carry over.
        progress.clearPendingHighScore()
      }
      .onDisappear {
        eventSub = nil
        progress.clearPendingHighScore()
      }
      .sheet(isPresented: $showShareSheet) {
        if let img = shareImage {
          ShareSheet(items: [img])
        }
      }
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
      SpeedLines(
        tint: tint(for: game), intensity: CGFloat(min(1, coordinator.engine.liveMagnitude)))
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

  private func topBar(for game: any Game, venue: Venue) -> some View {
    HStack {
      Button(action: onExit) {
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
      VStack(spacing: 0) {
        Text(game.title.uppercased())
          .font(.hype(20))
          .foregroundColor(Theme.textPrimary)
          .shadow(color: tint(for: game), radius: 0, x: 2, y: 2)
        Text("AT \(venue.name.uppercased())")
          .font(.hype(10)).tracking(2)
          .foregroundColor(Theme.textSecondary)
      }
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
    let venue = progress.currentVenue(for: game.id)
    return HStack(alignment: .top, spacing: 12) {
      Image(systemName: venue.modifier.flavorLine == nil ? "lightbulb.fill" : "sparkles")
        .foregroundColor(.black)
        .padding(6)
        .background(tint(for: game))
        .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
      VStack(alignment: .leading, spacing: 2) {
        Text(game.howToPlay)
          .font(.footnote.weight(.semibold))
          .foregroundColor(Theme.textPrimary)
        if let flavor = venue.modifier.flavorLine {
          Text(flavor.uppercased())
            .font(.hype(10)).tracking(2)
            .foregroundColor(tint(for: game))
        }
      }
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
            .frame(
              width: min(
                proxy.size.width, CGFloat(coordinator.engine.liveMagnitude) * proxy.size.width))
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
      if let flash = progress.pendingHighScore, flash.gameID == game.id {
        newRecordRibbon(flash: flash, tint: tint(for: game))
      } else {
        Text("FINAL SCORE")
          .font(.hype(14)).tracking(4)
          .foregroundColor(Theme.textSecondary)
      }
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
        Button(action: { prepareAndShare(for: game) }) {
          HStack(spacing: 4) {
            Image(systemName: "square.and.arrow.up")
            Text("SHARE").tracking(3)
          }
          .font(.hype(16))
          .foregroundColor(.black)
          .padding(.horizontal, 14).padding(.vertical, 10)
          .background(Theme.textPrimary)
          .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
        }
        .buttonStyle(.plain)
        Button(action: onExit) {
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

  private func prepareAndShare(for game: any Game) {
    let venue = progress.currentVenue(for: game.id)
    let isRecord = progress.pendingHighScore?.gameID == game.id
    let card = ShareCardView(
      gameTitle: game.title,
      venueName: venue.name,
      venueTagline: venue.tagline,
      venueBackground: venue.background,
      tint: tint(for: game),
      score: game.score,
      isNewRecord: isRecord
    )
    if let img = ShareCardRenderer.render(card) {
      shareImage = img
      showShareSheet = true
    }
  }

  private func newRecordRibbon(flash: ProgressStore.HighScoreFlash, tint: Color) -> some View {
    VStack(spacing: 4) {
      Text("NEW RECORD!")
        .font(.hype(18)).tracking(4)
        .foregroundColor(.black)
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(tint)
        .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
        .rotationEffect(.degrees(-3))
      Text("PREVIOUS BEST \(flash.previous)")
        .font(.hype(11)).tracking(3)
        .foregroundColor(Theme.textSecondary)
    }
  }

  // MARK: - Hero art dispatcher

  @ViewBuilder
  private func heroArt(for game: any Game) -> some View {
    switch game.id {
    case "bowling": if let g = game as? BowlingGame { BowlingArt(game: g) }
    case "tennis": if let g = game as? TennisGame { TennisArt(game: g) }
    case "pingpong": if let g = game as? PingPongGame { PingPongArt(game: g) }
    case "boxing": if let g = game as? BoxingGame { BoxingArt(game: g) }
    case "archery": if let g = game as? ArcheryGame { ArcheryArt(game: g) }
    case "fruitslash": if let g = game as? FruitSlashGame { FruitSlashArt(game: g) }
    default: GenericArt(game: game)
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

  // 1 = ball at the player end (bottom), 0 = ball at the pins (top).
  @State private var ballRollProgress: Double = 1

  var body: some View {
    VStack(spacing: 8) {
      HStack {
        Text("Frame \(game.frame)").font(.caption.bold())
        Text("·").foregroundColor(Theme.textSecondary)
        Text("Ball \(game.ballInFrame)").font(.caption.bold())
        Spacer()
        Text("\(game.pinsRemaining) pins")
          .font(.caption2).foregroundColor(Theme.textSecondary)
      }
      .foregroundColor(Theme.textPrimary)
      .padding(.horizontal, 4)

      GeometryReader { geo in
        ZStack {
          // Lane trapezoid — narrow at the top (far), wide at the
          // bottom (player) for forced perspective.
          BowlingLaneShape()
            .fill(
              LinearGradient(
                colors: [
                  Color(red: 0.42, green: 0.30, blue: 0.18),  // far wood
                  Color(red: 0.62, green: 0.45, blue: 0.28),  // near wood
                ],
                startPoint: .top,
                endPoint: .bottom
              )
            )
            .overlay(
              BowlingLaneShape()
                .stroke(Color.black.opacity(0.4), lineWidth: 1)
            )

          // Lane stripe down the middle for perspective hint.
          BowlingLaneStripe()
            .stroke(Color.white.opacity(0.15), lineWidth: 1)

          // Gutters — black bars on either side of the lane.
          BowlingGutterShape(side: .left)
            .fill(Color.black.opacity(0.85))
          BowlingGutterShape(side: .right)
            .fill(Color.black.opacity(0.85))

          // Pins in triangle formation at the back (top) of the lane.
          pinsLayout
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 14)

          // Ball — visible only while rolling/knocking, animates from
          // bottom (player) to top (pins) over the rolling phase.
          if showsBall {
            Circle()
              .fill(
                RadialGradient(
                  colors: [tint.opacity(0.95), tint.opacity(0.6)],
                  center: UnitPoint(x: 0.35, y: 0.35),
                  startRadius: 2,
                  endRadius: 25
                )
              )
              .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
              .frame(
                width: ballSize(progress: ballRollProgress),
                height: ballSize(progress: ballRollProgress)
              )
              .position(ballPosition(progress: ballRollProgress, geo: geo))
              .transition(.opacity)
          }
        }
      }
      .frame(height: 240)
      .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))

      HStack {
        Text("Total \(game.score)").font(.caption.bold())
        Spacer()
        Text(phaseHint)
          .font(.caption2)
          .foregroundColor(Theme.textSecondary)
      }
      .padding(.horizontal, 4)
    }
    .onChange(of: game.phase) { _, newPhase in
      switch newPhase {
      case .rolling:
        // Ball appears at the player end and rolls toward the pins.
        ballRollProgress = 1
        withAnimation(.easeIn(duration: 1.5)) {
          ballRollProgress = 0
        }
      case .knocking, .resetting, .idle, .finalScoring:
        // No ball animation — view either holds at pins (knocking) or
        // hides the ball entirely (idle/resetting/finalScoring).
        break
      }
    }
  }

  /// Ball is on screen during the roll itself and the brief pin-strike
  /// hold. Hidden between rolls so it doesn't sit "stuck" in the pins.
  private var showsBall: Bool {
    switch game.phase {
    case .rolling, .knocking: return true
    default: return false
    }
  }

  private var phaseHint: String {
    switch game.phase {
    case .idle:
      return game.lastRoll > 0 ? "Last roll: \(game.lastRoll)" : "Ready"
    case .rolling: return "Rolling…"
    case .knocking: return "Pins falling…"
    case .resetting: return "Resetting rack…"
    case .finalScoring: return "Game complete"
    }
  }

  // MARK: - Pin layout

  @ViewBuilder
  private var pinsLayout: some View {
    VStack(spacing: 4) {
      // Back row, 4 pins (display indices 6, 7, 8, 9).
      HStack(spacing: 5) {
        ForEach(6..<10, id: \.self) { idx in pin(displayIndex: idx) }
      }
      // 3 pins (3, 4, 5).
      HStack(spacing: 5) {
        ForEach(3..<6, id: \.self) { idx in pin(displayIndex: idx) }
      }
      // 2 pins (1, 2).
      HStack(spacing: 5) {
        ForEach(1..<3, id: \.self) { idx in pin(displayIndex: idx) }
      }
      // Front pin (0).
      pin(displayIndex: 0)
    }
    .frame(maxWidth: .infinity)
  }

  private func pin(displayIndex: Int) -> some View {
    // Pins fall front-first as the ball comes in. pinsRemaining=10 → none
    // fallen. pinsRemaining=7 → indices 0,1,2 fallen (front pin + row 2).
    let fallenCount = 10 - game.pinsRemaining
    let isFallen = displayIndex < fallenCount
    // Stable per-pin tilt direction so the same pin always falls the same
    // way (no flicker between renders).
    let tiltDeg = (displayIndex % 2 == 0 ? 1.0 : -1.0) * 55.0
    return BowlingPinShape()
      .fill(
        LinearGradient(
          colors: [Color.white, Color(white: 0.85)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .overlay(
        // Red neck stripe (real bowling pin detail).
        Rectangle()
          .fill(Color.red)
          .frame(width: 10, height: 2)
          .offset(y: -7)
      )
      .frame(width: 14, height: 30)
      .opacity(isFallen ? 0.25 : 1)
      .rotationEffect(.degrees(isFallen ? tiltDeg : 0), anchor: .bottom)
      .scaleEffect(y: isFallen ? 0.55 : 1, anchor: .bottom)
      .animation(.spring(response: 0.45, dampingFraction: 0.55), value: isFallen)
  }

  // MARK: - Ball trajectory

  private func ballPosition(progress: Double, geo: GeometryProxy) -> CGPoint {
    let w = geo.size.width
    let h = geo.size.height
    let x = w / 2
    // 1 → near (bottom 88%), 0 → far (top 22%).
    let y = lerp(h * 0.88, h * 0.22, 1 - progress)
    return CGPoint(x: x, y: y)
  }

  private func ballSize(progress: Double) -> CGFloat {
    // Ball appears smaller as it rolls into the distance (perspective).
    let near: CGFloat = 38
    let far: CGFloat = 18
    return CGFloat(lerp(Double(near), Double(far), 1 - progress))
  }

  private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
  }
}

// MARK: - Bowling shapes

private struct BowlingLaneShape: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    let topInset = rect.width * 0.22
    p.move(to: CGPoint(x: topInset, y: 0))
    p.addLine(to: CGPoint(x: rect.width - topInset, y: 0))
    p.addLine(to: CGPoint(x: rect.width, y: rect.height))
    p.addLine(to: CGPoint(x: 0, y: rect.height))
    p.closeSubpath()
    return p
  }
}

private struct BowlingLaneStripe: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: rect.midX, y: 0))
    p.addLine(to: CGPoint(x: rect.midX, y: rect.height))
    return p
  }
}

private struct BowlingGutterShape: Shape {
  enum Side { case left, right }
  let side: Side
  func path(in rect: CGRect) -> Path {
    var p = Path()
    let topInset = rect.width * 0.22
    switch side {
    case .left:
      p.move(to: CGPoint(x: 0, y: 0))
      p.addLine(to: CGPoint(x: topInset, y: 0))
      p.addLine(to: CGPoint(x: 0, y: rect.height))
      p.closeSubpath()
    case .right:
      p.move(to: CGPoint(x: rect.width - topInset, y: 0))
      p.addLine(to: CGPoint(x: rect.width, y: 0))
      p.addLine(to: CGPoint(x: rect.width, y: rect.height))
      p.closeSubpath()
    }
    return p
  }
}

private struct BowlingPinShape: Shape {
  /// Real bowling-pin silhouette: small head, narrow neck, wide belly,
  /// gentle waist, small flat base. Proportions taken from regulation
  /// USBC pin specs (head ≈ 47% of widest, neck ≈ 39%, belly = widest,
  /// base ≈ 43%) so it doesn't read as anything other than a pin.
  func path(in rect: CGRect) -> Path {
    var p = Path()
    let w = rect.width
    let h = rect.height
    let cx = w * 0.5

    // Half-widths (distance from center axis to silhouette edge).
    let headHalf = w * 0.235  // small head
    let neckHalf = w * 0.195  // narrowest waist
    let bellyHalf = w * 0.50  // widest point
    let waistHalf = w * 0.30  // gentle taper toward base
    let baseHalf = w * 0.215  // small foot

    let topY: CGFloat = 0
    let headY = h * 0.18
    let neckY = h * 0.30
    let bellyY = h * 0.62
    let waistY = h * 0.86
    let baseY = h * 1.0

    // Down the right side, top to bottom.
    p.move(to: CGPoint(x: cx, y: topY))
    p.addQuadCurve(
      to: CGPoint(x: cx + headHalf, y: headY),
      control: CGPoint(x: cx + headHalf, y: topY)
    )
    p.addQuadCurve(
      to: CGPoint(x: cx + neckHalf, y: neckY),
      control: CGPoint(x: cx + neckHalf, y: (headY + neckY) * 0.5)
    )
    p.addQuadCurve(
      to: CGPoint(x: cx + bellyHalf, y: bellyY),
      control: CGPoint(x: cx + bellyHalf, y: (neckY + bellyY) * 0.5)
    )
    p.addQuadCurve(
      to: CGPoint(x: cx + waistHalf, y: waistY),
      control: CGPoint(x: cx + waistHalf, y: (bellyY + waistY) * 0.5)
    )
    p.addLine(to: CGPoint(x: cx + baseHalf, y: baseY))
    // Across the bottom.
    p.addLine(to: CGPoint(x: cx - baseHalf, y: baseY))
    // Up the left side, bottom to top.
    p.addLine(to: CGPoint(x: cx - waistHalf, y: waistY))
    p.addQuadCurve(
      to: CGPoint(x: cx - bellyHalf, y: bellyY),
      control: CGPoint(x: cx - waistHalf, y: (bellyY + waistY) * 0.5)
    )
    p.addQuadCurve(
      to: CGPoint(x: cx - neckHalf, y: neckY),
      control: CGPoint(x: cx - bellyHalf, y: (neckY + bellyY) * 0.5)
    )
    p.addQuadCurve(
      to: CGPoint(x: cx - headHalf, y: headY),
      control: CGPoint(x: cx - neckHalf, y: (headY + neckY) * 0.5)
    )
    p.addQuadCurve(
      to: CGPoint(x: cx, y: topY),
      control: CGPoint(x: cx - headHalf, y: topY)
    )
    p.closeSubpath()
    return p
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
    case .serve: return "Serve"
    case .rally: return "Rally"
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
    case .up: return CGSize(width: 0, height: -50)
    case .down: return CGSize(width: 0, height: 50)
    case .left: return CGSize(width: -80, height: 0)
    case .right: return CGSize(width: 80, height: 0)
    default: return .zero
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
