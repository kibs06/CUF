import { ASK_PUSH_FUNCTION, askEndingPush } from './askDelivery.js'

// ─── The wake-up, as opposed to the notice ─────────────────────────
//
// The closing RPCs write the seller a notice inside the transaction that closes
// the ask, on both channels — that is the fact, and this file cannot change it,
// improve it or skip it. What the RPCs *cannot* do is reach a phone: Postgres
// has no FCM credentials and this project has no database-to-HTTP trigger (the
// pg_net one was dropped before it ever ran — `docs/fixes` and the push
// documentation record why). So a closed ask sat in the bell, unread, until the
// seller happened to open the app.
//
// Every other push in this codebase is sent the same way and for the same
// reason: a client invokes `send-notification-push` right after the write it is
// about (`seller_notification_service.dart`'s `_triggerPush`, and the message,
// reservation and report services). This is that pattern, on the one client that
// knows a request was closed — the admin portal.
//
// ⚠️ THREE PROPERTIES THIS FUNCTION MUST KEEP, and they are the reason it looks
// the way it does:
//
//   1. **It never throws and never decides anything.** By the time it runs the
//      ask is already closed and the seller already has the notice. A push that
//      failed is a push that did not happen; turning that into an error would
//      make a committed close report as a failure, which is the `liveButOpen`
//      mistake in a new place. Hence: every failure is caught, logged, and
//      reported as data.
//
//   2. **It is best-effort and labelled so.** The admin's browser is the sender,
//      so a tab closed mid-flight simply skips this push — the bell row does not
//      depend on it. Nothing in the portal's copy claims otherwise; the sentence
//      the page shows says the *database* told the seller.
//
//   3. **It says what the bell says.** The title and body come from
//      `askEndingPush` in `askDelivery.js`, whose sentences are contract-tested
//      against the RPC bodies. No second copy of the words exists here.
//
// The client is passed in rather than imported so this can be driven by a fake
// in tests — the same seam the app uses for its own data sources — and so that
// importing this module never touches a live client.

/** The columns the payload needs: which store to notify, which product to point
 *  at, and the name both the bell and the push put first in the sentence. */
const REQUEST_SELECT =
  'store_id, product_id, products!shoe_model_requests_product_id_fkey(name)'

/**
 * Ask for the push that goes with one closed ask.
 *
 * Returns a small `{ sent, why }` result for the caller (and for a test) rather
 * than a boolean, because "not sent" has several honest explanations and the
 * console line should name the one that happened.
 */
export async function sendAskEndingPush({ client, requestId, kind, note, reason }) {
  const notSent = (why) => {
    console.warn(`[askPush] no push for request ${requestId}: ${why}`)
    return { sent: false, why }
  }

  try {
    if (!client) return notSent('no client')
    if (!requestId) return notSent('no request id')

    // Read the row rather than trusting the caller's copy of it: the hooks that
    // call this pass an id and nothing else, so there is one place that knows
    // which store and which product a push is about.
    const { data: request, error: requestError } = await client
      .from('shoe_model_requests')
      .select(REQUEST_SELECT)
      .eq('id', requestId)
      .maybeSingle()

    if (requestError) return notSent(`the request could not be read (${requestError.message})`)
    if (!request) return notSent('the request is not readable')

    // The push is addressed to a USER, and the bell row is addressed to a STORE.
    // `stores.owner_id` is the join between them, and it is also the recipient
    // the app's own seller pushes use.
    const { data: store, error: storeError } = await client
      .from('stores')
      .select('owner_id')
      .eq('id', request.store_id)
      .maybeSingle()

    if (storeError) return notSent(`the store could not be read (${storeError.message})`)

    const recipientUserId = store?.owner_id
    if (!recipientUserId) return notSent('the store has no owner to notify')

    const message = askEndingPush({
      kind,
      productName: request.products?.name,
      note,
      reason,
      productId: request.product_id,
    })
    if (!message) return notSent(`unknown ending "${kind}"`)

    const { error } = await client.functions.invoke(ASK_PUSH_FUNCTION, {
      body: { recipientUserId, ...message },
    })

    if (error) return notSent(`the push service refused it (${error.message ?? error})`)
    return { sent: true }
  } catch (e) {
    // The catch is the contract, not a formality: see property 1 above.
    return notSent(`unexpected failure (${e?.message ?? e})`)
  }
}
