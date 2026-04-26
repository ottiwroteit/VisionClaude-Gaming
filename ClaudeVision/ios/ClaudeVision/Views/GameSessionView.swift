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
  /// Coaching panels the player has explicitly dismissed (per game id).
  /// Once you tap the X you don't see the how-to-play hint again this
  /// session.
  @State private var dismissedCoaching: Set<String> = []
  /// Per-aim-window state for the bowling ball picker. After the
  /// player taps the X on the picker card, it stays hidden until the
  /// next `.idle` phase begins (next ball / next frame).
  @State private var bowlingPickerDismissed: Bool = false

  var body: some View {
    guard let game = activeGame else {
      return AnyView(EmptyView())
    }
    let venue = progress.currentVenue(for: game.id)
    let isBowling = game.id == "bowling"
    return AnyView(
      ZStack {
        // Venue sits at the very back — the whole session plays
        // inside the selected environment.
        venue.background
          .ignoresSafeArea()
        Color.black.opacity(isBowling ? 0.10 : 0.35).ignoresSafeArea()
        Halftone().ignoresSafeArea().opacity(isBowling ? 0.35 : 1)

        if isBowling {
          // Bowling gets a full-bleed lane with the chrome overlaid on
          // top. Other games keep the windowed layout below.
          heroContainer(for: game)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
          if let bowlingGame = game as? BowlingGame {
            BowlingPinTracker(game: bowlingGame, tint: tint(for: game))
              .padding(.top, 150)
              .padding(.leading, 14)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
              .allowsHitTesting(false)
          }
        }

        VStack(spacing: isBowling ? 8 : 16) {
          topBar(for: game, venue: venue)
          if !isBowling {
            scoreRow(for: game)
            heroContainer(for: game)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            // Bowling: top bar stays at the top; everything else gets
            // pushed to the bottom of the screen so the lane is visible
            // through the middle. Order from the bottom up: motion bar,
            // coaching panel, scoreboard, ball picker.
            Spacer(minLength: 0)
            if let bowlingGame = game as? BowlingGame,
              bowlingGame.phase == .idle,
              !bowlingPickerDismissed
            {
              bowlingBallPickerSection(for: bowlingGame)
            }
            BowlingScoreboard(frames: bowlingFrames(game), total: game.score)
              .fixedSize(horizontal: false, vertical: true)
              .background(.ultraThinMaterial)
              .clipShape(RoundedRectangle(cornerRadius: 6))
          }
          if !dismissedCoaching.contains(game.id) {
            coachingPanel(for: game)
              .background(.ultraThinMaterial.opacity(isBowling ? 0.95 : 0))
              .clipShape(
                RoundedRectangle(cornerRadius: isBowling ? 12 : 0))
          }
          liveMotionBar(for: game)
            .background(.ultraThinMaterial.opacity(isBowling ? 0.85 : 0))
            .clipShape(
              RoundedRectangle(cornerRadius: isBowling ? 8 : 0))
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
      .onChange(of: (game as? BowlingGame)?.phase) { _, newPhase in
        // A new aim window resets the picker dismissal so the player
        // gets a fresh choice for each ball.
        if newPhase == .idle {
          bowlingPickerDismissed = false
        }
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

  /// Pulls the frame breakdown off the game when it's bowling — falls
  /// back to an empty array for other game types so the helper can be
  /// called unconditionally from the chrome layout.
  private func bowlingFrames(_ game: any Game) -> [BowlingGame.FrameDisplay] {
    (game as? BowlingGame)?.frameDisplays ?? []
  }

  /// Wraps the BowlingBallPicker with a top-trailing close button. A
  /// horizontal swipe-to-dismiss conflicted with the picker's internal
  /// horizontal scroll so we use an explicit X tap instead — picker
  /// auto-comes-back on the next aim window via the `.onChange(of:
  /// phase)` reset on the body.
  private func bowlingBallPickerSection(for game: BowlingGame) -> some View {
    BowlingBallPicker(game: game, tint: tint(for: game))
      .overlay(alignment: .topTrailing) {
        Button {
          withAnimation(.easeOut(duration: 0.18)) {
            bowlingPickerDismissed = true
          }
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 11, weight: .black))
            .foregroundColor(.white)
            .padding(6)
            .background(Color.black.opacity(0.55))
            .clipShape(Circle())
            .overlay(Circle().stroke(tint(for: game), lineWidth: 1.5))
            .padding(6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide ball picker")
      }
      .transition(.opacity)
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
      Button {
        withAnimation(.easeOut(duration: 0.18)) {
          _ = dismissedCoaching.insert(game.id)
        }
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(Theme.textSecondary)
          .padding(6)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Dismiss instructions")
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
    case "bowling":
      if let g = game as? BowlingGame {
        BowlingScene(game: g, venueID: progress.currentVenue(for: g.id).id)
      }
    case "tennis":
      if let g = game as? TennisGame {
        TennisScene(game: g, venueID: progress.currentVenue(for: g.id).id)
      }
    case "pingpong":
      if let g = game as? PingPongGame {
        PingPongScene(game: g, venueID: progress.currentVenue(for: g.id).id)
      }
    case "boxing":
      if let g = game as? BoxingGame {
        BoxingScene(
          game: g,
          venueID: progress.currentVenue(for: g.id).id,
          tint: tint(for: g))
      }
    case "archery":
      if let g = game as? ArcheryGame {
        ArcheryScene(game: g, venueID: progress.currentVenue(for: g.id).id)
      }
    case "fruitslash":
      if let g = game as? FruitSlashGame {
        FruitSlashScene(game: g, venueID: progress.currentVenue(for: g.id).id)
      }
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
  // Lane shake offset for celebration impact. Decays back to .zero.
  @State private var shakeOffset: CGSize = .zero

  var body: some View {
    GeometryReader { outerGeo in
      laneStack(outerGeo: outerGeo)
    }
    .ignoresSafeArea()
  }

  @ViewBuilder
  private func laneStack(outerGeo: GeometryProxy) -> some View {
    GeometryReader { geo in
      ZStack {
        // Lane trapezoid — narrow at the top (far), wide at the
        // bottom (player) for forced perspective.
        BowlingLaneShape()
          .fill(
            LinearGradient(
              colors: [
                Color(red: 0.32, green: 0.22, blue: 0.12),  // far wood (deeper)
                Color(red: 0.68, green: 0.50, blue: 0.30),  // near wood (warmer)
              ],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .overlay(
            // Wood-grain plank lines running down the lane.
            BowlingLaneShape()
              .clipShape(BowlingLaneShape())
              .overlay(BowlingLaneGrain())
              .opacity(0.25)
          )
          .overlay(
            // Glossy reflective sheen — light vertical band centered.
            BowlingLaneShape()
              .fill(
                LinearGradient(
                  colors: [
                    Color.white.opacity(0.18),
                    Color.white.opacity(0.0),
                  ],
                  startPoint: .top,
                  endPoint: .bottom
                )
              )
              .blendMode(.screen)
          )
          .overlay(
            BowlingLaneShape()
              .stroke(Color.black.opacity(0.5), lineWidth: 1)
          )

        // Lane stripe down the middle for perspective hint.
        BowlingLaneStripe()
          .stroke(Color.white.opacity(0.18), lineWidth: 1)

        // Gutters — recessed channels.
        BowlingGutterShape(side: .left)
          .fill(
            LinearGradient(
              colors: [Color.black, Color(white: 0.15)],
              startPoint: .leading, endPoint: .trailing
            )
          )
        BowlingGutterShape(side: .right)
          .fill(
            LinearGradient(
              colors: [Color(white: 0.15), Color.black],
              startPoint: .leading, endPoint: .trailing
            )
          )

        // Pins in triangle formation at the back (top) of the lane.
        pinsLayout
          .frame(maxHeight: .infinity, alignment: .top)
          .padding(.top, 14)

        // QubicaAMF-style pinspotter: overhead rack that descends to
        // pick up standing pins, sweep bar that clears fallen pins.
        BowlingPinSpotter(
          phase: game.phase,
          laneWidth: geo.size.width,
          laneHeight: geo.size.height
        )

        // Aim guide — visible only while the player is lining up the
        // shot (phase == .idle). A faint dotted line plus a marker
        // shows where the ball is currently aimed.
        if game.phase == .idle {
          BowlingAimGuide(
            aim: game.aimPosition,
            tint: tint,
            laneWidth: geo.size.width,
            laneHeight: geo.size.height
          )
        }

        // Arcade 3-2-1 countdown overlay before each turn.
        if let n = game.countdownValue {
          BowlingCountdown(value: n, tint: tint)
            .frame(width: geo.size.width, height: geo.size.height)
            .allowsHitTesting(false)
        }

        // Ball — visible only while rolling/knocking, animates from
        // bottom (player) to top (pins). On a gutter ball it curves
        // toward the appropriate side instead of going straight.
        if showsBall {
          // Light trail behind the ball — tapered streak fading
          // toward the back of the lane. Strike/spare get a hotter
          // gradient so the celebration reads even before pins fall.
          let trailColors: [Color] =
            (game.isOnFire || game.lastOutcome == .strike)
            ? [Color.yellow, Color.orange, Color.red.opacity(0)]
            : [tint.opacity(0.9), tint.opacity(0.5), tint.opacity(0)]
          ballTrail(in: geo, colors: trailColors)

          // Soft glow under the ball.
          Circle()
            .fill(tint.opacity(0.55))
            .frame(
              width: ballSize(progress: ballRollProgress) * 1.6,
              height: ballSize(progress: ballRollProgress) * 1.6
            )
            .blur(radius: 14)
            .position(ballPosition(progress: ballRollProgress, geo: geo))

          BowlingBallView(
            size: ballSize(progress: ballRollProgress),
            tint: tint,
            skin: game.activeSkin
          )
          .rotation3DEffect(
            .degrees(720 * (1 - ballRollProgress)),
            axis: (1, 0, 0)
          )
          .position(ballPosition(progress: ballRollProgress, geo: geo))
          .transition(.opacity)
        }

        // Strike / spare celebration: particle burst + giant pop-up text.
        BowlingCelebration(
          outcome: game.lastOutcome,
          rollNumber: game.rollNumber,
          laneWidth: geo.size.width,
          laneHeight: geo.size.height,
          tint: tint
        )
        .allowsHitTesting(false)
      }
    }
    // Lane fills the entire screen. Pre-rotation it sits a bit larger
    // than the screen so once we tilt it backward there's still depth
    // to recede into.
    .frame(width: outerGeo.size.width, height: outerGeo.size.height * 1.35)
    .rotation3DEffect(
      .degrees(-38),
      axis: (1, 0, 0),
      anchor: .bottom,
      anchorZ: 0,
      perspective: 0.95
    )
    // Camera-follow zoom: as the ball travels, scale up slightly with
    // the anchor at the top (pin end) so the view "drives in" toward
    // the pins. ~1.0 → 1.18 over the roll.
    .scaleEffect(
      1.0 + (1.0 - ballRollProgress) * 0.18,
      anchor: .top
    )
    .frame(width: outerGeo.size.width, height: outerGeo.size.height)
    .offset(x: shakeOffset.width, y: shakeOffset.height)
    .onChange(of: game.rollNumber) { _, _ in
      guard let outcome = game.lastOutcome else { return }
      if outcome == .strike {
        shake(intensity: 8)
      } else if outcome == .spare {
        shake(intensity: 4)
      }
    }
    .onChange(of: game.phase) { _, newPhase in
      switch newPhase {
      case .rolling:
        // Ball appears at the player end and rolls toward the pins.
        ballRollProgress = 1
        withAnimation(.easeIn(duration: 1.5)) {
          ballRollProgress = 0
        }
      case .knocking, .resetting, .idle, .countingDown, .finalScoring:
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
    case .countingDown: return "Get ready…"
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
    return ZStack(alignment: .bottom) {
      // Soft elliptical shadow under each pin so the rack reads as 3D
      // resting on the lane.
      Ellipse()
        .fill(Color.black.opacity(isFallen ? 0.12 : 0.35))
        .frame(width: 14, height: 5)
        .blur(radius: 1.5)
        .offset(y: 4)

      BowlingPinShape()
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
    .frame(width: 14, height: 30)
  }

  // MARK: - Ball trajectory

  private func ballPosition(progress: Double, geo: GeometryProxy) -> CGPoint {
    let w = geo.size.width
    let h = geo.size.height
    let centerX = w / 2

    // The ball travels in a straight line along the aim vector — aim of
    // 0 = down the middle, ±1 ≈ deep gutter. If the model flagged this
    // roll as a gutter ball we still use a quadratic curve so it visually
    // sweeps into the gutter rather than landing flat.
    let aim = CGFloat(game.aimPosition)
    var x = centerX + aim * (w * 0.42) * CGFloat(1 - progress)
    if let gutter = game.gutter {
      let t = 1 - progress
      let curve = t * t
      let gutterX: CGFloat = (gutter == .left) ? w * 0.08 : w * 0.92
      x = CGFloat(lerp(Double(centerX), Double(gutterX), Double(curve)))
    }

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

  /// Tapered light streak behind the rolling ball. Drawn as a thick
  /// stroke from the player's release point to the ball's current
  /// position so the trail naturally narrows in screen space (the
  /// rotation3DEffect on the parent does the perspective work).
  private func ballTrail(in geo: GeometryProxy, colors: [Color]) -> some View {
    let p0 = ballPosition(progress: 1, geo: geo)
    let p1 = ballPosition(progress: ballRollProgress, geo: geo)
    return Path { path in
      path.move(to: p0)
      path.addLine(to: p1)
    }
    .stroke(
      LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top),
      style: StrokeStyle(lineWidth: ballSize(progress: ballRollProgress) * 0.8, lineCap: .round)
    )
    .blur(radius: 4)
    .opacity(0.85)
  }

  /// Three-stage screen shake: snap one direction, snap the other, settle.
  /// Intensity is the peak offset in points.
  private func shake(intensity: CGFloat) {
    let i = intensity
    Task { @MainActor in
      withAnimation(.easeOut(duration: 0.06)) { shakeOffset = CGSize(width: -i, height: i / 2) }
      try? await Task.sleep(nanoseconds: 60_000_000)
      withAnimation(.easeInOut(duration: 0.08)) { shakeOffset = CGSize(width: i, height: -i / 2) }
      try? await Task.sleep(nanoseconds: 80_000_000)
      withAnimation(.easeInOut(duration: 0.08)) {
        shakeOffset = CGSize(width: -i / 2, height: i / 3)
      }
      try? await Task.sleep(nanoseconds: 80_000_000)
      withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { shakeOffset = .zero }
    }
  }
}

// MARK: - Bowling shapes

// Lane geometry — kept consistent across lane / gutter shapes so the
// gutters sit flush alongside the lane in correct forced perspective.
private enum LaneGeo {
  static let topLaneInset: CGFloat = 0.32  // lane edge at far end
  static let bottomLaneInset: CGFloat = 0.13  // lane edge at near end
  static let topGutterOuter: CGFloat = 0.18  // gutter outer edge at far end
}

private struct BowlingLaneShape: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    let w = rect.width
    let h = rect.height
    let topInset = w * LaneGeo.topLaneInset
    let bottomInset = w * LaneGeo.bottomLaneInset
    p.move(to: CGPoint(x: topInset, y: 0))
    p.addLine(to: CGPoint(x: w - topInset, y: 0))
    p.addLine(to: CGPoint(x: w - bottomInset, y: h))
    p.addLine(to: CGPoint(x: bottomInset, y: h))
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
    let w = rect.width
    let h = rect.height
    let laneTop = w * LaneGeo.topLaneInset
    let laneBottom = w * LaneGeo.bottomLaneInset
    let outerTop = w * LaneGeo.topGutterOuter
    switch side {
    case .left:
      // Gutter is the strip between the rect's left edge and the lane.
      p.move(to: CGPoint(x: outerTop, y: 0))
      p.addLine(to: CGPoint(x: laneTop, y: 0))
      p.addLine(to: CGPoint(x: laneBottom, y: h))
      p.addLine(to: CGPoint(x: 0, y: h))
      p.closeSubpath()
    case .right:
      p.move(to: CGPoint(x: w - laneTop, y: 0))
      p.addLine(to: CGPoint(x: w - outerTop, y: 0))
      p.addLine(to: CGPoint(x: w, y: h))
      p.addLine(to: CGPoint(x: w - laneBottom, y: h))
      p.closeSubpath()
    }
    return p
  }
}

// MARK: - Bowling ball with finger holes

private struct BowlingBallView: View {
  let size: CGFloat
  let tint: Color
  var skin: BowlingGame.BallSkin = .classic

  var body: some View {
    ZStack {
      // Base sphere with the skin's tint/pattern.
      base
      // Finger holes — drawn AFTER the skin so even patterned balls
      // still read as bowling balls.
      fingerHoles
      // Fire skin gets an additional flame halo around the ball.
      if skin == .fire {
        fireHalo
      }
    }
    .frame(width: size, height: size)
    .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1))
  }

  @ViewBuilder
  private var base: some View {
    switch skin {
    case .classic:
      Circle().fill(
        RadialGradient(
          colors: [tint.opacity(0.95), tint.opacity(0.55)],
          center: UnitPoint(x: 0.32, y: 0.32),
          startRadius: max(2, size * 0.05),
          endRadius: size * 0.7
        ))
    case .skull:
      // Sugar-skull style: white base with red/black face glyphs.
      Circle().fill(
        RadialGradient(
          colors: [Color.white, Color(white: 0.85)],
          center: UnitPoint(x: 0.3, y: 0.3),
          startRadius: 2, endRadius: size * 0.7
        ))
      // Eye sockets.
      Group {
        Circle().fill(Color.red.opacity(0.85))
          .frame(width: size * 0.18, height: size * 0.18)
          .offset(x: -size * 0.16, y: -size * 0.08)
        Circle().fill(Color.red.opacity(0.85))
          .frame(width: size * 0.18, height: size * 0.18)
          .offset(x: size * 0.16, y: -size * 0.08)
      }
    case .superhero:
      Circle().fill(
        RadialGradient(
          colors: [
            Color(red: 0.10, green: 0.18, blue: 0.55), Color(red: 0.05, green: 0.10, blue: 0.30),
          ],
          center: UnitPoint(x: 0.3, y: 0.3),
          startRadius: 2, endRadius: size * 0.7
        ))
      // Lightning-bolt glyph.
      Image(systemName: "bolt.fill")
        .font(.system(size: size * 0.5, weight: .black))
        .foregroundColor(.yellow)
        .shadow(color: .yellow.opacity(0.6), radius: 3)
    case .eightBall:
      Circle().fill(
        RadialGradient(
          colors: [Color(white: 0.18), Color.black],
          center: UnitPoint(x: 0.3, y: 0.3),
          startRadius: 2, endRadius: size * 0.7
        ))
      // White roundel with "8".
      Circle().fill(Color.white).frame(width: size * 0.45, height: size * 0.45)
      Text("8")
        .font(.system(size: size * 0.32, weight: .black))
        .foregroundColor(.black)
    case .basketball:
      Circle().fill(
        RadialGradient(
          colors: [
            Color(red: 0.85, green: 0.42, blue: 0.18), Color(red: 0.55, green: 0.25, blue: 0.10),
          ],
          center: UnitPoint(x: 0.3, y: 0.3),
          startRadius: 2, endRadius: size * 0.7
        ))
      // Seam lines.
      Path { p in
        p.move(to: CGPoint(x: 0, y: size * 0.5))
        p.addLine(to: CGPoint(x: size, y: size * 0.5))
        p.move(to: CGPoint(x: size * 0.5, y: 0))
        p.addLine(to: CGPoint(x: size * 0.5, y: size))
        p.move(to: CGPoint(x: size * 0.15, y: size * 0.15))
        p.addQuadCurve(
          to: CGPoint(x: size * 0.85, y: size * 0.15),
          control: CGPoint(x: size * 0.5, y: size * 0.45)
        )
        p.move(to: CGPoint(x: size * 0.15, y: size * 0.85))
        p.addQuadCurve(
          to: CGPoint(x: size * 0.85, y: size * 0.85),
          control: CGPoint(x: size * 0.5, y: size * 0.55)
        )
      }
      .stroke(Color.black.opacity(0.7), lineWidth: 1.5)
      .clipShape(Circle())
    case .soccer:
      Circle().fill(Color.white)
      // Black pentagon center.
      Pentagon()
        .fill(Color.black)
        .frame(width: size * 0.32, height: size * 0.32)
      // Surrounding pentagon hints.
      ForEach(0..<5, id: \.self) { i in
        Pentagon()
          .fill(Color.black.opacity(0.85))
          .frame(width: size * 0.14, height: size * 0.14)
          .offset(
            x: cos(Double(i) * .pi * 2 / 5 - .pi / 2) * Double(size) * 0.3,
            y: sin(Double(i) * .pi * 2 / 5 - .pi / 2) * Double(size) * 0.3
          )
      }
      .clipShape(Circle())
    case .fire:
      Circle().fill(
        RadialGradient(
          colors: [
            Color.yellow,
            Color.orange,
            Color.red,
          ],
          center: UnitPoint(x: 0.3, y: 0.3),
          startRadius: 2, endRadius: size * 0.7
        ))
    }
  }

  private var fingerHoles: some View {
    Group {
      Circle()
        .fill(Color.black.opacity(0.7))
        .frame(width: size * 0.13, height: size * 0.13)
        .offset(x: -size * 0.18, y: -size * 0.10)
      Circle()
        .fill(Color.black.opacity(0.7))
        .frame(width: size * 0.10, height: size * 0.10)
        .offset(x: size * 0.18, y: -size * 0.06)
      Circle()
        .fill(Color.black.opacity(0.7))
        .frame(width: size * 0.10, height: size * 0.10)
        .offset(x: 0, y: size * 0.12)
    }
  }

  private var fireHalo: some View {
    ZStack {
      Circle()
        .fill(Color.orange.opacity(0.55))
        .frame(width: size * 1.6, height: size * 1.6)
        .blur(radius: 16)
      Circle()
        .fill(Color.yellow.opacity(0.4))
        .frame(width: size * 1.2, height: size * 1.2)
        .blur(radius: 10)
    }
  }
}

// MARK: - Bowling ball picker
// Horizontal row of thumbnails — tap to set the player's preferred
// ball skin. Lives in the chrome overlay so the player can change
// between rolls. The "fire" skin is excluded; it's auto-applied
// during a 3+ strike streak and not user-pickable.

struct BowlingBallPicker: View {
  @ObservedObject var game: BowlingGame
  let tint: Color

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(BowlingGame.BallSkin.allCases.filter { $0 != .fire }) { skin in
          Button {
            game.selectedSkin = skin
          } label: {
            VStack(spacing: 3) {
              ZStack {
                if skin == game.selectedSkin {
                  Circle()
                    .stroke(tint, lineWidth: 3)
                    .frame(width: 44, height: 44)
                }
                BowlingBallView(size: 36, tint: tint, skin: skin)
              }
              Text(skin.displayName)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
    }
    .background(.ultraThinMaterial.opacity(0.85))
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }
}

private struct Pentagon: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    let r = min(rect.width, rect.height) / 2
    let cx = rect.midX
    let cy = rect.midY
    for i in 0..<5 {
      let angle = Double(i) * .pi * 2 / 5 - .pi / 2
      let x = cx + CGFloat(cos(angle)) * r
      let y = cy + CGFloat(sin(angle)) * r
      if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    p.closeSubpath()
    return p
  }
}

// MARK: - Bowling lane wood grain
// Vertical plank lines (with mild perspective inset toward the top) to
// suggest a polished wood lane. Drawn as paths so they line up with the
// trapezoid lane shape.

private struct BowlingLaneGrain: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    let w = rect.width
    let h = rect.height
    let topInset = w * LaneGeo.topLaneInset
    let bottomInset = w * LaneGeo.bottomLaneInset
    let topLane = w - 2 * topInset
    let bottomLane = w - 2 * bottomInset
    let planks = 7
    for i in 0...planks {
      let frac = CGFloat(i) / CGFloat(planks)
      let topX = topInset + frac * topLane
      let bottomX = bottomInset + frac * bottomLane
      p.move(to: CGPoint(x: bottomX, y: h))
      p.addLine(to: CGPoint(x: topX, y: 0))
    }
    return
      p
      .strokedPath(StrokeStyle(lineWidth: 0.5, lineCap: .round))
  }
}

// MARK: - Bowling celebration overlay
// Strike → giant "STRIKE!" pop-up + radial particle burst from the pin
// area. Spare → softer "SPARE!" pop-up + smaller burst. Triggered off
// game.rollNumber so re-entering the same outcome still re-fires.

private struct BowlingCelebration: View {
  let outcome: BowlingGame.RollOutcome?
  let rollNumber: Int
  let laneWidth: CGFloat
  let laneHeight: CGFloat
  let tint: Color

  @State private var lastShownRoll: Int = 0
  @State private var visibleOutcome: BowlingGame.RollOutcome? = nil
  @State private var textScale: CGFloat = 0.3
  @State private var textOpacity: Double = 0
  @State private var particles: [Particle] = []

  private struct Particle: Identifiable {
    let id = UUID()
    let angle: Double
    let distance: CGFloat
    let size: CGFloat
    let color: Color
    var progress: CGFloat = 0
  }

  var body: some View {
    ZStack {
      // Particles emanating from the pin area (top-center).
      ForEach(particles) { p in
        Circle()
          .fill(p.color)
          .frame(width: p.size, height: p.size)
          .position(
            x: laneWidth / 2 + cos(p.angle) * p.distance * p.progress,
            y: laneHeight * 0.25 + sin(p.angle) * p.distance * p.progress
          )
          .opacity(Double(1 - p.progress))
      }

      // Big pop-up text.
      if let o = visibleOutcome, let label = label(for: o) {
        Text(label)
          .font(.system(size: 48, weight: .black, design: .rounded))
          .foregroundColor(tint)
          .shadow(color: .black.opacity(0.6), radius: 0, x: 4, y: 4)
          .scaleEffect(textScale)
          .opacity(textOpacity)
          .rotationEffect(.degrees(-6))
      }
    }
    .onChange(of: rollNumber) { _, newRoll in
      // Fire only once per roll, and only for celebratory outcomes.
      guard newRoll != lastShownRoll, let o = outcome else { return }
      guard o == .strike || o == .spare else { return }
      lastShownRoll = newRoll
      fire(outcome: o)
    }
  }

  private func label(for outcome: BowlingGame.RollOutcome) -> String? {
    switch outcome {
    case .strike: return "STRIKE!"
    case .spare: return "SPARE!"
    case .open, .gutter: return nil
    }
  }

  private func fire(outcome: BowlingGame.RollOutcome) {
    visibleOutcome = outcome
    textScale = 0.3
    textOpacity = 0
    let count = outcome == .strike ? 32 : 18
    let maxDistance: CGFloat = outcome == .strike ? 160 : 100
    particles = (0..<count).map { _ in
      Particle(
        angle: Double.random(in: 0...(.pi * 2)),
        distance: CGFloat.random(in: 60...maxDistance),
        size: CGFloat.random(in: 4...10),
        color: [tint, .yellow, .white, .orange].randomElement()!,
        progress: 0
      )
    }

    // Pop in.
    withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
      textScale = 1.2
      textOpacity = 1
    }
    // Particles fan out.
    withAnimation(.easeOut(duration: 0.8)) {
      for i in particles.indices {
        particles[i].progress = 1
      }
    }
    // Settle.
    withAnimation(.easeInOut(duration: 0.18).delay(0.32)) {
      textScale = 1.0
    }
    // Fade out and clear.
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 900_000_000)
      withAnimation(.easeOut(duration: 0.35)) {
        textOpacity = 0
        textScale = 0.7
      }
      try? await Task.sleep(nanoseconds: 400_000_000)
      visibleOutcome = nil
      particles = []
    }
  }
}

// MARK: - Bowling aim guide
// Shown during the .idle phase so the player can see where the ball
// will travel before they release. A vertical dotted line plus a
// triangular marker at the player end, both shifted left/right by aim.

private struct BowlingAimGuide: View {
  let aim: Float
  let tint: Color
  let laneWidth: CGFloat
  let laneHeight: CGFloat

  var body: some View {
    let centerX = laneWidth / 2
    let aimOffset = CGFloat(aim) * laneWidth * 0.42
    let bottomX = centerX
    let topX = centerX + aimOffset
    let bottomY = laneHeight * 0.85
    let topY = laneHeight * 0.18

    ZStack {
      // Thick red glow underlay — gives the beam a heat-trail vibe.
      Path { p in
        p.move(to: CGPoint(x: bottomX, y: bottomY))
        p.addLine(to: CGPoint(x: topX, y: topY))
      }
      .stroke(
        Color.red.opacity(0.6),
        style: StrokeStyle(lineWidth: 14, lineCap: .round)
      )
      .blur(radius: 6)

      // Solid red beam. The rotation3DEffect on the parent lane gives
      // it natural perspective — far end visually narrows in screen
      // space without us having to manually taper the stroke.
      Path { p in
        p.move(to: CGPoint(x: bottomX, y: bottomY))
        p.addLine(to: CGPoint(x: topX, y: topY))
      }
      .stroke(
        Color.red,
        style: StrokeStyle(lineWidth: 4, lineCap: .round)
      )

      // Bright spec at the impact point so the player can see exactly
      // where the ball is targeted.
      Circle()
        .fill(Color.white)
        .frame(width: 10, height: 10)
        .shadow(color: .red, radius: 6)
        .position(x: topX, y: topY)

      // Subtle release-point marker so the player understands the line
      // originates at the ball's foot.
      Circle()
        .fill(Color.red.opacity(0.85))
        .frame(width: 12, height: 12)
        .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
        .position(x: bottomX, y: bottomY)
    }
    .animation(.easeOut(duration: 0.12), value: aim)
  }
}

private struct Triangle: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: rect.midX, y: rect.minY))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    p.closeSubpath()
    return p
  }
}

// MARK: - Bowling arcade countdown
// Big bold "3 / 2 / 1" overlay before each turn. Each digit scales in
// with a quick spring and fades as it leaves so the next number can
// pop in cleanly.

private struct BowlingCountdown: View {
  let value: Int
  let tint: Color

  @State private var scale: CGFloat = 0.4
  @State private var opacity: Double = 0

  var body: some View {
    ZStack {
      Color.black.opacity(0.35).blendMode(.multiply)
      Text("\(value)")
        .font(.system(size: 140, weight: .black, design: .rounded))
        .foregroundColor(tint)
        .shadow(color: .black.opacity(0.6), radius: 0, x: 4, y: 4)
        .scaleEffect(scale)
        .opacity(opacity)
        .id(value)  // force re-render so each new digit replays the spring
    }
    .onAppear { animateIn() }
    .onChange(of: value) { _, _ in
      // Reset and re-animate for the next digit.
      scale = 0.4
      opacity = 0
      animateIn()
    }
  }

  private func animateIn() {
    withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
      scale = 1.0
      opacity = 1.0
    }
    // Fade slightly toward the end of the digit's lifetime so the
    // hand-off into the next digit feels intentional.
    withAnimation(.easeOut(duration: 0.25).delay(0.4)) {
      opacity = 0.7
    }
  }
}

// MARK: - Bowling pinspotter mechanism
// Mimics the QubicaAMF-style pinsetter: an overhead rack descends to
// pick up standing pins, a sweep bar drops down and pushes fallen pins
// off the back of the deck, then the rack returns either with the
// picked-up pins (mid-frame) or a fresh full rack (frame end).

private struct BowlingPinSpotter: View {
  let phase: BowlingGame.RollPhase
  let laneWidth: CGFloat
  let laneHeight: CGFloat

  // 0 = retracted up out of view, 1 = fully descended over the pin deck.
  @State private var rackDown: CGFloat = 0
  // -0.2 = above the pin deck, 1.1 = below it (just past the pins).
  @State private var sweepProgress: CGFloat = -0.2

  private var pinAreaTop: CGFloat { 6 }
  private var pinAreaBottom: CGFloat { laneHeight * 0.50 }
  private var pinAreaHeight: CGFloat { pinAreaBottom - pinAreaTop }
  private var rackWidth: CGFloat { laneWidth * 0.62 }

  var body: some View {
    ZStack(alignment: .top) {
      // Overhead rail — always faintly visible; it's the structure the
      // rack hangs from.
      Rectangle()
        .fill(Color(white: 0.18))
        .frame(width: laneWidth * 0.72, height: 4)
        .overlay(Rectangle().stroke(Color.black.opacity(0.6), lineWidth: 1))
        .position(x: laneWidth / 2, y: 4)

      // Pinspotter rack — a chunky bar with 10 vertical "spots" (small
      // hangers where pins clip in). Descends from the overhead rail.
      VStack(spacing: 2) {
        Rectangle()
          .fill(Color(white: 0.30))
          .frame(width: rackWidth, height: 6)
          .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
        HStack(spacing: 4) {
          ForEach(0..<10, id: \.self) { _ in
            Rectangle()
              .fill(Color(white: 0.40))
              .frame(width: 4, height: 8)
          }
        }
      }
      .position(x: laneWidth / 2, y: pinAreaTop + rackDown * (pinAreaHeight * 0.5))
      .opacity(Double(rackDown))

      // Sweep bar — wide flat blade that descends and traverses the
      // pin deck top-to-bottom (in screen coords), pushing fallen pins
      // off the back.
      Rectangle()
        .fill(Color(white: 0.25))
        .frame(width: laneWidth * 0.78, height: 7)
        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
        .position(
          x: laneWidth / 2,
          y: pinAreaTop + sweepProgress * pinAreaHeight
        )
        .opacity(sweepProgress > -0.2 && sweepProgress < 1.05 ? 1 : 0)
    }
    .onChange(of: phase) { _, newPhase in
      runMechanism(for: newPhase)
    }
  }

  private func runMechanism(for phase: BowlingGame.RollPhase) {
    switch phase {
    case .knocking:
      // Wait for pins to visibly fall, then drop the rack to "pick up"
      // standing pins, then the sweep traverses the deck.
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 300_000_000)
        withAnimation(.easeIn(duration: 0.25)) { rackDown = 1 }
        try? await Task.sleep(nanoseconds: 280_000_000)
        sweepProgress = -0.2
        withAnimation(.linear(duration: 0.45)) { sweepProgress = 1.1 }
      }
    case .resetting:
      // Sweep finishes off-screen; the rack lifts back up with either
      // standing pins replaced or a fresh rack of 10 (the model handles
      // the actual pin-state reset).
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 150_000_000)
        withAnimation(.easeOut(duration: 0.35)) { rackDown = 0 }
      }
    case .idle, .rolling, .countingDown, .finalScoring:
      // Make sure the mechanism is parked when we go back to play.
      withAnimation(.easeOut(duration: 0.2)) {
        rackDown = 0
        sweepProgress = -0.2
      }
    }
  }
}

// MARK: - Bowling scoreboard
// Mimics the QubicaAMF-style overhead apparatus: frame numbers on top,
// per-ball cells with strike/spare marks, cumulative running totals
// underneath, and a wider TOTAL column on the right.

private struct BowlingScoreboard: View {
  let frames: [BowlingGame.FrameDisplay]
  let total: Int

  private let frameNumberHeight: CGFloat = 14
  private let cellHeight: CGFloat = 36

  var body: some View {
    VStack(spacing: 0) {
      headerRow
      Rectangle().fill(Color.orange).frame(height: 1)
      bodyRow
    }
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(Color.orange, lineWidth: 1.5)
    )
  }

  private var headerRow: some View {
    HStack(spacing: 0) {
      ForEach(1...10, id: \.self) { n in
        Text("\(n)")
          .font(.system(size: 10, weight: .heavy, design: .rounded))
          .foregroundColor(n == 10 ? .red : Color(white: 0.15))
          .frame(maxWidth: .infinity)
          .frame(height: frameNumberHeight)
        if n < 10 {
          Rectangle().fill(Color.orange.opacity(0.7)).frame(width: 1)
        }
      }
      Rectangle().fill(Color.orange.opacity(0.7)).frame(width: 1)
      Text("TOT")
        .font(.system(size: 10, weight: .heavy, design: .rounded))
        .foregroundColor(Color(white: 0.15))
        .frame(width: 38, height: frameNumberHeight)
    }
    .background(Color.orange)
  }

  private var bodyRow: some View {
    HStack(spacing: 0) {
      ForEach(frames, id: \.number) { frame in
        frameCell(frame)
        if frame.number < 10 {
          Rectangle().fill(Color.white.opacity(0.4)).frame(width: 1)
        }
      }
      Rectangle().fill(Color.white.opacity(0.4)).frame(width: 1)
      // Total column.
      Text("\(total)")
        .font(.system(size: 16, weight: .heavy, design: .rounded))
        .foregroundColor(.white)
        .frame(width: 38, height: cellHeight)
        .background(Color.purple.opacity(0.85))
    }
    .frame(height: cellHeight)
    .background(Color.purple.opacity(0.6))
  }

  @ViewBuilder
  private func frameCell(_ frame: BowlingGame.FrameDisplay) -> some View {
    let bg = frame.isCurrent ? Color.purple : Color.purple.opacity(0.7)
    VStack(spacing: 0) {
      // Top: per-ball labels. 10th frame has 3 boxes, others have 2.
      HStack(spacing: 0) {
        let slots = frame.number == 10 ? 3 : 2
        ForEach(0..<slots, id: \.self) { idx in
          Text(idx < frame.rolls.count ? frame.rolls[idx] : "")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 16)
            .border(Color.white.opacity(0.25), width: 0.5)
        }
      }
      // Bottom: cumulative score (shown only when finalized).
      Text(frame.cumulative.map { "\($0)" } ?? "")
        .font(.system(size: 12, weight: .heavy, design: .rounded))
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: cellHeight - 16)
    }
    .frame(maxWidth: .infinity)
    .background(bg)
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
