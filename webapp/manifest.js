/**
 * VisionClaude games manifest — single source of truth.
 *
 * Each entry maps a 6-digit SHARE CODE to a deployable game URL. The
 * code appears on the game's title screen; the share landing page
 * resolves the code back to the URL and triggers the add-to-glasses flow.
 *
 * Codes are intentionally simple sequentials starting at 100001 so they're
 * memorable (no "is that a 0 or an O" confusion — digits only).
 *
 * Add a game by appending to GAMES and bumping the next sequential code.
 */

export const HOST = 'https://visionclaude-bowling.vercel.app';

export const GAMES = [
  {
    id: 'bowling',
    name: 'Meta Bowling',
    shareCode: '100001',
    path: '/bowling/',
    blurb: '10-pin arcade · aim, curve, power.',
    emoji: '🎳',
  },
];

export function findByCode(code) {
  return GAMES.find((g) => g.shareCode === String(code).trim());
}

export function findById(id) {
  return GAMES.find((g) => g.id === id);
}

export function fullUrl(game) {
  return HOST + game.path;
}

/**
 * Construct the Meta AI deep-link that opens the "Add a web app" flow
 * on the user's paired phone with the game URL pre-filled.
 *
 * Format from
 *   /tmp/meta-wearables-webapp/plugins/meta-wearables-webapp/skills/publish-to-vercel/SKILL.md
 */
export function deepLink(game) {
  const url = encodeURIComponent(fullUrl(game));
  const name = encodeURIComponent(game.name);
  return `fb-viewapp://web_app_deep_link?appName=${name}&appUrl=${url}`;
}

/**
 * True if we're running on a phone where the deep-link can be triggered
 * directly. iOS Safari, Android Chrome, in-app browsers all match.
 */
export function isMobileBrowser() {
  if (typeof navigator === 'undefined') return false;
  return /iphone|ipad|ipod|android/i.test(navigator.userAgent);
}
