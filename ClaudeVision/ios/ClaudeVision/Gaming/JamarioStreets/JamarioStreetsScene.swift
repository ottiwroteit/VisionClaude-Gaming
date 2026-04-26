import SpriteKit
import SwiftUI

/// SwiftUI hosting wrapper for the JamarioStreetsGameScene. Same shape
/// as the JamarioScene wrapper — UIViewRepresentable presents an
/// SKView with the game scene; theme is irrelevant for this game so
/// the parameter is just the venue id (which the scene uses for
/// background colour selection in a future iteration).
struct JamarioStreetsScene: UIViewRepresentable {
  @ObservedObject var game: JamarioStreetsGame
  let venueID: String

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> SKView {
    let view = SKView(frame: .zero)
    view.backgroundColor = .clear
    view.allowsTransparency = true
    view.preferredFramesPerSecond = 60
    view.ignoresSiblingOrder = true
    view.isAsynchronous = true
    let scene = JamarioStreetsGameScene(size: CGSize(width: 800, height: 600))
    scene.scaleMode = .resizeFill
    scene.game = game
    context.coordinator.scene = scene
    view.presentScene(scene)
    return view
  }

  func updateUIView(_ view: SKView, context: Context) {
    // Theme switching deferred — Streets only ships one venue (city
    // skyline) for v1.
  }

  final class Coordinator {
    var scene: JamarioStreetsGameScene?
  }
}
