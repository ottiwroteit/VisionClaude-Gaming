import Foundation
import SceneKit

/// Per-frame camera follow for the archery scene. Same shape as
/// `BowlingCameraTracker` — a non-isolated NSObject that lerps the
/// camera toward a target node every render-thread tick, then back to
/// its home position when no target is set.
///
/// For archery the target is the *stuck arrow* node spawned by the
/// controller in `fireArrow()`. While the arrow is in flight the
/// camera trails just behind it; once the controller clears the
/// `followNode` (after flight + dwell), the camera glides home.
final class ArcheryCameraTracker: NSObject, SCNSceneRendererDelegate {

  let cameraNode: SCNNode
  let homePosition: SCNVector3

  /// Trail distance along +Z behind the followed node — keeps the
  /// camera slightly behind the arrow rather than sitting on top of it.
  let followOffset: Float = 1.4
  /// Per-frame lerp factor. Higher = snappier; tuned a bit more
  /// aggressive than bowling because the arrow flight is much shorter
  /// (~0.4 s vs the ball's ~2 s travel).
  let positionLerp: Float = 0.28

  /// Set by the controller when an arrow fires; cleared when flight
  /// + dwell complete. Plain optional ref — nodes are owned by the
  /// scene graph so we don't need to retain them ourselves.
  weak var followNode: SCNNode?

  init(cameraNode: SCNNode) {
    self.cameraNode = cameraNode
    self.homePosition = cameraNode.position
    super.init()
  }

  func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
    let current = cameraNode.position
    let target: SCNVector3
    if let node = followNode {
      let p = node.presentation.position
      // Trail behind the arrow's Z, pan a fraction of its X so a
      // ring-edge hit keeps the arrow framed without a wild yaw.
      target = SCNVector3(p.x * 0.4, homePosition.y, p.z + followOffset)
    } else {
      target = homePosition
    }
    cameraNode.position = SCNVector3(
      current.x + (target.x - current.x) * positionLerp,
      current.y + (target.y - current.y) * positionLerp,
      current.z + (target.z - current.z) * positionLerp
    )
  }
}
