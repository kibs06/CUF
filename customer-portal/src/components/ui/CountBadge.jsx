/**
 * A count, as a badge.
 *
 * ## Why this is shared
 *
 * Four places draw the same number the same way: the seller avatar, its two
 * menu rows, and the customer's cart button. The portal has already paid for
 * duplicated badge markup once — two copies of it live inside
 * `SellerAccountMenu` alone — and the drift is not hypothetical: the cap, the
 * pop and the screen-reader treatment are three separate decisions that end up
 * made differently in each copy.
 *
 * The look is the cart's, unchanged: a clay pill, `h-5` with a `1.25rem` floor so
 * one digit and two are the same width, in the numeric face because a count is a
 * reading.
 *
 * ## What it says, and when it says nothing
 *
 * `badgeRules.js` owns that — zero draws nothing, `99+` is the cap, and an
 * unreadable count draws nothing — because the four callers have to agree about
 * it and agreement is easier to check in a test than in four components.
 *
 * The fourth decision is here, because it is about markup rather than
 * arithmetic: **the number is announced exactly once**. With a `label`, the digit
 * is followed by `sr-only` text — "3 unread notifications", because "3" on its
 * own is not a sentence. Without one the badge is `aria-hidden`, which is the case
 * where the control around it already says the number in its own `aria-label` (the
 * avatar, the cart). `label` is therefore not a nicety: it is how a caller says
 * "this badge is the only place this number is written".
 *
 * `key={shown}` is what replays the pop when the number changes — a new order
 * arriving is otherwise silent, and the badge moving is the only confirmation
 * that it did. The animation is additive: see "Animations must fail open" in the
 * README, and a badge that does not animate is still a badge.
 *
 * `pointer-events-none` is not decoration either. Every one of these badges sits
 * over a control — inside a row's button, or on top of the avatar's corner — and
 * without it the badge would swallow the click it is advertising.
 */

import { badgeCount } from '../../lib/badgeRules.js'

/**
 * @param {object} props
 * @param {number} props.count
 * @param {string} [props.label]    sr-only text after the digit; omit to hide it
 * @param {string} [props.className] positioning, from the caller
 */
export default function CountBadge({ count, label, className = '' }) {
  const shown = badgeCount(count)
  if (shown === null) return null

  return (
    <span
      key={shown}
      aria-hidden={label ? undefined : 'true'}
      className={`num pop-enter pointer-events-none inline-flex h-5 min-w-[1.25rem] items-center justify-center rounded-full bg-clay px-1 text-[11px] font-semibold text-ink-inverse ${className}`}
    >
      {shown}
      {label ? <span className="sr-only"> {label}</span> : null}
    </span>
  )
}
