import SceneKit
import SwiftUI

/// SwiftUI hosting wrapper for the FruitSlashSceneController.
struct FruitSlashScene: UIViewRepresentable {
  @ObservedObject var game: FruitSlashGame
  let venueID: String

  func makeCoordinator() -> FruitSlashSceneController {
    FruitSlashSceneController(
      game: game,
      theme: FruitSlashSceneTheme.theme(forVenueID: venueID)
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
    context.coordinator.update(theme: FruitSlashSceneTheme.theme(forVenueID: venueID))
  }
}
