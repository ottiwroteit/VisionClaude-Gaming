/**
 * Meta Bowling — game loop, state machine, rendering, input.
 *
 * Ported from ClaudeVision/ios/ClaudeVision/Gaming/Games/BowlingGame.swift.
 * The Swift version uses SceneKit + chin-flick gestures; this version uses
 * Canvas2D + D-pad (arrow keys + Enter) for the Meta Display webapp platform.
 *
 * Architecture
 * ============
 * State machine drives everything:
 *   TITLE → HOWTO → COUNTDOWN → AIM → POWER → BOWL → KNOCKING → BETWEEN_FRAMES → AIM …
 *                                                              → FINAL
 *
 * Render loop runs at 30fps via setInterval(tick, 33). Each tick advances
 * any active animation (ball travel, power meter oscillation, particles),
 * updates the HUD, and redraws the canvas.
 *
 * Pin physics is deterministic — no real rigid-body. The Swift version's
 * SceneKit physics had a jitter bug; here we use an analytical impact
 * model so the same (aim, curve, power) always produces the same result.
 */

import {
  computeScore,
  frameDisplays,
  isFinalRoll,
  tenthFrameRolls,
  TOTAL_FRAMES,
} from './scoring.js';
import { setMode as setFocusMode, focusFirst } from '../shared/focus.js';
import {
  drawLane,
  drawPin,
  drawBall,
  drawParticles,
  scaleForDepth,
  yForDepth,
  xForLanePos,
} from '../shared/canvas-utils.js';

// ===== Pin layout =====
// Standard 10-pin triangle. depth=0 is at the bowler; depth=1 at the back wall.
// Pin 1 is the FRONT pin (smallest depth among the pins).
// Lane x is normalized: -1 = left gutter, 0 = center, +1 = right gutter.
const PINS = [
  { id: 1, x: 0.0, depth: 0.85 },
  { id: 2, x: -0.1, depth: 0.91 },
  { id: 3, x: 0.1, depth: 0.91 },
  { id: 4, x: -0.2, depth: 0.95 },
  { id: 5, x: 0.0, depth: 0.95 },
  { id: 6, x: 0.2, depth: 0.95 },
  { id: 7, x: -0.3, depth: 1.0 },
  { id: 8, x: -0.1, depth: 1.0 },
  { id: 9, x: 0.1, depth: 1.0 },
  { id: 10, x: 0.3, depth: 1.0 },
];

// Adjacency table for chain-reaction knockdowns. Each entry lists the pin
// IDs that a falling pin would topple in turn, ordered by likelihood.
const PIN_NEIGHBORS = {
  1: [2, 3],
  2: [1, 4, 5],
  3: [1, 5, 6],
  4: [2, 7, 8],
  5: [2, 3, 8, 9],
  6: [3, 9, 10],
  7: [4, 8],
  8: [5, 7, 9],
  9: [5, 8, 10],
  10: [6, 9],
};

const HIT_RADIUS = 0.07; // lane-units; ball needs to pass this close to directly hit a pin

// ===== State =====

const State = Object.freeze({
  TITLE: 'TITLE',
  HOWTO: 'HOWTO',
  COUNTDOWN: 'COUNTDOWN',
  AIM: 'AIM',
  POWER: 'POWER',
  BOWL: 'BOWL',
  KNOCKING: 'KNOCKING',
  BETWEEN_FRAMES: 'BETWEEN_FRAMES',
  FINAL: 'FINAL',
});

const game = {
  state: State.TITLE,
  frame: 1, // 1..10
  ballInFrame: 1, // 1..3 (3 only possible in 10th)
  pinsRemaining: 10,
  pinsKnocked: new Set(), // for current frame
  rolls: [], // flat roll history (USBC-compatible)
  consecutiveStrikes: 0,

  // Aim controls
  aim: 0, // -1..1 (lane position)
  curve: 0, // -1..1 (hook/slice)
  power: 0, // 0..1, oscillates while in POWER state
  powerDir: 1,

  // Active ball animation
  ball: null, // { t: 0..1, startX, endX, startedAt }
  ballTrajectory: null, // computed at BOWL start

  // Particle bursts for celebration
  particles: [],

  // Countdown
  countdownValue: null,

  // Pin fall timings (id → 0..1 progress)
  fallingPins: new Map(),

  // Callout text + style class
  callout: null,
};

// ===== DOM refs =====

const $ = (id) => document.getElementById(id);
const canvas = $('lane');
const ctx = canvas.getContext('2d');

const screens = {
  title: $('screen-title'),
  howto: $('screen-howto'),
  game: $('screen-game'),
  final: $('screen-final'),
};

const hud = {
  frame: $('hud-frame-num'),
  ball: $('hud-ball-num'),
  score: $('hud-score-value'),
  status: $('status-line'),
};

const meters = {
  aimFill: $('meter-aim-fill'),
  curveFill: $('meter-curve-fill'),
  powerFill: $('meter-power-fill'),
};

// ===== Screen transitions =====

function showScreen(name) {
  for (const [k, el] of Object.entries(screens)) {
    el.classList.toggle('hidden', k !== name);
  }
  if (name === 'title' || name === 'howto' || name === 'final') {
    setFocusMode('menu');
    requestAnimationFrame(focusFirst);
  } else {
    setFocusMode('game');
  }
}

// ===== Game flow =====

function newGame() {
  game.state = State.COUNTDOWN;
  game.frame = 1;
  game.ballInFrame = 1;
  game.pinsRemaining = 10;
  game.pinsKnocked = new Set();
  game.rolls = [];
  game.consecutiveStrikes = 0;
  game.aim = 0;
  game.curve = 0;
  game.power = 0;
  game.powerDir = 1;
  game.particles = [];
  game.fallingPins = new Map();
  game.callout = null;
  showScreen('game');
  updateHud();
  startCountdown();
}

function startCountdown() {
  game.state = State.COUNTDOWN;
  game.aim = 0;
  game.curve = 0;
  game.power = 0;
  game.powerDir = 1;
  game.countdownValue = 3;
  setStatus(`Frame ${game.frame} · get ready…`);

  const step = (n) => {
    game.countdownValue = n;
    if (n === 0) {
      game.countdownValue = null;
      game.state = State.AIM;
      setStatus('Aim ◄ ► · Curve ▲ ▼ · Enter to lock');
      return;
    }
    setTimeout(() => step(n - 1), 550);
  };
  step(3);
}

function lockAimEnterPower() {
  if (game.state !== State.AIM) return;
  game.state = State.POWER;
  game.power = 0;
  game.powerDir = 1;
  setStatus('Hold steady · Enter to RELEASE');
}

function releaseBall() {
  if (game.state !== State.POWER) return;
  // Snapshot the launch intent.
  const launch = {
    aim: game.aim,
    curve: game.curve,
    power: Math.max(0.15, game.power), // tiny floor so you don't get 0-velocity stalls
  };
  game.state = State.BOWL;
  game.ball = { t: 0, startedAt: performance.now() };
  game.ballTrajectory = launch;
  setStatus('Rolling…');
}

function computeImpact(launch) {
  // Compute the ball's final lateral position at depth=1 (the back wall),
  // accounting for the curve. The curve accelerates late, mimicking a hook.
  const finalX = launch.aim + launch.curve * 0.35;
  return { finalX, launch };
}

function pinKnockedByBall(pin, launch) {
  // Compute the ball's lateral position when it passes this pin's depth.
  // Path is parametric on depth d ∈ [0,1]:
  //   x(d) = aim + curve * 0.35 * d^1.6     (curve effect biases late)
  const d = pin.depth;
  const ballX = launch.aim + launch.curve * 0.35 * Math.pow(d, 1.6);
  return Math.abs(ballX - pin.x) < HIT_RADIUS;
}

/**
 * Pure pin-knockdown calculation. Given the launch intent and which pins are
 * still standing, return a Set of pin IDs newly toppled this roll.
 * Deterministic — same input → same output (fixes the iOS jitter bug).
 */
function calculateKnockdown(launch, standingIds) {
  const knocked = new Set();

  // First pass: direct ball hits.
  for (const pin of PINS) {
    if (!standingIds.has(pin.id)) continue;
    if (pinKnockedByBall(pin, launch)) {
      knocked.add(pin.id);
    }
  }

  // Cascade: each knocked pin may topple neighbors. Strength of cascade
  // scales with power. Iterate until no new pins fall.
  const cascadeStrength = launch.power; // 0..1
  let changed = true;
  while (changed) {
    changed = false;
    for (const id of [...knocked]) {
      for (const n of PIN_NEIGHBORS[id] || []) {
        if (knocked.has(n) || !standingIds.has(n)) continue;
        // Deterministic threshold per (id, n) pair based on cascade strength.
        // The further down the pyramid, the harder to topple from afar.
        const threshold = 0.42 + (n > id ? 0.05 : 0);
        if (cascadeStrength > threshold) {
          knocked.add(n);
          changed = true;
        }
      }
    }
  }

  // Gutter check: if ball passed outside the lane (|aim+effective curve| > 0.7),
  // it's a gutter ball — zero knockdowns regardless of the above.
  const finalX = launch.aim + launch.curve * 0.35;
  if (Math.abs(finalX) > 0.7) return new Set();

  return knocked;
}

function handleSettle() {
  // Ball reached the back of the lane. Compute knockdown and play it.
  const standing = new Set(PINS.map((p) => p.id).filter((id) => !game.pinsKnocked.has(id)));
  const knocked = calculateKnockdown(game.ballTrajectory, standing);
  const count = knocked.size;

  // Stage the falling pins for the knock animation.
  game.fallingPins = new Map();
  let delay = 0;
  for (const id of knocked) {
    game.fallingPins.set(id, { progress: 0, startDelay: delay });
    delay += 40;
  }

  // Update model state.
  for (const id of knocked) game.pinsKnocked.add(id);
  game.pinsRemaining -= count;
  game.rolls.push(count);
  game.state = State.KNOCKING;

  // Detect strike / spare / open.
  // Strike rules per Swift port: a strike means knocking all 10 on a fresh rack.
  // True on ball 1 of frames 1–9, AND on 10th-frame fill balls when the rack
  // was just refreshed by a prior strike/spare.
  const wasFullRack = count === 10 && standing.size === 10;
  const isStrike = wasFullRack && (game.ballInFrame === 1 || rackJustResetIn10th());
  const isSpare = !isStrike && game.pinsRemaining === 0 && count > 0;
  const isGutter = count === 0;

  if (isStrike) game.consecutiveStrikes += 1;
  else if (count !== 0) game.consecutiveStrikes = 0;

  // Callout.
  if (isGutter) {
    showCallout('GUTTER', 'gutter');
  } else if (isStrike) {
    if (game.consecutiveStrikes >= 3) {
      showCallout('TURKEY 🔥', 'turkey');
      burstParticles();
    } else if (game.consecutiveStrikes === 2) {
      showCallout('DOUBLE', '');
    } else {
      showCallout('STRIKE!', '');
    }
  } else if (isSpare) {
    showCallout('SPARE', '');
  }

  setStatus(
    isGutter
      ? `Gutter ball · ${score()} total`
      : `${count} pin${count === 1 ? '' : 's'} · ${score()} total`
  );

  // After the knock animation finishes, advance state.
  setTimeout(() => transitionAfterKnock(), 1100);
}

function rackJustResetIn10th() {
  if (game.frame !== TOTAL_FRAMES) return false;
  const tenth = tenthFrameRolls(game.rolls);
  // Rack-reset moments in the 10th: after a strike on ball 1 (rack reset for ball 2),
  // after a double on balls 1&2 (rack reset for ball 3), after a spare on balls 1&2.
  // 'tenth' here doesn't include the current ball yet because we push AFTER state.
  // Wait — game.rolls already includes the current ball at this point. So subtract it.
  const beforeCurrent = tenth.slice(0, tenth.length - 1);
  if (beforeCurrent.length === 1 && beforeCurrent[0] === 10) return true; // ball 2 after strike
  if (beforeCurrent.length === 2) {
    if (beforeCurrent[0] === 10 && beforeCurrent[1] === 10) return true; // ball 3 after double
    if (beforeCurrent[0] !== 10 && beforeCurrent[0] + beforeCurrent[1] === 10) return true; // ball 3 after spare
  }
  return false;
}

function transitionAfterKnock() {
  if (isFinalRoll(game.rolls, game.frame)) {
    endGame();
    return;
  }
  if (game.frame < TOTAL_FRAMES) {
    transitionFramesOneToNine();
  } else {
    transitionTenthFrame();
  }
}

function transitionFramesOneToNine() {
  const lastRoll = game.rolls[game.rolls.length - 1];
  const strikeOnBall1 = game.ballInFrame === 1 && lastRoll === 10;
  const frameOver = strikeOnBall1 || game.ballInFrame === 2;
  if (frameOver) {
    advanceFrameWithReset();
  } else {
    game.ballInFrame = 2;
    setStatus(`${game.pinsRemaining} left · aim again`);
    updateHud();
    game.state = State.AIM;
  }
}

function transitionTenthFrame() {
  const tenth = tenthFrameRolls(game.rolls);
  if (tenth.length === 1) {
    if (tenth[0] === 10) {
      resetRackThenAdvanceTenth(2);
    } else {
      game.ballInFrame = 2;
      setStatus(`${game.pinsRemaining} left · aim again`);
      updateHud();
      game.state = State.AIM;
    }
  } else if (tenth.length === 2) {
    const [r1, r2] = tenth;
    if (r1 === 10) {
      if (r2 === 10) resetRackThenAdvanceTenth(3);
      else {
        game.ballInFrame = 3;
        setStatus(`${game.pinsRemaining} left · fill ball`);
        updateHud();
        game.state = State.AIM;
      }
    } else if (r1 + r2 === 10) {
      resetRackThenAdvanceTenth(3);
    } else {
      endGame();
    }
  } else {
    endGame();
  }
}

function advanceFrameWithReset() {
  game.state = State.BETWEEN_FRAMES;
  setTimeout(() => {
    game.frame += 1;
    game.ballInFrame = 1;
    game.pinsRemaining = 10;
    game.pinsKnocked = new Set();
    game.fallingPins = new Map();
    setStatus(`Frame ${game.frame} · get ready…`);
    updateHud();
    startCountdown();
  }, 600);
}

function resetRackThenAdvanceTenth(ball) {
  game.state = State.BETWEEN_FRAMES;
  setTimeout(() => {
    game.pinsRemaining = 10;
    game.pinsKnocked = new Set();
    game.fallingPins = new Map();
    game.ballInFrame = ball;
    setStatus(`Fresh rack · ball ${ball}`);
    updateHud();
    startCountdown();
  }, 600);
}

function endGame() {
  game.state = State.FINAL;
  $('final-score').textContent = String(score());
  renderScoreboard();
  showScreen('final');
}

// ===== Score & HUD =====

function score() {
  return computeScore(game.rolls);
}

function updateHud() {
  hud.frame.textContent = String(game.frame);
  hud.ball.textContent = String(game.ballInFrame);
  hud.score.textContent = String(score());
}

function setStatus(text) {
  hud.status.textContent = text;
}

function setMeters() {
  // Aim: -1..1, anchored center.
  const aimPct = (game.aim + 1) / 2;
  meters.aimFill.style.left = `${Math.min(50, aimPct * 100)}%`;
  meters.aimFill.style.width = `${Math.abs(game.aim) * 50}%`;
  // Curve: -1..1, anchored center.
  const curvePct = (game.curve + 1) / 2;
  meters.curveFill.style.left = `${Math.min(50, curvePct * 100)}%`;
  meters.curveFill.style.width = `${Math.abs(game.curve) * 50}%`;
  // Power: 0..1, anchored left.
  meters.powerFill.style.width = `${game.power * 100}%`;
}

function renderScoreboard() {
  const cells = frameDisplays(game.rolls, game.frame, game.state === State.FINAL);
  const sb = $('scoreboard');
  sb.innerHTML = '';
  for (const cell of cells) {
    const div = document.createElement('div');
    div.className = 'scoreboard-cell' + (cell.isCurrent ? ' is-current' : '');
    const rolls = document.createElement('div');
    rolls.className = 'cell-rolls';
    for (const r of cell.rolls) {
      const span = document.createElement('span');
      span.textContent = r;
      rolls.appendChild(span);
    }
    const total = document.createElement('div');
    total.className = 'cell-total';
    total.textContent = cell.cumulative != null ? String(cell.cumulative) : '';
    div.appendChild(rolls);
    div.appendChild(total);
    sb.appendChild(div);
  }
}

// ===== Callouts =====

function showCallout(text, className) {
  let el = document.querySelector('.callout');
  if (!el) {
    el = document.createElement('div');
    el.className = 'callout';
    screens.game.appendChild(el);
  }
  el.textContent = text;
  el.className = 'callout';
  if (className) el.classList.add(className);
  // Trigger reflow then animate.
  void el.offsetWidth;
  el.classList.add('visible');
  setTimeout(() => el.classList.remove('visible'), 900);
}

function burstParticles() {
  const colors = ['#00ff88', '#ffb800', '#ff3ec9', '#00e5ff', '#ffffff'];
  for (let i = 0; i < 40; i++) {
    const angle = (Math.PI * 2 * i) / 40 + Math.random() * 0.2;
    const speed = 2 + Math.random() * 2;
    game.particles.push({
      x: 300,
      y: 220,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      life: 1,
      color: colors[i % colors.length],
    });
  }
}

// ===== Input =====

document.addEventListener('keydown', (e) => {
  // Menu screens use the shared focus.js handler. We only handle game-state input.
  if (game.state === State.TITLE || game.state === State.HOWTO || game.state === State.FINAL) {
    return;
  }
  const k = e.key;

  if (game.state === State.AIM) {
    if (k === 'ArrowLeft') {
      e.preventDefault();
      game.aim = Math.max(-1, game.aim - 0.06);
    } else if (k === 'ArrowRight') {
      e.preventDefault();
      game.aim = Math.min(1, game.aim + 0.06);
    } else if (k === 'ArrowUp') {
      e.preventDefault();
      game.curve = Math.max(-1, game.curve - 0.08);
    } else if (k === 'ArrowDown') {
      e.preventDefault();
      game.curve = Math.min(1, game.curve + 0.08);
    } else if (k === 'Enter') {
      e.preventDefault();
      lockAimEnterPower();
    }
  } else if (game.state === State.POWER) {
    if (k === 'Enter') {
      e.preventDefault();
      releaseBall();
    }
  }
});

// Menu button clicks (also triggered by Enter via focus.js)
document.addEventListener('click', (e) => {
  const btn = e.target.closest('[data-action]');
  if (!btn) return;
  switch (btn.dataset.action) {
    case 'start-game':
      newGame();
      break;
    case 'show-howto':
      game.state = State.HOWTO;
      showScreen('howto');
      break;
    case 'back-to-title':
      game.state = State.TITLE;
      showScreen('title');
      break;
    case 'play-again':
      newGame();
      break;
  }
});

// ===== Render loop =====

const TICK_MS = 33;
const BOWL_DURATION_MS = 1400;

function tick() {
  // Update animations.
  if (game.state === State.POWER) {
    // Oscillate the power meter.
    game.power += 0.045 * game.powerDir;
    if (game.power >= 1) {
      game.power = 1;
      game.powerDir = -1;
    } else if (game.power <= 0) {
      game.power = 0;
      game.powerDir = 1;
    }
  }
  if (game.state === State.BOWL) {
    const elapsed = performance.now() - game.ball.startedAt;
    game.ball.t = Math.min(1, elapsed / BOWL_DURATION_MS);
    if (game.ball.t >= 1) {
      handleSettle();
    }
  }
  if (game.state === State.KNOCKING || game.state === State.BETWEEN_FRAMES) {
    for (const [id, fp] of game.fallingPins) {
      if (fp.startDelay > 0) {
        fp.startDelay -= TICK_MS;
      } else {
        fp.progress = Math.min(1, fp.progress + 0.06);
      }
    }
  }
  // Advance particles.
  for (const p of game.particles) {
    p.x += p.vx;
    p.y += p.vy;
    p.vy += 0.08; // gravity
    p.life -= 0.02;
  }
  game.particles = game.particles.filter((p) => p.life > 0);

  setMeters();
  render();
}

function render() {
  ctx.clearRect(0, 0, canvas.width, canvas.height);

  // 1. Lane.
  drawLane(ctx, canvas.width, canvas.height);

  // 2. Pins. Standing first, then falling/fallen.
  for (const pin of PINS) {
    const knocked = game.pinsKnocked.has(pin.id);
    const fp = game.fallingPins.get(pin.id);
    const standing = !knocked || (fp && fp.startDelay > 0);
    const scale = scaleForDepth(pin.depth);
    const x = xForLanePos(pin.x, pin.depth, canvas.width);
    const y = yForDepth(pin.depth, canvas.height);
    drawPin(ctx, x, y, scale, standing);
  }

  // 3. Aim indicator (a faint line from bowler position to projected impact).
  if (game.state === State.AIM || game.state === State.POWER) {
    drawAimIndicator();
  }

  // 4. Ball.
  if (game.state === State.BOWL && game.ball) {
    const t = game.ball.t;
    const depth = t;
    const lanePos = game.ballTrajectory.aim + game.ballTrajectory.curve * 0.35 * Math.pow(depth, 1.6);
    const x = xForLanePos(lanePos, depth, canvas.width);
    const y = yForDepth(depth, canvas.height);
    drawBall(ctx, x, y, scaleForDepth(depth));
  } else if (game.state === State.AIM || game.state === State.POWER) {
    // Ball waiting at the bowler's foul line.
    const x = xForLanePos(game.aim, 0, canvas.width);
    const y = yForDepth(0, canvas.height);
    drawBall(ctx, x, y, scaleForDepth(0));
  }

  // 5. Particles.
  drawParticles(ctx, game.particles);

  // 6. Countdown overlay (drawn on canvas so it lives over the lane).
  if (game.state === State.COUNTDOWN && game.countdownValue) {
    ctx.save();
    ctx.fillStyle = '#00e5ff';
    ctx.shadowColor = 'rgba(0, 229, 255, 0.8)';
    ctx.shadowBlur = 40;
    ctx.font = 'bold 140px ui-monospace, monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(String(game.countdownValue), canvas.width / 2, canvas.height / 2);
    ctx.restore();
  }
}

function drawAimIndicator() {
  const startX = xForLanePos(game.aim, 0, canvas.width);
  const startY = yForDepth(0, canvas.height);
  // Sample 8 points along the curve trajectory.
  ctx.save();
  ctx.strokeStyle = 'rgba(255, 62, 201, 0.55)';
  ctx.lineWidth = 2;
  ctx.setLineDash([4, 4]);
  ctx.beginPath();
  ctx.moveTo(startX, startY);
  for (let i = 1; i <= 16; i++) {
    const d = i / 16;
    const lanePos = game.aim + game.curve * 0.35 * Math.pow(d, 1.6);
    ctx.lineTo(xForLanePos(lanePos, d, canvas.width), yForDepth(d, canvas.height));
  }
  ctx.stroke();
  ctx.setLineDash([]);
  ctx.restore();
}

// ===== Boot =====

setInterval(tick, TICK_MS);
showScreen('title');
