import SpriteKit
import SwiftUI

/// SwiftUI hosting wrapper for the Jamario SpriteKit scene. Different
/// shape from the SceneKit games (which use UIViewRepresentable around
/// SCNView) because SpriteKit needs an SKView and an SKScene presented
/// into it. The pattern is otherwise identical: a transparent host so
/// the SwiftUI venue background can show behind, observation of the
/// game model handled inside the SpriteKit scene itself.
struct JamarioScene: UIViewRepresentable {
  @ObservedObject var game: JamarioGame
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
    // Reasonable default scene size; SpriteKit's `.resizeFill`
    // scaling adapts to the actual view bounds at present time.
    let scene = JamarioGameScene(size: CGSize(width: 800, height: 600))
    scene.scaleMode = .resizeFill
    scene.configure(game: game, theme: JamarioSceneTheme.theme(forVenueID: venueID))
    context.coordinator.scene = scene
    view.presentScene(scene)
    return view
  }

  func updateUIView(_ view: SKView, context: Context) {
    context.coordinator.scene?.applyTheme(JamarioSceneTheme.theme(forVenueID: venueID))
  }

  /// Holds a strong ref to the SKScene so SwiftUI's diffing doesn't
  /// drop it between updates. SwiftUI normally deallocates the
  /// UIViewRepresentable's coordinator with the view, so this is the
  /// right lifetime for the scene.
  final class Coordinator {
    var scene: JamarioGameScene?
  }
}
