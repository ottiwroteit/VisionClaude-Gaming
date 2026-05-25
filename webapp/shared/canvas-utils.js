/**
 * Canvas2D helpers for Meta Display webapps.
 *
 * The display is ADDITIVE TRANSPARENT — black renders as see-through, and
 * the BRIGHTER the color the more visible it is. So we render with high
 * saturation and clear hard edges; gradients and soft shadows wash out.
 */

/**
 * Map a depth value (0 = near, 1 = far down the lane) to a perspective
 * scale factor. Used to shrink the ball and pins as they recede.
 */
export function scaleForDepth(depth) {
  // Near things are full size, far things shrink to ~30%.
  return 1.0 - depth * 0.7;
}

/**
 * Map a depth value to a y-coordinate on the canvas. Near = bottom,
 * far = top, with the vanishing point a bit below the top edge.
 *
 * @param {number} depth 0..1
 * @param {number} canvasH height of the canvas
 * @param {number} laneFarY y of the vanishing point (default 80)
 * @param {number} laneNearY y of the player-side line (default canvasH - 80)
 */
export function yForDepth(depth, canvasH, laneFarY = 80, laneNearY = null) {
  const near = laneNearY ?? canvasH - 80;
  return near + (laneFarY - near) * depth;
}

/**
 * Convert a lane-relative x position (-1 left gutter, 0 center, +1 right gutter)
 * to a canvas x coordinate, accounting for the perspective at the given depth.
 *
 * @param {number} lanePos -1..1
 * @param {number} depth 0..1
 * @param {number} canvasW
 */
export function xForLanePos(lanePos, depth, canvasW) {
  const centerX = canvasW / 2;
  // Lane is wider at the near end, narrower in the distance.
  const nearHalfWidth = canvasW * 0.42;
  const farHalfWidth = canvasW * 0.12;
  const halfWidth = nearHalfWidth + (farHalfWidth - nearHalfWidth) * depth;
  return centerX + lanePos * halfWidth;
}

/**
 * Draw a single bowling pin as a bright diamond+circle silhouette.
 * Pins are styled to read clearly on a transparent additive display.
 *
 * @param {CanvasRenderingContext2D} ctx
 * @param {number} x center x
 * @param {number} y center y
 * @param {number} scale perspective scale 0..1
 * @param {boolean} standing true if upright, false if knocked over
 */
export function drawPin(ctx, x, y, scale, standing) {
  const pinHeight = 38 * scale;
  const pinHeadR = 7 * scale;
  const pinWaistY = y - pinHeight * 0.45;
  const pinBaseY = y;

  ctx.save();
  ctx.translate(x, 0);
  if (!standing) {
    // Knocked-over pin lies on its side, faded.
    ctx.globalAlpha = 0.35;
    ctx.rotate(Math.PI / 2);
  }
  ctx.strokeStyle = '#ffffff';
  ctx.lineWidth = Math.max(1.5, 2.5 * scale);
  ctx.fillStyle = '#ffffff';
  // Body: pear-ish silhouette via two arcs and tapered base.
  ctx.beginPath();
  ctx.moveTo(0, pinBaseY - pinHeight);
  ctx.bezierCurveTo(
    -pinHeadR * 1.4,
    pinBaseY - pinHeight + pinHeight * 0.25,
    -pinHeadR * 1.4,
    pinWaistY,
    -pinHeadR * 0.7,
    pinWaistY + pinHeight * 0.18
  );
  ctx.bezierCurveTo(
    -pinHeadR * 1.6,
    pinWaistY + pinHeight * 0.35,
    -pinHeadR * 1.4,
    pinBaseY - 2 * scale,
    0,
    pinBaseY - 1 * scale
  );
  ctx.bezierCurveTo(
    pinHeadR * 1.4,
    pinBaseY - 2 * scale,
    pinHeadR * 1.6,
    pinWaistY + pinHeight * 0.35,
    pinHeadR * 0.7,
    pinWaistY + pinHeight * 0.18
  );
  ctx.bezierCurveTo(
    pinHeadR * 1.4,
    pinWaistY,
    pinHeadR * 1.4,
    pinBaseY - pinHeight + pinHeight * 0.25,
    0,
    pinBaseY - pinHeight
  );
  ctx.fill();
  ctx.stroke();
  // Red collar stripe.
  if (standing) {
    ctx.strokeStyle = '#ff3344';
    ctx.lineWidth = Math.max(1, 2 * scale);
    ctx.beginPath();
    ctx.moveTo(-pinHeadR * 1.1, pinBaseY - pinHeight + pinHeight * 0.45);
    ctx.lineTo(pinHeadR * 1.1, pinBaseY - pinHeight + pinHeight * 0.45);
    ctx.stroke();
  }
  ctx.restore();
}

/**
 * Draw the bowling ball as a bright magenta circle. Magenta reads well
 * on additive displays and contrasts the white pins.
 *
 * @param {CanvasRenderingContext2D} ctx
 * @param {number} x
 * @param {number} y
 * @param {number} scale
 */
export function drawBall(ctx, x, y, scale) {
  const r = 18 * scale;
  ctx.save();
  ctx.fillStyle = '#ff3ec9';
  ctx.shadowColor = 'rgba(255, 62, 201, 0.75)';
  ctx.shadowBlur = 16 * scale;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fill();
  // Highlight crescent for a touch of dimension.
  ctx.shadowBlur = 0;
  ctx.fillStyle = 'rgba(255, 255, 255, 0.7)';
  ctx.beginPath();
  ctx.arc(x - r * 0.3, y - r * 0.3, r * 0.35, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

/**
 * Draw the lane as bright cyan rails converging to the vanishing point.
 * Optional dashed center line for aim reference.
 */
export function drawLane(ctx, canvasW, canvasH) {
  const farY = 80;
  const nearY = canvasH - 80;
  const farHalf = canvasW * 0.12;
  const nearHalf = canvasW * 0.42;
  const cx = canvasW / 2;

  ctx.save();
  ctx.strokeStyle = 'rgba(0, 229, 255, 0.85)';
  ctx.lineWidth = 3;
  // Left rail
  ctx.beginPath();
  ctx.moveTo(cx - nearHalf, nearY);
  ctx.lineTo(cx - farHalf, farY);
  ctx.stroke();
  // Right rail
  ctx.beginPath();
  ctx.moveTo(cx + nearHalf, nearY);
  ctx.lineTo(cx + farHalf, farY);
  ctx.stroke();
  // Foul line
  ctx.strokeStyle = 'rgba(0, 229, 255, 0.5)';
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(cx - nearHalf, nearY - 12);
  ctx.lineTo(cx + nearHalf, nearY - 12);
  ctx.stroke();
  // Dashed center aim line
  ctx.strokeStyle = 'rgba(0, 229, 255, 0.35)';
  ctx.lineWidth = 1.5;
  ctx.setLineDash([6, 8]);
  ctx.beginPath();
  ctx.moveTo(cx, nearY);
  ctx.lineTo(cx, farY);
  ctx.stroke();
  ctx.setLineDash([]);
  ctx.restore();
}

/**
 * Draw a particle burst — used for strike celebration ("turkey") VFX.
 * Particles render as bright dots; the additive display loves them.
 *
 * @param {CanvasRenderingContext2D} ctx
 * @param {Array<{x:number,y:number,vx:number,vy:number,life:number,color:string}>} particles
 */
export function drawParticles(ctx, particles) {
  ctx.save();
  for (const p of particles) {
    ctx.fillStyle = p.color;
    ctx.globalAlpha = Math.max(0, p.life);
    ctx.beginPath();
    ctx.arc(p.x, p.y, 3, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
}
