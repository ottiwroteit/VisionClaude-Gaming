/**
 * Bowling scoring — USBC-spec, ported from the iOS implementation at
 * ClaudeVision/ios/ClaudeVision/Gaming/Games/BowlingGame.swift.
 *
 * Pure functions over a roll history (array of pins-knocked integers).
 * No side effects, no mutation, no DOM. Trivially testable.
 *
 *   computeScore([10, 10, 10, ...])         → 300 for a perfect game
 *   frameDisplays(rolls, currentFrame, end) → 10 cells for the scoreboard
 */

export const TOTAL_FRAMES = 10;

/**
 * Cumulative score so far, applying real strike/spare bonuses.
 *
 * Strike (frames 1–9): 10 + next 2 rolls.
 * Spare (frames 1–9):  10 + next 1 roll.
 * Open frame:          just sum the two balls.
 * 10th frame:          sum of all balls played in the frame (1–3), no further lookahead.
 *
 * @param {number[]} rolls
 * @returns {number}
 */
export function computeScore(rolls) {
  let total = 0;
  let idx = 0;
  let f = 0;
  while (f < TOTAL_FRAMES && idx < rolls.length) {
    if (f === TOTAL_FRAMES - 1) {
      // 10th frame: take everything left in the array as that frame's rolls.
      for (let i = idx; i < rolls.length; i++) total += rolls[i];
      break;
    }
    const r1 = rolls[idx];
    if (r1 === 10) {
      // Strike: 10 + next 2 (regardless of frame boundary).
      total += 10;
      if (idx + 1 < rolls.length) total += rolls[idx + 1];
      if (idx + 2 < rolls.length) total += rolls[idx + 2];
      idx += 1;
    } else if (idx + 1 < rolls.length) {
      const r2 = rolls[idx + 1];
      total += r1 + r2;
      if (r1 + r2 === 10 && idx + 2 < rolls.length) {
        total += rolls[idx + 2];
      }
      idx += 2;
    } else {
      // Only one ball played in this open frame so far.
      total += r1;
      break;
    }
    f += 1;
  }
  return total;
}

/**
 * Return just the rolls that belong to the 10th frame.
 *
 * @param {number[]} rolls
 * @returns {number[]}
 */
export function tenthFrameRolls(rolls) {
  let idx = 0;
  let f = 0;
  while (f < TOTAL_FRAMES - 1 && idx < rolls.length) {
    if (rolls[idx] === 10) {
      idx += 1; // strike — single roll consumed
    } else if (idx + 1 < rolls.length) {
      idx += 2; // open or spare — two rolls consumed
    } else {
      return []; // still inside an earlier frame
    }
    f += 1;
  }
  if (idx > rolls.length) return [];
  return rolls.slice(idx);
}

/**
 * True if the 10th-frame roll array represents a completed frame
 * (i.e. the game is over).
 *
 * @param {number[]} frameRolls
 */
export function isFrame10Complete(frameRolls) {
  if (frameRolls.length >= 3) return true;
  if (frameRolls.length === 2) {
    return frameRolls[0] !== 10 && frameRolls[0] + frameRolls[1] !== 10;
  }
  return false;
}

/**
 * True if the just-completed roll ended the game.
 *
 * @param {number[]} rolls full roll history including the latest ball
 * @param {number} frame  current frame at the time of the roll
 */
export function isFinalRoll(rolls, frame) {
  if (frame !== TOTAL_FRAMES) return false;
  return isFrame10Complete(tenthFrameRolls(rolls));
}

/**
 * Render a single roll's pin count as a scoreboard label.
 *   10  → "X"   (strike — only used for ball 1 of frames 1–9)
 *   0   → "-"   (gutter / miss)
 *   1–9 → the digit
 */
function rollLabel(n) {
  if (n === 10) return 'X';
  if (n === 0) return '-';
  return String(n);
}

/**
 * Render the 10th-frame rolls. Spares get "/", strikes "X", misses "-".
 */
function renderTenthFrameLabels(frameRolls) {
  const out = [];
  for (let i = 0; i < frameRolls.length; i++) {
    const r = frameRolls[i];
    if (r === 10) {
      out.push('X');
    } else if (i === 1 && frameRolls[0] !== 10 && frameRolls[0] + r === 10) {
      out.push('/');
    } else if (
      i === 2 &&
      frameRolls[1] !== 10 &&
      frameRolls[0] !== 10 &&
      frameRolls[1] + r === 10
    ) {
      // Spare on balls 2+3 of 10th (edge case — won't occur with current
      // gameplay flow but stays here for safety).
      out.push('/');
    } else if (r === 0) {
      out.push('-');
    } else {
      out.push(String(r));
    }
  }
  return out;
}

/**
 * @typedef {Object} FrameDisplay
 * @property {number} number     1..10
 * @property {string[]} rolls    rendered labels for the rolls in this frame
 * @property {number|null} cumulative running total at this frame, or null if waiting on a bonus
 * @property {boolean} isCurrent
 */

/**
 * Build a 10-cell scoreboard from a roll history.
 *
 * @param {number[]} rolls
 * @param {number} currentFrame 1..10
 * @param {boolean} isFinished
 * @returns {FrameDisplay[]}
 */
export function frameDisplays(rolls, currentFrame, isFinished) {
  const out = [];
  let idx = 0;
  let running = 0;

  for (let f = 0; f < TOTAL_FRAMES; f++) {
    const isCurrent = currentFrame - 1 === f && !isFinished;

    if (idx >= rolls.length) {
      out.push({ number: f + 1, rolls: [], cumulative: null, isCurrent });
      continue;
    }

    if (f === TOTAL_FRAMES - 1) {
      const frameRolls = rolls.slice(idx);
      running += frameRolls.reduce((a, b) => a + b, 0);
      const labels = renderTenthFrameLabels(frameRolls);
      const total = isFrame10Complete(frameRolls) ? running : null;
      out.push({ number: 10, rolls: labels, cumulative: total, isCurrent });
      break;
    }

    const r1 = rolls[idx];
    if (r1 === 10) {
      // Strike — bonus needs the next 2 rolls.
      const b1 = idx + 1 < rolls.length ? rolls[idx + 1] : null;
      const b2 = idx + 2 < rolls.length ? rolls[idx + 2] : null;
      const total = b1 !== null && b2 !== null ? running + 10 + b1 + b2 : null;
      if (total !== null) running = total;
      out.push({ number: f + 1, rolls: ['', 'X'], cumulative: total, isCurrent });
      idx += 1;
    } else if (idx + 1 < rolls.length) {
      const r2 = rolls[idx + 1];
      const isSpare = r1 + r2 === 10;
      const r1Label = rollLabel(r1);
      const r2Label = isSpare ? '/' : rollLabel(r2);
      if (isSpare) {
        const bonus = idx + 2 < rolls.length ? rolls[idx + 2] : null;
        const total = bonus !== null ? running + 10 + bonus : null;
        if (total !== null) running = total;
        out.push({
          number: f + 1,
          rolls: [r1Label, r2Label],
          cumulative: total,
          isCurrent,
        });
      } else {
        running += r1 + r2;
        out.push({
          number: f + 1,
          rolls: [r1Label, r2Label],
          cumulative: running,
          isCurrent,
        });
      }
      idx += 2;
    } else {
      // Only ball 1 of an open frame so far — partial display.
      out.push({
        number: f + 1,
        rolls: [rollLabel(r1)],
        cumulative: null,
        isCurrent,
      });
      break;
    }
  }

  // Pad empty frames so the scoreboard always has 10 cells.
  while (out.length < TOTAL_FRAMES) {
    const n = out.length + 1;
    out.push({
      number: n,
      rolls: [],
      cumulative: null,
      isCurrent: currentFrame === n && !isFinished,
    });
  }
  return out;
}
