import Combine
import Foundation
import SpriteKit
import UIKit

/// AI Slasher SpriteKit scene. AI/LLM company logos fall from the
/// top of the screen; the player wields a samurai sword whose tip
/// tracks their head movement (`game.swordCommand`). When the sword
/// tip passes through a logo, it's sliced — the logo splits into two
/// halves that fly apart, and the game model's score increments.
/// "Rogue AGI" bombs are mixed in; slicing one costs a life.
final class FruitSlashGameScene: SKScene {

  // MARK: External wiring

  weak var game: FruitSlashGame?

  // MARK: Tunables

  /// How many logo descriptors the spawner picks from. Each carries
  /// a brand colour + short label. Keep the list small enough that
  /// the user recognizes them at speed.
  private let logoCatalog: [LogoSpec] = [
    LogoSpec(label: "GPT", color: UIColor(red: 0.06, green: 0.64, blue: 0.50, alpha: 1)),
    LogoSpec(label: "Claude", color: UIColor(red: 0.91, green: 0.46, blue: 0.35, alpha: 1)),
    LogoSpec(label: "Gemini", color: UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1)),
    LogoSpec(label: "Llama", color: UIColor(red: 0.49, green: 0.23, blue: 0.93, alpha: 1)),
    LogoSpec(label: "Mistral", color: UIColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1)),
    LogoSpec(label: "Grok", color: UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)),
    LogoSpec(label: "Cohere", color: UIColor(red: 0.93, green: 0.28, blue: 0.60, alpha: 1)),
    LogoSpec(label: "Pi", color: UIColor(red: 0.13, green: 0.72, blue: 0.65, alpha: 1)),
    LogoSpec(label: "Copilot", color: UIColor(red: 0.43, green: 0.25, blue: 0.67, alpha: 1)),
    LogoSpec(label: "Perplexity", color: UIColor(red: 0.08, green: 0.50, blue: 0.55, alpha: 1)),
  ]
  private let bombSpec = LogoSpec(
    label: "AGI",
    color: UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1),
    isBomb: true)

  /// Probability a given spawn is a bomb instead of a normal logo.
  private let bombProbability: Double = 0.13
  /// Average seconds between spawns. Spawn rate ramps gently with
  /// score so later play is busier.
  private var spawnInterval: TimeInterval = 1.0
  /// Logo radius at spawn.
  private let logoRadius: CGFloat = 38
  /// Falling speed (points/sec).
  private let fallSpeed: CGFloat = 180
  /// Sword length from hilt to tip.
  private let swordLength: CGFloat = 220
  /// Sword movement smoothing (per-frame lerp toward head-target).
  private let swordLerp: CGFloat = 0.22

  // MARK: Internal state

  private var swordNode: SKNode!
  private var swordTipNode: SKNode!  // child node at the tip — used for hit detection
  private var lastSwordTipPos: CGPoint = .zero  // for swing direction
  private var spawnSub: AnyCancellable?
  private var nextSpawnTime: TimeInterval = 0
  /// Active falling logos.
  private var logos: [Logo] = []
  /// Per-logo cooldown to prevent the sword from re-slicing the same
  /// logo across multiple frames before it's removed.
  private var slicedIDs: Set<UUID> = []

  // MARK: Setup

  override func didMove(to view: SKView) {
    backgroundColor = UIColor(red: 0.06, green: 0.05, blue: 0.10, alpha: 1)
    scaleMode = .resizeFill
    physicsWorld.gravity = CGVector(dx: 0, dy: -3)  // gentle for slice halves

    buildBackground()
    buildSword()
  }

  private func buildBackground() {
    // Distant gradient rect (cheap two-stop "sunset" feel).
    let top = SKShapeNode(rectOf: CGSize(width: size.width * 4, height: size.height))
    top.fillColor = UIColor(red: 0.20, green: 0.05, blue: 0.30, alpha: 1)
    top.strokeColor = .clear
    top.position = CGPoint(x: size.width / 2, y: size.height * 0.75)
    top.zPosition = -100
    addChild(top)

    let bot = SKShapeNode(rectOf: CGSize(width: size.width * 4, height: size.height))
    bot.fillColor = UIColor(red: 0.06, green: 0.05, blue: 0.10, alpha: 1)
    bot.strokeColor = .clear
    bot.position = CGPoint(x: size.width / 2, y: size.height * 0.25)
    bot.zPosition = -100
    addChild(bot)
  }

  /// Builds the samurai sword: brown handle → gold guard → silver
  /// blade with a triangular tip. Pivots from its hilt at the
  /// bottom of the screen; the tip is the hit-detection point.
  private func buildSword() {
    let host = SKNode()
    host.zPosition = 50

    // Handle.
    let handle = SKShapeNode(
      rect: CGRect(x: -7, y: 0, width: 14, height: 38), cornerRadius: 3)
    handle.fillColor = UIColor(red: 0.30, green: 0.18, blue: 0.10, alpha: 1)
    handle.strokeColor = .black
    handle.lineWidth = 1
    host.addChild(handle)

    // Crossguard.
    let guardShape = SKShapeNode(
      rect: CGRect(x: -22, y: 38, width: 44, height: 8), cornerRadius: 2)
    guardShape.fillColor = UIColor(red: 0.85, green: 0.70, blue: 0.20, alpha: 1)
    guardShape.strokeColor = .black
    guardShape.lineWidth = 1
    host.addChild(guardShape)

    // Blade body.
    let blade = SKShapeNode(
      rect: CGRect(x: -5, y: 46, width: 10, height: swordLength - 60), cornerRadius: 2)
    blade.fillColor = UIColor(red: 0.92, green: 0.93, blue: 0.95, alpha: 1)
    blade.strokeColor = UIColor(white: 0.3, alpha: 1)
    blade.lineWidth = 1
    host.addChild(blade)

    // Tip — sharp triangle at the top of the blade.
    let tipPath = CGMutablePath()
    let tipBaseY = 46 + swordLength - 60
    tipPath.move(to: CGPoint(x: -5, y: tipBaseY))
    tipPath.addLine(to: CGPoint(x: 5, y: tipBaseY))
    tipPath.addLine(to: CGPoint(x: 0, y: tipBaseY + 24))
    tipPath.closeSubpath()
    let tipShape = SKShapeNode(path: tipPath)
    tipShape.fillColor = UIColor(red: 0.92, green: 0.93, blue: 0.95, alpha: 1)
    tipShape.strokeColor = UIColor(white: 0.3, alpha: 1)
    tipShape.lineWidth = 1
    host.addChild(tipShape)

    // Tip hit-detection node — invisible point at the very top of the
    // blade in sword-local coords. The sword's transform moves it.
    swordTipNode = SKNode()
    swordTipNode.position = CGPoint(x: 0, y: tipBaseY + 24)
    host.addChild(swordTipNode)

    swordNode = host
    swordNode.position = CGPoint(x: size.width / 2, y: size.height * 0.10)
    addChild(swordNode)
  }

  // MARK: Spawning

  private func spawnLogo() {
    let isBomb = Double.random(in: 0...1) < bombProbability
    let spec = isBomb ? bombSpec : (logoCatalog.randomElement() ?? logoCatalog[0])

    let visual = SKNode()
    let circle = SKShapeNode(circleOfRadius: logoRadius)
    circle.fillColor = spec.color
    circle.strokeColor = isBomb ? UIColor.red : UIColor.white.withAlphaComponent(0.7)
    circle.lineWidth = isBomb ? 3 : 1.5
    visual.addChild(circle)

    let label = SKLabelNode(text: spec.label.uppercased())
    label.fontName = "Avenir-Heavy"
    label.fontSize = spec.label.count > 5 ? 11 : 14
    label.fontColor = .white
    label.verticalAlignmentMode = .center
    label.horizontalAlignmentMode = .center
    visual.addChild(label)

    if isBomb {
      // Pulse warning ring around bomb so it's visually distinct.
      let warning = SKShapeNode(circleOfRadius: logoRadius + 6)
      warning.fillColor = .clear
      warning.strokeColor = .red
      warning.lineWidth = 2
      let pulse = SKAction.sequence([
        .fadeAlpha(to: 0.3, duration: 0.4),
        .fadeAlpha(to: 1.0, duration: 0.4),
      ])
      warning.run(.repeatForever(pulse))
      visual.addChild(warning)
    }

    visual.position = CGPoint(
      x: CGFloat.random(in: 80...(size.width - 80)),
      y: size.height + logoRadius + 20)
    visual.zPosition = 10
    addChild(visual)

    let logo = Logo(node: visual, spec: spec, radius: logoRadius)
    logos.append(logo)
  }

  // MARK: Update

  override func update(_ currentTime: TimeInterval) {
    guard let game else { return }
    if game.isFinished {
      // Halt sword + spawning when the game ends.
      logos.forEach { $0.node.removeAllActions() }
      return
    }

    // Spawn cadence.
    if currentTime >= nextSpawnTime {
      nextSpawnTime = currentTime + spawnInterval
      // Difficulty ramp: every 5 slices the interval shortens by 5%
      // (down to a 0.45s floor so the screen doesn't get unplayable).
      spawnInterval = max(0.45, 1.0 * pow(0.95, Double(game.slices) / 5.0))
      spawnLogo()
    }

    // Move sword toward the head-target. The game's swordCommand is
    // in [-1, +1] head-tilt space; map to screen-space with the
    // bottom-centre as the resting position.
    let cmd = game.swordCommand
    let restX = size.width / 2
    let restY = size.height * 0.20
    let targetX = restX + CGFloat(cmd.x) * (size.width * 0.45)
    let targetY = restY + CGFloat(cmd.y) * (size.height * 0.55)
    let cur = swordNode.position
    let newX = cur.x + (targetX - cur.x) * swordLerp
    let newY = cur.y + (targetY - cur.y) * swordLerp
    swordNode.position = CGPoint(x: newX, y: newY)

    // Rotate the sword slightly so it angles in the direction of motion.
    let dx = swordNode.position.x - lastSwordTipPos.x
    let dy = swordNode.position.y - lastSwordTipPos.y
    if abs(dx) + abs(dy) > 0.5 {
      let targetAngle = atan2(dx, dy) * -1  // sword points up by default
      // Lerp rotation too.
      let curRot = swordNode.zRotation
      let newRot = curRot + (targetAngle - curRot) * 0.15
      swordNode.zRotation = max(-0.7, min(0.7, newRot))
    }
    lastSwordTipPos = swordNode.position

    // Hit detection — convert the tip node's position into scene-space
    // and check against each falling logo.
    let tipScene = convert(swordTipNode.position, from: swordNode)

    // Update each logo's fall, check slice, check escape.
    var stillAlive: [Logo] = []
    for logo in logos {
      logo.node.position.y -= fallSpeed * (1.0 / 60.0)
      // Slice?
      if !slicedIDs.contains(logo.id) {
        let dx = tipScene.x - logo.node.position.x
        let dy = tipScene.y - logo.node.position.y
        if (dx * dx + dy * dy) <= (logo.radius + 6) * (logo.radius + 6) {
          slicedIDs.insert(logo.id)
          performSlice(on: logo)
          if logo.spec.isBomb {
            game.didSliceBomb()
          } else {
            game.didSliceLogo()
          }
          continue
        }
      }
      // Escaped?
      if logo.node.position.y < -logo.radius {
        logo.node.removeFromParent()
        if !logo.spec.isBomb {
          game.didMissLogo()
        }
        continue
      }
      stillAlive.append(logo)
    }
    logos = stillAlive
  }

  // MARK: Slice

  /// Real slice-in-half. Replaces the original logo node with two
  /// half-disc shape nodes (left + right of a vertical cut line),
  /// gives them opposite horizontal velocities + a small upward kick,
  /// fades them out, removes them. Reads as a katana cut.
  private func performSlice(on logo: Logo) {
    let pos = logo.node.position
    logo.node.removeFromParent()

    // Pick a slice angle from the sword's current rotation. Mostly
    // horizontal — a katana cut bisects vertically through the body.
    let axisAngle = swordNode.zRotation + .pi / 2  // perpendicular to sword
    let cos = CGFloat(Foundation.cos(axisAngle))
    let sin = CGFloat(Foundation.sin(axisAngle))

    let leftHalf = makeHalf(of: logo.spec, side: .left, radius: logo.radius)
    let rightHalf = makeHalf(of: logo.spec, side: .right, radius: logo.radius)
    leftHalf.position = pos
    rightHalf.position = pos
    leftHalf.zRotation = axisAngle
    rightHalf.zRotation = axisAngle
    leftHalf.zPosition = 11
    rightHalf.zPosition = 11
    addChild(leftHalf)
    addChild(rightHalf)

    let kick: CGFloat = 140
    let leftVec = CGVector(dx: -cos * kick, dy: -sin * kick + 60)
    let rightVec = CGVector(dx: cos * kick, dy: sin * kick + 60)
    let leftBody = SKPhysicsBody(circleOfRadius: logo.radius * 0.6)
    leftBody.affectedByGravity = true
    leftBody.linearDamping = 1.0
    leftBody.collisionBitMask = 0
    leftBody.velocity = leftVec
    leftBody.angularVelocity = -2.5
    leftHalf.physicsBody = leftBody

    let rightBody = SKPhysicsBody(circleOfRadius: logo.radius * 0.6)
    rightBody.affectedByGravity = true
    rightBody.linearDamping = 1.0
    rightBody.collisionBitMask = 0
    rightBody.velocity = rightVec
    rightBody.angularVelocity = 2.5
    rightHalf.physicsBody = rightBody

    let fadeOut = SKAction.sequence([
      .wait(forDuration: 0.6),
      .fadeOut(withDuration: 0.5),
      .removeFromParent(),
    ])
    leftHalf.run(fadeOut)
    rightHalf.run(fadeOut)

    // Slash flash — a thin white line along the cut axis.
    let slash = SKShapeNode(rectOf: CGSize(width: logo.radius * 3, height: 2))
    slash.fillColor = .white
    slash.strokeColor = .clear
    slash.position = pos
    slash.zRotation = axisAngle
    slash.zPosition = 20
    slash.alpha = 0.85
    addChild(slash)
    slash.run(
      .sequence([.fadeOut(withDuration: 0.18), .removeFromParent()]))
  }

  /// Builds one half of a sliced logo — uses an SKCropNode to crop a
  /// full-circle visual of the logo to just the desired side.
  private enum HalfSide { case left, right }
  private func makeHalf(of spec: LogoSpec, side: HalfSide, radius: CGFloat) -> SKNode {
    let crop = SKCropNode()
    // Full visual of the logo (circle + label).
    let visual = SKNode()
    let circle = SKShapeNode(circleOfRadius: radius)
    circle.fillColor = spec.color
    circle.strokeColor = .clear
    visual.addChild(circle)
    let label = SKLabelNode(text: spec.label.uppercased())
    label.fontName = "Avenir-Heavy"
    label.fontSize = spec.label.count > 5 ? 11 : 14
    label.fontColor = .white
    label.verticalAlignmentMode = .center
    label.horizontalAlignmentMode = .center
    visual.addChild(label)
    crop.addChild(visual)

    // Mask = a rectangle covering only the desired side of the disc.
    let maskNode = SKShapeNode(
      rect: CGRect(
        x: side == .left ? -radius : 0,
        y: -radius,
        width: radius,
        height: radius * 2))
    maskNode.fillColor = .white
    maskNode.strokeColor = .clear
    crop.maskNode = maskNode
    return crop
  }

  // MARK: Types

  private struct LogoSpec {
    let label: String
    let color: UIColor
    var isBomb: Bool = false
  }

  private final class Logo {
    let id = UUID()
    let node: SKNode
    let spec: LogoSpec
    let radius: CGFloat
    init(node: SKNode, spec: LogoSpec, radius: CGFloat) {
      self.node = node
      self.spec = spec
      self.radius = radius
    }
  }
}
