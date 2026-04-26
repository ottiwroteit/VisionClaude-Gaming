import Combine
import Foundation
import SpriteKit
import UIKit

/// SpriteKit scene for Jamario: Streets — the side-scrolling brawler.
///
/// One fixed arena (no infinite scrolling). Jamario can walk left and
/// right; enemies spawn from off-screen right and walk toward him.
/// Punch (chin UP) and kick (chin DOWN) deal damage when an enemy is
/// in melee range. Each defeated enemy bumps the wave score; when the
/// wave is cleared the game model advances and we spawn the next.
///
/// Sprites are reused from the Jamario auto-runner asset catalog
/// (idle, run cycle, jump, plus new punch + kick poses) plus the
/// existing enemy idle / walk frames.
final class JamarioStreetsGameScene: SKScene, SKPhysicsContactDelegate {

  // MARK: Categories

  private static let categoryPlayer: UInt32 = 1 << 0
  private static let categoryGround: UInt32 = 1 << 1
  private static let categoryEnemy: UInt32 = 1 << 2
  private static let categoryPlayerHitbox: UInt32 = 1 << 3

  // MARK: Tunables

  private let walkMaxSpeed: CGFloat = 220
  private let gravity: CGVector = CGVector(dx: 0, dy: 0)  // top-down arena, no gravity
  private let playerHitbox = CGSize(width: 36, height: 60)
  private let enemyHitbox = CGSize(width: 36, height: 60)
  private static let playerVisualSize = CGSize(width: 80, height: 110)
  private static let enemyVisualSize = CGSize(width: 70, height: 96)

  /// Reach of the punch and kick from Jamario's centre to enemy centre.
  private let punchReach: CGFloat = 90
  private let kickReach: CGFloat = 130
  /// Vertical tolerance for a hit — enemies must be within this many
  /// points of Jamario's Y to count as in-line (otherwise the hit
  /// passes over them harmlessly).
  private let hitYTolerance: CGFloat = 36
  /// How long the punch / kick sprite shows before snapping back to
  /// the run/idle frame.
  private let punchAnimDuration: TimeInterval = 0.18
  private let kickAnimDuration: TimeInterval = 0.28

  /// Y of the "ground" the player walks on (top-down style).
  private var groundY: CGFloat { size.height * 0.30 }
  /// X bounds Jamario's walk is clamped to.
  private var leftWall: CGFloat { 60 }
  private var rightWall: CGFloat { size.width - 60 }

  // MARK: Sprite textures (top-level imagesets via UIImage(named:))

  private static func loadTexture(_ name: String) -> SKTexture {
    guard let img = UIImage(named: name) else {
      print("[JamarioStreets] missing image: \(name)")
      return SKTexture()
    }
    return SKTexture(image: img)
  }
  private lazy var playerIdleTexture: SKTexture = Self.loadTexture("jamario_idle")
  private lazy var playerPunchTexture: SKTexture = Self.loadTexture("jamario_punch")
  private lazy var playerKickTexture: SKTexture = Self.loadTexture("jamario_kick")
  private lazy var playerRunTextures: [SKTexture] = (1...8).map {
    Self.loadTexture("jamario_run_\($0)")
  }
  private lazy var enemyIdleTexture: SKTexture = Self.loadTexture("jamario_enemy_idle")
  private lazy var enemyWalkTextures: [SKTexture] = [
    Self.loadTexture("jamario_enemy_walk_1"),
    Self.loadTexture("jamario_enemy_walk_2"),
  ]

  // MARK: External wiring

  weak var game: JamarioStreetsGame?

  // MARK: Scene state

  private let backgroundLayer = SKNode()
  private let worldLayer = SKNode()
  private var player: SKSpriteNode!
  /// Current facing: +1 = facing right (default), -1 = facing left.
  /// Sprites are drawn facing right; flip via xScale = -1.
  private var playerFacing: CGFloat = 1
  /// Active enemies in the scene.
  private var enemies: [Enemy] = []
  /// Per-frame attack-state flag — true while the punch/kick anim is
  /// on screen. Prevents the run/idle animation from overwriting the
  /// attack pose mid-swing.
  private var attackingUntil: TimeInterval = 0

  private var punchSub: AnyCancellable?
  private var kickSub: AnyCancellable?
  /// Last published wave count from the game — used to detect wave
  /// transitions and respawn enemies.
  private var lastObservedWave: Int = 0

  // MARK: Enemy bookkeeping

  private final class Enemy {
    let node: SKSpriteNode
    var hp: Int
    /// Last time this enemy successfully damaged the player. Used to
    /// throttle continuous-contact damage.
    var lastHitDealt: TimeInterval = 0
    init(node: SKSpriteNode, hp: Int) {
      self.node = node
      self.hp = hp
    }
  }

  // MARK: Setup

  override func didMove(to view: SKView) {
    physicsWorld.gravity = gravity
    physicsWorld.contactDelegate = self
    backgroundColor = UIColor(red: 0.18, green: 0.18, blue: 0.22, alpha: 1)
    scaleMode = .resizeFill

    addChild(backgroundLayer)
    addChild(worldLayer)
    buildBackground()
    spawnPlayer()
    if let game {
      lastObservedWave = game.wave
      spawnWaveEnemies(count: game.enemiesPerWave)
      punchSub = game.$punchEventID.dropFirst().sink { [weak self] _ in
        self?.performPunch()
      }
      kickSub = game.$kickEventID.dropFirst().sink { [weak self] _ in
        self?.performKick()
      }
    }
  }

  // MARK: Background

  /// Stylized urban street: sky band on top, building silhouettes,
  /// concrete sidewalk below. Drawn from primitives — no textures.
  private func buildBackground() {
    backgroundLayer.removeAllChildren()

    // Distant sky band (warm sunset).
    let sky = SKShapeNode(rectOf: CGSize(width: size.width * 4, height: size.height))
    sky.fillColor = UIColor(red: 0.55, green: 0.30, blue: 0.40, alpha: 1)
    sky.strokeColor = .clear
    sky.position = CGPoint(x: size.width / 2, y: size.height * 0.75)
    sky.zPosition = -100
    backgroundLayer.addChild(sky)

    // City skyline silhouette band.
    let buildings = SKShapeNode()
    let bpath = CGMutablePath()
    let buildingY: CGFloat = size.height * 0.42
    bpath.move(to: CGPoint(x: -50, y: buildingY))
    var bx: CGFloat = -50
    while bx < size.width + 50 {
      let w = CGFloat.random(in: 50...110)
      let h = CGFloat.random(in: 80...180)
      bpath.addLine(to: CGPoint(x: bx, y: buildingY + h))
      bpath.addLine(to: CGPoint(x: bx + w, y: buildingY + h))
      bx += w
    }
    bpath.addLine(to: CGPoint(x: size.width + 50, y: buildingY))
    bpath.addLine(to: CGPoint(x: -50, y: buildingY))
    bpath.closeSubpath()
    buildings.path = bpath
    buildings.fillColor = UIColor(red: 0.10, green: 0.08, blue: 0.18, alpha: 1)
    buildings.strokeColor = .clear
    buildings.zPosition = -90
    backgroundLayer.addChild(buildings)

    // Lit windows scattered on the buildings.
    for _ in 0..<40 {
      let w = SKShapeNode(rectOf: CGSize(width: 4, height: 6))
      w.fillColor = UIColor(red: 1.00, green: 0.85, blue: 0.40, alpha: 0.85)
      w.strokeColor = .clear
      w.position = CGPoint(
        x: CGFloat.random(in: 0...size.width),
        y: CGFloat.random(in: buildingY + 20...buildingY + 160))
      w.zPosition = -85
      backgroundLayer.addChild(w)
    }

    // Sidewalk (concrete) beneath the action.
    let street = SKShapeNode(
      rectOf: CGSize(width: size.width * 4, height: size.height * 0.32))
    street.fillColor = UIColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
    street.strokeColor = .clear
    street.position = CGPoint(x: size.width / 2, y: size.height * 0.16)
    street.zPosition = -70
    backgroundLayer.addChild(street)

    // Painted yellow line on the road.
    for i in 0..<8 {
      let dash = SKShapeNode(rectOf: CGSize(width: 36, height: 4))
      dash.fillColor = UIColor(red: 0.95, green: 0.85, blue: 0.30, alpha: 1)
      dash.strokeColor = .clear
      dash.position = CGPoint(
        x: CGFloat(i) * 80 + 30, y: size.height * 0.10)
      dash.zPosition = -65
      backgroundLayer.addChild(dash)
    }
  }

  // MARK: Player

  private func spawnPlayer() {
    player = SKSpriteNode(texture: playerIdleTexture)
    player.size = Self.playerVisualSize
    player.zPosition = 10
    player.position = CGPoint(x: size.width * 0.30, y: groundY)

    let body = SKPhysicsBody(rectangleOf: playerHitbox)
    body.allowsRotation = false
    body.affectedByGravity = false
    body.linearDamping = 8
    body.friction = 0
    body.mass = 1.0
    body.categoryBitMask = Self.categoryPlayer
    body.collisionBitMask = Self.categoryEnemy
    body.contactTestBitMask = Self.categoryEnemy
    player.physicsBody = body
    addChild(player)
  }

  // MARK: Attack performance

  private func performPunch() {
    guard let game else { return }
    attackingUntil = max(attackingUntil, currentTime + punchAnimDuration)
    player.removeAction(forKey: "anim")
    player.texture = playerPunchTexture

    // Hit detection — front cone.
    var landed = false
    for enemy in enemies {
      if isInRange(enemy: enemy, reach: punchReach) {
        enemy.hp -= game.punchDamage
        landed = true
        flashEnemyHit(enemy)
        if enemy.hp <= 0 {
          killEnemy(enemy)
        }
      }
    }
    if landed { game.didLandPunch() }

    // Schedule animation reset.
    let restore = SKAction.run { [weak self] in
      self?.attackingUntil = 0
    }
    player.run(.sequence([.wait(forDuration: punchAnimDuration), restore]))
  }

  private func performKick() {
    guard let game else { return }
    attackingUntil = max(attackingUntil, currentTime + kickAnimDuration)
    player.removeAction(forKey: "anim")
    player.texture = playerKickTexture

    var landed = false
    for enemy in enemies {
      if isInRange(enemy: enemy, reach: kickReach) {
        enemy.hp -= game.kickDamage
        landed = true
        flashEnemyHit(enemy)
        if enemy.hp <= 0 {
          killEnemy(enemy)
        }
      }
    }
    if landed { game.didLandKick() }

    let restore = SKAction.run { [weak self] in
      self?.attackingUntil = 0
    }
    player.run(.sequence([.wait(forDuration: kickAnimDuration), restore]))
  }

  /// True if the enemy is in front of the player (matching facing) AND
  /// within `reach` horizontally + within hitYTolerance vertically.
  private func isInRange(enemy: Enemy, reach: CGFloat) -> Bool {
    let dx = enemy.node.position.x - player.position.x
    let dy = abs(enemy.node.position.y - player.position.y)
    guard dy <= hitYTolerance else { return false }
    if playerFacing > 0 {
      return dx >= 0 && dx <= reach
    } else {
      return dx <= 0 && abs(dx) <= reach
    }
  }

  private func flashEnemyHit(_ enemy: Enemy) {
    let flash = SKAction.sequence([
      .colorize(with: .red, colorBlendFactor: 0.7, duration: 0.06),
      .colorize(with: .clear, colorBlendFactor: 0, duration: 0.20),
    ])
    enemy.node.run(flash, withKey: "hitFlash")
  }

  private func killEnemy(_ enemy: Enemy) {
    enemies.removeAll { $0 === enemy }
    let die = SKAction.sequence([
      .group([.fadeOut(withDuration: 0.35), .scaleY(to: 0.2, duration: 0.35)]),
      .removeFromParent(),
    ])
    enemy.node.run(die)
    game?.didDefeatEnemy()
  }

  // MARK: Enemies

  private func spawnWaveEnemies(count: Int) {
    for i in 0..<count {
      // Stagger spawns slightly so they don't all march in lockstep.
      let delay = TimeInterval(i) * 0.7
      run(.sequence([.wait(forDuration: delay), .run { [weak self] in self?.spawnEnemy() }]))
    }
  }

  private func spawnEnemy() {
    let node = SKSpriteNode(texture: enemyIdleTexture)
    node.size = Self.enemyVisualSize
    node.zPosition = 9
    node.position = CGPoint(
      x: size.width + CGFloat.random(in: 30...160),
      y: groundY + CGFloat.random(in: -8...8))

    let body = SKPhysicsBody(rectangleOf: enemyHitbox)
    body.allowsRotation = false
    body.affectedByGravity = false
    body.linearDamping = 8
    body.mass = 0.7
    body.categoryBitMask = Self.categoryEnemy
    body.collisionBitMask = Self.categoryPlayer | Self.categoryEnemy
    body.contactTestBitMask = Self.categoryPlayer
    node.physicsBody = body
    addChild(node)

    // Walking animation — sprites face left already so no flip needed.
    let cycle = SKAction.animate(
      with: enemyWalkTextures, timePerFrame: 0.18, resize: false, restore: false)
    node.run(.repeatForever(cycle), withKey: "walk")

    enemies.append(Enemy(node: node, hp: 30))
  }

  // MARK: Update loop

  private var currentTime: TimeInterval = 0

  override func update(_ time: TimeInterval) {
    currentTime = time
    guard let game else { return }
    if game.isFinished {
      player.physicsBody?.velocity = .zero
      enemies.forEach { $0.node.physicsBody?.velocity = .zero }
      return
    }

    // Wave change → spawn next batch.
    if game.wave != lastObservedWave {
      lastObservedWave = game.wave
      enemies.forEach { $0.node.removeFromParent() }
      enemies.removeAll()
      spawnWaveEnemies(count: game.enemiesPerWave)
    }

    // Walk: pull walkAxis from game; clamp inside arena.
    let axis = CGFloat(game.walkAxis)
    if abs(axis) > 0.05 {
      player.physicsBody?.velocity = CGVector(dx: axis * walkMaxSpeed, dy: 0)
      // Update facing so attacks aim toward the new direction.
      playerFacing = axis >= 0 ? 1 : -1
      player.xScale = playerFacing > 0 ? 1 : -1
    } else {
      player.physicsBody?.velocity = CGVector(dx: 0, dy: 0)
    }
    player.position.x = max(leftWall, min(rightWall, player.position.x))
    player.position.y = groundY  // lock Y to street level

    // Update player animation (run if walking, idle if not, attack
    // pose if mid-attack).
    if currentTime < attackingUntil {
      // Hold the attack pose; texture was set in performPunch/Kick.
    } else if abs(axis) > 0.05 {
      if player.action(forKey: "anim") == nil {
        let cycle = SKAction.animate(
          with: playerRunTextures, timePerFrame: 0.07, resize: false, restore: false)
        player.run(.repeatForever(cycle), withKey: "anim")
      }
    } else {
      if player.action(forKey: "anim") != nil {
        player.removeAction(forKey: "anim")
        player.texture = playerIdleTexture
      }
    }

    // Enemy AI: walk toward player; on close-contact, deal damage with
    // per-enemy cooldown.
    for enemy in enemies {
      let dx = player.position.x - enemy.node.position.x
      let dist = abs(dx)
      let speed: CGFloat = 90
      if dist > 35 {
        enemy.node.physicsBody?.velocity = CGVector(
          dx: (dx > 0 ? 1 : -1) * speed, dy: 0)
        enemy.node.xScale = dx > 0 ? -1 : 1  // walk sprites face left; flip when chasing right
      } else {
        enemy.node.physicsBody?.velocity = .zero
        // In contact range: deal damage on cooldown.
        if currentTime - enemy.lastHitDealt > game.perEnemyHitCooldown {
          enemy.lastHitDealt = currentTime
          game.didTakeDamage()
          if game.isFinished { return }
        }
      }
      enemy.node.position.y = groundY  // lock Y
    }
  }

  // MARK: Contact (reserved — currently using AABB checks in update)

  func didBegin(_ contact: SKPhysicsContact) {
    // No-op — combat resolution is in update() via reach checks; the
    // physics contact only matters for enemy/enemy push-back so they
    // don't stack on top of each other (collisionBitMask handles it).
  }
}
