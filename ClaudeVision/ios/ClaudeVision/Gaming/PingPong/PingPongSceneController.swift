import Combine
import Foundation
import SceneKit
import UIKit

/// Owns the SceneKit scene graph for ping-pong: a 3D table extending
/// away from the camera, a paddle at each end, a ball that ping-pongs
/// across the net in response to game shot events.
///
/// Contract with `PingPongGame`:
/// - On `.serve` event: animate ball from CPU paddle → player end.
/// - On `.playerReturn` event: swing player paddle, then animate ball
///   player → CPU → player (full round trip taking ~returnWindow s).
/// - On `.miss` event: animate ball flying past the player camera,
///   then re-serve.
/// - On `.point` event: brief celebration burst above the table.
@MainActor
final class PingPongSceneController: NSObject {

  // MARK: Public surface

  let scene: SCNScene
  private(set) var theme: PingPongSceneTheme

  // MARK: Game wiring

  private weak var game: PingPongGame?
  private var shotSub: AnyCancellable?

  // MARK: Scene graph

  private var tableNode: SCNNode!
  private var centerLineNode: SCNNode!
  private var netNode: SCNNode!
  private var ballNode: SCNNode!
  private var playerPaddleNode: SCNNode!
  private var cpuPaddleNode: SCNNode!
  private var cameraNode: SCNNode!
  private var keyLightNode: SCNNode!
  private var ambientLightNode: SCNNode!

  // MARK: Tunables

  /// Half the table's length — i.e. distance from net to either end.
  private let tableHalfLength: Float = 1.6
  private let tableWidth: Float = 1.5
  private let tableThickness: Float = 0.06
  private let tableTopY: Float = 0.0
  private let netHeight: Float = 0.18
  private let ballRadius: CGFloat = 0.06
  private let ballArcHeight: Float = 0.45
  private let paddleZPlayer: Float = 1.6
  private let paddleZCPU: Float = -1.6

  // MARK: Init

  init(game: PingPongGame, theme: PingPongSceneTheme) {
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

    // Table top.
    let tableGeo = SCNBox(
      width: CGFloat(tableWidth),
      height: CGFloat(tableThickness),
      length: CGFloat(tableHalfLength * 2),
      chamferRadius: 0.02
    )
    let tableMat = SCNMaterial()
    tableMat.diffuse.contents = UIColor.systemBlue
    tableMat.roughness.contents = 0.4
    tableGeo.firstMaterial = tableMat
    tableNode = SCNNode(geometry: tableGeo)
    tableNode.position = SCNVector3(0, tableTopY - tableThickness / 2, 0)
    root.addChildNode(tableNode)

    // Centre line painted on top.
    let lineGeo = SCNPlane(
      width: CGFloat(tableWidth) * 0.95,
      height: 0.014
    )
    let lineMat = SCNMaterial()
    lineMat.diffuse.contents = UIColor.white
    lineGeo.firstMaterial = lineMat
    centerLineNode = SCNNode(geometry: lineGeo)
    centerLineNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
    centerLineNode.position = SCNVector3(0, tableTopY + 0.001, 0)
    root.addChildNode(centerLineNode)

    // Net at the table midpoint.
    let netGeo = SCNBox(
      width: CGFloat(tableWidth + 0.10),
      height: CGFloat(netHeight),
      length: 0.02,
      chamferRadius: 0
    )
    let netMat = SCNMaterial()
    netMat.diffuse.contents = UIColor.lightGray
    netMat.transparency = 0.85
    netGeo.firstMaterial = netMat
    netNode = SCNNode(geometry: netGeo)
    netNode.position = SCNVector3(0, tableTopY + netHeight / 2, 0)
    root.addChildNode(netNode)

    // Ball.
    let ballGeo = SCNSphere(radius: ballRadius)
    let ballMat = SCNMaterial()
    ballMat.diffuse.contents = UIColor.white
    ballGeo.firstMaterial = ballMat
    ballNode = SCNNode(geometry: ballGeo)
    ballNode.position = ballRestPosition()
    root.addChildNode(ballNode)

    // Paddles. Modeled as flat-ish boxes at each end of the table.
    playerPaddleNode = makePaddleNode()
    playerPaddleNode.position = SCNVector3(0, tableTopY + 0.15, paddleZPlayer)
    root.addChildNode(playerPaddleNode)

    cpuPaddleNode = makePaddleNode()
    cpuPaddleNode.position = SCNVector3(0, tableTopY + 0.15, paddleZCPU)
    cpuPaddleNode.eulerAngles = SCNVector3(0, Float.pi, 0)
    root.addChildNode(cpuPaddleNode)

    // Camera — slightly above the player end looking down the table.
    let camera = SCNCamera()
    camera.fieldOfView = 55
    camera.zNear = 0.05
    camera.zFar = 60
    cameraNode = SCNNode()
    cameraNode.camera = camera
    cameraNode.position = SCNVector3(0, 0.85, paddleZPlayer + 1.4)
    cameraNode.eulerAngles = SCNVector3(-0.35, 0, 0)
    root.addChildNode(cameraNode)

    // Lights.
    let key = SCNLight()
    key.type = .directional
    key.intensity = 950
    key.castsShadow = true
    key.shadowMode = .deferred
    keyLightNode = SCNNode()
    keyLightNode.light = key
    keyLightNode.eulerAngles = SCNVector3(-0.85, 0.35, 0)
    keyLightNode.position = SCNVector3(2, 5, 3)
    root.addChildNode(keyLightNode)

    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.intensity = 480
    ambientLightNode = SCNNode()
    ambientLightNode.light = ambient
    root.addChildNode(ambientLightNode)
  }

  private func makePaddleNode() -> SCNNode {
    let geo = SCNBox(width: 0.32, height: 0.36, length: 0.04, chamferRadius: 0.04)
    let mat = SCNMaterial()
    mat.diffuse.contents = UIColor.red
    mat.roughness.contents = 0.6
    geo.firstMaterial = mat
    return SCNNode(geometry: geo)
  }

  private func ballRestPosition() -> SCNVector3 {
    SCNVector3(0, tableTopY + Float(ballRadius) + 0.01, paddleZCPU + 0.25)
  }

  // MARK: Theme

  func update(theme: PingPongSceneTheme) {
    self.theme = theme
    applyTheme(theme)
  }

  private func applyTheme(_ theme: PingPongSceneTheme) {
    tableNode.geometry?.firstMaterial?.diffuse.contents = theme.tableColor
    centerLineNode.geometry?.firstMaterial?.diffuse.contents = theme.tableLineColor
    netNode.geometry?.firstMaterial?.diffuse.contents = theme.netColor
    ballNode.geometry?.firstMaterial?.diffuse.contents = theme.ballColor
    playerPaddleNode.geometry?.firstMaterial?.diffuse.contents = theme.playerPaddleColor
    cpuPaddleNode.geometry?.firstMaterial?.diffuse.contents = theme.cpuPaddleColor
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
    case .miss: animateMiss()
    case .point: animatePoint()
    }
  }

  // MARK: Shot animations

  private func animateServe() {
    let window = Float(game?.sceneReturnWindow ?? 1.5)
    swingPaddle(cpuPaddleNode)
    let path = arcAction(
      from: cpuStartPosition(), to: playerEndPosition(), duration: TimeInterval(window))
    ballNode.removeAllActions()
    ballNode.position = cpuStartPosition()
    ballNode.runAction(path)
  }

  private func animatePlayerReturn() {
    let window = Float(game?.sceneReturnWindow ?? 1.5)
    let halfWindow = TimeInterval(window) / 2
    swingPaddle(playerPaddleNode)
    // Round trip: ball goes player → CPU (with a CPU paddle swing on
    // arrival) → back to player.
    let outbound = arcAction(
      from: playerEndPosition(), to: cpuEndPosition(), duration: halfWindow)
    let cpuSwing = SCNAction.run { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.swingPaddle(self?.cpuPaddleNode)
      }
    }
    let inbound = arcAction(
      from: cpuEndPosition(), to: playerEndPosition(), duration: halfWindow)
    ballNode.removeAllActions()
    ballNode.position = playerEndPosition()
    ballNode.runAction(.sequence([outbound, cpuSwing, inbound]))
  }

  private func animateMiss() {
    // Ball flies past the player camera.
    let target = SCNVector3(0, tableTopY + 0.1, paddleZPlayer + 2.5)
    let pass = SCNAction.move(to: target, duration: 0.45)
    pass.timingMode = .easeOut
    ballNode.removeAllActions()
    ballNode.runAction(.sequence([pass, .wait(duration: 0.2)])) {
      Task { @MainActor [weak self] in
        // Re-serve after the miss.
        self?.animateServe()
      }
    }
  }

  private func animatePoint() {
    // Quick fireworks above the net.
    let burst = SCNParticleSystem()
    burst.particleColor = UIColor(red: 1.0, green: 0.85, blue: 0.30, alpha: 1)
    burst.particleSize = 0.05
    burst.birthRate = 800
    burst.particleLifeSpan = 0.7
    burst.particleVelocity = 5
    burst.particleVelocityVariation = 3
    burst.spreadingAngle = 180
    burst.acceleration = SCNVector3(0, -2, 0)
    burst.emissionDuration = 0.25
    burst.loops = false
    burst.blendMode = .additive

    let host = SCNNode()
    host.position = SCNVector3(0, tableTopY + 0.7, 0)
    host.addParticleSystem(burst)
    scene.rootNode.addChildNode(host)

    Task { @MainActor [weak host] in
      try? await Task.sleep(nanoseconds: 1_300_000_000)
      host?.removeFromParentNode()
    }
  }

  // MARK: Helpers

  private func cpuStartPosition() -> SCNVector3 {
    SCNVector3(0, tableTopY + Float(ballRadius) + 0.05, paddleZCPU)
  }

  private func cpuEndPosition() -> SCNVector3 {
    SCNVector3(0, tableTopY + Float(ballRadius) + 0.05, paddleZCPU + 0.10)
  }

  private func playerEndPosition() -> SCNVector3 {
    SCNVector3(0, tableTopY + Float(ballRadius) + 0.05, paddleZPlayer - 0.10)
  }

  /// SCNAction that moves the ball from `start` to `end` along a
  /// shallow arc that peaks at ballArcHeight above the table midpoint.
  /// Approximated as a 3-step keyframe via group + custom action.
  private func arcAction(
    from start: SCNVector3, to end: SCNVector3, duration: TimeInterval
  ) -> SCNAction {
    let peakY = max(start.y, end.y) + ballArcHeight
    return SCNAction.customAction(duration: duration) { node, elapsed in
      let t = Float(elapsed / duration)
      let invT = 1 - t
      let x = start.x * invT + end.x * t
      let z = start.z * invT + end.z * t
      // Parabola: peaks at t=0.5.
      let y = start.y * invT + end.y * t + 4.0 * peakY * t * invT - 4.0 * end.y * t * invT
      node.position = SCNVector3(x, y, z)
    }
  }

  /// Brief paddle swing — a quick rotation around X, then back.
  private func swingPaddle(_ paddle: SCNNode?) {
    guard let paddle else { return }
    let swing = SCNAction.rotateBy(x: -0.7, y: 0, z: 0, duration: 0.08)
    swing.timingMode = .easeOut
    let unswing = SCNAction.rotateBy(x: 0.7, y: 0, z: 0, duration: 0.18)
    unswing.timingMode = .easeIn
    paddle.removeAction(forKey: "swing")
    paddle.runAction(.sequence([swing, unswing]), forKey: "swing")
  }
}
