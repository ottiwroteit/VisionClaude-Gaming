import SceneKit
import SwiftUI

/// SwiftUI hosting wrapper for the PingPongSceneController.
struct PingPongScene: UIViewRepresentable {
  @ObservedObject var game: PingPongGame
  let venueID: String

  func makeCoordinator() -> PingPongSceneController {
    PingPongSceneController(
      game: game,
      theme: PingPongSceneTheme.theme(forVenueID: venueID)
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
    context.coordinator.update(theme: PingPongSceneTheme.theme(forVenueID: venueID))
  }
}
