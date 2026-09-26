/**
 * The theme wipe — the circle that carries an appearance change across the
 * screen.
 *
 * Switching theme is the one moment the entire page changes at once, and a page
 * that changes at once *flickers*: every token, shadow and hairline arrives in
 * the same frame, so the eye reads it as a repaint rather than as a choice
 * landing. The wipe gives the change a direction instead of a flash, and the
 * direction is the point:
 *
 *  * **Going light, the light grows from where the customer clicked** — the new
 *    theme arrives from the cursor and spreads until it covers the screen.
 *  * **Going dark, it is the reverse**: the light recedes *to* the cursor, and
 *    the dark is what is left behind. Not a dark circle growing backwards —
 *    that would leave a light ring at the edge of the screen for the whole
 *    animation and snap at the end.
 *
 * ## Why this is a rules module and not five lines in the provider
 *
 * The geometry is where this is easy to get subtly wrong: a radius that is too
 * small leaves a corner un-wiped (a light wedge in a dark page at the end of the
 * animation), an origin that is off by a scroll offset starts the circle in the
 * wrong place, and a pointer that never arrived (the customer used the keyboard)
 * has to fall back to something rather than to `NaN`. None of that needs a
 * browser to be worth being sure about, so all of it is pure.
 *
 * The animation itself is the View Transitions API — see `useTheme.jsx`. Where
 * that API is missing there is no wipe at all and the theme simply switches:
 * **the animation is a flourish on a change that has already happened**, never a
 * condition of it. See "Animations must fail open" in the README.
 *
 * ## Reduced motion, and the one exception in the codebase
 *
 * Everywhere else on this site, `prefers-reduced-motion` sends a duration to
 * **zero** — the customer asked for less movement and gets the destination, not
 * the journey. This is the one animation that does not have that option, because
 * it is not decoration: it is the thing that explains a full-screen change of
 * *every colour on the page*. Removing it leaves a hard flip, which is the
 * larger sensory event of the two. So reduced motion here means **shorter and
 * softer** (a fast, small circle rather than a slow, sweeping one), not none.
 * That is a deliberate, named exception — `THEME_WIPE_REDUCED_DURATION` — and
 * not a pattern to copy elsewhere.
 */

/**
 * How long the circle takes.
 *
 * Longer than the site's 150–260ms entrances, and deliberately so: this one is
 * a full-screen movement rather than a small element arriving, and at an
 * entrance's length a movement that large reads as a glitch rather than a
 * transition. It is also the slowest thing on the site by a wide margin, and the
 * only animation here paced for how it *looks* rather than for how quickly it
 * gets out of the way — the theme is already applied underneath the snapshots,
 * so nothing is waiting on this except the eye.
 *
 * 700ms: tuned up from an initial 520, which read as a flick on a 1440px screen.
 */
export const THEME_WIPE_DURATION = 700

/**
 * The circle a reduced-motion customer gets: quick enough to read as a wipe
 * rather than a sweep, and still a wipe, for the reason above. Kept at roughly
 * a third of the full length, so the two feel like the same gesture.
 */
export const THEME_WIPE_REDUCED_DURATION = 220

/** The app's `Curves.easeOutCubic`, the same curve as every other transition. */
export const THEME_WIPE_EASING = 'cubic-bezier(0.33, 1, 0.68, 1)'

/**
 * Where the circle is centred: the pointer, clamped to the viewport.
 *
 * A click outside the viewport (or a keyboard selection, where there is no
 * pointer at all) falls back to the centre of the screen, because a missing
 * origin must not become `NaN` in a `circle()` — an invalid clip-path is
 * ignored, and an ignored clip-path is a full-screen cross-fade, which looks
 * exactly like the flicker this exists to remove.
 *
 * @param {{ x?: number, y?: number } | null | undefined} point
 * @param {{ width?: number, height?: number } | null | undefined} size
 */
export function wipeOrigin(point, size) {
  const width = Number(size?.width) || 0
  const height = Number(size?.height) || 0
  const centre = { x: width / 2, y: height / 2 }

  const x = Number(point?.x)
  const y = Number(point?.y)
  if (!Number.isFinite(x) || !Number.isFinite(y)) return centre

  return {
    x: Math.min(Math.max(x, 0), width),
    y: Math.min(Math.max(y, 0), height),
  }
}

/**
 * The radius that covers the whole viewport from that origin — the distance to
 * the farthest corner, rounded up.
 *
 * Rounding up matters: a fractionally short radius leaves an un-wiped sliver of
 * the old theme in the far corner, and the whole animation ends on that sliver
 * instead of on the new theme.
 */
export function wipeRadius(origin, size) {
  const width = Number(size?.width) || 0
  const height = Number(size?.height) || 0
  const x = Number(origin?.x) || 0
  const y = Number(origin?.y) || 0

  const dx = Math.max(x, width - x)
  const dy = Math.max(y, height - y)
  return Math.ceil(Math.hypot(dx, dy))
}

/** A `clip-path` circle at a radius, centred on an origin. */
export function wipeCircle(radius, origin) {
  const x = Number(origin?.x) || 0
  const y = Number(origin?.y) || 0
  return `circle(${Math.max(Number(radius) || 0, 0)}px at ${x}px ${y}px)`
}

/**
 * Which snapshot carries the circle, and in which direction.
 *
 * The View Transitions API paints two stills of the page — the old theme and
 * the new one — so a direction is a choice of *which still is being clipped*:
 *
 *  * going **light**, the new (light) still grows from nothing to the full
 *    circle, so light spreads out of the cursor;
 *  * going **dark**, the old (light) still recedes from the full circle to
 *    nothing, so the dark underneath is what the screen settles on.
 *
 * That second case is why this function returns a pseudo-element name rather
 * than just keyframes: the outgoing still must be painted *above* the incoming
 * one, and `index.css` does that on `html[data-theme-wipe="dark"]`.
 */
export function themeWipeFrames(theme, origin, radius) {
  const open = wipeCircle(radius, origin)
  const closed = wipeCircle(0, origin)

  if (theme === 'light') {
    return {
      pseudoElement: '::view-transition-new(root)',
      keyframes: [closed, open],
    }
  }

  return {
    pseudoElement: '::view-transition-old(root)',
    keyframes: [open, closed],
  }
}

/**
 * What the wipe should be, or `null` when this browser cannot run one at all.
 *
 * Returning a plan rather than a boolean is the whole point of the reduced-motion
 * exception above: the decision is not *whether* to run the circle but *how
 * fast*, so a customer who asked for less movement still gets the explanation of
 * what just changed.
 */
export function themeWipePlan({ supported, reduceMotion }) {
  if (!supported) return null
  return { duration: reduceMotion ? THEME_WIPE_REDUCED_DURATION : THEME_WIPE_DURATION }
}
