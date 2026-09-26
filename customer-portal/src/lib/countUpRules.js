/**
 * How long a counter takes to count up to its value.
 *
 * ## The problem with one duration for every number
 *
 * The counter was 400ms for everything, and that is the wrong shape because the
 * *same* 400ms is a different animation depending on the number:
 *
 *  * `0 → 3` in 400ms is three ticks. Each one lasts about 130ms, which is
 *    shorter than a blink, so the figure does not read as *counting* — it reads
 *    as a flicker from nothing to three.
 *  * `0 → 12480` in 400ms is thirty thousand ticks a second, which is not
 *    counting either: it is a smear, and a smear of digits in a tabular face at
 *    60px looks like a rendering fault rather than a measurement settling.
 *
 * So the length falls as the number gets bigger, which is the opposite of what
 * "bigger number, more work" intuition suggests and the right way round for the
 * eye: a small figure has few increments to show, so each one can be given
 * enough time to be seen; a large figure does not have time to show its
 * increments at any duration, so its count is only there to say *this figure is
 * live and it just changed*, and it should get out of the way.
 *
 * ## Why the curve is logarithmic, and why it is clamped
 *
 * It is the number of **digits** that makes a count unreadable, not the value,
 * and each extra digit multiplies the count by ten — so the duration is mapped
 * linearly across `log10`, which gives every decade the same amount of time
 * saved. A linear map over the value itself would have to be re-tuned for every
 * magnitude the portal might display (a ₱300 order total and a ₱1,200,000
 * month). In log space, one span covers 1 through 10,000 and everything above
 * that sits at the floor, which is exactly where a figure that is genuinely
 * large should be: past five digits nobody is reading the increments.
 *
 * The two ends are chosen rather than derived:
 *
 *  * **0.8s for a single digit.** `0 → 3` is three increments at roughly a
 *    quarter of a second each, which is slow enough to read and still quicker
 *    than the eye can get bored of. It is deliberately not slower: the span is
 *    showing `0` while the true value is `1` or `3`, and half a second of that
 *    is a count, while a second and a half is a figure that looks stuck.
 *  * **0.2s at five digits and beyond.** At this end the animation is a flourish
 *    on a number that is already correct underneath it (`CountUp` fails open),
 *    so it is kept just long enough to be seen as movement — and it is *faster*
 *    than the 400ms this replaced, which is the case the seller actually waits
 *    on, since the hero figure on the dashboard is money.
 *
 * ## This one knowingly exceeds the site's own guidance
 *
 * `motion/transitions.js` says anything above ~400ms should be a considered
 * one-off rather than a default, and 0.8s is above it. This is that one-off: it
 * is only ever spent on numbers small enough that the movement is the point, and
 * no other animation in the portal takes its timing from here.
 *
 * Kept pure and separate from the component for the same reason
 * `themeWipeRules.js` is: the interesting part is arithmetic with two ends and a
 * clamp, and it can be checked without a browser — which matters here, because
 * node has no `requestAnimationFrame`, so a test that had to *watch* a tween
 * would prove nothing.
 */

/**
 * The slowest count: a single digit, e.g. `0 → 3`. See the docblock for why this
 * is 0.8 and not more.
 */
export const COUNTUP_SLOWEST_SECONDS = 0.8

/** The fastest count: five digits and up, where the increments are a blur. */
export const COUNTUP_FASTEST_SECONDS = 0.2

/**
 * How many decades the curve spans — 0 through 4, i.e. 1 through 10,000. Values
 * past the end are clamped to `COUNTUP_FASTEST_SECONDS` rather than continuing
 * to shrink, because a duration that kept falling would eventually round to a
 * frame or two and a count that short is a snap, not a count.
 */
export const COUNTUP_MAGNITUDE_SPAN = 4

/**
 * How long to spend counting up to `value`, in seconds.
 *
 * Monotonic: a larger number is never given more time than a smaller one, which
 * is the whole property this exists for and is asserted in the tests.
 *
 * Guarded against the values that would break the animation rather than the
 * arithmetic: a `NaN` (or a missing figure, which is a `undefined` before the
 * query lands) becomes `0` and therefore the slowest count — a duration of `NaN`
 * handed to `animate` never completes, and an animation that never completes is
 * a figure stuck at zero, which is the failure `CountUp`'s docblock spends its
 * length on. A negative value counts for as long as its magnitude: money coming
 * back is not a shorter journey than money arriving.
 *
 * @param {number} value The number the counter is heading for.
 * @returns {number} Seconds, always inside
 *   `[COUNTUP_FASTEST_SECONDS, COUNTUP_SLOWEST_SECONDS]`.
 */
export function countUpSeconds(value) {
  const magnitude = Math.log10(Math.abs(Number(value) || 0) + 1)
  const span = Math.min(Math.max(magnitude / COUNTUP_MAGNITUDE_SPAN, 0), 1)

  /*
    The two ends are returned as themselves rather than as the result of the
    interpolation, which is not pedantry: `0.8 + (0.2 - 0.8) * 1` is
    0.19999999999999996, and a floor that every large figure misses by a
    5e-17th of a second is a floor nothing can be compared against.
  */
  if (span <= 0) return COUNTUP_SLOWEST_SECONDS
  if (span >= 1) return COUNTUP_FASTEST_SECONDS

  return (
    COUNTUP_SLOWEST_SECONDS +
    (COUNTUP_FASTEST_SECONDS - COUNTUP_SLOWEST_SECONDS) * span
  )
}
