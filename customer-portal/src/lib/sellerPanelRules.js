/**
 * The seller's side panel — the rules, kept pure so the state that decides
 * whether a drawer is docked can be tested without a browser.
 *
 * ## What the panel is
 *
 * Notifications and Messages open in a column on the right of the screen rather
 * than as a page you navigate to. A seller checking "has anything come in" is
 * doing it *from* the thing they were already doing — reading an order, editing
 * a size — and a full page navigation throws that context away and costs a back
 * press to get it back.
 *
 * ## Pin or not
 *
 *  * **Unpinned** — an overlay drawer over the page. It closes on Escape, on a
 *    click outside, and on navigation, because a drawer you did not ask to keep
 *    is a drawer that should get out of the way.
 *  * **Pinned** — docked beside the page, and it stays across navigation. The
 *    page content narrows instead of being covered, so a pinned panel and the
 *    page are read together: orders on the left, notifications on the right.
 *
 * Below `lg` there is nothing to dock beside — a column and a page cannot
 * share a phone's width — so a pinned panel falls back to the overlay there and
 * becomes a column again when the window is wide enough. That decision belongs
 * to the component, because it is about pixels, not about state.
 *
 * ## How wide it is, and how wide it is allowed to be
 *
 * The panel is draggable by its inner edge, and it can be expanded to its
 * ceiling with one click. Both of those end at the same wall, which is the point
 * of the words "with limitations": a panel that can be dragged arbitrarily wide
 * is a panel that becomes the page, and the reason this exists at all is that the
 * page and the panel are supposed to be read *together*. So there are three
 * numbers, all in rem:
 *
 *  * **16rem is the floor** — the width at which a notification card still has a
 *    title and a body and not a column of single words.
 *  * **22rem is where it starts**, which is what the panel has always been.
 *  * **40rem is the ceiling**, and it is not the real one: the real one depends
 *    on the window. Docked, the panel may take **55%** of it — past that the page
 *    it is docked beside stops being a page. Over the page it may take **92%**,
 *    which leaves a strip of the thing behind it visible on purpose: a drawer
 *    that covers the window completely is a navigation, and this exists so that
 *    it does not have to be one.
 *
 * The seller's own width is remembered, and the window's ceiling is applied when
 * it is *drawn* rather than when it is saved — so a panel widened on a big screen
 * does not store a number that breaks a small one, and shrinking the window and
 * widening it again gives the width back rather than the floor.
 */

/** The two panels. A closed panel is `null`, never a third name. */
export const SELLER_PANEL_IDS = ['notifications', 'messages']

/** What the panel's own header calls each one. */
const PANEL_TITLES = {
  notifications: 'Notifications',
  messages: 'Messages',
}

/** The full page each panel is the quick view of, for its "open as page" link. */
const PANEL_PAGES = {
  notifications: '/seller/notifications',
  messages: '/seller/messages',
}

/**
 * The panel's width limits, in rem.
 *
 * `min` and `max` are the walls the seller can hit; the window can lower the
 * ceiling further, through `panelMaxRem`. `default` is where every panel starts
 * and where the first one ever drew.
 */
export const PANEL_WIDTH = {
  min: 16,
  default: 22,
  max: 40,
}

/** How much of the window each form may take, as a fraction of its width. */
const DOCKED_SHARE = 0.55
const OVERLAY_SHARE = 0.92

/**
 * The widest this panel may be on this window, in rem.
 *
 * Docked gets the smaller share on purpose: there is a page beside it that has
 * to keep being readable, and the whole argument for docking is that both are
 * legible at once. The overlay gets 92%, because 8% of the page showing through
 * is what stops a drawer from becoming a navigation.
 *
 * A missing or nonsense viewport answers `PANEL_WIDTH.max`. There is no window
 * on a server, and "assume there is room" is the honest default there because
 * the element also carries a CSS `max-width` — the JavaScript ceiling is the
 * belt, and the stylesheet is the braces for the frame before it is measured.
 */
export function panelMaxRem(viewportRem, { docked = false } = {}) {
  const share = docked ? DOCKED_SHARE : OVERLAY_SHARE
  if (!Number.isFinite(viewportRem) || viewportRem <= 0) return PANEL_WIDTH.max
  return Math.max(PANEL_WIDTH.min, Math.min(PANEL_WIDTH.max, viewportRem * share))
}

/**
 * A width as a number of rem, snapped to a quarter and inside the fixed walls.
 *
 * The snapping is what keeps a drag from writing `22.318181818181817rem` into
 * storage and a style attribute on every pointer move: a quarter of a rem is
 * finer than anyone can aim at with a mouse, and it makes the value something a
 * test can assert on.
 */
export function normalizePanelWidth(value) {
  /*
    Only a number or a numeric string counts. `Number(null)`, `Number(false)`
    and `Number('')` are all `0`, which would pass a bare `isFinite` and land on
    the floor — a missing width silently becoming the narrowest panel.
  */
  const numeric = typeof value === 'number' || (typeof value === 'string' && value.trim() !== '')
  const rem = numeric ? Number(value) : NaN
  if (!Number.isFinite(rem)) return PANEL_WIDTH.default
  const snapped = Math.round(rem * 4) / 4
  return Math.min(PANEL_WIDTH.max, Math.max(PANEL_WIDTH.min, snapped))
}

/**
 * A width made to fit this window's ceiling.
 *
 * The ceiling is clamped *after* the snapping, not before: a window 1024px wide
 * gives a docked ceiling of 35.2rem, and snapping that to 35.25 would be a panel
 * two pixels wider than the rule allows. The stored width is never touched by
 * this — see the module docblock.
 */
export function clampPanelWidth(width, maxRem = PANEL_WIDTH.max) {
  const ceiling = Number.isFinite(maxRem) ? Math.max(PANEL_WIDTH.min, maxRem) : PANEL_WIDTH.max
  return Math.min(ceiling, normalizePanelWidth(width))
}

/** How far one arrow key moves the panel. */
export const PANEL_RESIZE_STEP_REM = 1

/**
 * The width a keypress asks for, or `null` if the key means nothing here.
 *
 * Arrow **left** widens the panel, because the panel is on the right and its
 * grab is on its left edge: the arrow follows the edge being moved, which is the
 * same thing the pointer does. Home and End are the two walls, and they are the
 * reason a keyboard can reach every width a mouse can.
 */
export function panelWidthForKey({ key, width, maxRem } = {}) {
  switch (key) {
    case 'ArrowLeft':
      return clampPanelWidth(normalizePanelWidth(width) + PANEL_RESIZE_STEP_REM, maxRem)
    case 'ArrowRight':
      return clampPanelWidth(normalizePanelWidth(width) - PANEL_RESIZE_STEP_REM, maxRem)
    case 'Home':
      return clampPanelWidth(PANEL_WIDTH.min, maxRem)
    case 'End':
      return clampPanelWidth(PANEL_WIDTH.max, maxRem)
    default:
      return null
  }
}

/**
 * The width to draw at: the expanded ceiling, or the seller's own width.
 *
 * `expanded` and `width` are two separate facts on purpose. Expanding is not
 * "set the width to 40rem" — that would throw away the width the seller had
 * chosen, and collapsing would then have to guess it back. So the choice is kept
 * underneath, and collapsing restores it for free.
 */
export function appliedPanelWidth({ width, expanded, maxRem } = {}) {
  if (expanded === true) return clampPanelWidth(PANEL_WIDTH.max, maxRem)
  return clampPanelWidth(width, maxRem)
}

/** `notifications` / `messages` / `null` — anything else is no panel at all. */
export function normalizePanelId(value) {
  const id = String(value ?? '').trim().toLowerCase()
  return SELLER_PANEL_IDS.includes(id) ? id : null
}

export function sellerPanelTitle(panel) {
  return PANEL_TITLES[normalizePanelId(panel)] ?? ''
}

/** The page a panel stands in for, or `null` for a panel with no page. */
export function sellerPanelPage(panel) {
  return PANEL_PAGES[normalizePanelId(panel)] ?? null
}

/**
 * The state to start from, from whatever was last written to storage.
 *
 * `pinned` is remembered and `panel` is remembered **only when pinned**. An
 * unpinned panel is a transient thing — a drawer someone opened and did not ask
 * to keep — so restoring one on the next visit would be the site reopening a
 * drawer at somebody who had closed the tab on it. A pinned one is a layout
 * choice, and a layout choice that is forgotten on every reload is not one.
 *
 * Every field is individually defended: this parses a string a previous version
 * of the app (or a person with devtools) wrote, so a missing field, a wrong type
 * and a JSON syntax error all have to land on a sane state rather than throw
 * during the first render of the shell.
 */
export function normalizePanelState(raw) {
  const fallback = { pinned: false, panel: null, width: PANEL_WIDTH.default, expanded: false }
  if (!raw) return fallback

  let parsed = raw
  if (typeof raw === 'string') {
    try {
      parsed = JSON.parse(raw)
    } catch {
      return fallback
    }
  }

  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return fallback

  const pinned = parsed.pinned === true
  const panel = normalizePanelId(parsed.panel)
  /*
    The width and the expansion are remembered whether or not the panel is. An
    unpinned drawer is forgotten because reopening one is presumptuous; how wide
    the seller likes this panel is not — it is the same layout choice the pin is,
    and it is stated again the moment they open one.
  */
  const width = normalizePanelWidth(parsed.width)
  const expanded = parsed.expanded === true

  return { pinned, panel: pinned ? panel : null, width, expanded }
}

/** What to store for a state — the inverse of `normalizePanelState`. */
export function serializePanelState(state) {
  return JSON.stringify(normalizePanelState(state))
}

/**
 * Whether a panel is currently *docked*, as opposed to drawn over the page.
 *
 * Three things have to be true and all three are load-bearing: a panel is open,
 * it is pinned, and there is room beside the page for it. Any one of them
 * missing and the panel is an overlay — which is the state that always works,
 * and therefore the one to fail into.
 */
export function isPanelDocked({ panel, pinned, wide } = {}) {
  return Boolean(normalizePanelId(panel)) && pinned === true && wide === true
}
