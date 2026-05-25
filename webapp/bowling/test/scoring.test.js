/**
 * USBC-spec bowling scoring tests. Run with:
 *   node --test webapp/bowling/test/scoring.test.js
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  computeScore,
  frameDisplays,
  tenthFrameRolls,
  isFinalRoll,
  TOTAL_FRAMES,
} from '../scoring.js';

test('gutter game scores 0', () => {
  const rolls = Array(20).fill(0);
  assert.equal(computeScore(rolls), 0);
});

test('all ones game scores 20', () => {
  const rolls = Array(20).fill(1);
  assert.equal(computeScore(rolls), 20);
});

test('perfect game scores 300', () => {
  // 12 strikes (9 frames of 1 strike each + 3 strikes in 10th).
  const rolls = Array(12).fill(10);
  assert.equal(computeScore(rolls), 300);
});

test('all spares (5/5) with bonus 5 scores 150', () => {
  const rolls = [];
  for (let i = 0; i < 10; i++) rolls.push(5, 5);
  rolls.push(5); // bonus ball after 10th-frame spare
  assert.equal(computeScore(rolls), 150);
});

test('single strike in frame 1 with 3,4 next scores 24', () => {
  // Frame 1: strike → 10 + 3 + 4 = 17
  // Frame 2: 3 + 4 = 7
  // Total: 24
  const rolls = [10, 3, 4];
  assert.equal(computeScore(rolls), 24);
});

test('single spare in frame 1 with 7 next scores 24', () => {
  // Frame 1: spare → 10 + 7 = 17
  // Frame 2: 7 + 0 = 7  (only 7 played so far)
  // Total: 24
  const rolls = [6, 4, 7];
  assert.equal(computeScore(rolls), 24);
});

test('10th frame strike + two bonus rolls', () => {
  // 9 open frames of 4,5 each = 9 * 9 = 81
  // 10th frame: X 7 2 = 10+7+2 = 19
  // Total: 100
  const rolls = [];
  for (let i = 0; i < 9; i++) rolls.push(4, 5);
  rolls.push(10, 7, 2);
  assert.equal(computeScore(rolls), 100);
});

test('10th frame spare + one bonus roll', () => {
  // 9 open frames of 3,4 each = 9 * 7 = 63
  // 10th frame: 5 5 9 = 10 + 9 = 19  (spare bonus is the bonus ball itself)
  // Total: 82
  const rolls = [];
  for (let i = 0; i < 9; i++) rolls.push(3, 4);
  rolls.push(5, 5, 9);
  assert.equal(computeScore(rolls), 82);
});

test('10th frame triple strike', () => {
  // 9 open frames of 8,1 each = 81
  // 10th: X X X = 30
  // Total: 111
  const rolls = [];
  for (let i = 0; i < 9; i++) rolls.push(8, 1);
  rolls.push(10, 10, 10);
  assert.equal(computeScore(rolls), 111);
});

test('partial game scores only what is played', () => {
  // Just 3 frames in: 7,2 / 10 / 4,3
  // F1 open: 9
  // F2 strike: 10 + 4 + 3 = 17
  // F3 open: 7
  // Total: 33
  const rolls = [7, 2, 10, 4, 3];
  assert.equal(computeScore(rolls), 33);
});

test('strike with only 1 bonus ball known yet does not finalize that frame', () => {
  const rolls = [10, 5];
  // Running total reflects all pins down (10 + bonus 5 + frame-2 ball 5 = 20).
  // But Frame 1's CUMULATIVE cell on the scoreboard stays null until 2
  // bonus balls are known — that's the real "doesn't finalize" check.
  assert.equal(computeScore(rolls), 20);
  const cells = frameDisplays(rolls, 2, false);
  assert.equal(cells[0].cumulative, null, 'F1 should be pending until 2 bonus rolls known');
});

test('strike with 2 bonus balls finalizes that frame', () => {
  const rolls = [10, 5, 3];
  const cells = frameDisplays(rolls, 2, false);
  assert.equal(cells[0].cumulative, 18);
  assert.equal(cells[1].cumulative, 26);
});

test('spare with bonus ball finalizes that frame', () => {
  const rolls = [7, 3, 6];
  const cells = frameDisplays(rolls, 2, false);
  assert.equal(cells[0].cumulative, 16); // 10 + 6
  assert.equal(cells[1].cumulative, null); // F2 only has ball 1
});

test('frameDisplays pads to 10 cells', () => {
  const cells = frameDisplays([10], 1, false);
  assert.equal(cells.length, TOTAL_FRAMES);
});

test('frameDisplays marks current frame', () => {
  const cells = frameDisplays([7, 2], 2, false);
  assert.equal(cells[1].isCurrent, true);
  assert.equal(cells[0].isCurrent, false);
});

test('tenthFrameRolls returns just the 10th-frame balls after 9 open frames', () => {
  const rolls = [];
  for (let i = 0; i < 9; i++) rolls.push(3, 4);
  rolls.push(10, 5, 5);
  assert.deepEqual(tenthFrameRolls(rolls), [10, 5, 5]);
});

test('tenthFrameRolls returns just the 10th-frame balls after 9 strikes', () => {
  const rolls = [10, 10, 10, 10, 10, 10, 10, 10, 10, 7, 3];
  assert.deepEqual(tenthFrameRolls(rolls), [7, 3]);
});

test('isFinalRoll: triple-strike 10th frame ends game', () => {
  const rolls = [];
  for (let i = 0; i < 9; i++) rolls.push(0, 0);
  rolls.push(10, 10, 10);
  assert.equal(isFinalRoll(rolls, 10), true);
});

test('isFinalRoll: open 10th frame ends game after 2 balls', () => {
  const rolls = [];
  for (let i = 0; i < 9; i++) rolls.push(0, 0);
  rolls.push(5, 4);
  assert.equal(isFinalRoll(rolls, 10), true);
});

test('isFinalRoll: spare 10th frame after just 2 balls is NOT final', () => {
  const rolls = [];
  for (let i = 0; i < 9; i++) rolls.push(0, 0);
  rolls.push(5, 5);
  assert.equal(isFinalRoll(rolls, 10), false);
});

test('isFinalRoll: strike on ball 1 of 10th is NOT final', () => {
  const rolls = [];
  for (let i = 0; i < 9; i++) rolls.push(0, 0);
  rolls.push(10);
  assert.equal(isFinalRoll(rolls, 10), false);
});
