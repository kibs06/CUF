import { MESSAGE_PUSH_FUNCTION, messagePushPayload } from './messagePushRules.js'
import { supabase } from './supabase.js'

/**
 * Ask the push Edge Function to wake the other side's phone.
 *
 * ## Fire and forget, on purpose
 *
 * Nothing is awaited and nothing is returned to wait on. Two things follow, and
 * both are the reason it is written this way rather than as an `async` function a
 * caller might `await`:
 *
 *  1. **A message that was sent is sent.** The text is already in the table by the
 *     time this runs, so a push that fails is a missing notification and not a
 *     message the seller has to send twice. Awaiting it would turn a timeout at
 *     Google's end into a failed-looking send for a reply the customer can
 *     already see.
 *  2. **A rejection has nowhere to go.** `functions.invoke` rejects when the
 *     network is down or the function was never deployed, and an unhandled
 *     rejection in a chat composer is a console error at the exact moment
 *     everything else worked. The `catch` is the point of the design, not a
 *     shrug: the failure is real, and this is not where anyone can act on it —
 *     the function logs its own failures, where the FCM credentials are.
 *
 * ## The return value is not a success flag
 *
 * `true` means "there was something to send and the request was made", `false`
 * means the row was not pushable at all (see `messagePushPayload`). A push that
 * was made and rejected by the function still returns `true`, because the caller
 * could not do anything about that either.
 */
export function triggerMessagePush(row) {
  const payload = messagePushPayload(row)
  if (!payload) return false

  try {
    supabase.functions
      .invoke(MESSAGE_PUSH_FUNCTION, { body: payload })
      .catch(() => {})
  } catch {
    // `invoke` itself throws only if the client has no URL configured, which is a
    // build-time mistake. A message send must not fail over it.
    return false
  }

  return true
}
