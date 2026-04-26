import Combine
import Foundation
import SceneKit
import UIKit

/// Owns the SceneKit scene graph for fruit slash. Each spawned fruit
/// (or bomb) becomes a 3D node that flies in from one of the four
/// edge positions toward a point near the camera; the player resolves
/// it via a chin-flick in the matching direction. Outcome is animated
/// when the game model publishes one (slice → split + particles,
/// miss → continue past camera, bomb-sliced → explosion, etc.).
@MainActor
final class FruitSlashSceneController: NSObject {

  // MARK: Public surface

  let scene: SCNScene
  private(set) var theme: FruitSlashSceneTheme

  // MARK: Game wiring

  private weak var game: FruitSlashGame?
  private var fruitSub: AnyCancellable?
  private var outcomeSub: AnyCancellable?

  // MARK: Scene graph

  private var cameraNode: SCNNode!
  private var keyLightNode: SCNNode!
  private var ambientLightNode: SCNNode!
  /// The currently-active fruit node, if any. Set when game.currentFruit
  /// transitions to non-nil; cleared when the outcome is resolved.
  private weak var activeFruitNode: SCNNode?
  /// Identifier of the active fruit so a stale outcome event for an
  /// already-cleaned-up fruit doesn't try to animate something that
  /// no longer exists.
  private var activeFruitID: UUID?

  // MARK: Tunables

  /// Seconds the fruit takes to traverse from spawn → near-camera.
  /// Matches the model's 1.4 s expiry so the visual reaches its
  /// closest pose right when the timer runs out.
  private let flightDuration: TimeInterval = 1.4
  /// Distance from camera centre to the spawn position along the
  /// horizontal axis (left/right) and vertical (up/down).
  private let spawnDistance: Float = 2.4
  /// Z position fruits spawn at (negative = into the scene).
  private let spawnZ: Float = -3.5
  /// Z position fruits arrive at (closer to camera).
  private let arriveZ: Float = -1.0

  // MARK: Init

  init(game: FruitSlashGame, theme: FruitSlashSceneTheme) {
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

    let camera = SCNCamera()
    camera.fieldOfView = 60
    camera.zNear = 0.05
    camera.zFar = 60
    cameraNode = SCNNode()
    cameraNode.camera = camera
    cameraNode.position = SCNVector3(0, 0, 0.5)
    root.addChildNode(cameraNode)

    let key = SCNLight()
    key.type = .directional
    key.intensity = 950
    keyLightNode = SCNNode()
    keyLightNode.light = key
    keyLightNode.eulerAngles = SCNVector3(-0.5, 0.4, 0)
    keyLightNode.position = SCNVector3(2, 4, 2)
    root.addChildNode(keyLightNode)

    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.intensity = 460
    ambientLightNode = SCNNode()
    ambientLightNode.light = ambient
    root.addChildNode(ambientLightNode)
  }

  // MARK: Theme

  func update(theme: FruitSlashSceneTheme) {
    self.theme = theme
    applyTheme(theme)
  }

  private func applyTheme(_ theme: FruitSlashSceneTheme) {
    keyLightNode.light?.color = theme.keyLightColor
    ambientLightNode.light?.color = theme.ambientColor
    scene.fogColor = theme.fogColor
    scene.fogStartDistance = theme.fogStartDistance
    scene.fogEndDistance = theme.fogEndDistance
  }

  // MARK: Game observation

  private func observeGame() {
    guard let game else { return }
    fruitSub = game.$currentFruit.receive(on: RunLoop.main).sink {
      [weak self] fruit in
      guard let self else { return }
      if let fruit {
        self.spawnFruit(fruit)
      }
    }
    outcomeSub = game.$outcomeEventID.receive(on: RunLoop.main).sink { [weak self] _ in
      self?.resolveActiveFruit()
    }
  }

  // MARK: Spawn

  private func spawnFruit(_ fruit: FruitSlashGame.Fruit) {
    // If a previous fruit is still on stage (somehow), nuke it now —
    // the new one is the source of truth.
    activeFruitNode?.removeFromParentNode()
    activeFruitNode = nil

    let node = fruit.isBomb ? makeBombNode() : makeFruitNode()
    node.position = spawnPosition(forDirection: fruit.direction)
    scene.rootNode.addChildNode(node)
    activeFruitNode = node
    activeFruitID = fruit.id

    // Fly toward the centre near the camera over the flight duration,
    // adding a gentle spin so it reads as moving (not just translating).
    let arrive = SCNAction.move(
      to: SCNVector3(0, 0, arriveZ), duration: flightDuration)
    arrive.timingMode = .easeIn
    let spin = SCNAction.repeatForever(
      .rotateBy(x: 1.4, y: 1.6, z: 0.7, duration: 1.0))
    node.runAction(arrive, forKey: "flight")
    node.runAction(spin, forKey: "spin")
  }

  private func spawnPosition(forDirection direction: GestureDirection) -> SCNVector3 {
    switch direction {
    case .up: return SCNVector3(0, spawnDistance, spawnZ)
    case .down: return SCNVector3(0, -spawnDistance, spawnZ)
    case .left: return SCNVector3(-spawnDistance, 0, spawnZ)
    case .right: return SCNVector3(spawnDistance, 0, spawnZ)
    default: return SCNVector3(0, 0, spawnZ)
    }
  }

  // MARK: Outcome

  private func resolveActiveFruit() {
    guard let game, let outcome = game.lastOutcome, let node = activeFruitNode else { return }
    activeFruitNode = nil
    activeFruitID = nil

    switch outcome.kind {
    case .sliced:
      animateSlice(node: node)
    case .bombSliced:
      animateExplosion(node: node)
    case .missed:
      animateFlyPast(node: node)
    case .bombDodged:
      animateFadeOut(node: node)
    case .expired:
      animateFlyPast(node: node)
    }
  }

  private func animateSlice(node: SCNNode) {
    // Quick scale-up + fade and a particle burst behind it.
    let burst = makeSliceParticles()
    let burstHost = SCNNode()
    burstHost.position = node.presentation.position
    burstHost.addParticleSystem(burst)
    scene.rootNode.addChildNode(burstHost)

    let scale = SCNAction.scale(to: 1.4, duration: 0.18)
    let fade = SCNAction.fadeOut(duration: 0.18)
    node.runAction(.sequence([.group([scale, fade]), .removeFromParentNode()]))

    Task { @MainActor [weak burstHost] in
      try? await Task.sleep(nanoseconds: 1_400_000_000)
      burstHost?.removeFromParentNode()
    }
  }

  private func animateExplosion(node: SCNNode) {
    // Bigger, redder burst. Same lifecycle.
    let boom = makeExplosionParticles()
    let host = SCNNode()
    host.position = node.presentation.position
    host.addParticleSystem(boom)
    scene.rootNode.addChildNode(host)

    let scale = SCNAction.scale(to: 1.8, duration: 0.20)
    let fade = SCNAction.fadeOut(duration: 0.20)
    node.runAction(.sequence([.group([scale, fade]), .removeFromParentNode()]))

    Task { @MainActor [weak host] in
      try? await Task.sleep(nanoseconds: 1_600_000_000)
      host?.removeFromParentNode()
    }
  }

  private func animateFlyPast(node: SCNNode) {
    // Continue translating past the camera + fade.
    let pass = SCNAction.move(by: SCNVector3(0, 0, 4), duration: 0.45)
    let fade = SCNAction.fadeOut(duration: 0.45)
    node.runAction(.sequence([.group([pass, fade]), .removeFromParentNode()]))
  }

  private func animateFadeOut(node: SCNNode) {
    let fade = SCNAction.fadeOut(duration: 0.4)
    node.runAction(.sequence([fade, .removeFromParentNode()]))
  }

  // MARK: Geometry factories

  private func makeFruitNode() -> SCNNode {
    let palette: [UIColor] = [
      UIColor(red: 0.92, green: 0.20, blue: 0.20, alpha: 1),  // apple
      UIColor(red: 1.00, green: 0.55, blue: 0.10, alpha: 1),  // orange
      UIColor(red: 0.95, green: 0.85, blue: 0.20, alpha: 1),  // lemon
      UIColor(red: 0.40, green: 0.78, blue: 0.30, alpha: 1),  // lime
      UIColor(red: 0.65, green: 0.20, blue: 0.78, alpha: 1),  // berry
    ]
    let base = palette.randomElement() ?? palette[0]
    let final = theme.fruitTint.map { tint(base, by: $0) } ?? base

    let geo = SCNSphere(radius: 0.32)
    let mat = SCNMaterial()
    mat.diffuse.contents = final
    mat.roughness.contents = 0.5
    geo.firstMaterial = mat
    return SCNNode(geometry: geo)
  }

  private func makeBombNode() -> SCNNode {
    let parent = SCNNode()
    let body = SCNSphere(radius: 0.34)
    let bodyMat = SCNMaterial()
    bodyMat.diffuse.contents = theme.bombColor
    bodyMat.roughness.contents = 0.4
    bodyMat.metalness.contents = 0.6
    body.firstMaterial = bodyMat
    parent.addChildNode(SCNNode(geometry: body))

    // Fuse: a thin cylinder on top.
    let fuse = SCNCylinder(radius: 0.025, height: 0.18)
    let fuseMat = SCNMaterial()
    fuseMat.diffuse.contents = UIColor.brown
    fuse.firstMaterial = fuseMat
    let fuseNode = SCNNode(geometry: fuse)
    fuseNode.position = SCNVector3(0, 0.42, 0)
    parent.addChildNode(fuseNode)

    // Spark on the fuse tip.
    let spark = SCNSphere(radius: 0.05)
    let sparkMat = SCNMaterial()
    sparkMat.diffuse.contents = UIColor.orange
    sparkMat.emission.contents = UIColor.yellow
    spark.firstMaterial = sparkMat
    let sparkNode = SCNNode(geometry: spark)
    sparkNode.position = SCNVector3(0, 0.55, 0)
    parent.addChildNode(sparkNode)
    return parent
  }

  private func makeSliceParticles() -> SCNParticleSystem {
    let p = SCNParticleSystem()
    p.particleColor = theme.slashAccentColor
    p.particleColorVariation = SCNVector4(0.05, 0.05, 0.05, 0)
    p.particleSize = 0.05
    p.particleSizeVariation = 0.03
    p.birthRate = 700
    p.particleLifeSpan = 0.6
    p.particleVelocity = 4
    p.particleVelocityVariation = 3
    p.spreadingAngle = 180
    p.acceleration = SCNVector3(0, -2, 0)
    p.emissionDuration = 0.18
    p.loops = false
    p.blendMode = .additive
    return p
  }

  private func makeExplosionParticles() -> SCNParticleSystem {
    let p = SCNParticleSystem()
    p.particleColor = UIColor(red: 1.0, green: 0.45, blue: 0.10, alpha: 1)
    p.particleColorVariation = SCNVector4(0.1, 0.1, 0.05, 0)
    p.particleSize = 0.08
    p.particleSizeVariation = 0.05
    p.birthRate = 1500
    p.particleLifeSpan = 0.9
    p.particleVelocity = 7
    p.particleVelocityVariation = 5
    p.spreadingAngle = 180
    p.acceleration = SCNVector3(0, -3, 0)
    p.emissionDuration = 0.30
    p.loops = false
    p.blendMode = .additive
    return p
  }

  /// Multiplies a base UIColor by a tint colour (each channel × the
  /// tint channel, capped at 1). Used to apply per-venue mood (the
  /// orchard tint warms fruits slightly; heaven cools them).
  private func tint(_ base: UIColor, by tint: UIColor) -> UIColor {
    var br: CGFloat = 0
    var bg: CGFloat = 0
    var bb: CGFloat = 0
    var ba: CGFloat = 0
    base.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
    var tr: CGFloat = 0
    var tg: CGFloat = 0
    var tb: CGFloat = 0
    var ta: CGFloat = 0
    tint.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
    return UIColor(
      red: min(1, br * tr),
      green: min(1, bg * tg),
      blue: min(1, bb * tb),
      alpha: ba)
  }
}
