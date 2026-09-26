import { useReducedMotion } from 'motion/react'

/**
 * Motion tokens.
 *
 * The point of centralising these is that "premium" motion is *consistent*
 * motion: a hover that eases over 300ms next to a panel that snaps in 120ms
 * reads as two different products. So every duration and curve in the portal
 * comes from here, and they are chosen to match the app:
 *
 *   EASE_OUT_CUBIC ↔ Curves.easeOutCubic, the app's standard curve
 *
 * Durations are deliberately short. A storefront is browsed quickly — an
 * animation the customer has to wait for is a tax, not a flourish. Anything
 * above ~400ms should be a considered one-off, not a default.
 */
export const EASE_OUT_CUBIC = [0.33, 1, 0.68, 1]

/** A gentle overshoot for things that should feel *placed*, not slid. */
export const EASE_BACK_OUT = [0.34, 1.4, 0.64, 1]

export const DURATION = {
  /** Colour, opacity, border — the things that should barely be noticed. */
  quick: 0.15,
  /** Hover lifts, badge fades. */
  base: 0.26,
  /** Page transitions and entrances. */
  slow: 0.4,
  /** A product image breathing under the cursor. Slower on purpose: it is the
   *  one motion large enough to be seen sideways, and a fast zoom looks cheap. */
  image: 0.55,
}

export const fadeUp = {
  hidden: { opacity: 0, y: 12 },
  show: { opacity: 1, y: 0 },
}

/** Parent variants that walk a grid in, one card after another. */
export function staggerChildren(stagger = 0.045, delayChildren = 0) {
  return {
    hidden: {},
    show: { transition: { staggerChildren: stagger, delayChildren } },
  }
}

/**
 * Reduced motion, as a value to multiply by rather than a branch to duplicate.
 *
 * `useReducedMotion` is the JS half of the reduced-motion story — the CSS half
 * is the media query in `index.css` — because motion drives transforms in JS
 * that a stylesheet cannot reach.
 *
 * Note the durations go to ZERO rather than to "a shorter time": a customer who
 * has asked for less motion wants the destination, not a faster journey.
 */
export function useTransitionTiming() {
  const reduce = useReducedMotion()
  return {
    reduce,
    /** Clamp a duration: 0 when reduced motion is on. */
    d: (seconds) => (reduce ? 0 : seconds),
  }
}
