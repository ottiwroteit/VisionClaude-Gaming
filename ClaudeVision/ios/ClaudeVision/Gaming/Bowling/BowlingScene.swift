import SceneKit
import SwiftUI

/// SwiftUI hosting wrapper for the BowlingSceneController. Replaces the
/// old SwiftUI-primitive `BowlingArt` in the hero-art dispatcher. The
/// SCNView's background is transparent so the venue art behind it shows
/// through, giving the SceneKit lane an environment without rebuilding
/// the venues in 3D.
struct BowlingScene: UIViewRepresentable {
  @ObservedObject var game: BowlingGame
  /// Venue id from the active session. Used to resolve which
  /// BowlingSceneTheme to apply on init and on later venue changes.
  let venueID: String

  func makeCoordinator() -> BowlingSceneController {
    BowlingSceneController(
      game: game,
      theme: BowlingSceneTheme.theme(forVenueID: venueID)
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
    // Render-thread camera follow. The tracker captures the ball and
    // camera nodes on init and lerps the camera Z toward the ball Z
    // every frame when the controller has flipped its `followingEnabled`.
    view.delegate = context.coordinator.cameraTracker
    return view
  }

  func updateUIView(_ view: SCNView, context: Context) {
    context.coordinator.update(theme: BowlingSceneTheme.theme(forVenueID: venueID))
  }
}
