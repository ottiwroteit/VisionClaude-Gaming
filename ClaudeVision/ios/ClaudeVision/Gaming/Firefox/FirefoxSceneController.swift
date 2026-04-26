import Combine
import Foundation
import SceneKit
import UIKit

/// Owns the SceneKit scene graph for Meta Firefox. First-person flight
/// combat: the camera is locked to a "cockpit rig" that tilts in
/// response to the player's bank/pitch commands; enemy fighters spawn
/// far ahead and approach over time; missiles fired by the player
/// travel away from the camera and detonate enemies they hit.
@MainActor
final class FirefoxSceneController: NSObject {

  // MARK: Public surface

  let scene: SCNScene
  private(set) var theme: FirefoxSceneTheme

  // MARK: Game wiring

  private weak var game: FirefoxGame?
  private var fireSub: AnyCancellable?

  // MARK: Scene graph

  /// Camera rig — tilted by bank/pitch every frame to convey banking.
  /// The actual camera node is its child so the rig orientation
  /// rotates the view.
  private var cameraRig: SCNNode!
  private var cameraNode: SCNNode!
  private var skyNode: SCNNode!
  private var groundNode: SCNNode!
  private var keyLightNode: SCNNode!
  private var ambientLightNode: SCNNode!
  private var cloudHostNode: SCNNode!

  /// Enemy fighters currently in the world, with the Z they spawned at
  /// (used to know how far they've flown toward the camera).
  private var enemies: [EnemyEntry] = []
  /// Currently-flying missiles fired by the player.
  private var missiles: [MissileEntry] = []

  // MARK: Tunables

  /// Camera FOV — wide-ish for cockpit feel.
  private let fov: CGFloat = 70
  /// Maximum bank angle in radians the rig leans to at full bank command.
  private let maxBank: Float = 0.5  // ~28°
  private let maxPitch: Float = 0.4  // ~23°
  /// Per-frame lerp toward the target rig orientation.
  private let rigLerp: Float = 0.18
  /// Z-distance at which enemies spawn ahead of the camera (cam looks -Z).
  private let enemySpawnZ: Float = -110
  /// Speed enemies fly toward the camera (positive Z, since they're at -Z).
  private let enemyApproachSpeed: Float = 18
  /// Z distance past which an enemy that wasn't shot becomes a player-hit.
  private let enemyContactZ: Float = -2
  /// Speed missiles travel away from the camera.
  private let missileSpeed: Float = 80
  /// How often a new enemy spawns when there's room.
  private let enemySpawnInterval: TimeInterval = 1.4

  private var lastEnemySpawn: TimeInterval = 0
  private var lastFrameTime: TimeInterval = 0

  // MARK: Init

  init(game: FirefoxGame, theme: FirefoxSceneTheme) {
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

    // Camera rig + camera.
    cameraRig = SCNNode()
    cameraRig.position = SCNVector3(0, 0, 0)
    root.addChildNode(cameraRig)
    let camera = SCNCamera()
    camera.fieldOfView = fov
    camera.zNear = 0.1
    camera.zFar = 200
    cameraNode = SCNNode()
    cameraNode.camera = camera
    cameraRig.addChildNode(cameraNode)

    // Sky — a HUGE sphere surrounding the camera, single-sided
    // inside-out via .doubleSided so the inside renders.
    let sky = SCNSphere(radius: 180)
    let skyMat = SCNMaterial()
    skyMat.diffuse.contents = UIColor.cyan
    skyMat.isDoubleSided = true
    skyMat.cullMode = .front  // render the inside surface
    sky.firstMaterial = skyMat
    skyNode = SCNNode(geometry: sky)
    root.addChildNode(skyNode)

    // Ground — a large plane far below for visual depth reference.
    let ground = SCNPlane(width: 400, height: 400)
    let groundMat = SCNMaterial()
    groundMat.diffuse.contents = UIColor.brown
    ground.firstMaterial = groundMat
    groundNode = SCNNode(geometry: ground)
    groundNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
    groundNode.position = SCNVector3(0, -25, -50)
    root.addChildNode(groundNode)

    // Cloud field — a few semi-transparent flat sphere clusters at
    // various Z so the sense of motion reads.
    cloudHostNode = SCNNode()
    root.addChildNode(cloudHostNode)
    for _ in 0..<14 {
      let cloud = makeCloud()
      cloud.position = SCNVector3(
        Float.random(in: -50...50),
        Float.random(in: -8...10),
        Float.random(in: -90...(-10)))
      cloudHostNode.addChildNode(cloud)
    }

    // Lights.
    let key = SCNLight()
    key.type = .directional
    key.intensity = 950
    keyLightNode = SCNNode()
    keyLightNode.light = key
    keyLightNode.eulerAngles = SCNVector3(-0.6, 0.4, 0)
    keyLightNode.position = SCNVector3(2, 6, 3)
    root.addChildNode(keyLightNode)

    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.intensity = 520
    ambientLightNode = SCNNode()
    ambientLightNode.light = ambient
    root.addChildNode(ambientLightNode)
  }

  private func makeCloud() -> SCNNode {
    let host = SCNNode()
    let count = Int.random(in: 3...5)
    for _ in 0..<count {
      let r = CGFloat.random(in: 1.5...3.5)
      let geo = SCNSphere(radius: r)
      let mat = SCNMaterial()
      mat.diffuse.contents = UIColor.white
      mat.transparency = 0.65
      geo.firstMaterial = mat
      let bump = SCNNode(geometry: geo)
      bump.position = SCNVector3(
        Float.random(in: -2...2),
        Float.random(in: -0.5...0.5),
        Float.random(in: -2...2))
      host.addChildNode(bump)
    }
    return host
  }

  /// A simple enemy fighter — narrow fuselage capsule + two flat wing
  /// boxes + a small tail box. Painted in the theme's enemy colour.
  private func makeEnemy() -> SCNNode {
    let host = SCNNode()

    let fuselage = SCNCapsule(capRadius: 0.35, height: 2.4)
    let mat = SCNMaterial()
    mat.diffuse.contents = theme.enemyColor
    fuselage.firstMaterial = mat
    let body = SCNNode(geometry: fuselage)
    body.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)  // lay flat along Z
    host.addChildNode(body)

    let wing = SCNBox(width: 3.0, height: 0.10, length: 0.7, chamferRadius: 0.05)
    let wingMat = SCNMaterial()
    wingMat.diffuse.contents = theme.enemyColor
    wing.firstMaterial = wingMat
    let wingNode = SCNNode(geometry: wing)
    wingNode.position = SCNVector3(0, 0, 0.1)
    host.addChildNode(wingNode)

    let tail = SCNBox(width: 0.8, height: 0.6, length: 0.10, chamferRadius: 0.05)
    let tailMat = SCNMaterial()
    tailMat.diffuse.contents = theme.enemyColor
    tail.firstMaterial = tailMat
    let tailNode = SCNNode(geometry: tail)
    tailNode.position = SCNVector3(0, 0.3, -1.0)
    host.addChildNode(tailNode)
    return host
  }

  /// Bright bullet/missile — small glowing sphere.
  private func makeMissile() -> SCNNode {
    let geo = SCNSphere(radius: 0.18)
    let mat = SCNMaterial()
    mat.diffuse.contents = theme.missileColor
    mat.emission.contents = theme.missileColor
    geo.firstMaterial = mat
    return SCNNode(geometry: geo)
  }

  // MARK: Theme

  func update(theme: FirefoxSceneTheme) {
    self.theme = theme
    applyTheme(theme)
  }

  private func applyTheme(_ theme: FirefoxSceneTheme) {
    skyNode.geometry?.firstMaterial?.diffuse.contents = theme.skyColor
    groundNode.geometry?.firstMaterial?.diffuse.contents = theme.groundColor
    keyLightNode.light?.color = theme.keyLightColor
    ambientLightNode.light?.color = theme.ambientColor
    scene.fogColor = theme.fogColor
    scene.fogStartDistance = theme.fogStartDistance
    scene.fogEndDistance = theme.fogEndDistance
    // Existing enemies keep their original colour; new spawns pick
    // up the new tint via theme.enemyColor at construction.
    for cloud in cloudHostNode.childNodes {
      for bump in cloud.childNodes {
        bump.geometry?.firstMaterial?.diffuse.contents = theme.cloudColor
      }
    }
  }

  // MARK: Game observation

  private func observeGame() {
    guard let game else { return }
    fireSub = game.$fireEventID.dropFirst().sink { [weak self] _ in
      self?.fireMissile()
    }
  }

  // MARK: Per-frame update — called from the SwiftUI wrapper

  func tick(time: TimeInterval) {
    guard let game, !game.isFinished else { return }
    let dt = lastFrameTime > 0 ? Float(time - lastFrameTime) : 1.0 / 60.0
    lastFrameTime = time

    // Apply bank/pitch to the rig with smoothing toward the target.
    let targetRoll = -game.bankCommand * maxBank  // negative so right-tilt = right roll
    let targetPitch = game.pitchCommand * maxPitch
    var currentEuler = cameraRig.eulerAngles
    currentEuler.z += (targetRoll - currentEuler.z) * rigLerp
    currentEuler.x += (targetPitch - currentEuler.x) * rigLerp
    cameraRig.eulerAngles = currentEuler

    // Spawn enemies on a cadence as long as we have room.
    if enemies.count < 3, time - lastEnemySpawn > enemySpawnInterval {
      lastEnemySpawn = time
      spawnEnemy()
    }

    // Move enemies toward the camera. If one passes the contact Z,
    // it counts as a hit on the player and is removed.
    var stillAlive: [EnemyEntry] = []
    for entry in enemies {
      let n = entry.node
      n.position.z += enemyApproachSpeed * dt
      if n.position.z >= enemyContactZ {
        n.removeFromParentNode()
        game.didTakeHit()
        if game.isFinished { return }
      } else {
        stillAlive.append(entry)
      }
    }
    enemies = stillAlive

    // Move missiles forward (away from camera = more negative Z).
    var liveMissiles: [MissileEntry] = []
    for entry in missiles {
      let m = entry.node
      m.position.z -= missileSpeed * dt
      var hit = false
      // Check against all enemies — if within radius, kill the enemy
      // and consume the missile.
      for (i, eEntry) in enemies.enumerated() {
        if simd_length(
          simd_float3(
            eEntry.node.position.x - m.position.x,
            eEntry.node.position.y - m.position.y,
            eEntry.node.position.z - m.position.z)) < 2.0
        {
          // Kill the enemy.
          burstAt(eEntry.node.position)
          eEntry.node.removeFromParentNode()
          enemies.remove(at: i)
          game.didDownEnemy()
          hit = true
          break
        }
      }
      if hit || m.position.z < -120 {
        m.removeFromParentNode()
      } else {
        liveMissiles.append(entry)
      }
    }
    missiles = liveMissiles
  }

  // MARK: Actions

  private func fireMissile() {
    let m = makeMissile()
    // Spawn just in front of the camera.
    m.position = SCNVector3(0, -0.4, -2)
    scene.rootNode.addChildNode(m)
    missiles.append(MissileEntry(node: m))
  }

  private func spawnEnemy() {
    let enemy = makeEnemy()
    enemy.position = SCNVector3(
      Float.random(in: -10...10),
      Float.random(in: -3...4),
      enemySpawnZ)
    // Face the camera (rotate 180° around Y so the nose points at us).
    enemy.eulerAngles = SCNVector3(0, Float.pi, 0)
    scene.rootNode.addChildNode(enemy)
    enemies.append(EnemyEntry(node: enemy))
  }

  private func burstAt(_ position: SCNVector3) {
    let p = SCNParticleSystem()
    p.particleColor = theme.missileColor
    p.particleSize = 0.15
    p.birthRate = 800
    p.particleLifeSpan = 0.5
    p.particleVelocity = 6
    p.particleVelocityVariation = 4
    p.spreadingAngle = 180
    p.acceleration = SCNVector3(0, 0, 0)
    p.emissionDuration = 0.15
    p.loops = false
    p.blendMode = .additive

    let host = SCNNode()
    host.position = position
    host.addParticleSystem(p)
    scene.rootNode.addChildNode(host)
    Task { @MainActor [weak host] in
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      host?.removeFromParentNode()
    }
  }

  // MARK: Bookkeeping

  private final class EnemyEntry {
    let node: SCNNode
    init(node: SCNNode) { self.node = node }
  }
  private final class MissileEntry {
    let node: SCNNode
    init(node: SCNNode) { self.node = node }
  }
}

// MARK: - Render-thread tick bridge

/// Thin SCNSceneRendererDelegate that dispatches the per-frame
/// callback to the (MainActor) controller's tick(time:) method.
/// Same pattern as the bowling/archery camera trackers — keeps the
/// controller @MainActor while still getting frame-synced updates.
final class FirefoxRenderTicker: NSObject, SCNSceneRendererDelegate {
  weak var controller: FirefoxSceneController?

  func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
    Task { @MainActor [weak self] in
      self?.controller?.tick(time: time)
    }
  }
}
