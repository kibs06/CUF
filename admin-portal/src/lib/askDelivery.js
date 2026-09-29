import { MODELLING_ENDING } from './modelPublish.js'

// ─── The other end of the loop: whether the seller was told (roadmap P3) ──
//
// P2 made the queue able to *answer* an ask. Answering told nobody, which is the
// same gap one level down: the seller's stateful row in the product action sheet
// speaks only to a seller who opens it, and a week of somebody else's work is
// exactly long enough for them to file the same ask twice.
//
// That half is built, and it is built in the database: `fulfil_shoe_model_request`
// and `decline_shoe_model_request` write the seller's notice **inside the
// transaction that closes the ask**, so "closed" and "told" cannot disagree. The
// alternative — this page sending the notice after the RPC — was rejected for the
// reason the app's own phase gives: a notice a client can decline to send is a
// courtesy rather than a fact, and every client would have to remember.
//
// So this module is deliberately narrow, and it exists for two reasons.
//
// **1. The portal's copy makes a claim about SQL it does not own.** A page that
// says "the seller has been told" is asserting a property of a function in
// `supabase/migrations/`. `askDelivery.contract.test.js` reads that SQL and
// fails if the notices move, so the claim cannot quietly become a lie — the
// same shape as the app's `notification_category_contract_test.dart`, and the
// reason the phase's real deliverable is a test rather than a paragraph.
//
// **2. The portal must never send a notice itself, nor close an ask by writing
// the row.** Both short-cuts would break the property above, and both are
// guarded mechanically in that same test rather than left to a comment.
//
// What this module will *not* do is pretend the portal can see the notice. It
// cannot: both notice tables grant SELECT to the recipient alone (`
// auth.uid() = user_id`, the store's owner) and no admin policy exists, so
// "told at 14:02" is a claim no browser here can verify. The honest version is
// the sentence below, which quotes what the seller reads and says who wrote it.
//
// ⚠️ AND A THIRD THING THIS MODULE LEARNED THE HARD WAY: a notice row is not a
// push. Both rows land in the database, and a seller whose phone is in their
// pocket learns nothing until they open the app — which is what "I never got a
// notification" turned out to mean. So the portal now also asks for the OS-level
// push (`sendAskEndingPush`, in `askPush.js`) after a closing RPC commits.
//
// The distinction is the whole reason that is allowed while "the portal must
// never send a notice itself" still holds:
//
//   * the ROW is the fact — it is written inside the transaction that closes
//     the ask, so "closed" and "told" cannot disagree, and no client can skip it;
//   * the PUSH is the wake-up — a best-effort copy of that fact onto a lock
//     screen, sent by whichever client happens to be running, and its absence
//     makes the bell no less true. It is a courtesy, and it is labelled one.
//
// So the push must never be the only thing carrying the news, and the sentences
// below are shared by both halves: the push says exactly what the bell says,
// and `askDelivery.contract.test.js` reads the RPC bodies to keep that so.

/** The category the closing RPCs file the notice under, on the per-user channel. */
export const NOTICE_CATEGORY = 'models'

/** The `seller_notifications.type` the closing RPCs use on the store's bell. */
export const SELLER_NOTICE_TYPE = 'model_request'

// ⚠️ Two rows, not one, and that is V2.14's finding rather than thoroughness: the
// per-user row lives in `public.notifications`, which the seller app never
// renders — a seller's session lands in `SellerShell`, whose bell reads
// `public.seller_notifications`. A notice on one channel only was correct and
// unreadable at the same time, so the portal's claim covers both.
export const NOTICE_CHANNELS = [
  { table: 'notifications', key: 'user_id', label: 'the seller’s user feed' },
  { table: 'seller_notifications', key: 'store_id', label: 'the seller’s bell' },
]

// The titles, verbatim from the two RPCs. These are what the seller reads, so
// the portal quotes them rather than paraphrasing: a paraphrase is how "your
// model is ready" becomes "the team finished your model" in an admin's head.
//
// The feed filters by SUBJECT and not by polarity, so both endings file under
// the same category and only the words say which one arrived — which is why
// these two sentences must never be made to look alike.
export const CLOSING_NOTICE = {
  FULFILLED: 'Your 3D model is ready',
  DECLINED: 'Your 3D model request was declined',
}

/** How the fulfil RPC quotes the admin's note into both rows. */
export const TEAM_QUOTE = 'From the team: '

/** How the decline RPC quotes the reason — a different phrase on purpose: an
 *  answer to "why not" is not the same sentence as a note on finished work. */
export const DECLINE_QUOTE = 'They said: '

// ─── The push that goes with the notice ────────────────────────────
//
// ⚠️ Every string in this section is quoted from the two RPCs rather than
// invented here, because the push and the bell are read by the same person about
// the same fact: a phone that says one thing and a bell that says another is
// worse than a phone that stays quiet. `askDelivery.contract.test.js` reads the
// migration and fails if any of them moves.

/** The Edge Function that fans a push out to FCM (`supabase/functions/`). */
export const ASK_PUSH_FUNCTION = 'send-notification-push'

/**
 * Where a tap on the push lands.
 *
 * The app's existing key for the seller's own catalogue — the same one the
 * low-stock push already uses. The app only navigates for a key it knows
 * (`seller_shell.dart`'s switch, and a contract test here reads it), so an
 * invented key would swallow the tap. What it opens is the **Products tab**, and
 * the request row is one long-press away there on the product's actions sheet —
 * which is where the model and the ask both live. The app does not deep-link
 * further than that for this key, and this module says so rather than implying a
 * screen it does not get.
 */
export const ASK_PUSH_SCREEN = 'seller_product_detail'

/** The two endings, as the hooks name them. */
export const ASK_ENDING = {
  FULFILLED: 'fulfilled',
  DECLINED: 'declined',
}

/**
 * The middle of each body — the half the RPC owns. The opening word is the
 * product's name (or `'Your product'`, the RPC's own fallback) and the optional
 * tail is the admin's note or reason.
 */
export const ASK_BODY = {
  FULFILLED: ' — it is live on the product page.',
  DECLINED: ' — the team could not make a model for it.',
}

/** What the decline adds after the reason, because its seller's move is another
 *  ask rather than a wait — the partial unique index is what allows it. */
export const ASK_AGAIN_TAIL = " You can ask again from the product's actions."

/** The name-less product, spelled exactly as the bell row spells it. */
export const ASK_NAME_FALLBACK = 'Your product'

/**
 * The push payload for one ending, or `null` for an ending this module does not
 * know — the same rule as `sellerWasTold`: a fact about the seller's phone is
 * never guessed, so an unrecognised ending pushes nothing at all.
 *
 * `referenceId` is coerced to a string on purpose. FCM's `data` map is
 * string-to-string, and the edge function copies this value into it verbatim; a
 * bigint that arrived as a number would fail the send at FCM rather than here,
 * where the reason is visible.
 */
export function askEndingPush({ kind, productName, note, reason, productId } = {}) {
  const name = String(productName ?? '').trim() || ASK_NAME_FALLBACK
  const referenceId = productId === null || productId === undefined ? null : String(productId)

  if (kind === ASK_ENDING.FULFILLED) {
    const quoted = String(note ?? '').trim()
    return {
      title: CLOSING_NOTICE.FULFILLED,
      body:
        `${name}${ASK_BODY.FULFILLED}` +
        (quoted === '' ? '' : ` ${TEAM_QUOTE}${quoted}`),
      type: SELLER_NOTICE_TYPE,
      referenceId,
      screen: ASK_PUSH_SCREEN,
    }
  }

  if (kind === ASK_ENDING.DECLINED) {
    const quoted = String(reason ?? '').trim()
    return {
      title: CLOSING_NOTICE.DECLINED,
      body:
        `${name}${ASK_BODY.DECLINED}` +
        (quoted === '' ? '' : ` ${DECLINE_QUOTE}${quoted}`) +
        ASK_AGAIN_TAIL,
      type: SELLER_NOTICE_TYPE,
      referenceId,
      screen: ASK_PUSH_SCREEN,
    }
  }

  return null
}

/**
 * Did the ending tell the seller?
 *
 * Exactly one of the three endings did, and the other two are not failures of
 * delivery — they are the two cases where nothing changed on the seller's side,
 * so there is nothing to tell. Worth naming anyway: an admin who reads "the
 * model did not go live" and assumes the seller was told something has just
 * been misled by silence.
 */
export function sellerWasTold(ending) {
  return ending === MODELLING_ENDING.CLOSED
}

/** One line for a toast: the claim, short enough to read in 3.5 seconds. */
export function deliveryHeadline(ending) {
  return sellerWasTold(ending)
    ? 'The seller has been told.'
    : 'The seller has not been told.'
}

/** The same one line for the decline, which is not a modelling ending — a
 *  decline always tells the seller, because the RPC it calls is the writer. */
export function declineHeadline() {
  return 'The seller has been told, with your reason.'
}

/**
 * The paragraph under an ending — what the seller received, in whose words.
 *
 * For the two silent endings the sentence says *why* nothing was sent, because
 * "no notice" is a fact an admin has to be able to explain to a seller who
 * calls: nothing was closed, so nothing is claimed.
 */
export function deliverySentence(ending) {
  if (ending === MODELLING_ENDING.CLOSED) {
    return (
      `The seller has been told — the database wrote "${CLOSING_NOTICE.FULFILLED}" ` +
      `to ${NOTICE_CHANNELS.length} channels (${NOTICE_CHANNELS.map((c) => c.label).join(' and ')}) ` +
      'in the same transaction that closed the ask, so a close nobody was told about is not a ' +
      'state this can reach.'
    )
  }

  if (ending === MODELLING_ENDING.LIVE_BUT_OPEN) {
    return (
      'The seller has not been told anything: the ask is still open, so no notice was written. ' +
      'Their row still reads as waiting, which is the one outcome here that a green tick would ' +
      'have hidden.'
    )
  }

  if (ending === MODELLING_ENDING.NOT_LIVE) {
    return (
      'The seller has not been told anything, and needs nothing: nothing went live and the ask ' +
      'is untouched, so it still reads as waiting and their move is still to wait.'
    )
  }

  return 'Whether the seller was told is unknown for this ending — treat it as not told.'
}

/**
 * The decline's delivery, which carries the reason the admin typed.
 *
 * Two details are the whole point. The reason travels **verbatim** into the
 * notice, so the sentence the admin writes is the sentence the seller reads —
 * and a blank one is possible from an older client or a direct RPC call, where
 * the database degrades to a notice that stands on its own rather than to a
 * dangling colon. This page refuses a blank reason, and so does the app's own
 * admin screen; the degradation is for the clients that are not this one.
 */
export function declineDeliverySentence({ reason } = {}) {
  const trimmed = String(reason ?? '').trim()

  if (trimmed === '') {
    return (
      `The seller has been told — "${CLOSING_NOTICE.DECLINED}" — but with no reason in it. ` +
      'This page refuses to send a decline without one; the server tolerates it for older ' +
      'clients, and the notice still stands on its own.'
    )
  }

  return (
    `The seller has been told — "${CLOSING_NOTICE.DECLINED}" — and the notice quotes you ` +
    `verbatim (${DECLINE_QUOTE}${trimmed}). They can ask again from the product's actions, ` +
    'which the open-ask index allows precisely because a declined ask is closed rather than deleted.'
  )
}

/**
 * A decline on an ask that was already closed changes nothing and tells nobody.
 *
 * The RPC answers `success:false` and this page shows the server's own sentence
 * instead of "done", which is the guard that matters: a seller told "declined"
 * about a model that is live on their product is the worst thing this feature
 * could say.
 */
export const NOTHING_TO_DECLINE_SENTENCE =
  'A decline on an ask that is already closed changes nothing and tells nobody — the server ' +
  'answers "not found or already closed", and this page shows that rather than "done".'

/** What the admin's optional note becomes, so a note has a known audience. */
export function noteReachesSeller() {
  return (
    `The note is quoted into the notice as "${TEAM_QUOTE}…", on both channels — it is the ` +
    'seller’s only written explanation, so it is worth a sentence rather than a code.'
  )
}

/**
 * ⚠️ What the portal cannot do, said plainly rather than shown as a blank.
 *
 * Both notice tables are readable by their recipient only. An admin session has
 * no policy that grants SELECT on another user's notice, so a "told at 14:02"
 * stamp here would have to be invented. This is the sentence to show instead.
 */
export const NOTICE_NOT_READABLE_SENTENCE =
  'The portal cannot display the notice itself: both notice tables grant SELECT to the recipient, ' +
  'and no admin policy exists — so this says what was written and shows no timestamp it cannot read.'
