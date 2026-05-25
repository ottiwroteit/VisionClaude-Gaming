/**
 * D-pad focus management for Meta Display webapps.
 *
 * The Neural Band emits standard keydown events:
 *   ArrowUp / ArrowDown / ArrowLeft / ArrowRight  → focus navigation
 *   Enter                                          → activate focused element
 *
 * Pattern lifted from the Meta Snake sample (examples/snake/app.js):
 * tag interactive elements with the `.focusable` class; this module
 * cycles focus through the visible ones based on D-pad direction and
 * triggers a click on the focused element when Enter is pressed.
 *
 * Games that have their own in-game arrow-key handling should call
 * `setMode('game')` while playing and `setMode('menu')` while showing a
 * menu/overlay. In 'game' mode the focus manager is a no-op and arrow
 * keys flow straight through to the game's own handlers.
 */

let mode = 'menu'; // 'menu' | 'game'

export function setMode(next) {
  mode = next;
}

export function getMode() {
  return mode;
}

function getVisibleFocusables() {
  return Array.from(document.querySelectorAll('.focusable')).filter((el) => {
    const style = getComputedStyle(el);
    if (style.display === 'none' || style.visibility === 'hidden') return false;
    if (el.offsetParent === null && style.position !== 'fixed') return false;
    return true;
  });
}

function currentIndex(focusables) {
  return focusables.indexOf(document.activeElement);
}

function focusAt(focusables, idx) {
  const i = (idx + focusables.length) % focusables.length;
  focusables[i].focus();
}

document.addEventListener('keydown', (e) => {
  if (mode !== 'menu') return;
  const focusables = getVisibleFocusables();
  if (focusables.length === 0) return;
  const idx = currentIndex(focusables);

  switch (e.key) {
    case 'ArrowDown':
    case 'ArrowRight':
      e.preventDefault();
      focusAt(focusables, idx < 0 ? 0 : idx + 1);
      break;
    case 'ArrowUp':
    case 'ArrowLeft':
      e.preventDefault();
      focusAt(focusables, idx < 0 ? 0 : idx - 1);
      break;
    case 'Enter':
      e.preventDefault();
      if (idx >= 0) focusables[idx].click();
      break;
  }
});

/**
 * Move focus to the first .focusable element. Call this when transitioning
 * to a menu so the user has something selected to operate on with the D-pad.
 */
export function focusFirst() {
  const focusables = getVisibleFocusables();
  if (focusables.length > 0) focusables[0].focus();
}
