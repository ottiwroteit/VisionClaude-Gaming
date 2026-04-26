import Combine
import Foundation
import SceneKit
import UIKit

/// Owns the SceneKit scene graph for archery: a target with concentric
/// scoring rings at the back of the scene, a single arrow that animates
/// nocking back as the player draws, and per-arrow flight + stick
/// animation when the player fires.
///
/// The contract with `ArcheryGame` is intentionally narrow:
/// - Watch `drawStrength` to translate the arrow back along its rest
///   axis as the draw builds (visible "pulling the string" effect).
/// - Watch `arrowEventID` for fire events; on each new ID, read
///   `lastArrowScore` to pick the landing ring and animate the arrow
///   from rest to that ring on the target plane.
/// - Watch `isFinished` to reset the visual stack when a new round
///   begins (the game itself owns reset; we just sync visuals).
@MainActor
final class ArcherySceneController: NSObject {

  // MARK: Public surface

  let scene: SCNScene
  private(set) var theme: ArcherySceneTheme

  // MARK: Game wiring

  private weak var game: ArcheryGame?
  private var drawSub: AnyCancellable?
  private var fireSub: AnyCancellable?
  private var resetSub: AnyCancellable?

  // MARK: Scene graph

  private var arrowNode: SCNNode!
  private var targetNode: SCNNode!
  private var bullseyeNode: SCNNode!
  private var innerRingNode: SCNNode!
  private var midRingNode: SCNNode!
  private var outerRingNode: SCNNode!
  private var cameraNode: SCNNode!
  private var keyLightNode: SCNNode!
  private var ambientLightNode: SCNNode!
  /// Nodes representing arrows already stuck in the target. Cleared on
  /// game reset; one new node added per fire().
  private var stuckArrowNodes: [SCNNode] = []
  /// Render-thread camera follow. Owned by the controller, installed
  /// as the SCNView's delegate by the SwiftUI wrapper. Built once the
  /// camera node exists at the end of `buildScene`.
  private(set) var cameraTracker: ArcheryCameraTracker!
  /// Background task that clears the camera's follow target after the
  /// arrow has flown + dwelled. Cancelled if a new arrow fires before
  /// the previous one's dwell completes.
  private var cameraReleaseTask: Task<Void, Never>?

  // MARK: Tunables

  /// Distance from camera to the target plane along -Z.
  private let targetZ: Float = -8.0
  /// Resting (un-drawn) Z position of the active arrow.
  private let arrowRestZ: Float = 4.5
  /// How far back the arrow pulls at full draw strength.
  private let arrowMaxDrawback: Float = 0.7
  /// Arrow Y position (eye-level so it reads in front of the camera).
  private let arrowY: Float = 0.0
  /// Y position of the target centre.
  private let targetY: Float = 0.0
  /// Target ring radii in scene units. Bullseye is ringRadii[0] (centre
  /// of the disc, no inner radius); subsequent values are the OUTER
  /// radius of each successive band.
  private let ringRadii: [CGFloat] = [0.18, 0.40, 0.65, 0.95]
  /// Visual length of an arrow shaft.
  private let arrowLength: CGFloat = 1.0
  private let arrowShaftRadius: CGFloat = 0.018

  // MARK: Init

  init(game: ArcheryGame, theme: ArcherySceneTheme) {
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

    // Target — a thin cylinder disc with concentric ring discs stacked
    // slightly forward so each ring is visible without z-fighting.
    let backPlate = SCNCylinder(radius: ringRadii[3], height: 0.03)
    let backMat = SCNMaterial()
    backMat.diffuse.contents = UIColor(white: 0.92, alpha: 1)
    backPlate.firstMaterial = backMat
    targetNode = SCNNode(geometry: backPlate)
    targetNode.position = SCNVector3(0, targetY, targetZ)
    // Lay the cylinder flat so its face points at the camera (+Z).
    targetNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
    root.addChildNode(targetNode)

    outerRingNode = makeRingDisc(radius: ringRadii[3], yOffset: 0.001)
    targetNode.addChildNode(outerRingNode)
    midRingNode = makeRingDisc(radius: ringRadii[2], yOffset: 0.002)
    targetNode.addChildNode(midRingNode)
    innerRingNode = makeRingDisc(radius: ringRadii[1], yOffset: 0.003)
    targetNode.addChildNode(innerRingNode)
    bullseyeNode = makeRingDisc(radius: ringRadii[0], yOffset: 0.004)
    targetNode.addChildNode(bullseyeNode)

    // Active arrow — visible nocked in front of the camera, pulls back
    // as drawStrength grows, flies forward on fire().
    arrowNode = makeArrowNode()
    arrowNode.position = SCNVector3(0, arrowY, arrowRestZ)
    root.addChildNode(arrowNode)

    // Camera — looks straight down -Z at the target.
    let camera = SCNCamera()
    camera.fieldOfView = 50
    camera.zNear = 0.05
    camera.zFar = 80
    cameraNode = SCNNode()
    cameraNode.camera = camera
    cameraNode.position = SCNVector3(0, 0, 6)
    root.addChildNode(cameraNode)

    // Lights.
    let key = SCNLight()
    key.type = .directional
    key.intensity = 900
    key.castsShadow = false
    keyLightNode = SCNNode()
    keyLightNode.light = key
    keyLightNode.eulerAngles = SCNVector3(-0.6, 0.4, 0)
    keyLightNode.position = SCNVector3(2, 4, 2)
    root.addChildNode(keyLightNode)

    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.intensity = 480
    ambientLightNode = SCNNode()
    ambientLightNode.light = ambient
    root.addChildNode(ambientLightNode)

    // Render-thread camera tracker — built last so it captures the
    // final camera home position from the just-positioned cameraNode.
    cameraTracker = ArcheryCameraTracker(cameraNode: cameraNode)
  }

  /// Builds a flat disc node at the given radius. Stacking these on
  /// top of the back plate (with tiny y-offsets) gives the visual of
  /// concentric rings without complex torus geometry.
  private func makeRingDisc(radius: CGFloat, yOffset: Float) -> SCNNode {
    let geo = SCNCylinder(radius: radius, height: 0.005)
    let mat = SCNMaterial()
    mat.diffuse.contents = UIColor.white
    geo.firstMaterial = mat
    let node = SCNNode(geometry: geo)
    node.position = SCNVector3(0, yOffset, 0)
    return node
  }

  /// A simple two-piece arrow: thin cylindrical shaft + a small cone
  /// tip pointing in -Z. Aligned along the Z axis so translating Z
  /// reads as "into the scene" or "back toward the bowman".
  private func makeArrowNode() -> SCNNode {
    let parent = SCNNode()

    let shaft = SCNCylinder(radius: arrowShaftRadius, height: arrowLength)
    let shaftMat = SCNMaterial()
    shaftMat.diffuse.contents = UIColor.brown
    shaft.firstMaterial = shaftMat
    let shaftNode = SCNNode(geometry: shaft)
    // SCNCylinder's axis is Y by default; rotate -90° around X to lay
    // it along Z so the arrow points down the -Z axis.
    shaftNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
    parent.addChildNode(shaftNode)

    let tip = SCNCone(topRadius: 0, bottomRadius: arrowShaftRadius * 2.2, height: 0.10)
    let tipMat = SCNMaterial()
    tipMat.diffuse.contents = UIColor.systemGray
    tip.firstMaterial = tipMat
    let tipNode = SCNNode(geometry: tip)
    tipNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
    tipNode.position = SCNVector3(0, 0, -Float(arrowLength) / 2 - 0.05)
    parent.addChildNode(tipNode)

    // Three small fletching capsules at the back, splayed at 120°.
    for i in 0..<3 {
      let fletching = SCNCone(topRadius: 0.005, bottomRadius: 0.045, height: 0.10)
      let fletchMat = SCNMaterial()
      fletchMat.diffuse.contents = UIColor.systemYellow
      fletching.firstMaterial = fletchMat
      let fletchNode = SCNNode(geometry: fletching)
      let angle = Float(i) * (.pi * 2.0 / 3.0)
      fletchNode.eulerAngles = SCNVector3(0, 0, angle)
      fletchNode.position = SCNVector3(
        cos(angle) * 0.035, sin(angle) * 0.035, Float(arrowLength) / 2 + 0.02)
      parent.addChildNode(fletchNode)
    }
    return parent
  }

  // MARK: Theme

  func update(theme: ArcherySceneTheme) {
    self.theme = theme
    applyTheme(theme)
  }

  private func applyTheme(_ theme: ArcherySceneTheme) {
    bullseyeNode.geometry?.firstMaterial?.diffuse.contents = theme.targetBullseyeColor
    innerRingNode.geometry?.firstMaterial?.diffuse.contents = theme.targetInnerColor
    midRingNode.geometry?.firstMaterial?.diffuse.contents = theme.targetMidColor
    outerRingNode.geometry?.firstMaterial?.diffuse.contents = theme.targetOuterColor
    keyLightNode.light?.color = theme.keyLightColor
    ambientLightNode.light?.color = theme.ambientColor
    scene.fogColor = theme.fogColor
    scene.fogStartDistance = theme.fogStartDistance
    scene.fogEndDistance = theme.fogEndDistance
    // Re-paint shaft + accents on the active arrow only — already-stuck
    // arrows keep their original tint (history reads better that way).
    if let shaftNode = arrowNode.childNodes.first {
      shaftNode.geometry?.firstMaterial?.diffuse.contents = theme.arrowShaftColor
    }
    for child in arrowNode.childNodes.dropFirst() {
      child.geometry?.firstMaterial?.diffuse.contents = theme.arrowAccentColor
    }
  }

  // MARK: Game observation

  private func observeGame() {
    guard let game else { return }
    drawSub = game.$drawStrength.receive(on: RunLoop.main).sink { [weak self] strength in
      self?.applyDraw(strength: strength)
    }
    fireSub = game.$arrowEventID.receive(on: RunLoop.main).sink { [weak self] _ in
      self?.fireArrow()
    }
    resetSub = game.$arrowsLeft.receive(on: RunLoop.main).sink { [weak self] count in
      // arrowsLeft snapping back to the round size means the round
      // restarted — clear the stuck-arrow visual stack and rest the
      // active arrow.
      guard let self else { return }
      if count == 5 {
        self.clearStuckArrows()
        self.applyDraw(strength: 0)
      }
    }
  }

  private func applyDraw(strength: Float) {
    let clamped = max(0, min(1, strength))
    let z = arrowRestZ + clamped * arrowMaxDrawback
    arrowNode.position = SCNVector3(0, arrowY, z)
  }

  private func fireArrow() {
    guard let game, let score = game.lastArrowScore else { return }
    // Pick a target landing position on the target plane based on the
    // scored ring. Add a small lateral randomization within the band
    // so the arrows don't pile up exactly on top of each other.
    let landing = landingPosition(forScore: score)

    // Snapshot the current arrow into a frozen "stuck" copy at its
    // resting position; we'll animate that copy to the landing point.
    let stuck = arrowNode.flattenedClone()
    stuck.position = arrowNode.position
    scene.rootNode.addChildNode(stuck)
    stuckArrowNodes.append(stuck)

    // Reset the active (next) arrow to its rest position.
    arrowNode.position = SCNVector3(0, arrowY, arrowRestZ)

    // Animate the stuck arrow forward to the landing point. Quick
    // linear flight (no gravity arc — keeps the read clean for a
    // gesture-driven shot).
    let flightDuration: TimeInterval = 0.4
    let flight = SCNAction.move(
      to: SCNVector3(landing.x, landing.y, targetZ + 0.05), duration: flightDuration)
    flight.timingMode = .easeOut
    stuck.runAction(flight)

    // Camera follow — same pattern as the bowling scene's ball
    // tracker. Tracker lerps the camera toward the in-flight arrow's
    // position; we clear the follow target after flight + a dwell so
    // the camera glides back to home.
    cameraReleaseTask?.cancel()
    cameraTracker.followNode = stuck
    cameraReleaseTask = Task { @MainActor [weak self] in
      // Flight + brief dwell on the impact point before pulling back.
      try? await Task.sleep(nanoseconds: UInt64((flightDuration + 0.45) * 1_000_000_000))
      guard !Task.isCancelled else { return }
      self?.cameraTracker.followNode = nil
    }
  }

  private func landingPosition(forScore score: Int) -> (x: Float, y: Float) {
    // Outer radius for each scoring band — picks where the arrow can
    // land within the ring.
    let outer: Float
    let inner: Float
    switch score {
    case 10:
      outer = Float(ringRadii[0])
      inner = 0
    case 7:
      outer = Float(ringRadii[1])
      inner = Float(ringRadii[0])
    case 4:
      outer = Float(ringRadii[2])
      inner = Float(ringRadii[1])
    default:
      outer = Float(ringRadii[3])
      inner = Float(ringRadii[2])
    }
    let r = Float.random(in: inner...outer)
    let angle = Float.random(in: 0..<(.pi * 2))
    return (cos(angle) * r, sin(angle) * r)
  }

  private func clearStuckArrows() {
    for node in stuckArrowNodes { node.removeFromParentNode() }
    stuckArrowNodes.removeAll()
  }
}
