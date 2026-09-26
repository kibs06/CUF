/**
 * The seller side of messaging — the handful of rules that differ from the
 * customer's, kept pure so they can be tested without a database.
 *
 * Almost everything about a thread is the same for both parties, and those
 * pieces stay in `messageRules.js`: the inbox order (`nullsFirst`), the preview,
 * the unread badge, the read receipt, `mergeMessage`. What changes is **who the
 * other party is**:
 *
 *  * a customer's inbox lists *stores*, which is why the customer's row carries
 *    a `stores(...)` embed;
 *  * a seller's inbox lists *people*, and the name for that comes from
 *    `conversations.customer_name`.
 *
 * `customer_name` is denormalised on purpose
 * (`20260715090300_add_customer_name_to_conversations.sql`): profiles RLS made
 * the seller's inbox join return zero rows, so the name is copied onto the
 * thread by a trigger and kept in sync when the customer renames themselves.
 * The column is therefore the right source, not a fallback for one — but it is
 * also **nullable**, because it was added to a table that already had rows, and
 * a thread that predates the backfill has a null name. Hence the reader below:
 * a seller looking at a blank row cannot tell whether it is a customer they
 * have never spoken to or a page that failed to load.
 */

/** What a thread is called when the column has no name in it. */
export const SELLER_CONVERSATION_FALLBACK_NAME = 'Customer'

/**
 * The person on the other end of one of the seller's threads.
 *
 * `customer_name` first, then nothing else: there is deliberately no e-mail
 * fallback, because the portal never selects the customer's e-mail on this path
 * and inventing a second source would make the two disagree the moment a
 * customer changes one of them.
 */
export function sellerConversationName(conversation) {
  const name = String(conversation?.customer_name ?? '').trim()
  return name || SELLER_CONVERSATION_FALLBACK_NAME
}

/**
 * Whether this thread has ever been written to.
 *
 * The seller's inbox says "no messages yet" about a thread a customer opened
 * from the app and never used — which is exactly the row that needs saying,
 * since it is the one sitting at the top of the list.
 */
export function sellerConversationStarted(conversation) {
  return Boolean(conversation?.last_message_at)
}
