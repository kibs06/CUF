/**
 * Where a context menu goes, given where the pointer was.
 *
 * A right-click menu is positioned by a number the browser hands you — the
 * pointer — and a menu is a box with a size, so the arithmetic is a rule rather
 * than a component's business: it is the same question for every surface in the
 * portal, it has edges that only show up on the pages nobody tests by hand (a
 * row at the very bottom of a long list, a phone in landscape), and it can be
 * proved without a browser.
 *
 * The behaviour, in the order it matters:
 *
 *  1. **Hang the menu from the pointer, down and to the right** — the ordinary
 *     desktop convention, and the placement that keeps the menu's top-left under
 *     the cursor so the first item is the one nearest it.
 *  2. **Flip rather than clamp when it would overflow.** A menu at the bottom of
 *     a list must open *upward*, not be pushed up until it is clamped flat
 *     against the viewport edge and its first item sits under the pointer. The
 *     flip is the menu's own width or height, so its edge lands exactly on the
 *     pointer.
 *  3. **Clamp afterwards, for the case a flip cannot fix** — a menu taller than
 *     the viewport (a long item list on a phone in landscape). Something has to
 *     be off screen then; the margin is what is left of the top.
 *
 * A zero or missing viewport is treated as unknown rather than as an error: the
 * caller may be measuring before layout, and a menu placed at the pointer is a
 * better default than one placed at the origin.
 */

/** The gap kept between a menu and the viewport edge, in CSS pixels. */
export const CONTEXT_MENU_MARGIN = 8

export function contextMenuPosition({
  x = 0,
  y = 0,
  width = 0,
  height = 0,
  viewport = {},
  margin = CONTEXT_MENU_MARGIN,
} = {}) {
  const pointerX = Number.isFinite(Number(x)) ? Number(x) : 0
  const pointerY = Number.isFinite(Number(y)) ? Number(y) : 0
  const menuWidth = Math.max(0, Number(width) || 0)
  const menuHeight = Math.max(0, Number(height) || 0)
  const gap = Math.max(0, Number(margin) || 0)

  const viewportWidth = Number(viewport?.width) || 0
  const viewportHeight = Number(viewport?.height) || 0

  let left = pointerX
  let flippedX = false
  if (viewportWidth > 0 && pointerX + menuWidth + gap > viewportWidth) {
    left = pointerX - menuWidth
    flippedX = true
  }

  let top = pointerY
  let flippedY = false
  if (viewportHeight > 0 && pointerY + menuHeight + gap > viewportHeight) {
    top = pointerY - menuHeight
    flippedY = true
  }

  if (viewportWidth > 0) {
    left = Math.min(Math.max(gap, left), Math.max(gap, viewportWidth - menuWidth - gap))
  }
  if (viewportHeight > 0) {
    top = Math.min(Math.max(gap, top), Math.max(gap, viewportHeight - menuHeight - gap))
  }

  return { left, top, flippedX, flippedY }
}
