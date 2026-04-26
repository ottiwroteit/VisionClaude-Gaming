import SceneKit
import SwiftUI

/// SwiftUI hosting wrapper for the TennisSceneController.
struct TennisScene: UIViewRepresentable {
  @ObservedObject var game: TennisGame
  let venueID: String

  func makeCoordinator() -> TennisSceneController {
    TennisSceneController(
      game: game,
      theme: TennisSceneTheme.theme(forVenueID: venueID)
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
    context.coordinator.update(theme: TennisSceneTheme.theme(forVenueID: venueID))
  }
}
