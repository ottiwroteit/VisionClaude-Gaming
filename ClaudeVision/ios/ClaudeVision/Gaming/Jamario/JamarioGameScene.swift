import Combine
import Foundation
import SpriteKit
import UIKit

/// SpriteKit scene for the Jamario auto-runner. Procedurally generates
/// the level ahead of the player as they advance and despawns chunks
/// behind. All geometry is built from SKShapeNode primitives — no
/// asset files. The chin-UP gesture (delivered via the parent
/// JamarioGame's published `jumpEventID`) triggers a single jump if
/// Jamario is currently grounded.
final class JamarioGameScene: SKScene, SKPhysicsContactDelegate {

  // MARK: Categories

  private static let categoryPlayer: UInt32 = 1 << 0
  private static let categoryGround: UInt32 = 1 << 1
  private static let categoryEnemy: UInt32 = 1 << 2
  private static let categoryCoin: UInt32 = 1 << 3
  private static let categoryKillFloor: UInt32 = 1 << 4

  // MARK: Tunables

  /// Horizontal scroll speed in points per second. Tuned to feel like
  /// "auto-running but in control" — fast enough to keep tension,
  /// slow enough that you can react to one obstacle at a time.
  private let runSpeed: CGFloat = 240
  private let jumpImpulse: CGFloat = 380
  private let gravity: CGVector = CGVector(dx: 0, dy: -28)
  private let playerSize = CGSize(width: 36, height: 44)
  /// Y of the top of the ground tier — Jamario stands here.
  private var groundTopY: CGFloat { size.height * 0.30 }
  /// Y below which the player is considered to have fallen into a pit.
  private var killFloorY: CGFloat { -size.height * 0.6 }
  /// Player's fixed X in screen-space (camera follows).
  private var playerScreenX: CGFloat { size.width * 0.30 }
  /// World units per "meter" reported back to the game model.
  private let pointsPerMeter: CGFloat = 32

  // MARK: External wiring

  weak var game: JamarioGame?
  var theme: JamarioSceneTheme = .jamarioKingdom

  // MARK: Layers

  private let backgroundLayer = SKNode()
  private let parallaxFarLayer = SKNode()
  private let parallaxMidLayer = SKNode()
  private let parallaxNearLayer = SKNode()
  private let worldLayer = SKNode()
  private let cameraNode = SKCameraNode()

  // MARK: Player + state

  private var player: SKShapeNode!
  /// Number of currently-active ground contacts. >0 = grounded.
  private var groundContactCount: Int = 0
  private var isAlive: Bool = true
  /// Last camera X — used to drive parallax and metered distance.
  private var lastCameraX: CGFloat = 0
  /// X position up to which the level has been generated. New chunks
  /// spawn when the camera approaches this value.
  private var generatedToX: CGFloat = 0
  /// Lookahead distance — generate chunks up to this far ahead of
  /// the camera so the player never sees an empty seam.
  private let chunkLookahead: CGFloat = 1400
  /// Despawn nodes this far behind the camera.
  private let despawnBehind: CGFloat = 600
  /// Sky / mountain / hill background nodes (rebuilt on theme change).
  private var backgroundNodes: [SKNode] = []
  /// Combine subscription on game.$jumpEventID.
  private var jumpSub: AnyCancellable?

  // MARK: Init

  func configure(game: JamarioGame, theme: JamarioSceneTheme) {
    self.game = game
    self.theme = theme
  }

  override func didMove(to view: SKView) {
    physicsWorld.gravity = gravity
    physicsWorld.contactDelegate = self
    backgroundColor = theme.skyBottom
    scaleMode = .resizeFill

    addChild(backgroundLayer)
    addChild(parallaxFarLayer)
    addChild(parallaxMidLayer)
    addChild(parallaxNearLayer)
    addChild(worldLayer)
    addChild(cameraNode)
    camera = cameraNode
    cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)

    rebuildBackground()
    spawnPlayer()
    // Seed the first stretch of safe ground so the player doesn't
    // spawn into a pit on a particularly cruel RNG roll.
    generateOpeningRunway()
    generateAhead()

    if let game {
      jumpSub = game.$jumpEventID.dropFirst().sink { [weak self] _ in
        self?.attemptJump()
      }
    }
  }

  // MARK: Background

  private func rebuildBackground() {
    backgroundNodes.forEach { $0.removeFromParent() }
    backgroundNodes.removeAll()

    // Sky gradient — two stacked rectangles approximating top → bottom.
    // SpriteKit doesn't have a true gradient shape; this is the
    // cheapest readable approximation.
    let halfHeight = size.height / 2
    let topRect = SKShapeNode(rectOf: CGSize(width: size.width * 4, height: halfHeight + 4))
    topRect.fillColor = theme.skyTop
    topRect.strokeColor = .clear
    topRect.position = CGPoint(x: size.width / 2, y: size.height * 0.75)
    topRect.zPosition = -100
    backgroundLayer.addChild(topRect)
    backgroundNodes.append(topRect)

    let bottomRect = SKShapeNode(rectOf: CGSize(width: size.width * 4, height: halfHeight + 4))
    bottomRect.fillColor = theme.skyBottom
    bottomRect.strokeColor = .clear
    bottomRect.position = CGPoint(x: size.width / 2, y: size.height * 0.25)
    bottomRect.zPosition = -100
    backgroundLayer.addChild(bottomRect)
    backgroundNodes.append(bottomRect)

    // Distant mountain band — a few overlapping triangles repeated.
    let mountainTile = makeMountainTile()
    mountainTile.position = CGPoint(x: size.width / 2, y: groundTopY + 70)
    mountainTile.zPosition = -90
    parallaxFarLayer.addChild(mountainTile)
    backgroundNodes.append(mountainTile)

    // Mid-distance hills.
    let hillTile = makeHillTile()
    hillTile.position = CGPoint(x: size.width / 2, y: groundTopY + 30)
    hillTile.zPosition = -80
    parallaxMidLayer.addChild(hillTile)
    backgroundNodes.append(hillTile)

    // A few clouds dotted across the upper sky.
    for i in 0..<6 {
      let cloud = makeCloudNode()
      let xs: [CGFloat] = [-400, -120, 80, 320, 580, 880]
      cloud.position = CGPoint(
        x: xs[i],
        y: size.height * 0.78 + CGFloat((i % 2) * 18)
      )
      cloud.zPosition = -70
      parallaxNearLayer.addChild(cloud)
      backgroundNodes.append(cloud)
    }
  }

  private func makeMountainTile() -> SKNode {
    let host = SKNode()
    let tileWidth: CGFloat = 1600
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -tileWidth / 2, y: 0))
    var x: CGFloat = -tileWidth / 2
    while x < tileWidth / 2 {
      let peakHeight = CGFloat.random(in: 60...120)
      let peakWidth = CGFloat.random(in: 110...180)
      path.addLine(to: CGPoint(x: x + peakWidth / 2, y: peakHeight))
      path.addLine(to: CGPoint(x: x + peakWidth, y: 0))
      x += peakWidth
    }
    path.addLine(to: CGPoint(x: tileWidth / 2, y: -200))
    path.addLine(to: CGPoint(x: -tileWidth / 2, y: -200))
    path.closeSubpath()
    let shape = SKShapeNode(path: path)
    shape.fillColor = theme.mountainColor
    shape.strokeColor = .clear
    host.addChild(shape)
    return host
  }

  private func makeHillTile() -> SKNode {
    let host = SKNode()
    let tileWidth: CGFloat = 1200
    for i in 0..<5 {
      let hill = SKShapeNode(circleOfRadius: CGFloat.random(in: 80...140))
      hill.fillColor = theme.hillColor
      hill.strokeColor = .clear
      hill.position = CGPoint(
        x: -tileWidth / 2 + CGFloat(i) * 280 + CGFloat.random(in: -40...40),
        y: -hill.frame.height * 0.4
      )
      host.addChild(hill)
    }
    return host
  }

  private func makeCloudNode() -> SKNode {
    let host = SKNode()
    let bumps = Int.random(in: 3...4)
    for j in 0..<bumps {
      let r = CGFloat.random(in: 22...32)
      let bump = SKShapeNode(circleOfRadius: r)
      bump.fillColor = theme.cloudColor
      bump.strokeColor = .clear
      bump.position = CGPoint(x: CGFloat(j) * 28 - CGFloat(bumps) * 14, y: 0)
      host.addChild(bump)
    }
    return host
  }

  // MARK: Player

  private func spawnPlayer() {
    let path = CGPath(
      roundedRect: CGRect(
        x: -playerSize.width / 2, y: -playerSize.height / 2,
        width: playerSize.width, height: playerSize.height),
      cornerWidth: 6, cornerHeight: 6, transform: nil)
    player = SKShapeNode(path: path)
    player.fillColor = theme.playerColor
    player.strokeColor = .black
    player.lineWidth = 1.5

    // Cap stripe — a thin overlay rectangle near the top of the body.
    let stripe = SKShapeNode(
      rect: CGRect(
        x: -playerSize.width / 2, y: playerSize.height / 2 - 12,
        width: playerSize.width, height: 6))
    stripe.fillColor = theme.playerAccentColor
    stripe.strokeColor = .clear
    player.addChild(stripe)

    // Two simple eye dots so the player has a face.
    let leftEye = SKShapeNode(circleOfRadius: 3)
    leftEye.fillColor = .white
    leftEye.strokeColor = .black
    leftEye.lineWidth = 1
    leftEye.position = CGPoint(x: -6, y: 4)
    player.addChild(leftEye)
    let rightEye = SKShapeNode(circleOfRadius: 3)
    rightEye.fillColor = .white
    rightEye.strokeColor = .black
    rightEye.lineWidth = 1
    rightEye.position = CGPoint(x: 8, y: 4)
    player.addChild(rightEye)

    let body = SKPhysicsBody(rectangleOf: playerSize)
    body.allowsRotation = false
    body.friction = 0
    body.restitution = 0
    body.linearDamping = 0
    body.mass = 1.0
    body.categoryBitMask = Self.categoryPlayer
    body.collisionBitMask = Self.categoryGround
    body.contactTestBitMask =
      Self.categoryGround | Self.categoryEnemy | Self.categoryCoin | Self.categoryKillFloor
    player.physicsBody = body

    player.position = CGPoint(x: playerScreenX, y: groundTopY + playerSize.height)
    player.zPosition = 10
    addChild(player)

    // Kill-floor sensor — invisible wide rectangle below the world
    // that catches a player who falls into a pit.
    let killFloor = SKNode()
    killFloor.position = CGPoint(x: 0, y: killFloorY)
    let killBody = SKPhysicsBody(
      edgeFrom: CGPoint(x: -10000, y: 0), to: CGPoint(x: 100000, y: 0))
    killBody.isDynamic = false
    killBody.categoryBitMask = Self.categoryKillFloor
    killBody.contactTestBitMask = Self.categoryPlayer
    killBody.collisionBitMask = 0
    killFloor.physicsBody = killBody
    addChild(killFloor)
  }

  private func attemptJump() {
    guard isAlive, groundContactCount > 0, let body = player.physicsBody else { return }
    body.velocity = CGVector(dx: body.velocity.dx, dy: 0)
    body.applyImpulse(CGVector(dx: 0, dy: jumpImpulse))
  }

  // MARK: Level generation

  /// Spawn ~1.5 screens of flat ground at game start so the first
  /// jump is always a deliberate one, never a survival reaction.
  private func generateOpeningRunway() {
    addGroundSegment(fromX: -200, toX: size.width * 1.5)
    generatedToX = size.width * 1.5
  }

  private func generateAhead() {
    while generatedToX < cameraNode.position.x + chunkLookahead {
      spawnNextChunk(startingAt: generatedToX)
    }
  }

  /// Pick a random chunk type and spawn it. Each chunk advances
  /// `generatedToX` so successive calls walk forward through the
  /// world. Chunk frequencies are weighted toward "easy" so the level
  /// is playable rather than punishing.
  private func spawnNextChunk(startingAt x: CGFloat) {
    let roll = Int.random(in: 0..<100)
    switch roll {
    case 0..<35:
      // Plain ground stretch.
      let length = CGFloat.random(in: 220...360)
      addGroundSegment(fromX: x, toX: x + length)
      generatedToX = x + length
    case 35..<55:
      // Ground with a coin row hovering above.
      let length = CGFloat.random(in: 280...420)
      addGroundSegment(fromX: x, toX: x + length)
      addCoinRow(fromX: x + 60, toX: x + length - 60, y: groundTopY + 110)
      generatedToX = x + length
    case 55..<70:
      // Small pit with safe ground on both sides.
      let preLand: CGFloat = CGFloat.random(in: 120...180)
      let pit: CGFloat = CGFloat.random(in: 70...110)
      let postLand: CGFloat = CGFloat.random(in: 200...300)
      addGroundSegment(fromX: x, toX: x + preLand)
      // Pit gap is just empty space — kill floor handles fall-throughs.
      addGroundSegment(fromX: x + preLand + pit, toX: x + preLand + pit + postLand)
      generatedToX = x + preLand + pit + postLand
    case 70..<82:
      // Floating platform over flat ground.
      let length = CGFloat.random(in: 300...420)
      addGroundSegment(fromX: x, toX: x + length)
      let platformX = x + length / 2
      addPlatform(centerX: platformX, y: groundTopY + 130, width: 140)
      // Coins on top of the platform.
      addCoinRow(fromX: platformX - 50, toX: platformX + 50, y: groundTopY + 170)
      generatedToX = x + length
    case 82..<92:
      // Goomba patrol on flat ground.
      let length = CGFloat.random(in: 320...440)
      addGroundSegment(fromX: x, toX: x + length)
      let count = Int.random(in: 1...2)
      for i in 0..<count {
        let ex = x + 100 + CGFloat(i) * 140
        addEnemy(atX: ex, y: groundTopY + 22)
      }
      generatedToX = x + length
    default:
      // Wide pit with a stepping-stone platform in the middle.
      let preLand: CGFloat = 160
      let pitWidth: CGFloat = CGFloat.random(in: 220...300)
      let postLand: CGFloat = 220
      addGroundSegment(fromX: x, toX: x + preLand)
      addPlatform(centerX: x + preLand + pitWidth / 2, y: groundTopY + 60, width: 90)
      addGroundSegment(
        fromX: x + preLand + pitWidth, toX: x + preLand + pitWidth + postLand)
      generatedToX = x + preLand + pitWidth + postLand
    }
  }

  // MARK: Level node factories

  private func addGroundSegment(fromX startX: CGFloat, toX endX: CGFloat) {
    let width = endX - startX
    guard width > 0 else { return }
    let height: CGFloat = groundTopY  // ground spans from y=0 to y=groundTopY
    let body = SKShapeNode(
      rect: CGRect(x: 0, y: 0, width: width, height: height))
    body.fillColor = theme.groundBodyColor
    body.strokeColor = .clear
    body.position = CGPoint(x: startX, y: 0)
    body.zPosition = 1

    // Top grass strip.
    let grass = SKShapeNode(rect: CGRect(x: 0, y: height - 8, width: width, height: 8))
    grass.fillColor = theme.groundTopColor
    grass.strokeColor = .clear
    body.addChild(grass)

    let physicsBody = SKPhysicsBody(
      edgeLoopFrom: CGRect(x: 0, y: 0, width: width, height: height))
    physicsBody.isDynamic = false
    physicsBody.friction = 0
    physicsBody.restitution = 0
    physicsBody.categoryBitMask = Self.categoryGround
    physicsBody.contactTestBitMask = Self.categoryPlayer
    physicsBody.collisionBitMask = Self.categoryPlayer | Self.categoryEnemy
    body.physicsBody = physicsBody
    worldLayer.addChild(body)
  }

  private func addPlatform(centerX: CGFloat, y: CGFloat, width: CGFloat) {
    let height: CGFloat = 16
    let node = SKShapeNode(
      rect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
      cornerRadius: 4)
    node.fillColor = theme.platformColor
    node.strokeColor = .black
    node.lineWidth = 1
    node.position = CGPoint(x: centerX, y: y)
    node.zPosition = 2

    let body = SKPhysicsBody(rectangleOf: CGSize(width: width, height: height))
    body.isDynamic = false
    body.friction = 0
    body.restitution = 0
    body.categoryBitMask = Self.categoryGround
    body.contactTestBitMask = Self.categoryPlayer
    body.collisionBitMask = Self.categoryPlayer | Self.categoryEnemy
    node.physicsBody = body
    worldLayer.addChild(node)
  }

  private func addEnemy(atX x: CGFloat, y: CGFloat) {
    let enemySize = CGSize(width: 32, height: 28)
    let path = CGPath(
      roundedRect: CGRect(
        x: -enemySize.width / 2, y: -enemySize.height / 2,
        width: enemySize.width, height: enemySize.height),
      cornerWidth: 10, cornerHeight: 10, transform: nil)
    let node = SKShapeNode(path: path)
    node.fillColor = theme.enemyColor
    node.strokeColor = .black
    node.lineWidth = 1
    node.position = CGPoint(x: x, y: y)
    node.zPosition = 5
    node.name = "enemy"

    // Tiny eyes for character.
    for ex in [-5.0, 6.0] {
      let eye = SKShapeNode(circleOfRadius: 2.5)
      eye.fillColor = .white
      eye.strokeColor = .black
      eye.lineWidth = 0.8
      eye.position = CGPoint(x: ex, y: 3)
      node.addChild(eye)
    }

    let body = SKPhysicsBody(rectangleOf: enemySize)
    body.allowsRotation = false
    body.friction = 0
    body.restitution = 0
    body.linearDamping = 0
    body.mass = 0.5
    body.categoryBitMask = Self.categoryEnemy
    body.contactTestBitMask = Self.categoryPlayer
    body.collisionBitMask = Self.categoryGround
    node.physicsBody = body
    // Patrol left at a slow constant speed.
    body.velocity = CGVector(dx: -60, dy: 0)
    worldLayer.addChild(node)
  }

  private func addCoinRow(fromX startX: CGFloat, toX endX: CGFloat, y: CGFloat) {
    let spacing: CGFloat = 36
    var x = startX
    while x <= endX {
      addCoin(atX: x, y: y)
      x += spacing
    }
  }

  private func addCoin(atX x: CGFloat, y: CGFloat) {
    let coin = SKShapeNode(circleOfRadius: 9)
    coin.fillColor = theme.coinColor
    coin.strokeColor = UIColor.brown
    coin.lineWidth = 1
    coin.position = CGPoint(x: x, y: y)
    coin.zPosition = 6
    coin.name = "coin"

    // Subtle glint inside the disc.
    let glint = SKShapeNode(circleOfRadius: 3)
    glint.fillColor = theme.coinGlintColor
    glint.strokeColor = .clear
    glint.position = CGPoint(x: -2, y: 2)
    coin.addChild(glint)

    // Gentle spin to give the coin some life.
    coin.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 1.4)))

    let body = SKPhysicsBody(circleOfRadius: 9)
    body.isDynamic = false
    body.categoryBitMask = Self.categoryCoin
    body.contactTestBitMask = Self.categoryPlayer
    body.collisionBitMask = 0  // sensor — no collision response
    coin.physicsBody = body
    worldLayer.addChild(coin)
  }

  // MARK: Update loop

  override func update(_ currentTime: TimeInterval) {
    guard let game else { return }
    if game.isFinished {
      // Halt motion so the "game over" overlay isn't shown over a
      // running scene.
      player.physicsBody?.velocity = .zero
      return
    }
    if isAlive {
      // Auto-run: lock dx, leave dy to physics so jumps still apply.
      let body = player.physicsBody
      let currentDY = body?.velocity.dy ?? 0
      body?.velocity = CGVector(dx: runSpeed, dy: currentDY)
    }

    // Camera follows the player.
    cameraNode.position = CGPoint(
      x: player.position.x + size.width * 0.2,
      y: size.height / 2)

    // Distance reporting: convert camera X (minus initial offset)
    // into "meters" via pointsPerMeter.
    let metersAdvanced = max(0, Int((cameraNode.position.x - size.width * 0.5) / pointsPerMeter))
    game.didAdvance(meters: metersAdvanced)

    // Parallax — keep background layers near the camera but slower.
    let camX = cameraNode.position.x
    backgroundLayer.position = CGPoint(x: camX - size.width / 2, y: 0)
    parallaxFarLayer.position = CGPoint(x: camX * 0.20, y: 0)
    parallaxMidLayer.position = CGPoint(x: camX * 0.45, y: 0)
    parallaxNearLayer.position = CGPoint(x: camX * 0.75, y: 0)

    // Generate ahead, despawn behind.
    generateAhead()
    despawnBehindCamera()

    lastCameraX = camX
  }

  private func despawnBehindCamera() {
    let cutoff = cameraNode.position.x - despawnBehind
    for child in worldLayer.children where child.position.x < cutoff {
      child.removeFromParent()
    }
  }

  // MARK: Death + reset

  /// Called when the player hits a goomba from the side or falls into
  /// a pit. Loses one life and resets the level.
  private func dieAndReset(reason: DeathReason) {
    guard isAlive else { return }
    isAlive = false
    switch reason {
    case .pit: game?.didDieFromPit()
    case .enemy: game?.didDieFromEnemy()
    }
    if game?.isFinished == true {
      // Final death — leave the scene where it is; the chrome shows
      // a Game Over overlay.
      return
    }
    // Brief "respawn pause" before resetting so the death reads.
    let wait = SKAction.wait(forDuration: 0.4)
    let reset = SKAction.run { [weak self] in
      self?.fullLevelReset()
    }
    run(.sequence([wait, reset]))
  }

  private enum DeathReason { case pit, enemy }

  private func fullLevelReset() {
    worldLayer.removeAllChildren()
    generatedToX = 0
    cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
    player.position = CGPoint(x: playerScreenX, y: groundTopY + playerSize.height)
    player.physicsBody?.velocity = .zero
    groundContactCount = 0
    generateOpeningRunway()
    generateAhead()
    isAlive = true
  }

  // MARK: Theme update

  func applyTheme(_ newTheme: JamarioSceneTheme) {
    theme = newTheme
    backgroundColor = newTheme.skyBottom
    rebuildBackground()
    // The world layer's procedural nodes keep their original colour
    // (they were tinted at spawn time). New chunks generated after
    // the theme change pick up the new palette automatically.
    player.fillColor = newTheme.playerColor
    if let stripe = player.children.first(where: { $0 is SKShapeNode }) as? SKShapeNode {
      stripe.fillColor = newTheme.playerAccentColor
    }
  }

  // MARK: Contact

  func didBegin(_ contact: SKPhysicsContact) {
    let bodies = (contact.bodyA, contact.bodyB)
    let categoryA = bodies.0.categoryBitMask
    let categoryB = bodies.1.categoryBitMask

    // Player landed on / touched ground.
    if categoryA | categoryB == Self.categoryPlayer | Self.categoryGround {
      let normalY = contact.contactNormal.dy
      // Contact normal points from B to A. We only count it as a
      // "landing" if Jamario is approximately on top of the ground —
      // otherwise side scrapes spuriously mark him grounded.
      if abs(normalY) > 0.6 {
        groundContactCount += 1
      }
      return
    }

    // Coin pickup.
    if categoryA | categoryB == Self.categoryPlayer | Self.categoryCoin {
      let coinBody = (categoryA == Self.categoryCoin) ? bodies.0 : bodies.1
      coinBody.node?.run(
        .sequence([
          .group([.scale(by: 1.6, duration: 0.10), .fadeOut(withDuration: 0.10)]),
          .removeFromParent(),
        ]))
      game?.didCollectCoin()
      return
    }

    // Enemy contact — stomp from above kills the enemy, side hit kills
    // the player.
    if categoryA | categoryB == Self.categoryPlayer | Self.categoryEnemy {
      let playerBody = (categoryA == Self.categoryPlayer) ? bodies.0 : bodies.1
      let enemyBody = (categoryA == Self.categoryEnemy) ? bodies.0 : bodies.1
      let stompedFromAbove =
        (playerBody.node?.position.y ?? 0) > (enemyBody.node?.position.y ?? 0) + 12
      if stompedFromAbove {
        enemyBody.node?.run(
          .sequence([
            .group([.scaleY(to: 0.2, duration: 0.10), .fadeOut(withDuration: 0.18)]),
            .removeFromParent(),
          ]))
        game?.didStompEnemy()
        // Bounce — small upward impulse so the stomp feels mechanical.
        playerBody.applyImpulse(CGVector(dx: 0, dy: jumpImpulse * 0.55))
      } else {
        dieAndReset(reason: .enemy)
      }
      return
    }

    // Player fell off the world.
    if categoryA | categoryB == Self.categoryPlayer | Self.categoryKillFloor {
      dieAndReset(reason: .pit)
      return
    }
  }

  func didEnd(_ contact: SKPhysicsContact) {
    let cats = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
    if cats == Self.categoryPlayer | Self.categoryGround {
      let normalY = contact.contactNormal.dy
      if abs(normalY) > 0.6 {
        groundContactCount = max(0, groundContactCount - 1)
      }
    }
  }
}
