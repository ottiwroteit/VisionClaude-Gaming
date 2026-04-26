import SceneKit
import SwiftUI

/// SwiftUI hosting wrapper for the ArcherySceneController. Same shape
/// as BowlingScene — transparent SCNView so the venue art behind it
/// shows through, controller mounted as the @StateObject-equivalent
/// via UIViewRepresentable's coordinator pattern.
struct ArcheryScene: UIViewRepresentable {
  @ObservedObject var game: ArcheryGame
  let venueID: String

  func makeCoordinator() -> ArcherySceneController {
    ArcherySceneController(
      game: game,
      theme: ArcherySceneTheme.theme(forVenueID: venueID)
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
    // Render-thread camera follow — tracker lerps the camera toward
    // the in-flight arrow when one is set, otherwise glides home.
    view.delegate = context.coordinator.cameraTracker
    return view
  }

  func updateUIView(_ view: SCNView, context: Context) {
    context.coordinator.update(theme: ArcherySceneTheme.theme(forVenueID: venueID))
  }
}
