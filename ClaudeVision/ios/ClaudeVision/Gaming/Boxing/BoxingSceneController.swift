import Combine
import Foundation
import SceneKit
import UIKit

/// Owns the SceneKit scene graph for boxing in first-person POV. The
/// player faces a stylized humanoid opponent built from primitives
/// (head + torso + arms + gloves + legs) and sees their own gloves at
/// the bottom of the frame, EA Sports Fight Night-style.
///
/// Scene reactions:
/// - Player lands a punch (lastPunchEventID bumps): the player's
///   matching glove swings forward into frame; the opponent's torso +
///   head recoil briefly in the opposite direction.
/// - CPU telegraphs an incoming attack (incomingAttack changes from
///   .none): the matching opponent glove extends straight toward the
///   camera over the 1 s warning window. Returning to .none snaps it
///   back to the guard position.
/// - Player takes damage (lastHitEventID bumps): a brief camera shake
///   so the hit reads kinetically even without a screen-flash overlay.
@MainActor
final class BoxingSceneController: NSObject {

  // MARK: Public surface

  let scene: SCNScene
  private(set) var theme: BoxingSceneTheme

  // MARK: Game wiring

  private weak var game: BoxingGame?
  private var punchSub: AnyCancellable?
  private var incomingSub: AnyCancellable?
  private var hitSub: AnyCancellable?

  // MARK: Scene graph — opponent

  private var opponentRoot: SCNNode!
  private var opponentTorso: SCNNode!
  private var opponentHead: SCNNode!
  private var opponentTrunks: SCNNode!
  private var opponentLeftArm: SCNNode!  // upper arm + forearm + glove tree
  private var opponentRightArm: SCNNode!
  private var opponentLeftGlove: SCNNode!
  private var opponentRightGlove: SCNNode!

  // MARK: Scene graph — first-person player gloves

  private var playerLeftGlove: SCNNode!
  private var playerRightGlove: SCNNode!

  // MARK: Scene graph — environment

  private var floorNode: SCNNode!
  private var cameraRig: SCNNode!  // shaken on hit
  private var cameraNode: SCNNode!
  private var keyLightNode: SCNNode!
  private var ambientLightNode: SCNNode!

  // MARK: Tunables

  /// Camera eye height — first-person, slightly above torso midline so
  /// the opponent's head is roughly at the centre of the frame.
  private let cameraY: Float = 1.55
  /// Camera distance from the opponent.
  private let cameraZ: Float = 1.2
  /// Z position of the opponent's pivot (origin of the body).
  private let opponentZ: Float = -1.6
  /// Resting glove positions in opponent-local space (Y above torso).
  private let opponentGuardLeftLocal = SCNVector3(-0.30, 1.30, 0.30)
  private let opponentGuardRightLocal = SCNVector3(0.30, 1.30, 0.30)
  /// Player glove "guard" positions — bottom of the frame, slightly
  /// forward, just inside the camera.
  private let playerGloveGuardLeft = SCNVector3(-0.35, -0.45, -0.55)
  private let playerGloveGuardRight = SCNVector3(0.35, -0.45, -0.55)
  /// How far forward the player's glove punches before retracting.
  private let playerPunchReach: Float = 0.85

  // MARK: Init

  init(game: BoxingGame, theme: BoxingSceneTheme) {
    self.scene = SCNScene()
    self.theme = theme
    self.game = game
    super.init()
    buildScene()
    applyTheme(theme)
    observeGame()
    startIdleBob()
  }

  // MARK: Scene construction

  private func buildScene() {
    scene.background.contents = nil
    let root = scene.rootNode

    // Floor — dim plane the boxer stands on.
    let floorGeo = SCNPlane(width: 12, height: 12)
    let floorMat = SCNMaterial()
    floorMat.diffuse.contents = UIColor.darkGray
    floorMat.roughness.contents = 0.95
    floorGeo.firstMaterial = floorMat
    floorNode = SCNNode(geometry: floorGeo)
    floorNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
    floorNode.position = SCNVector3(0, 0, 0)
    root.addChildNode(floorNode)

    // Opponent — built under a single pivot so we can sway/shift the
    // whole body for hit reactions.
    opponentRoot = SCNNode()
    opponentRoot.position = SCNVector3(0, 0, opponentZ)
    root.addChildNode(opponentRoot)
    buildOpponent(into: opponentRoot)

    // Camera rig — wraps the camera so we can shake the rig without
    // disturbing the camera's own local pose.
    cameraRig = SCNNode()
    cameraRig.position = SCNVector3(0, cameraY, cameraZ)
    root.addChildNode(cameraRig)

    let camera = SCNCamera()
    camera.fieldOfView = 60
    camera.zNear = 0.05
    camera.zFar = 60
    cameraNode = SCNNode()
    cameraNode.camera = camera
    cameraNode.position = SCNVector3(0, 0, 0)
    cameraNode.eulerAngles = SCNVector3(-0.05, 0, 0)
    cameraRig.addChildNode(cameraNode)

    // Player gloves — children of the camera rig so they stay in
    // first-person framing even when the rig shakes.
    playerLeftGlove = makeGloveNode()
    playerLeftGlove.position = playerGloveGuardLeft
    cameraRig.addChildNode(playerLeftGlove)
    playerRightGlove = makeGloveNode()
    playerRightGlove.position = playerGloveGuardRight
    cameraRig.addChildNode(playerRightGlove)

    // Lights.
    let key = SCNLight()
    key.type = .directional
    key.intensity = 950
    key.castsShadow = true
    key.shadowMode = .deferred
    keyLightNode = SCNNode()
    keyLightNode.light = key
    keyLightNode.eulerAngles = SCNVector3(-0.85, 0.40, 0)
    keyLightNode.position = SCNVector3(2, 5, 3)
    root.addChildNode(keyLightNode)

    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.intensity = 420
    ambientLightNode = SCNNode()
    ambientLightNode.light = ambient
    root.addChildNode(ambientLightNode)
  }

  private func buildOpponent(into root: SCNNode) {
    // Torso — capsule for the chest.
    let torsoGeo = SCNCapsule(capRadius: 0.30, height: 0.80)
    torsoGeo.firstMaterial = bodyMaterial()
    opponentTorso = SCNNode(geometry: torsoGeo)
    opponentTorso.position = SCNVector3(0, 1.10, 0)
    root.addChildNode(opponentTorso)

    // Head — sphere on top.
    let headGeo = SCNSphere(radius: 0.22)
    headGeo.firstMaterial = bodyMaterial()
    opponentHead = SCNNode(geometry: headGeo)
    opponentHead.position = SCNVector3(0, 1.75, 0)
    root.addChildNode(opponentHead)

    // Trunks — wide short cylinder around the hips.
    let trunksGeo = SCNCylinder(radius: 0.34, height: 0.40)
    trunksGeo.firstMaterial = trunksMaterial()
    opponentTrunks = SCNNode(geometry: trunksGeo)
    opponentTrunks.position = SCNVector3(0, 0.55, 0)
    root.addChildNode(opponentTrunks)

    // Legs — two narrower capsules.
    let legGeo = SCNCapsule(capRadius: 0.13, height: 0.55)
    legGeo.firstMaterial = bodyMaterial()
    let leftLeg = SCNNode(geometry: legGeo)
    leftLeg.position = SCNVector3(-0.16, 0.18, 0)
    root.addChildNode(leftLeg)
    let rightLeg = SCNNode(geometry: legGeo.copy() as! SCNCapsule)
    rightLeg.geometry?.firstMaterial = bodyMaterial()
    rightLeg.position = SCNVector3(0.16, 0.18, 0)
    root.addChildNode(rightLeg)

    // Arms + gloves (left / right). Each arm is a single capsule
    // pointing FROM the shoulder TO the glove; we reposition it as a
    // whole to extend toward the camera on incoming-attack telegraphs.
    opponentLeftArm = makeArmNode()
    opponentLeftArm.position = SCNVector3(-0.36, 1.40, 0)
    root.addChildNode(opponentLeftArm)
    opponentLeftGlove = makeGloveNode(playerSide: false)
    opponentLeftGlove.position = opponentGuardLeftLocal
    root.addChildNode(opponentLeftGlove)

    opponentRightArm = makeArmNode()
    opponentRightArm.position = SCNVector3(0.36, 1.40, 0)
    root.addChildNode(opponentRightArm)
    opponentRightGlove = makeGloveNode(playerSide: false)
    opponentRightGlove.position = opponentGuardRightLocal
    root.addChildNode(opponentRightGlove)
  }

  private func makeArmNode() -> SCNNode {
    let upper = SCNCapsule(capRadius: 0.10, height: 0.45)
    upper.firstMaterial = bodyMaterial()
    let node = SCNNode(geometry: upper)
    return node
  }

  private func makeGloveNode(playerSide: Bool = true) -> SCNNode {
    let geo = SCNSphere(radius: 0.16)
    let mat = SCNMaterial()
    mat.diffuse.contents = playerSide ? UIColor.blue : UIColor.red
    mat.roughness.contents = 0.55
    geo.firstMaterial = mat
    return SCNNode(geometry: geo)
  }

  private func bodyMaterial() -> SCNMaterial {
    let m = SCNMaterial()
    m.diffuse.contents = UIColor(red: 0.78, green: 0.55, blue: 0.40, alpha: 1)
    m.roughness.contents = 0.6
    return m
  }

  private func trunksMaterial() -> SCNMaterial {
    let m = SCNMaterial()
    m.diffuse.contents = UIColor.darkGray
    m.roughness.contents = 0.5
    return m
  }

  /// Continuous subtle bob on the opponent — keeps them feeling alive
  /// between attacks. Interrupted (and restored) by recoil and lunge
  /// animations.
  private func startIdleBob() {
    let down = SCNAction.moveBy(x: 0, y: -0.04, z: 0, duration: 0.6)
    down.timingMode = .easeInEaseOut
    let up = SCNAction.moveBy(x: 0, y: 0.04, z: 0, duration: 0.6)
    up.timingMode = .easeInEaseOut
    opponentRoot.runAction(.repeatForever(.sequence([down, up])), forKey: "idleBob")
  }

  // MARK: Theme

  func update(theme: BoxingSceneTheme) {
    self.theme = theme
    applyTheme(theme)
  }

  private func applyTheme(_ theme: BoxingSceneTheme) {
    opponentTorso.geometry?.firstMaterial?.diffuse.contents = theme.bodyColor
    opponentHead.geometry?.firstMaterial?.diffuse.contents = theme.bodyColor
    opponentLeftArm.geometry?.firstMaterial?.diffuse.contents = theme.bodyColor
    opponentRightArm.geometry?.firstMaterial?.diffuse.contents = theme.bodyColor
    opponentTrunks.geometry?.firstMaterial?.diffuse.contents = theme.trunksColor
    opponentLeftGlove.geometry?.firstMaterial?.diffuse.contents = theme.opponentGloveColor
    opponentRightGlove.geometry?.firstMaterial?.diffuse.contents = theme.opponentGloveColor
    playerLeftGlove.geometry?.firstMaterial?.diffuse.contents = theme.playerGloveColor
    playerRightGlove.geometry?.firstMaterial?.diffuse.contents = theme.playerGloveColor
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
      self?.playPlayerPunch()
    }
    incomingSub = game.$incomingAttack.receive(on: RunLoop.main).sink {
      [weak self] attack in
      self?.handleIncomingAttack(attack)
    }
    hitSub = game.$lastHitEventID.receive(on: RunLoop.main).sink { [weak self] _ in
      self?.shakeCamera()
    }
  }

  // MARK: Player offence

  private func playPlayerPunch() {
    guard let game else { return }
    // Decide which player glove swings. Center jab goes with the
    // right glove (orthodox stance default); hooks use the matching
    // side glove.
    let glove: SCNNode
    let restPos: SCNVector3
    switch game.lastPunchSide {
    case .center, .right:
      glove = playerRightGlove
      restPos = playerGloveGuardRight
    case .left:
      glove = playerLeftGlove
      restPos = playerGloveGuardLeft
    }
    let punchPos = SCNVector3(
      restPos.x * 0.5,  // pull slightly toward centre as it extends
      restPos.y + 0.15,
      restPos.z - playerPunchReach
    )
    let extend = SCNAction.move(to: punchPos, duration: 0.12)
    extend.timingMode = .easeOut
    let retract = SCNAction.move(to: restPos, duration: 0.22)
    retract.timingMode = .easeIn
    glove.removeAction(forKey: "punch")
    glove.runAction(.sequence([extend, retract]), forKey: "punch")

    // Opponent reacts: head + torso recoil briefly opposite the
    // player's swing direction.
    let recoilX: Float
    switch game.lastPunchSide {
    case .center: recoilX = 0
    case .left: recoilX = 0.10
    case .right: recoilX = -0.10
    }
    let bodyKick = SCNAction.moveBy(
      x: CGFloat(recoilX), y: 0, z: -0.10, duration: 0.10)
    bodyKick.timingMode = .easeOut
    let bodyReturn = SCNAction.moveBy(
      x: CGFloat(-recoilX), y: 0, z: 0.10, duration: 0.30)
    bodyReturn.timingMode = .easeInEaseOut
    let headKick = SCNAction.rotateBy(
      x: -0.25, y: CGFloat(recoilX * 1.5), z: 0, duration: 0.10)
    let headReturn = SCNAction.rotateBy(
      x: 0.25, y: CGFloat(-recoilX * 1.5), z: 0, duration: 0.30)
    opponentTorso.runAction(.sequence([bodyKick, bodyReturn]), forKey: "torsoRecoil")
    opponentHead.runAction(.sequence([headKick, headReturn]), forKey: "headRecoil")
  }

  // MARK: CPU offence (incoming attack telegraph)

  private func handleIncomingAttack(_ attack: BoxingGame.IncomingAttack) {
    switch attack {
    case .none:
      // Snap both opponent gloves back to guard.
      let leftSnap = SCNAction.move(to: opponentGuardLeftLocal, duration: 0.18)
      leftSnap.timingMode = .easeOut
      let rightSnap = SCNAction.move(to: opponentGuardRightLocal, duration: 0.18)
      rightSnap.timingMode = .easeOut
      opponentLeftGlove.removeAction(forKey: "incoming")
      opponentRightGlove.removeAction(forKey: "incoming")
      opponentLeftGlove.runAction(leftSnap)
      opponentRightGlove.runAction(rightSnap)
    case .jab:
      // Right hand straight forward at the camera.
      extendOpponentGlove(opponentRightGlove, toward: SCNVector3(0.10, 1.50, 1.30))
    case .uppercut:
      // Right hand angles up and forward.
      extendOpponentGlove(opponentRightGlove, toward: SCNVector3(0.05, 1.20, 1.20))
    case .hookLeft:
      // Opponent throws their left hook — appears on player's RIGHT
      // side of frame. Player must dodge right (matchDodge in the
      // game model already enforces this mapping).
      extendOpponentGlove(opponentLeftGlove, toward: SCNVector3(0.55, 1.45, 1.10))
    case .hookRight:
      extendOpponentGlove(opponentRightGlove, toward: SCNVector3(-0.55, 1.45, 1.10))
    }
  }

  private func extendOpponentGlove(_ glove: SCNNode, toward target: SCNVector3) {
    // Telegraph window in the model is ~1.0s; spend most of it
    // extending so the player has time to read the direction.
    let extend = SCNAction.move(to: target, duration: 0.55)
    extend.timingMode = .easeOut
    glove.runAction(extend, forKey: "incoming")
  }

  // MARK: Player getting hit

  private func shakeCamera() {
    let amp: Float = 0.08
    let s1 = SCNAction.moveBy(x: CGFloat(amp), y: -CGFloat(amp), z: 0, duration: 0.04)
    let s2 = SCNAction.moveBy(x: CGFloat(-amp * 2), y: CGFloat(amp * 1.6), z: 0, duration: 0.06)
    let s3 = SCNAction.moveBy(x: CGFloat(amp * 1.4), y: CGFloat(-amp * 0.8), z: 0, duration: 0.08)
    let s4 = SCNAction.moveBy(
      x: CGFloat(-amp * 0.4), y: CGFloat(amp * 0.2), z: 0, duration: 0.10)
    cameraRig.removeAction(forKey: "shake")
    cameraRig.runAction(.sequence([s1, s2, s3, s4]), forKey: "shake")
  }
}
