import Foundation
import SceneKit

/// Per-frame camera follow logic for the bowling scene. Lives outside
/// `BowlingSceneController` because it runs on the SceneKit render
/// thread (via SCNSceneRendererDelegate) and the controller is
/// `@MainActor` — keeping the tracker non-isolated avoids fighting the
/// concurrency checker every time we read or write `cameraNode.position`.
///
/// SceneKit's `presentation` tree is documented as safe to read from
/// the render-thread callback, and writing back to a node's position in
/// the same callback is the canonical pattern for camera follow / look-at
/// effects in Apple's own SceneKit examples.
final class BowlingCameraTracker: NSObject, SCNSceneRendererDelegate {

  /// Hard refs are fine — both nodes are owned by the scene graph,
  /// which outlives the tracker for the entire SCNView lifetime.
  let ballNode: SCNNode
  let cameraNode: SCNNode
  /// Resting position the camera returns to between rolls.
  let homeZ: Float
  let homeY: Float
  let homeX: Float
  /// Camera trails the ball by this many units in +Z (i.e. slightly
  /// behind the ball as it travels into the scene).
  let followOffset: Float = 1.8
  /// Per-frame lerp factor toward the target Z. Higher = snappier follow.
  let positionLerp: Float = 0.16
  /// Ball Z below this threshold (further into the scene) is the
  /// "trigger" for the camera to start following — keeps the camera
  /// still while the ball is launching from behind the bowler.
  let followTriggerZ: Float = 8.5
  /// Z floor the camera will not pass — keeps it just clear of the
  /// pin deck (~-10) on huge rolls. Previously this was -2 which
  /// clamped the camera halfway down the lane and made the ball
  /// disappear into the distance long before reaching the pins.
  let minCameraZ: Float = -8.5

  /// Toggled by the controller from MainActor when the game enters
  /// `.rolling`. Read on the render thread; one frame of staleness is
  /// invisible to the user, so a plain `Bool` is sufficient.
  var followingEnabled: Bool = false

  init(ballNode: SCNNode, cameraNode: SCNNode) {
    self.ballNode = ballNode
    self.cameraNode = cameraNode
    self.homeZ = cameraNode.position.z
    self.homeY = cameraNode.position.y
    self.homeX = cameraNode.position.x
    super.init()
  }

  func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
    let current = cameraNode.position
    let targetZ: Float
    let targetX: Float
    if followingEnabled {
      let ballPos = ballNode.presentation.position
      // Only start sliding the camera once the ball is past the
      // launch zone. Until then keep the camera at home so we don't
      // see a small jitter on release.
      if ballPos.z < followTriggerZ {
        targetZ = max(minCameraZ, ballPos.z + followOffset)
      } else {
        targetZ = homeZ
      }
      // Pan slightly with the ball's X so a hooked roll keeps the
      // ball in frame, but only a fraction of the lateral motion so
      // the camera doesn't yaw wildly.
      targetX = homeX + (ballPos.x * 0.35)
    } else {
      targetZ = homeZ
      targetX = homeX
    }
    let newZ = current.z + (targetZ - current.z) * positionLerp
    let newX = current.x + (targetX - current.x) * positionLerp
    cameraNode.position = SCNVector3(newX, homeY, newZ)
  }
}
