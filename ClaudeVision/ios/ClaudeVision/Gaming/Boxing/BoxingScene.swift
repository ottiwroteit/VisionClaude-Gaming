import SceneKit
import SwiftUI

/// SwiftUI hosting wrapper for the BoxingSceneController. Composes the
/// SCNView with a small SwiftUI overlay for the player/CPU health
/// bars and the incoming-attack warning banner — the original
/// BowlingArt-style chrome that lived inside the now-replaced
/// SwiftUI BoxingArt.
struct BoxingScene: View {
  @ObservedObject var game: BoxingGame
  let venueID: String
  let tint: Color

  var body: some View {
    ZStack {
      BoxingSCNHost(game: game, venueID: venueID)
      VStack(spacing: 12) {
        HStack(spacing: 12) {
          healthBar(label: "YOU", value: game.playerHealth, color: .green)
          healthBar(label: "CPU", value: game.cpuHealth, color: tint)
        }
        if game.incomingAttack != .none {
          Text("⚠ INCOMING \(game.incomingAttack.rawValue.uppercased())")
            .font(.system(size: 13, weight: .black))
            .tracking(2)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.85))
            .clipShape(Capsule())
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: game.incomingAttack)
        }
        Spacer()
      }
      .padding(.top, 24)
      .padding(.horizontal, 16)
      .allowsHitTesting(false)
    }
  }

  private func healthBar(label: String, value: Int, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(label)
          .font(.system(size: 10, weight: .heavy)).tracking(2)
          .foregroundColor(.white.opacity(0.85))
        Spacer()
        Text("\(value)")
          .font(.system(size: 11, weight: .black).monospaced())
          .foregroundColor(.white.opacity(0.85))
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.black.opacity(0.55))
          Capsule()
            .fill(color)
            .frame(width: proxy.size.width * CGFloat(value) / 100)
        }
      }
      .frame(height: 8)
    }
    .padding(8)
    .background(.ultraThinMaterial.opacity(0.9))
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }
}

/// The actual UIViewRepresentable hosting the SceneKit view. Split out
/// so BoxingScene can compose it with the health-bar overlay.
struct BoxingSCNHost: UIViewRepresentable {
  @ObservedObject var game: BoxingGame
  let venueID: String

  func makeCoordinator() -> BoxingSceneController {
    BoxingSceneController(
      game: game,
      theme: BoxingSceneTheme.theme(forVenueID: venueID)
    )
  }

  func makeUIView(context: Context) -> SCNView {
    let view = SCNView(frame: .zero)
    view.scene = context.coordinator.scene
    view.backgroundColor = .clear
    view.allowsCameraControl = false
    view.antialiasingMode = .multisampling4X
    view.preferredFramesPerSecond = 60
    view.rendersContinuously = true
    view.autoenablesDefaultLighting = false
    return view
  }

  func updateUIView(_ view: SCNView, context: Context) {
    context.coordinator.update(theme: BoxingSceneTheme.theme(forVenueID: venueID))
  }
}
