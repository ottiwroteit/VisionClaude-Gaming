import Combine
import Foundation
import SceneKit
import UIKit

/// Owns the SceneKit scene graph for tennis: a 3D court extending
/// away from the camera with a net at the midpoint, the player at the
/// near baseline (camera POV), and a stylized opponent at the far
/// baseline. The ball arcs back and forth in response to game shot
/// events.
@MainActor
final class TennisSceneController: NSObject {

  // MARK: Public surface

  let scene: SCNScene
  private(set) var theme: TennisSceneTheme

  // MARK: Game wiring

  private weak var game: TennisGame?
  private var shotSub: AnyCancellable?

  // MARK: Scene graph

  private var courtNode: SCNNode!
  private var serviceLineFarNode: SCNNode!
  private var serviceLineNearNode: SCNNode!
  private var centerLineNode: SCNNode!
  private var netNode: SCNNode!
  private var netPostLeft: SCNNode!
  private var netPostRight: SCNNode!
  private var ballNode: SCNNode!
  private var opponentBody: SCNNode!
  private var opponentHead: SCNNode!
  private var cameraNode: SCNNode!
  private var keyLightNode: SCNNode!
  private var ambientLightNode: SCNNode!

  // MARK: Tunables

  private let courtHalfLength: Float = 6.0
  private let courtWidth: Float = 4.0
  private let netHeight: Float = 0.95
  private let ballRadius: CGFloat = 0.10
  private let ballArcHeight: Float = 1.6
  private let ballPlayerEndZ: Float = 4.5
  private let ballOpponentEndZ: Float = -4.5
  private let arcDuration: TimeInterval = 1.0

  // MARK: Init

  init(game: TennisGame, theme: TennisSceneTheme) {
    self.scene = SCNScene()
    self.theme = theme
    self.game = game
    super.init()
    buildScene()
    applyTheme(theme)
    observeGame()
  }

  // MARK: Scene construction

  private func buildScene() {
    scene.background.contents = nil
    let root = scene.rootNode

    // Court — flat plane laid down on the ground.
    let courtGeo = SCNPlane(
      width: CGFloat(courtWidth),
      height: CGFloat(courtHalfLength * 2)
    )
    let courtMat = SCNMaterial()
    courtMat.diffuse.contents = UIColor.systemGreen
    courtMat.roughness.contents = 0.7
    courtGeo.firstMaterial = courtMat
    courtNode = SCNNode(geometry: courtGeo)
    courtNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
    courtNode.position = SCNVector3(0, 0, 0)
    root.addChildNode(courtNode)

    // Court lines — three thin painted strips: centre service line +
    // service lines near each baseline.
    centerLineNode = makeCourtLine(width: 0.05, length: courtHalfLength * 2 * 0.55)
    centerLineNode.position = SCNVector3(0, 0.005, 0)
    root.addChildNode(centerLineNode)

    serviceLineFarNode = makeCourtLine(width: courtWidth * 0.85, length: 0.05)
    serviceLineFarNode.position = SCNVector3(0, 0.005, -courtHalfLength * 0.30)
    root.addChildNode(serviceLineFarNode)

    serviceLineNearNode = makeCourtLine(width: courtWidth * 0.85, length: 0.05)
    serviceLineNearNode.position = SCNVector3(0, 0.005, courtHalfLength * 0.30)
    root.addChildNode(serviceLineNearNode)

    // Net + posts.
    let netGeo = SCNBox(
      width: CGFloat(courtWidth + 0.30),
      height: CGFloat(netHeight),
      length: 0.04,
      chamferRadius: 0
    )
    let netMat = SCNMaterial()
    netMat.diffuse.contents = UIColor.lightGray
    netMat.transparency = 0.85
    netGeo.firstMaterial = netMat
    netNode = SCNNode(geometry: netGeo)
    netNode.position = SCNVector3(0, netHeight / 2, 0)
    root.addChildNode(netNode)

    netPostLeft = makeNetPost()
    netPostLeft.position = SCNVector3(-courtWidth / 2 - 0.15, netHeight / 2 + 0.1, 0)
    root.addChildNode(netPostLeft)
    netPostRight = makeNetPost()
    netPostRight.position = SCNVector3(courtWidth / 2 + 0.15, netHeight / 2 + 0.1, 0)
    root.addChildNode(netPostRight)

    // Ball.
    let ballGeo = SCNSphere(radius: ballRadius)
    let ballMat = SCNMaterial()
    ballMat.diffuse.contents = UIColor.yellow
    ballGeo.firstMaterial = ballMat
    ballNode = SCNNode(geometry: ballGeo)
    ballNode.position = SCNVector3(0, Float(ballRadius) + 0.02, ballPlayerEndZ)
    root.addChildNode(ballNode)

    // Opponent — simple humanoid: body capsule + head sphere at far baseline.
    opponentBody = makeOpponentBody()
    opponentBody.position = SCNVector3(0, 0.95, ballOpponentEndZ - 0.4)
    root.addChildNode(opponentBody)

    opponentHead = makeOpponentHead()
    opponentHead.position = SCNVector3(0, 1.85, ballOpponentEndZ - 0.4)
    root.addChildNode(opponentHead)

    // Camera — slightly above and behind the player baseline.
    let camera = SCNCamera()
    camera.fieldOfView = 60
    camera.zNear = 0.05
    camera.zFar = 80
    cameraNode = SCNNode()
    cameraNode.camera = camera
    cameraNode.position = SCNVector3(0, 1.6, ballPlayerEndZ + 1.5)
    cameraNode.eulerAngles = SCNVector3(-0.30, 0, 0)
    root.addChildNode(cameraNode)

    // Lights.
    let key = SCNLight()
    key.type = .directional
    key.intensity = 1000
    key.castsShadow = true
    key.shadowMode = .deferred
    keyLightNode = SCNNode()
    keyLightNode.light = key
    keyLightNode.eulerAngles = SCNVector3(-0.95, 0.3, 0)
    keyLightNode.position = SCNVector3(2, 6, 3)
    root.addChildNode(keyLightNode)

    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.intensity = 500
    ambientLightNode = SCNNode()
    ambientLightNode.light = ambient
    root.addChildNode(ambientLightNode)
  }

  private func makeCourtLine(width: Float, length: Float) -> SCNNode {
    let geo = SCNPlane(width: CGFloat(width), height: CGFloat(length))
    let mat = SCNMaterial()
    mat.diffuse.contents = UIColor.white
    geo.firstMaterial = mat
    let node = SCNNode(geometry: geo)
    node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
    return node
  }

  private func makeNetPost() -> SCNNode {
    let geo = SCNCylinder(radius: 0.05, height: CGFloat(netHeight) + 0.20)
    let mat = SCNMaterial()
    mat.diffuse.contents = UIColor.darkGray
    geo.firstMaterial = mat
    return SCNNode(geometry: geo)
  }

  private func makeOpponentBody() -> SCNNode {
    let geo = SCNCapsule(capRadius: 0.30, height: 1.20)
    let mat = SCNMaterial()
    mat.diffuse.contents = UIColor.systemBlue
    geo.firstMaterial = mat
    return SCNNode(geometry: geo)
  }

  private func makeOpponentHead() -> SCNNode {
    let geo = SCNSphere(radius: 0.20)
    let mat = SCNMaterial()
    mat.diffuse.contents = UIColor(red: 0.78, green: 0.55, blue: 0.40, alpha: 1)
    geo.firstMaterial = mat
    return SCNNode(geometry: geo)
  }

  // MARK: Theme

  func update(theme: TennisSceneTheme) {
    self.theme = theme
    applyTheme(theme)
  }

  private func applyTheme(_ theme: TennisSceneTheme) {
    courtNode.geometry?.firstMaterial?.diffuse.contents = theme.courtColor
    centerLineNode.geometry?.firstMaterial?.diffuse.contents = theme.courtLineColor
    serviceLineFarNode.geometry?.firstMaterial?.diffuse.contents = theme.courtLineColor
    serviceLineNearNode.geometry?.firstMaterial?.diffuse.contents = theme.courtLineColor
    netNode.geometry?.firstMaterial?.diffuse.contents = theme.netColor
    ballNode.geometry?.firstMaterial?.diffuse.contents = theme.ballColor
    opponentBody.geometry?.firstMaterial?.diffuse.contents = theme.opponentColor
    keyLightNode.light?.color = theme.keyLightColor
    ambientLightNode.light?.color = theme.ambientColor
    scene.fogColor = theme.fogColor
    scene.fogStartDistance = theme.fogStartDistance
    scene.fogEndDistance = theme.fogEndDistance
  }

  // MARK: Game observation

  private func observeGame() {
    guard let game else { return }
    shotSub = game.$shotEventID.receive(on: RunLoop.main).sink { [weak self] _ in
      self?.handleShot()
    }
  }

  private func handleShot() {
    guard let game else { return }
    switch game.lastShotKind {
    case .serve: animateServe()
    case .playerReturn: animatePlayerReturn()
    case .pointWon: animatePointWon()
    case .pointLost: animatePointLost()
    }
  }

  // MARK: Shot animations

  private func animateServe() {
    // Player tosses + serves: ball arcs from player baseline to
    // opponent's service box (mid-far court), then opponent returns
    // it back to the player.
    let outbound = arcAction(
      from: SCNVector3(0, Float(ballRadius) + 0.02, ballPlayerEndZ),
      to: SCNVector3(0, 0.5, ballOpponentEndZ * 0.6),
      duration: arcDuration
    )
    let opponentSwing = SCNAction.run { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.swingOpponent()
      }
    }
    let inbound = arcAction(
      from: SCNVector3(0, 0.5, ballOpponentEndZ * 0.6),
      to: SCNVector3(0, Float(ballRadius) + 0.02, ballPlayerEndZ * 0.5),
      duration: arcDuration
    )
    ballNode.removeAllActions()
    ballNode.runAction(.sequence([outbound, opponentSwing, inbound]))
  }

  private func animatePlayerReturn() {
    let outbound = arcAction(
      from: ballNode.presentation.position,
      to: SCNVector3(0, 0.5, ballOpponentEndZ * 0.65),
      duration: arcDuration
    )
    let opponentSwing = SCNAction.run { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.swingOpponent()
      }
    }
    let inbound = arcAction(
      from: SCNVector3(0, 0.5, ballOpponentEndZ * 0.65),
      to: SCNVector3(0, Float(ballRadius) + 0.02, ballPlayerEndZ * 0.5),
      duration: arcDuration
    )
    ballNode.removeAllActions()
    ballNode.runAction(.sequence([outbound, opponentSwing, inbound]))
  }

  private func animatePointWon() {
    // Ball goes deep past the opponent's baseline.
    let target = SCNVector3(0, 0.4, ballOpponentEndZ - 1.2)
    let pass = arcAction(
      from: ballNode.presentation.position, to: target, duration: 0.7)
    ballNode.removeAllActions()
    ballNode.runAction(pass)
    burstParticles(at: target, color: UIColor(red: 0.95, green: 1.0, blue: 0.30, alpha: 1))
  }

  private func animatePointLost() {
    // Ball flies past the player's camera.
    let target = SCNVector3(0, 0.3, ballPlayerEndZ + 2.5)
    let pass = SCNAction.move(to: target, duration: 0.55)
    pass.timingMode = .easeOut
    ballNode.removeAllActions()
    ballNode.runAction(pass)
  }

  // MARK: Helpers

  /// Quick visible swing on the opponent — a brief torso lean as if
  /// they're returning a shot.
  private func swingOpponent() {
    let lean = SCNAction.rotateBy(x: 0, y: 0, z: 0.30, duration: 0.10)
    lean.timingMode = .easeOut
    let unlean = SCNAction.rotateBy(x: 0, y: 0, z: -0.30, duration: 0.20)
    unlean.timingMode = .easeIn
    opponentBody.removeAction(forKey: "swing")
    opponentBody.runAction(.sequence([lean, unlean]), forKey: "swing")
  }

  private func burstParticles(at position: SCNVector3, color: UIColor) {
    let p = SCNParticleSystem()
    p.particleColor = color
    p.particleSize = 0.06
    p.birthRate = 700
    p.particleLifeSpan = 0.7
    p.particleVelocity = 5
    p.particleVelocityVariation = 3
    p.spreadingAngle = 180
    p.acceleration = SCNVector3(0, -2, 0)
    p.emissionDuration = 0.2
    p.loops = false
    p.blendMode = .additive

    let host = SCNNode()
    host.position = position
    host.addParticleSystem(p)
    scene.rootNode.addChildNode(host)

    Task { @MainActor [weak host] in
      try? await Task.sleep(nanoseconds: 1_300_000_000)
      host?.removeFromParentNode()
    }
  }

  /// Same parabola helper used by the ping-pong scene — interpolate
  /// X+Z linearly, Y as a 4·t·(1-t) arc peaking at ballArcHeight above
  /// the segment's max Y.
  private func arcAction(
    from start: SCNVector3, to end: SCNVector3, duration: TimeInterval
  ) -> SCNAction {
    let peakY = max(start.y, end.y) + ballArcHeight
    return SCNAction.customAction(duration: duration) { node, elapsed in
      let t = Float(elapsed / duration)
      let invT = 1 - t
      let x = start.x * invT + end.x * t
      let z = start.z * invT + end.z * t
      let y = start.y * invT + end.y * t + 4.0 * peakY * t * invT - 4.0 * end.y * t * invT
      node.position = SCNVector3(x, y, z)
    }
  }
}
