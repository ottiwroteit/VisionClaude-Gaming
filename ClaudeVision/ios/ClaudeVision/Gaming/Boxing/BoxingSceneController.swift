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

  // MARK: Material registries
  // Multiple body parts share the "skin tone" colour; rather than
  // walking the node tree on theme change to find them, we keep the
  // material instances in flat arrays at construction time and re-tint
  // each one in applyTheme. Same trick for trunks and gloves so the
  // detailed boxer recolours cleanly across venue swaps.

  private var skinMaterials: [SCNMaterial] = []
  private var trunksMaterials: [SCNMaterial] = []
  private var opponentGloveMaterials: [SCNMaterial] = []
  private var playerGloveMaterials: [SCNMaterial] = []

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
    let torsoGeo = SCNCapsule(capRadius: 0.32, height: 0.85)
    torsoGeo.firstMaterial = bodyMaterial()
    opponentTorso = SCNNode(geometry: torsoGeo)
    opponentTorso.position = SCNVector3(0, 1.12, 0)
    root.addChildNode(opponentTorso)

    // Pectoral / shoulder bumps so the torso silhouette doesn't read
    // as a single tube. Two slight spheres on top, just under where
    // the shoulders sit.
    let pecGeo = SCNSphere(radius: 0.13)
    pecGeo.firstMaterial = bodyMaterial()
    let leftPec = SCNNode(geometry: pecGeo)
    leftPec.position = SCNVector3(-0.16, 0.30, 0.18)
    opponentTorso.addChildNode(leftPec)
    let rightPec = SCNNode(geometry: pecGeo.copy() as! SCNSphere)
    rightPec.geometry?.firstMaterial = bodyMaterial()
    rightPec.position = SCNVector3(0.16, 0.30, 0.18)
    opponentTorso.addChildNode(rightPec)

    // Neck — small connector between torso and head so the head
    // isn't visually floating above the chest.
    let neckGeo = SCNCylinder(radius: 0.08, height: 0.12)
    neckGeo.firstMaterial = bodyMaterial()
    let neck = SCNNode(geometry: neckGeo)
    neck.position = SCNVector3(0, 1.55, 0)
    root.addChildNode(neck)

    // Head — slightly egg-shaped skull with full face features.
    opponentHead = makeOpponentHead()
    opponentHead.position = SCNVector3(0, 1.75, 0)
    root.addChildNode(opponentHead)

    // Trunks — wide short cylinder around the hips.
    let trunksGeo = SCNCylinder(radius: 0.36, height: 0.40)
    trunksGeo.firstMaterial = trunksMaterial()
    opponentTrunks = SCNNode(geometry: trunksGeo)
    opponentTrunks.position = SCNVector3(0, 0.55, 0)
    root.addChildNode(opponentTrunks)

    // Waistband stripe — thin contrast cylinder at the top of the
    // trunks. Kept as a child so it moves with the trunks.
    let beltGeo = SCNCylinder(radius: 0.365, height: 0.07)
    let beltMat = SCNMaterial()
    beltMat.diffuse.contents = UIColor.white
    beltMat.roughness.contents = 0.5
    beltGeo.firstMaterial = beltMat
    let belt = SCNNode(geometry: beltGeo)
    belt.position = SCNVector3(0, 0.18, 0)
    opponentTrunks.addChildNode(belt)

    // Legs — upper + lower segment with a knee joint, plus boots.
    addLeg(into: root, xOffset: -0.16)
    addLeg(into: root, xOffset: 0.16)

    // Arms — upper arm + elbow + forearm hierarchy. Positioned at
    // the shoulders; geometry hangs down toward the gloves.
    opponentLeftArm = makeArmNode()
    opponentLeftArm.position = SCNVector3(-0.42, 1.42, 0)
    root.addChildNode(opponentLeftArm)
    opponentRightArm = makeArmNode()
    opponentRightArm.position = SCNVector3(0.42, 1.42, 0)
    root.addChildNode(opponentRightArm)

    // Gloves — separate top-level nodes so they can extend
    // independently on incoming-attack telegraphs.
    opponentLeftGlove = makeGloveNode(playerSide: false)
    opponentLeftGlove.position = opponentGuardLeftLocal
    root.addChildNode(opponentLeftGlove)
    opponentRightGlove = makeGloveNode(playerSide: false)
    opponentRightGlove.position = opponentGuardRightLocal
    root.addChildNode(opponentRightGlove)
  }

  /// Builds a stylized head with eyes, brows, nose, mouth, ears, hair,
  /// and a defined chin. The PARENT node still carries the main skull
  /// geometry so `applyTheme` can re-tint the skin colour by writing
  /// to `opponentHead.geometry?.firstMaterial?.diffuse`.
  private func makeOpponentHead() -> SCNNode {
    let skullGeo = SCNSphere(radius: 0.22)
    skullGeo.firstMaterial = bodyMaterial()
    let head = SCNNode(geometry: skullGeo)
    // Slight forward squash so the face has a flat-ish presentation.
    head.scale = SCNVector3(1.0, 1.05, 0.95)

    // Chin — a smaller sphere just below the skull, slightly forward.
    let chinGeo = SCNSphere(radius: 0.09)
    chinGeo.firstMaterial = bodyMaterial()
    let chin = SCNNode(geometry: chinGeo)
    chin.position = SCNVector3(0, -0.18, 0.06)
    head.addChildNode(chin)

    // Hair — dark short cap on top, modeled as a flattened sphere.
    let hairGeo = SCNSphere(radius: 0.20)
    let hairMat = SCNMaterial()
    hairMat.diffuse.contents = UIColor(red: 0.10, green: 0.07, blue: 0.05, alpha: 1)
    hairMat.roughness.contents = 0.85
    hairGeo.firstMaterial = hairMat
    let hair = SCNNode(geometry: hairGeo)
    hair.position = SCNVector3(0, 0.07, -0.01)
    hair.scale = SCNVector3(1.05, 0.65, 1.05)
    head.addChildNode(hair)

    // Eyebrows — thin dark boxes above each eye, slightly tilted in.
    addEyebrow(to: head, x: -0.075, tiltZ: -0.18)
    addEyebrow(to: head, x: 0.075, tiltZ: 0.18)

    // Eyes — white spheres + smaller dark pupils in front.
    addEye(to: head, x: -0.075)
    addEye(to: head, x: 0.075)

    // Nose — small sphere bump in the centre of the face. Avoids
    // the SCNCone-rotation gymnastics; reads fine.
    let noseGeo = SCNSphere(radius: 0.025)
    noseGeo.firstMaterial = bodyMaterial()
    let nose = SCNNode(geometry: noseGeo)
    nose.position = SCNVector3(0, -0.02, 0.215)
    head.addChildNode(nose)
    // A tiny shadow under the nose for definition.
    let nostrilGeo = SCNBox(width: 0.018, height: 0.005, length: 0.008, chamferRadius: 0)
    let nostrilMat = SCNMaterial()
    nostrilMat.diffuse.contents = UIColor(white: 0.10, alpha: 1)
    nostrilGeo.firstMaterial = nostrilMat
    let nostril = SCNNode(geometry: nostrilGeo)
    nostril.position = SCNVector3(0, -0.05, 0.225)
    head.addChildNode(nostril)

    // Mouth — thin dark box, set into the chin area.
    let mouthGeo = SCNBox(width: 0.07, height: 0.012, length: 0.005, chamferRadius: 0.002)
    let mouthMat = SCNMaterial()
    mouthMat.diffuse.contents = UIColor(red: 0.45, green: 0.10, blue: 0.10, alpha: 1)
    mouthGeo.firstMaterial = mouthMat
    let mouth = SCNNode(geometry: mouthGeo)
    mouth.position = SCNVector3(0, -0.10, 0.21)
    head.addChildNode(mouth)

    // Ears — small spheres on each side of the head, flattened
    // along X so they hug the skull.
    addEar(to: head, x: -0.21)
    addEar(to: head, x: 0.21)

    return head
  }

  private func addEyebrow(to head: SCNNode, x: Float, tiltZ: Float) {
    let geo = SCNBox(width: 0.075, height: 0.014, length: 0.018, chamferRadius: 0.003)
    let mat = SCNMaterial()
    mat.diffuse.contents = UIColor(red: 0.10, green: 0.07, blue: 0.05, alpha: 1)
    geo.firstMaterial = mat
    let brow = SCNNode(geometry: geo)
    brow.position = SCNVector3(x, 0.06, 0.20)
    brow.eulerAngles = SCNVector3(0, 0, tiltZ)
    head.addChildNode(brow)
  }

  private func addEye(to head: SCNNode, x: Float) {
    let whiteGeo = SCNSphere(radius: 0.030)
    let whiteMat = SCNMaterial()
    whiteMat.diffuse.contents = UIColor.white
    whiteGeo.firstMaterial = whiteMat
    let white = SCNNode(geometry: whiteGeo)
    white.position = SCNVector3(x, 0.02, 0.195)
    head.addChildNode(white)

    let pupilGeo = SCNSphere(radius: 0.013)
    let pupilMat = SCNMaterial()
    pupilMat.diffuse.contents = UIColor(white: 0.05, alpha: 1)
    pupilGeo.firstMaterial = pupilMat
    let pupil = SCNNode(geometry: pupilGeo)
    pupil.position = SCNVector3(x, 0.02, 0.215)
    head.addChildNode(pupil)
  }

  private func addEar(to head: SCNNode, x: Float) {
    let geo = SCNSphere(radius: 0.045)
    geo.firstMaterial = bodyMaterial()
    let ear = SCNNode(geometry: geo)
    ear.position = SCNVector3(x, 0.01, 0)
    ear.scale = SCNVector3(0.5, 1.0, 0.85)
    head.addChildNode(ear)
  }

  /// Builds a single leg: upper leg + knee joint + lower leg + boot.
  private func addLeg(into root: SCNNode, xOffset: Float) {
    let upper = SCNCapsule(capRadius: 0.13, height: 0.40)
    upper.firstMaterial = bodyMaterial()
    let upperNode = SCNNode(geometry: upper)
    upperNode.position = SCNVector3(xOffset, 0.30, 0)
    root.addChildNode(upperNode)

    let knee = SCNSphere(radius: 0.10)
    knee.firstMaterial = bodyMaterial()
    let kneeNode = SCNNode(geometry: knee)
    kneeNode.position = SCNVector3(xOffset, 0.10, 0.02)
    root.addChildNode(kneeNode)

    let lower = SCNCapsule(capRadius: 0.10, height: 0.30)
    lower.firstMaterial = bodyMaterial()
    let lowerNode = SCNNode(geometry: lower)
    lowerNode.position = SCNVector3(xOffset, -0.05, 0.02)
    root.addChildNode(lowerNode)

    // Boot — a small dark box at the bottom of the leg.
    let bootGeo = SCNBox(width: 0.18, height: 0.10, length: 0.24, chamferRadius: 0.04)
    let bootMat = SCNMaterial()
    bootMat.diffuse.contents = UIColor(white: 0.08, alpha: 1)
    bootMat.roughness.contents = 0.7
    bootGeo.firstMaterial = bootMat
    let bootNode = SCNNode(geometry: bootGeo)
    bootNode.position = SCNVector3(xOffset, -0.22, 0.05)
    root.addChildNode(bootNode)
  }

  /// Builds a multi-segment arm: upper arm + elbow joint + forearm.
  /// Hangs DOWN from the shoulder origin (Y=0 at the shoulder; the
  /// forearm ends near Y = -0.6).
  private func makeArmNode() -> SCNNode {
    let arm = SCNNode()

    let upper = SCNCapsule(capRadius: 0.085, height: 0.32)
    upper.firstMaterial = bodyMaterial()
    let upperNode = SCNNode(geometry: upper)
    upperNode.position = SCNVector3(0, -0.16, 0)
    arm.addChildNode(upperNode)

    let elbow = SCNSphere(radius: 0.075)
    elbow.firstMaterial = bodyMaterial()
    let elbowNode = SCNNode(geometry: elbow)
    elbowNode.position = SCNVector3(0, -0.34, 0)
    arm.addChildNode(elbowNode)

    let forearm = SCNCapsule(capRadius: 0.075, height: 0.28)
    forearm.firstMaterial = bodyMaterial()
    let forearmNode = SCNNode(geometry: forearm)
    forearmNode.position = SCNVector3(0, -0.50, 0)
    arm.addChildNode(forearmNode)
    return arm
  }

  /// Builds a boxing-glove node: a slightly oval main body in the
  /// theme's glove colour, with a darker wrist cuff stuck behind it
  /// and a small thumb bump up top so it reads as a glove rather
  /// than a featureless ball.
  private func makeGloveNode(playerSide: Bool = true) -> SCNNode {
    let mainGeo = SCNSphere(radius: 0.17)
    mainGeo.firstMaterial = gloveMaterial(playerSide: playerSide)
    let glove = SCNNode(geometry: mainGeo)
    // Squash slightly so the silhouette is a fat oval, not a perfect
    // ball. Scale ON THE NODE applies to its children too — both the
    // cuff and thumb get the same proportions, which is what we want.
    glove.scale = SCNVector3(1.05, 0.95, 1.15)

    // Cuff — flatter cylinder at the back of the glove (toward the
    // wrist). Cuff is a contrast colour, NOT themed — every theme
    // gets the same dark wristband.
    let cuffGeo = SCNCylinder(radius: 0.13, height: 0.06)
    let cuffMat = SCNMaterial()
    cuffMat.diffuse.contents = UIColor(white: 0.12, alpha: 1)
    cuffMat.roughness.contents = 0.6
    cuffGeo.firstMaterial = cuffMat
    let cuff = SCNNode(geometry: cuffGeo)
    cuff.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
    cuff.position = SCNVector3(0, 0, -0.15)
    glove.addChildNode(cuff)

    // Thumb bump — small sphere on top-front of the glove. Same
    // glove material so it re-tints with the main body on theme swap.
    let thumbGeo = SCNSphere(radius: 0.06)
    thumbGeo.firstMaterial = gloveMaterial(playerSide: playerSide)
    let thumb = SCNNode(geometry: thumbGeo)
    thumb.position = SCNVector3(0, 0.10, 0.07)
    glove.addChildNode(thumb)
    return glove
  }

  private func bodyMaterial() -> SCNMaterial {
    let m = SCNMaterial()
    m.diffuse.contents = UIColor(red: 0.78, green: 0.55, blue: 0.40, alpha: 1)
    m.roughness.contents = 0.6
    skinMaterials.append(m)
    return m
  }

  private func trunksMaterial() -> SCNMaterial {
    let m = SCNMaterial()
    m.diffuse.contents = UIColor.darkGray
    m.roughness.contents = 0.5
    trunksMaterials.append(m)
    return m
  }

  /// Opponent / player glove material factory. Registers the material
  /// into the matching glove-tracked array so applyTheme can recolour
  /// every glove sub-piece (main body + thumb) on a theme change.
  private func gloveMaterial(playerSide: Bool) -> SCNMaterial {
    let m = SCNMaterial()
    m.diffuse.contents = playerSide ? UIColor.blue : UIColor.red
    m.roughness.contents = 0.55
    if playerSide {
      playerGloveMaterials.append(m)
    } else {
      opponentGloveMaterials.append(m)
    }
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
    // Walk the registered materials so every skin / trunks / glove
    // sub-piece (face features that share the body tone, segmented
    // arms, leg parts, glove thumb, etc.) re-tints together.
    for m in skinMaterials { m.diffuse.contents = theme.bodyColor }
    for m in trunksMaterials { m.diffuse.contents = theme.trunksColor }
    for m in opponentGloveMaterials { m.diffuse.contents = theme.opponentGloveColor }
    for m in playerGloveMaterials { m.diffuse.contents = theme.playerGloveColor }
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
