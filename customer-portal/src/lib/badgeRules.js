/**
 * A count, as a badge — what it says, and when it says nothing at all.
 *
 * ## Why this is a module and not a component
 *
 * The badge is drawn in four places (the seller avatar, its two menu rows, and
 * the customer's cart button) and the four decisions below are the parts that
 * have to agree. `CountBadge` owns the pixels; this owns the arithmetic, and it
 * is separate for the same reason `countUpRules.js` is: the interesting part is
 * three edge cases, and they can be checked without a browser.
 *
 * ## The three edge cases
 *
 *  1. **Zero draws nothing.** A badge reading `0` means "nothing here" in the one
 *     place that exists to say something happened — and a pill permanently on the
 *     avatar would be a permanent claim that something had. So zero is the same
 *     answer as "do not draw a badge", not a badge with a nought in it.
 *  2. **Capped at `99+`.** Two digits and a plus cannot push a row in a 240px
 *     panel around, and past a hundred nobody reads a badge for the exact number.
 *     The cap is a *drawing* decision: a caller that has somewhere better to put
 *     the number — the cart's `aria-label`, `SellerAccountMenu`'s — should put the
 *     true figure there, because `99+` spelled out is not a quantity.
 *  3. **Unreadable counts draw nothing.** A badge is a claim, and `NaN` (or a
 *     count that has not loaded yet, which arrives as `undefined`) is not a claim
 *     anyone made. Drawing `NaN` in a pill would be worse than drawing nothing:
 *     it is a visible defect where silence is merely uninformative.
 *
 * Nothing here coerces a value *up* to zero: `badgeCount(null)` and
 * `badgeCount(0)` are both `null`, which is the same thing as far as the caller
 * is concerned, and having one answer for both is what keeps a caller from
 * needing to know which it holds.
 */

/**
 * The cap, and the only place it is decided.
 *
 * `99` rather than `9`, because a portal with a genuinely busy store counts
 * notifications in the tens — a single-digit cap would read `9+` on an ordinary
 * Tuesday and stop being information.
 */
export const MAX_BADGE = 99

/**
 * The text a badge shows, or `null` when it should not be drawn at all.
 *
 * Null for zero and for anything unreadable, which is the same answer: a count
 * that is not a number cannot be a claim that something happened.
 *
 * Truncated rather than rounded, so `1.9` is `1` and never `2`: every caller
 * counts whole things, and a badge is not the place to discover a fractional row
 * count.
 *
 * @param {number} count
 * @returns {string|null}
 */
export function badgeCount(count) {
  const value = Math.trunc(Number(count))
  if (!Number.isFinite(value) || value <= 0) return null
  return value > MAX_BADGE ? `${MAX_BADGE}+` : String(value)
}

/**
 * Several counts added up into the one a badge draws.
 *
 * This is what the seller's avatar badge is: *is anything waiting on me?* — which
 * is one question even though the portal answers it from two tables (notifications
 * and message threads). The two rows inside the panel still show their own counts;
 * this is only for the face of the button, which has room for one number.
 *
 * Unreadable parts count as zero rather than poisoning the sum. `undefined + 3` is
 * `NaN`, and one query that has not landed yet would otherwise blank a badge that
 * has a perfectly good answer in the other hand. A missing count is a count nobody
 * made; it is not evidence against the ones that arrived.
 *
 * @param {...number} counts
 * @returns {number} A whole, non-negative total — never `NaN`.
 */
export function waitingCount(...counts) {
  return counts.reduce((sum, count) => {
    const value = Math.trunc(Number(count))
    return sum + (Number.isFinite(value) && value > 0 ? value : 0)
  }, 0)
}
