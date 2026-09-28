/**
 * The toast centre's rules — which notification earns an interruption.
 *
 * The feed page answers "what have I missed?"; a toast answers "what is
 * happening now?". Those are different questions with different answers, and
 * collapsing them is how a portal ends up popping fourteen cards at a customer
 * who has just signed in to buy a pair of sandals.
 *
 * So the rules here are deliberately narrow:
 *
 *  1. **Unread only.** A toast about something already read is an interruption
 *     with nothing in it. Read state is also what keeps two open tabs from
 *     disagreeing: the second tab's refetch returns the same rows, and the read
 *     that happened in the first has already taken them out of the running.
 *  2. **Fresh only, inside `TOAST_MAX_AGE_MS`.** The portal cannot know when the
 *     customer was last here — there is no "last seen" column — so age is the
 *     only honest proxy it has. Anything older is backlog, and backlog belongs
 *     on the feed, which the badge already points at.
 *  3. **Newest first, capped at `TOAST_LIMIT`.** A seller whose shop wakes up to
 *     nine orders gets the newest three as toasts and the rest in the feed,
 *     rather than a queue that takes a minute to play through.
 *
 * ## What these rules do *not* decide
 *
 * Whether a notification has already been popped. That is session state — a
 * `Set` of ids — and it lives in the toaster itself (`NotificationToaster`),
 * which the shell mounts once and which outlives every refetch. Keeping it out
 * of here is what makes these two functions testable against a fixed `now`,
 * with no clock and no memory.
 */

/**
 * How fresh a notification has to be to earn a toast: half an hour.
 *
 * Chosen from the two feeds' own rhythms rather than from a round number. The
 * customer feed refetches on window focus, so in practice it is minutes old; a
 * seller's arrives over realtime, in seconds; and an order's status normally
 * moves within the day it was placed. Half an hour therefore catches "this
 * happened while you were away" and lets go of everything a customer would
 * rather read in the list.
 */
export const TOAST_MAX_AGE_MS = 30 * 60 * 1000

/** How many toasts one burst may produce. */
export const TOAST_LIMIT = 3

/**
 * Whether a row is recent enough to interrupt someone for.
 *
 * A timestamp in the future counts as fresh, deliberately: a phone with a clock
 * twenty minutes fast, or a row written by an Edge Function a moment before the
 * server NTPs itself, is a real row about something that just happened. Dropping
 * it would mean a customer not being told about their own order because of
 * somebody else's clock.
 *
 * A row with no readable timestamp is **not** fresh. There is no defensible
 * reading of "when" for it, and a toast drawn from the epoch — "20658d ago" — is
 * the kind of thing that makes people distrust the whole centre.
 */
export function toastIsFresh(row, now = Date.now(), maxAgeMs = TOAST_MAX_AGE_MS) {
  const created = new Date(row?.created_at ?? NaN).getTime()
  if (!Number.isFinite(created)) return false

  return Number(now) - created < maxAgeMs
}

/**
 * The rows worth popping, newest first — at most `limit` of them.
 *
 * Rows without an id are dropped: the toaster remembers what it has popped by
 * id, so a row whose id it cannot remember is a row it would pop again on every
 * refetch. Duplicate ids are folded for the same reason — the feeds merge a
 * realtime insert into a list that has already been read, and the same
 * notification arriving twice in one array is one notification.
 *
 * `now` is a parameter for the reason `notificationRelativeTime`'s is: a rule
 * that can only be tested against the wall clock is a test that passes at 23:59
 * and fails at 00:00.
 */
export function pickToastNotifications(
  rows,
  { limit = TOAST_LIMIT, now = Date.now(), maxAgeMs = TOAST_MAX_AGE_MS } = {},
) {
  const seen = new Set()
  const picked = []

  for (const row of rows ?? []) {
    const id = row?.id ? String(row.id) : null
    if (!id || seen.has(id)) continue
    if (row.is_read) continue
    if (!toastIsFresh(row, now, maxAgeMs)) continue

    seen.add(id)
    picked.push(row)
  }

  return picked
    .sort((a, b) => new Date(b?.created_at ?? 0) - new Date(a?.created_at ?? 0))
    .slice(0, Math.max(0, limit))
}
