import { functionError } from './checkoutRules.js'
import { deletionResult } from './securityRules.js'
import { supabase } from './supabase.js'

// The rules live next door — the copy and the "a pending request is not a
// failure" mapping both come from `securityRules.js`. Re-exported so screens
// have one import site for support.
export * from './securityRules.js'

/**
 * The function the app calls, so both clients land in the same admin queue.
 *
 * `request-account-deletion` is an edge function rather than an RPC because
 * writing the row is only half the job: it also pushes a notification to every
 * admin and files an in-app notification, which a `SECURITY DEFINER` function
 * cannot do. Calling the RPC directly from here would create the request and
 * tell nobody, and the customer's 48 hours would start against an empty queue.
 *
 * It requires a Bearer token — `functions.invoke` sends the session's — so an
 * anonymous caller gets a 401 rather than a request filed against nobody.
 */
export const DELETION_FUNCTION = 'request-account-deletion'

/**
 * Ask for the account to be deleted.
 *
 * Returns `{ ok, message }` rather than throwing on a soft outcome: "you
 * already have a pending request" is the function working correctly, and the
 * screen's job is to report it, not to colour it red. A real failure (no
 * session, no network, a 500) throws, so the caller can tell "done" from
 * "could not ask".
 */
export async function requestAccountDeletion(reason = null) {
  const { data, error } = await supabase.functions.invoke(DELETION_FUNCTION, {
    body: { reason },
  })

  if (error) {
    throw await functionError(
      error,
      'We could not send your request. Please try again, or contact support if it keeps failing.',
    )
  }

  return deletionResult(data)
}
