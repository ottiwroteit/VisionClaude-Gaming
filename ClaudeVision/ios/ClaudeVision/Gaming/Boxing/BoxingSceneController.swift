import Combine
import Foundation
import SceneKit
import UIKit

/// Owns the SceneKit scene graph for boxing: a heavy bag hanging from
/// chains, with a dim floor for grounding. The bag idles with a gentle
/// pendulum sway; player punches recoil it backwards (biased by side
/// for hooks); CPU incoming attacks lunge it forward toward the camera
/// as a telegraph the player can dodge.
///
/// Contract with `BoxingGame`:
/// - Watch `lastPunchEventID` for landed-punch events; read
///   `lastPunchSide` for the recoil bias.
/// - Watch `incomingAttack` to telegraph an incoming swing toward the
///   player; lunge direction comes from the attack type. Returning to
///   `.none` snaps the bag back home (whether the player dodged or
///   ate the hit).
@MainActor
final class BoxingSceneController: NSObject {

  // MARK: Public surface

  let scene: SCNScene
  private(set) var theme: BoxingSceneTheme

  // MARK: Game wiring

  private weak var game: BoxingGame?
  private var punchSub: AnyCancellable?
  private var incomingSub: AnyCancellable?

  // MARK: Scene graph

  /// Pivot node positioned at the top of the bag. The bag is a child;
  /// rotating the pivot's Z axis swings the bag like a pendulum.
  private var bagPivotNode: SCNNode!
  private var bagNode: SCNNode!
  private var bagAccentNode: SCNNode!
  private var leftChainNode: SCNNode!
  private var rightChainNode: SCNNode!
  private var floorNode: SCNNode!
  private var cameraNode: SCNNode!
  private var keyLightNode: SCNNode!
  private var ambientLightNode: SCNNode!

  // MARK: Tunables

  private let bagHeight: Float = 1.6
  private let bagRadius: CGFloat = 0.32
  private let cameraZ: Float = 4.5
  private let cameraY: Float = 0.5

  // MARK: Init

  init(game: BoxingGame, theme: BoxingSceneTheme) {
    self.scene = SCNScene()
    self.theme = theme
    self.game = game
    super.init()
    buildScene()
    applyTheme(theme)
    observeGame()
    startIdleSway()
  }

  // MARK: Scene construction

  private func buildScene() {
    scene.background.contents = nil
    let root = scene.rootNode

    // Pivot at the top of the bag — rotating around X tilts it like a
    // pendulum, around Z gives lateral sway.
    bagPivotNode = SCNNode()
    bagPivotNode.position = SCNVector3(0, 1.2, 0)
    root.addChildNode(bagPivotNode)

    // Bag — capsule hanging below the pivot.
    let bagGeo = SCNCapsule(capRadius: bagRadius, height: CGFloat(bagHeight))
    let bagMat = SCNMaterial()
    bagMat.diffuse.contents = UIColor.brown
    bagMat.roughness.contents = 0.7
    bagGeo.firstMaterial = bagMat
    bagNode = SCNNode(geometry: bagGeo)
    // Position so the TOP of the capsule is at pivot origin (Y=0 in
    // pivot-local space). Capsule is centered on Y=0 by default, so
    // we drop it by half its height + cap radius.
    bagNode.position = SCNVector3(0, -bagHeight / 2, 0)
    bagPivotNode.addChildNode(bagNode)

    // Mid-bag accent stripe — short cylinder banded around the body.
    let accentGeo = SCNCylinder(radius: bagRadius * 1.02, height: 0.16)
    let accentMat = SCNMaterial()
    accentMat.diffuse.contents = UIColor.red
    accentGeo.firstMaterial = accentMat
    bagAccentNode = SCNNode(geometry: accentGeo)
    bagAccentNode.position = SCNVector3(0, 0.05, 0)
    bagNode.addChildNode(bagAccentNode)

    // Hanging chains from off-camera (top) to the bag's top.
    leftChainNode = makeChainNode(xOffset: -0.08)
    rightChainNode = makeChainNode(xOffset: 0.08)
    bagPivotNode.addChildNode(leftChainNode)
    bagPivotNode.addChildNode(rightChainNode)

    // Floor — dim plane the bag visually rests above.
    let floorGeo = SCNPlane(width: 8, height: 8)
    let floorMat = SCNMaterial()
    floorMat.diffuse.contents = UIColor.darkGray
    floorMat.roughness.contents = 0.95
    floorGeo.firstMaterial = floorMat
    floorNode = SCNNode(geometry: floorGeo)
    floorNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
    floorNode.position = SCNVector3(0, -0.6, 0)
    root.addChildNode(floorNode)

    // Camera — front-and-slightly-above the bag, looking at its midline.
    let camera = SCNCamera()
    camera.fieldOfView = 50
    camera.zNear = 0.05
    camera.zFar = 60
    cameraNode = SCNNode()
    cameraNode.camera = camera
    cameraNode.position = SCNVector3(0, cameraY, cameraZ)
    cameraNode.eulerAngles = SCNVector3(-0.18, 0, 0)
    root.addChildNode(cameraNode)

    // Lights.
    let key = SCNLight()
    key.type = .directional
    key.intensity = 950
    key.castsShadow = true
    key.shadowMode = .deferred
    keyLightNode = SCNNode()
    keyLightNode.light = key
    keyLightNode.eulerAngles = SCNVector3(-0.85, 0.45, 0)
    keyLightNode.position = SCNVector3(2, 5, 3)
    root.addChildNode(keyLightNode)

    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.intensity = 420
    ambientLightNode = SCNNode()
    ambientLightNode.light = ambient
    root.addChildNode(ambientLightNode)
  }

  private func makeChainNode(xOffset: Float) -> SCNNode {
    // A thin tall cylinder hanging from above-camera down to the bag's
    // top. The pivot is at Y=0 (bag top); chain extends upward.
    let geo = SCNCylinder(radius: 0.012, height: 1.5)
    let mat = SCNMaterial()
    mat.diffuse.contents = UIColor.gray
    mat.metalness.contents = 0.6
    mat.roughness.contents = 0.4
    geo.firstMaterial = mat
    let node = SCNNode(geometry: geo)
    // Cylinder centred on Y, so push it up by half its height to
    // start at pivot Y=0 and rise from there.
    node.position = SCNVector3(xOffset, 0.75, 0)
    return node
  }

  /// Idle swing — a gentle continuous Z-axis rotation on the pivot so
  /// the bag drifts ~2° each side over a couple seconds. Cancellable
  /// because punches override the rotation directly with their own
  /// SCNAction (the action key clears any inherited rotation state).
  private func startIdleSway() {
    let amplitude: Float = 0.04  // ~2.3°
    let halfPeriod: TimeInterval = 1.6
    let toLeft = SCNAction.rotateTo(
      x: 0, y: 0, z: CGFloat(amplitude), duration: halfPeriod, usesShortestUnitArc: true)
    toLeft.timingMode = .easeInEaseOut
    let toRight = SCNAction.rotateTo(
      x: 0, y: 0, z: CGFloat(-amplitude), duration: halfPeriod, usesShortestUnitArc: true)
    toRight.timingMode = .easeInEaseOut
    bagPivotNode.runAction(.repeatForever(.sequence([toLeft, toRight])), forKey: "idleSway")
  }

  // MARK: Theme

  func update(theme: BoxingSceneTheme) {
    self.theme = theme
    applyTheme(theme)
  }

  private func applyTheme(_ theme: BoxingSceneTheme) {
    bagNode.geometry?.firstMaterial?.diffuse.contents = theme.bagColor
    bagAccentNode.geometry?.firstMaterial?.diffuse.contents = theme.bagAccentColor
    leftChainNode.geometry?.firstMaterial?.diffuse.contents = theme.chainColor
    rightChainNode.geometry?.firstMaterial?.diffuse.contents = theme.chainColor
    floorNode.geometry?.firstMaterial?.diffuse.contents = theme.floorColor
    keyLightNode.light?.color = theme.keyLightColor
    ambientLightNode.light?.color = theme.ambientColor
    scene.fogColor = theme.fogColor
    scene.fogStartDistance = theme.fogStartDistance
    scene.fogEndDistance = theme.fogEndDistance
  }

  // MARK: Game observation

  private func observeGame() {
    guard let game else { return }
    punchSub = game.$lastPunchEventID.receive(on: RunLoop.main).sink { [weak self] _ in
      self?.playPunchRecoil()
    }
    incomingSub = game.$incomingAttack.receive(on: RunLoop.main).sink {
      [weak self] attack in
      self?.handleIncomingAttack(attack)
    }
  }

  private func playPunchRecoil() {
    guard let game else { return }
    // Recoil: rotate the pivot a bigger angle than the idle sway in a
    // direction biased by the punch side. Center jab tilts purely
    // backward (X-axis); hooks add a Z lean.
    let backwardTilt: Float = 0.32  // ~18° forward (top tips toward camera, bag swings away)
    let lean: Float
    switch game.lastPunchSide {
    case .center: lean = 0
    case .left: lean = 0.18  // bag swings to scene-right (player threw a hook from their left)
    case .right: lean = -0.18
    }
    let recoil = SCNAction.rotateTo(
      x: CGFloat(backwardTilt), y: 0, z: CGFloat(lean), duration: 0.10,
      usesShortestUnitArc: true)
    recoil.timingMode = .easeOut
    let settle = SCNAction.rotateTo(
      x: 0, y: 0, z: 0, duration: 0.55, usesShortestUnitArc: true)
    settle.timingMode = .easeInEaseOut
    let resume = SCNAction.run { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.startIdleSway()
      }
    }
    bagPivotNode.removeAction(forKey: "idleSway")
    bagPivotNode.runAction(.sequence([recoil, settle, resume]), forKey: "punch")
  }

  private func handleIncomingAttack(_ attack: BoxingGame.IncomingAttack) {
    switch attack {
    case .none:
      // Snap home and resume idle.
      bagPivotNode.removeAction(forKey: "incoming")
      let snap = SCNAction.rotateTo(
        x: 0, y: 0, z: 0, duration: 0.18, usesShortestUnitArc: true)
      snap.timingMode = .easeOut
      let resume = SCNAction.run { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.startIdleSway()
        }
      }
      bagPivotNode.runAction(.sequence([snap, resume]))
    case .jab, .uppercut, .hookLeft, .hookRight:
      // Lunge toward the player (negative X-axis tilt = top tips away
      // from camera = bag swings TOWARD camera). Add lateral lean for
      // hooks so the dodge direction reads visually.
      let forwardTilt: Float = -0.30
      let lean: Float
      switch attack {
      case .hookLeft: lean = 0.22
      case .hookRight: lean = -0.22
      default: lean = 0
      }
      bagPivotNode.removeAction(forKey: "idleSway")
      let lunge = SCNAction.rotateTo(
        x: CGFloat(forwardTilt), y: 0, z: CGFloat(lean), duration: 0.45,
        usesShortestUnitArc: true)
      lunge.timingMode = .easeOut
      bagPivotNode.runAction(lunge, forKey: "incoming")
    }
  }
}
