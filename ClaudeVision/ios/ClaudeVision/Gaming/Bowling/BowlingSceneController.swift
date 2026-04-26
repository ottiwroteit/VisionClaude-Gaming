import Combine
import Foundation
import SceneKit
import UIKit

/// Owns the SceneKit scene graph for bowling: lane, gutters, ten pins,
/// ball, camera, and lighting. Observes `BowlingGame` phase transitions
/// and translates them into physics commands; observes the physics
/// world's settle state and translates that back into game-state calls.
///
/// The contract with `BowlingGame` is intentionally narrow:
/// - Read aim/power/hook from the game on the `.idle → .rolling`
///   transition (via `pendingPower`, `pendingHook`, `aimPosition`).
/// - Call `game.physicsDidSettle(knockedThisRoll:wasGutter:)` once the
///   ball stops moving and chain reactions have ended.
/// - Reset the rack on `.resetting → .idle` (i.e. when the next
///   `.countingDown` begins) only if the game indicates a fresh frame
///   (pinsRemaining == 10).
@MainActor
final class BowlingSceneController: NSObject {

  // MARK: Public surface

  /// The SceneKit scene mounted into the SCNView. Built once at init.
  let scene: SCNScene
  /// Current theme. Re-applied any time the venue changes.
  private(set) var theme: BowlingSceneTheme

  // MARK: Game wiring

  private weak var game: BowlingGame?
  private var phaseSub: AnyCancellable?
  private var skinSub: AnyCancellable?
  private var pinsRemainingSub: AnyCancellable?

  // MARK: Scene graph

  private var ballNode: SCNNode!
  private var pinNodes: [SCNNode] = []
  private var laneNode: SCNNode!
  private var leftGutterNode: SCNNode!
  private var rightGutterNode: SCNNode!
  private var backWallNode: SCNNode!
  private var cameraNode: SCNNode!
  private var keyLightNode: SCNNode!
  private var ambientLightNode: SCNNode!
  private var pinHomePositions: [SCNVector3] = []

  // MARK: Tunables

  /// Lane length in scene units (≈ 60 ft real, scaled down for camera framing).
  private let laneLength: Float = 22
  /// Lane width inside the gutter walls (≈ 3.5 ft real).
  private let laneWidth: Float = 1.4
  /// Gutter half-width on each side of the lane.
  private let gutterWidth: Float = 0.35
  /// Lane top surface Y.
  private let laneSurfaceY: Float = 0.0
  private let laneThickness: Float = 0.18
  /// Ball radius in scene units (regulation 8.5" → 0.10 unit at our scale).
  private let ballRadius: CGFloat = 0.105
  /// Pin half-height (regulation 15" → 0.18 unit). The pin geometry is
  /// approximated as a tapered cylinder; this is the half-height of the
  /// physics collider.
  private let pinHalfHeight: Float = 0.18
  private let pinBaseRadius: CGFloat = 0.045
  /// Distance from lane centre at which a ball is considered "in the gutter".
  private let gutterEdgeX: Float = 0.72
  /// Pin Y below which the pin is considered "fallen" for scoring.
  private let pinFallenY: Float = 0.18
  /// Ball impulse magnitude range. Power 0..1 maps linearly.
  private let baseImpulse: Float = 60
  private let powerImpulseSpan: Float = 65
  /// Hook lateral force range applied during the first part of the roll.
  private let hookForceMag: Float = 22
  /// How long after release we wait before declaring the roll settled.
  /// Keep above the typical pin-fall time at our impulse range.
  private let settleDelay: TimeInterval = 2.4

  // MARK: Roll lifecycle

  private var settleTask: Task<Void, Never>?
  private var lastObservedRoll: Int = 0

  // MARK: Init

  init(game: BowlingGame, theme: BowlingSceneTheme) {
    self.scene = SCNScene()
    self.theme = theme
    self.game = game
    super.init()
    buildScene()
    applyTheme(theme)
    observeGame()
  }

  deinit {
    settleTask?.cancel()
  }

  // MARK: Scene construction

  private func buildScene() {
    scene.physicsWorld.gravity = SCNVector3(0, -9.81, 0)
    scene.physicsWorld.timeStep = 1.0 / 120.0
    scene.background.contents = nil  // transparent; venue art shows through

    let root = scene.rootNode

    // Lane plank ------------------------------------------------------
    let laneGeo = SCNBox(
      width: CGFloat(laneWidth),
      height: CGFloat(laneThickness),
      length: CGFloat(laneLength),
      chamferRadius: 0.02
    )
    let laneMat = SCNMaterial()
    laneMat.diffuse.contents = UIColor.brown
    laneMat.roughness.contents = 0.3
    laneMat.metalness.contents = 0.0
    laneGeo.firstMaterial = laneMat
    laneNode = SCNNode(geometry: laneGeo)
    laneNode.position = SCNVector3(0, laneSurfaceY - laneThickness / 2, 0)
    let laneShape = SCNPhysicsShape(geometry: laneGeo, options: nil)
    let laneBody = SCNPhysicsBody(type: .static, shape: laneShape)
    laneBody.friction = 0.35
    laneBody.restitution = 0.05
    laneNode.physicsBody = laneBody
    root.addChildNode(laneNode)

    // Lane oil stripe -------------------------------------------------
    let stripeGeo = SCNPlane(
      width: CGFloat(laneWidth) * 0.18,
      height: CGFloat(laneLength) * 0.55
    )
    let stripeMat = SCNMaterial()
    stripeMat.diffuse.contents = UIColor.white
    stripeMat.transparency = 0.18
    stripeMat.isDoubleSided = true
    stripeGeo.firstMaterial = stripeMat
    let stripeNode = SCNNode(geometry: stripeGeo)
    stripeNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
    stripeNode.position = SCNVector3(0, laneSurfaceY + 0.001, -Float(laneLength) * 0.15)
    laneNode.addChildNode(stripeNode)

    // Gutters ---------------------------------------------------------
    leftGutterNode = makeGutter(side: -1)
    rightGutterNode = makeGutter(side: +1)
    root.addChildNode(leftGutterNode)
    root.addChildNode(rightGutterNode)

    // Back wall (catches the ball after it passes the pins) ----------
    let backGeo = SCNBox(
      width: CGFloat(laneWidth + gutterWidth * 2),
      height: 1.2, length: 0.05, chamferRadius: 0
    )
    let backMat = SCNMaterial()
    backMat.diffuse.contents = UIColor(white: 0.05, alpha: 1)
    backGeo.firstMaterial = backMat
    backWallNode = SCNNode(geometry: backGeo)
    backWallNode.position = SCNVector3(0, 0.5, -laneLength / 2 - 0.2)
    backWallNode.physicsBody = SCNPhysicsBody(
      type: .static, shape: SCNPhysicsShape(geometry: backGeo, options: nil))
    root.addChildNode(backWallNode)

    // Pins ------------------------------------------------------------
    let layout = pinLayoutPositions()
    pinHomePositions = layout
    pinNodes = layout.map { home in
      let node = makePinNode()
      node.position = home
      return node
    }
    pinNodes.forEach { root.addChildNode($0) }

    // Ball ------------------------------------------------------------
    let ballGeo = SCNSphere(radius: ballRadius)
    let ballMat = SCNMaterial()
    ballMat.diffuse.contents = UIColor.darkGray
    ballMat.metalness.contents = 0.4
    ballMat.roughness.contents = 0.2
    ballGeo.firstMaterial = ballMat
    ballNode = SCNNode(geometry: ballGeo)
    ballNode.position = ballHomePosition()
    let ballShape = SCNPhysicsShape(
      geometry: ballGeo,
      options: [SCNPhysicsShape.Option.collisionMargin: 0.001])
    let ballBody = SCNPhysicsBody(type: .dynamic, shape: ballShape)
    ballBody.mass = 6.4
    ballBody.friction = 0.45
    ballBody.rollingFriction = 0.02
    ballBody.restitution = 0.05
    ballBody.angularDamping = 0.05
    ballBody.damping = 0.08
    ballNode.physicsBody = ballBody
    root.addChildNode(ballNode)

    // Camera ----------------------------------------------------------
    let camera = SCNCamera()
    camera.fieldOfView = 55
    camera.zNear = 0.05
    camera.zFar = 80
    cameraNode = SCNNode()
    cameraNode.camera = camera
    cameraNode.position = SCNVector3(0, 0.65, laneLength / 2 + 1.4)
    cameraNode.eulerAngles = SCNVector3(-0.32, 0, 0)
    root.addChildNode(cameraNode)

    // Lights ----------------------------------------------------------
    let key = SCNLight()
    key.type = .directional
    key.intensity = 850
    key.castsShadow = true
    key.shadowMode = .deferred
    key.shadowRadius = 6
    key.shadowSampleCount = 16
    keyLightNode = SCNNode()
    keyLightNode.light = key
    keyLightNode.eulerAngles = SCNVector3(-1.0, 0.4, 0)
    keyLightNode.position = SCNVector3(2, 6, 4)
    root.addChildNode(keyLightNode)

    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.intensity = 480
    ambientLightNode = SCNNode()
    ambientLightNode.light = ambient
    root.addChildNode(ambientLightNode)
  }

  private func makeGutter(side: Float) -> SCNNode {
    // Gutter floor — slightly below lane surface so the ball drops in.
    let geo = SCNBox(
      width: CGFloat(gutterWidth),
      height: CGFloat(laneThickness),
      length: CGFloat(laneLength),
      chamferRadius: 0.01
    )
    let mat = SCNMaterial()
    mat.diffuse.contents = UIColor.darkGray
    geo.firstMaterial = mat
    let node = SCNNode(geometry: geo)
    let xOffset = (laneWidth / 2 + gutterWidth / 2) * side
    node.position = SCNVector3(xOffset, laneSurfaceY - laneThickness / 2 - 0.04, 0)
    let shape = SCNPhysicsShape(geometry: geo, options: nil)
    let body = SCNPhysicsBody(type: .static, shape: shape)
    body.friction = 0.85
    body.restitution = 0
    node.physicsBody = body
    return node
  }

  private func makePinNode() -> SCNNode {
    // Tapered cylinder approximation: regulation pin is hourglass-ish,
    // but a simple cylinder physics body works fine for collisions and
    // the visible geometry can be a slight cone for read.
    let visualGeo = SCNCylinder(radius: pinBaseRadius, height: CGFloat(pinHalfHeight * 2))
    let bodyMat = SCNMaterial()
    bodyMat.diffuse.contents = UIColor.white
    bodyMat.roughness.contents = 0.4
    visualGeo.firstMaterial = bodyMat
    let node = SCNNode(geometry: visualGeo)

    // Red stripe on the neck, just for visual identity.
    let stripeGeo = SCNCylinder(radius: pinBaseRadius * 1.05, height: 0.04)
    let stripeMat = SCNMaterial()
    stripeMat.diffuse.contents = UIColor.red
    stripeGeo.firstMaterial = stripeMat
    let stripe = SCNNode(geometry: stripeGeo)
    stripe.position = SCNVector3(0, pinHalfHeight * 0.45, 0)
    node.addChildNode(stripe)

    let physicsGeo = SCNCylinder(radius: pinBaseRadius * 1.05, height: CGFloat(pinHalfHeight * 2))
    let shape = SCNPhysicsShape(
      geometry: physicsGeo,
      options: [SCNPhysicsShape.Option.collisionMargin: 0.001])
    let body = SCNPhysicsBody(type: .dynamic, shape: shape)
    body.mass = 1.6
    body.friction = 0.55
    body.rollingFriction = 0.6
    body.restitution = 0.1
    body.damping = 0.05
    body.angularDamping = 0.1
    body.allowsResting = true
    node.physicsBody = body
    return node
  }

  /// 10-pin triangle layout. Returns the home position of each pin in
  /// canonical bowling order (1 = head pin, 2-3 second row, 4-6 third,
  /// 7-10 back row). Origin is the lane's pin-end (Z = -laneLength/2).
  private func pinLayoutPositions() -> [SCNVector3] {
    let pinSpacingX: Float = 0.20
    let rowSpacingZ: Float = 0.18
    let baseY = laneSurfaceY + pinHalfHeight + 0.005
    let backZ = -laneLength / 2 + 0.50  // back row Z (deepest into the scene)
    // Rows from BACK (away from bowler) to FRONT (head pin closest to bowler).
    // SceneKit camera sits at +Z, so "closer to bowler" = larger Z.
    let row1: [SCNVector3] = [
      SCNVector3(-1.5 * pinSpacingX, baseY, backZ),
      SCNVector3(-0.5 * pinSpacingX, baseY, backZ),
      SCNVector3(0.5 * pinSpacingX, baseY, backZ),
      SCNVector3(1.5 * pinSpacingX, baseY, backZ),
    ]
    let row2: [SCNVector3] = [
      SCNVector3(-1.0 * pinSpacingX, baseY, backZ + rowSpacingZ),
      SCNVector3(0, baseY, backZ + rowSpacingZ),
      SCNVector3(1.0 * pinSpacingX, baseY, backZ + rowSpacingZ),
    ]
    let row3: [SCNVector3] = [
      SCNVector3(-0.5 * pinSpacingX, baseY, backZ + 2 * rowSpacingZ),
      SCNVector3(0.5 * pinSpacingX, baseY, backZ + 2 * rowSpacingZ),
    ]
    let row4: [SCNVector3] = [
      SCNVector3(0, baseY, backZ + 3 * rowSpacingZ)
    ]
    // Concat in pin-number order: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].
    return row4 + row3 + row2 + row1
  }

  private func ballHomePosition() -> SCNVector3 {
    SCNVector3(0, Float(ballRadius) + laneSurfaceY + 0.005, laneLength / 2 - 0.6)
  }

  // MARK: Theme

  func update(theme: BowlingSceneTheme) {
    guard !theme.matches(self.theme) else { return }
    self.theme = theme
    applyTheme(theme)
  }

  private func applyTheme(_ theme: BowlingSceneTheme) {
    laneNode.geometry?.firstMaterial?.diffuse.contents = theme.laneColor
    leftGutterNode.geometry?.firstMaterial?.diffuse.contents = theme.gutterColor
    rightGutterNode.geometry?.firstMaterial?.diffuse.contents = theme.gutterColor
    keyLightNode.light?.color = theme.keyLightColor
    ambientLightNode.light?.color = theme.ambientColor
    scene.fogStartDistance = theme.fogStartDistance
    scene.fogEndDistance = theme.fogEndDistance
    scene.fogColor = theme.fogColor
    scene.fogDensityExponent = 1.6
    for pin in pinNodes {
      pin.geometry?.firstMaterial?.diffuse.contents = theme.pinBodyColor
      if let stripeNode = pin.childNodes.first {
        stripeNode.geometry?.firstMaterial?.diffuse.contents = theme.pinAccentColor
      }
    }
  }

  // MARK: Game observation

  private func observeGame() {
    guard let game else { return }
    phaseSub = game.$phase.receive(on: RunLoop.main).sink { [weak self] phase in
      self?.handlePhase(phase)
    }
    skinSub = game.$selectedSkin.receive(on: RunLoop.main).sink { [weak self] _ in
      self?.applyBallSkin()
    }
    pinsRemainingSub = game.$pinsRemaining.receive(on: RunLoop.main).sink { [weak self] remaining in
      // When the game's pin count snaps back to 10 outside of normal
      // physics flow (frame reset / 10th frame fresh rack), rack the
      // visual pins to match.
      guard let self else { return }
      if remaining == 10 && self.standingPinCount() < 9 {
        self.rackPins()
      }
    }
    applyBallSkin()
  }

  private func applyBallSkin() {
    guard let game else { return }
    ballNode.geometry?.firstMaterial?.diffuse.contents = game.activeSkin.sceneColor
  }

  private func handlePhase(_ phase: BowlingGame.RollPhase) {
    switch phase {
    case .countingDown:
      // New turn — make sure the ball is back home and the previous
      // roll's settle task is dead.
      settleTask?.cancel()
      settleTask = nil
      resetBallToHome()
    case .idle:
      break
    case .rolling:
      launchBall()
    case .knocking, .resetting, .finalScoring:
      break
    }
  }

  // MARK: Ball / pin manipulation

  private func resetBallToHome() {
    let body = ballNode.physicsBody
    body?.clearAllForces()
    body?.velocity = SCNVector3Zero
    body?.angularVelocity = SCNVector4(0, 1, 0, 0)
    ballNode.position = ballHomePosition()
    ballNode.eulerAngles = SCNVector3Zero
  }

  private func rackPins() {
    for (i, node) in pinNodes.enumerated() {
      let body = node.physicsBody
      body?.clearAllForces()
      body?.velocity = SCNVector3Zero
      body?.angularVelocity = SCNVector4(0, 1, 0, 0)
      node.position = pinHomePositions[i]
      node.eulerAngles = SCNVector3Zero
    }
  }

  private func launchBall() {
    guard let game else { return }
    settleTask?.cancel()

    // Ball start position offset by aim along X. Cap so the ball still
    // launches from inside the lane (not in a gutter at start).
    let aim = max(-1, min(1, game.aimPosition))
    let aimOffsetX = aim * (laneWidth / 2 - Float(ballRadius) - 0.02)
    var start = ballHomePosition()
    start.x = aimOffsetX
    ballNode.position = start
    ballNode.eulerAngles = SCNVector3Zero
    let body = ballNode.physicsBody
    body?.clearAllForces()
    body?.velocity = SCNVector3Zero
    body?.angularVelocity = SCNVector4(0, 1, 0, 0)

    // Forward impulse — power 0..1 → impulse magnitude.
    let power = max(0, min(1, game.pendingPower))
    let impulseMag = baseImpulse + powerImpulseSpan * power
    body?.applyForce(SCNVector3(0, 0, -impulseMag), asImpulse: true)

    // Hook — apply a lateral force over a brief window via SCNAction.
    // Doing it as a brief constant force (rather than an instantaneous
    // impulse) reads as a curving roll instead of a pop sideways.
    let hook = max(-1, min(1, game.pendingHook))
    if abs(hook) > 0.05 {
      let lateralForce = SCNVector3(hook * hookForceMag, 0, 0)
      // Use the action-target node passed into the closure rather than
      // capturing self.ballNode — keeps the renderer-thread work clear
      // of any main-actor-isolated state.
      let pulse = SCNAction.customAction(duration: 0.5) { node, elapsed in
        guard 0.5 - elapsed > 0 else { return }
        node.physicsBody?.applyForce(lateralForce, asImpulse: false)
      }
      ballNode.runAction(pulse, forKey: "hookPulse")
    }

    // Schedule a settle check. Don't await — this runs concurrent with
    // the physics step until we measure and report.
    settleTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(Self.settleDelayNanos))
      guard !Task.isCancelled else { return }
      self?.settleAndReport()
    }
  }

  private static let settleDelayNanos: UInt64 = 2_400_000_000

  private func settleAndReport() {
    guard let game else { return }
    let knockedNow = pinNodes.filter { $0.presentation.position.y < pinFallenY }.count
    let alreadyKnocked = 10 - game.pinsRemaining
    let newlyKnocked = max(0, knockedNow - alreadyKnocked)
    let ballX = ballNode.presentation.position.x
    let wasGutter = abs(ballX) > gutterEdgeX && newlyKnocked == 0
    game.physicsDidSettle(knockedThisRoll: newlyKnocked, wasGutter: wasGutter)
  }

  private func standingPinCount() -> Int {
    pinNodes.filter { $0.presentation.position.y >= pinFallenY }.count
  }
}

extension BowlingSceneTheme {
  /// Cheap equality check on the fields the controller actually applies.
  /// Avoids re-binding materials when SwiftUI re-renders without a real
  /// venue change.
  fileprivate func matches(_ other: BowlingSceneTheme) -> Bool {
    laneColor == other.laneColor
      && pinBodyColor == other.pinBodyColor
      && pinAccentColor == other.pinAccentColor
      && keyLightColor == other.keyLightColor
      && ambientColor == other.ambientColor
      && fogColor == other.fogColor
      && gutterColor == other.gutterColor
  }
}
