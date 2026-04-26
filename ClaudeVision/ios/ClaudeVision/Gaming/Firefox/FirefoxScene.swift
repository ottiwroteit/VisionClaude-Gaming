import SceneKit
import SwiftUI

/// SwiftUI hosting wrapper for FirefoxSceneController. Same pattern
/// as the other SceneKit games — UIViewRepresentable wrapping an
/// SCNView, transparent background so the venue art shows behind.
/// The render ticker is installed as the SCNView's delegate so the
/// controller's tick(time:) fires once per frame.
struct FirefoxScene: UIViewRepresentable {
  @ObservedObject var game: FirefoxGame
  let venueID: String

  final class Coordinator {
    let controller: FirefoxSceneController
    let ticker: FirefoxRenderTicker
    init(controller: FirefoxSceneController, ticker: FirefoxRenderTicker) {
      self.controller = controller
      self.ticker = ticker
      ticker.controller = controller
    }
  }

  func makeCoordinator() -> Coordinator {
    let controller = FirefoxSceneController(
      game: game,
      theme: FirefoxSceneTheme.theme(forVenueID: venueID))
    return Coordinator(controller: controller, ticker: FirefoxRenderTicker())
  }

  func makeUIView(context: Context) -> SCNView {
    let view = SCNView(frame: .zero)
    view.scene = context.coordinator.controller.scene
    view.backgroundColor = .clear
    view.allowsCameraControl = false
    view.antialiasingMode = .multisampling4X
    view.preferredFramesPerSecond = 60
    view.rendersContinuously = true
    view.autoenablesDefaultLighting = false
    view.delegate = context.coordinator.ticker
    return view
  }

  func updateUIView(_ view: SCNView, context: Context) {
    context.coordinator.controller.update(theme: FirefoxSceneTheme.theme(forVenueID: venueID))
  }
}
