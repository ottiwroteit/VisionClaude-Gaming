import SpriteKit
import SwiftUI

/// SwiftUI hosting wrapper for the AI Slasher SpriteKit scene. Same
/// shape as the JamarioStreets wrapper.
struct FruitSlashScene: UIViewRepresentable {
  @ObservedObject var game: FruitSlashGame
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
    let scene = FruitSlashGameScene(size: CGSize(width: 800, height: 600))
    scene.scaleMode = .resizeFill
    scene.game = game
    context.coordinator.scene = scene
    view.presentScene(scene)
    return view
  }

  func updateUIView(_ view: SKView, context: Context) {
    // Theme switching deferred — venue background is painted by the
    // SwiftUI host behind the transparent SKView.
  }

  final class Coordinator {
    var scene: FruitSlashGameScene?
  }
}
