import { useEffect } from 'react'
import { animate, motion, useMotionValue, useTransform } from 'motion/react'

import { EASE_OUT_CUBIC, useTransitionTiming } from '../motion/transitions'
import { countUpSeconds } from '../../lib/countUpRules.js'

/** Whole numbers, grouped. Module-level so its identity is stable across renders. */
const defaultFormat = (value) => Math.round(value).toLocaleString('en-PH')

/**
 * A number that counts up to its value.
 *
 * The Lightswind component is the idea; this is the same thing written to this
 * portal's rules, and the differences are not style preferences.
 *
 * ## 1. It fails open, because the alternative is a wrong number
 *
 * The published version holds its value in a motion value starting at `0` and
 * renders whatever that motion value currently says. So the rendered number is
 * `0` until a JavaScript animation runs and finishes — and if that animation
 * never runs (a background tab, an error, an observer that never fires) the
 * figure stays at zero.
 *
 * On a storefront that is a missing flourish. **On a seller's dashboard it is a
 * lie**: "Sales today ₱0" when the store took ₱12,480 is a number a maker would
 * act on, and this portal's README gives that failure a name — *"an element's
 * visible state must be its natural state, with the animation as an addition."*
 *
 * The fix is one expression: the motion value is seeded at `0` **only when there
 * is an animation to run**. With reduced motion on there is none, so it is
 * seeded at the true value and the component is simply a number.
 *
 * ## 2. No `triggerOnView`
 *
 * The published component can defer its start to an `IntersectionObserver`.
 * That is a second way for the value to be stuck at zero — an observer inside a
 * container that never reports 10% visible never fires — and it exists to solve
 * a problem this page does not have: the dashboard's figures are above the fold
 * on every screen size, so there is nothing to wait for.
 *
 * ## 3. `format` is a function, not `prefix`/`suffix`/`decimals`/`separator`
 *
 * Four props that reimplement number formatting would be a second formatter
 * beside `formatCurrency` and `formatCurrencyCompact` — and this project already
 * has a rule about that, because a storefront that disagrees with the app about
 * the price is the one bug a customer will notice. A caller passes the formatter
 * it already uses; the peso sign, the thousands separator and the decimals stay
 * with the function that owns them.
 *
 * ## The count itself
 *
 * It runs on mount **and on every later change**, which is deliberate: the data
 * arrives after the first render, so an "animate once on mount" rule would count
 * from 0 to 0 and then snap to the real figure — no count at all in the case it
 * exists for. A refetch produces a short tween, which is a useful "this changed"
 * cue rather than noise.
 *
 * ## The length comes from the number, not from a token
 *
 * There is no `DURATION` here on purpose. One length for every figure is the
 * wrong shape — 400ms is three ticks for a `3` (too fast to read as counting)
 * and thirty thousand for a peso total (a smear of digits) — so the tween is
 * paced by the figure's own magnitude in `lib/countUpRules.js`: slowest on a
 * single digit, fastest at five digits and up. Pass `duration` to opt out and
 * pin a length; nothing in the portal does.
 *
 * ## Accessibility
 *
 * The animated span is `aria-hidden` and the true value sits beside it in an
 * `sr-only` span, so a screen reader is read the actual figure — never `0`, and
 * never a value from halfway through the count.
 */
export default function CountUp({
  value,
  format = defaultFormat,
  duration = null,
  className = '',
}) {
  const { reduce } = useTransitionTiming()

  // Zero when reduced motion is on, which is also the signal that there is
  // nothing to animate — see the docblock. A `duration` of `null` means "pace it
  // by the figure", which is the rule; a number is an override.
  const seconds = reduce ? 0 : Math.max(0, duration ?? countUpSeconds(value))

  const motionValue = useMotionValue(seconds > 0 ? 0 : value)
  const text = useTransform(motionValue, (latest) => format(latest))

  useEffect(() => {
    if (seconds <= 0) {
      // No animation: make sure the value is the real one and stop.
      motionValue.set(value)
      return undefined
    }

    const controls = animate(motionValue, value, {
      duration: seconds,
      ease: EASE_OUT_CUBIC,
    })

    // Stopped rather than left running: a value that changes mid-count would
    // otherwise have two animations writing to it.
    return () => controls.stop()
  }, [value, seconds, motionValue])

  return (
    <>
      <span className="sr-only">{format(value)}</span>
      <motion.span aria-hidden="true" className={className}>
        {text}
      </motion.span>
    </>
  )
}
