import {
  CUSTOMER_SENDER_TYPE,
  SELLER_SENDER_TYPE,
  buildOutgoingMessage,
  deleteMessage,
  fetchMessages,
  fetchUnreadCountsByConversation,
  markConversationRead,
  sendMessage,
  sortConversations,
} from './messages.js'
import { sellerConversationName } from './sellerMessageRules.js'
import { supabase } from './supabase.js'

/*
  Re-exported so a seller screen imports "seller messages" once. The pure rules
  are literally the customer's — an inbox row, a bubble, a read receipt and the
  realtime fold are the same rules on both sides of a conversation, and a second
  copy of `mergeMessage` is a second chance to get duplication in a chat wrong.
*/
export * from './messageRules.js'
export * from './sellerMessageRules.js'
export { SELLER_SENDER_TYPE, subscribeToConversation } from './messages.js'

/**
 * The seller's side of messaging.
 *
 * `messages.js` owns the tables and the customer's read path; this module adds
 * the store-scoped ones. Everything that is genuinely the same is imported
 * rather than copied — `fetchMessages`, `sendMessage`, `deleteMessage`,
 * `markConversationRead`, `subscribeToConversation` and every rule in
 * `messageRules.js` work identically for both parties, because the database is
 * symmetrical: `20260713_messaging.sql` wrote a `seller_read_store_conversations`
 * / `seller_read_store_messages` policy next to the customer's, a
 * `seller_insert_messages` policy that requires `sender_type = 'seller'`, and
 * `mark_conversation_read(convo_id, reader_role)` takes the reader's side as an
 * argument. Nothing here changes the backend.
 *
 * ## The three things that ARE different
 *
 *  1. **A seller's thread is with a PERSON, not a store.** The inbox lists
 *     customers, so it reads `conversations.customer_name` — denormalised onto
 *     the row by a trigger precisely because profiles RLS made the join return
 *     nothing for a seller. There is no `stores(...)` embed here; the store is
 *     the seller's own.
 *  2. **The rows are found by `store_id`, not `customer_id`.** A seller owns one
 *     store, so its whole inbox is one indexed `eq`.
 *  3. **Unread means the customer's messages.** See
 *     `fetchUnreadCountsByConversation` — the counted side is a parameter, and
 *     this file passes the opposite of the customer's.
 */

/**
 * The thread row, with the two columns that make a seller's inbox readable.
 *
 * No store embed: the only store on this side is the seller's own, and it is
 * already in the shell.
 */
export const SELLER_CONVERSATION_SELECT =
  'id, store_id, customer_id, customer_name, last_message_at, last_message_preview, created_at'

/** A row → the shape the seller's inbox and thread header expect. */
export function mapSellerConversation(row) {
  if (!row) return null

  return {
    ...row,
    id: String(row.id),
    store_id: row.store_id ? String(row.store_id) : null,
    customer_id: row.customer_id ? String(row.customer_id) : null,
    customer_name: sellerConversationName(row),
    unread_count: 0,
  }
}

/**
 * This store's threads, newest activity first, each with its unread count —
 * the seller's inbox.
 *
 * `unread_count` is filled in by one extra read rather than by N+1 counting: a
 * single `messages` query returns `conversation_id` for the unread ones and the
 * tally is a group-by in JavaScript. RLS scopes both reads to the store, so the
 * filter is the ids alone.
 */
export async function fetchStoreConversations(storeId) {
  if (!storeId) return []

  const { data, error } = await supabase
    .from('conversations')
    .select(SELLER_CONVERSATION_SELECT)
    .eq('store_id', storeId)

  if (error) throw error

  const rows = (data ?? []).map(mapSellerConversation).filter(Boolean)
  const counts = await fetchUnreadCountsByConversation(
    rows.map((row) => row.id),
    CUSTOMER_SENDER_TYPE,
  )

  return sortConversations(
    rows.map((row) => ({ ...row, unread_count: counts[row.id] ?? 0 })),
  )
}

/**
 * How many of this store's threads have something unread — the menu's badge.
 *
 * A number, not the list: this renders in the seller's bar on every page, and
 * the inbox query carries a row per customer who has ever written. Two requests
 * rather than one because the answer genuinely depends on both tables, but
 * neither returns a body.
 */
export async function fetchStoreUnreadThreadCount(storeId) {
  if (!storeId) return 0

  const { data, error } = await supabase
    .from('conversations')
    .select('id')
    .eq('store_id', storeId)
    .not('last_message_at', 'is', null)

  if (error) throw error

  const counts = await fetchUnreadCountsByConversation(
    (data ?? []).map((row) => row.id),
    CUSTOMER_SENDER_TYPE,
  )

  return Object.keys(counts).filter((id) => counts[id] > 0).length
}

/** One thread — `null` when it is not this store's (RLS answers with nothing). */
export async function fetchStoreConversation(conversationId) {
  if (!conversationId) return null

  const { data, error } = await supabase
    .from('conversations')
    .select(SELLER_CONVERSATION_SELECT)
    .eq('id', conversationId)
    .maybeSingle()

  if (error) throw error
  return mapSellerConversation(data)
}

/** A thread's messages, oldest first — the same read the customer's thread makes. */
export async function fetchStoreMessages(conversationId) {
  return fetchMessages(conversationId)
}

/**
 * The row a reply from the shop becomes.
 *
 * Delegates to the customer's builder with the seller's side named, rather than
 * assembling a payload here: `sender_type` is required to match the reader by
 * the INSERT policy, so the row should come from the one function that knows
 * that. `customerId` is that function's name for "the signed-in person" — on
 * this side it is the seller's own id.
 */
export function buildStoreMessage({ conversationId, sellerId, body, orderReferenceId = null }) {
  return buildOutgoingMessage({
    conversationId,
    customerId: sellerId,
    body,
    orderReferenceId,
    readerType: SELLER_SENDER_TYPE,
  })
}

/** Insert one reply and hand back the stored row. */
export async function sendStoreMessage(row) {
  return sendMessage(row)
}

/**
 * Mark the customer's messages in this thread read.
 *
 * The RPC, never a table UPDATE: there is no client UPDATE policy on
 * `messages`, so an update matches zero rows and **reports success** — the same
 * silent no-op `orders.js` documents for cancelling. `reader_role` is what keeps
 * a seller's call from marking their own replies read.
 */
export async function markStoreConversationRead(conversationId) {
  return markConversationRead(conversationId, SELLER_SENDER_TYPE)
}

/** Delete one of the shop's own messages — RLS allows the seller's own only. */
export async function deleteStoreMessage(messageId) {
  return deleteMessage(messageId)
}

/**
 * Watch this store's inbox.
 *
 * Subscribes to `conversations`, not `messages`: the trigger already moves
 * `last_message_at` on every insert, so "a thread changed" is exactly the event
 * the list needs, and it is one row per change instead of every message any
 * customer sends. `store_id` is the filter because that is the column this
 * read is about — the customer's inbox filters on `customer_id` for the same
 * reason.
 */
export function subscribeToStoreInbox(storeId, onChange) {
  if (!storeId) return null

  const channel = supabase
    .channel(`seller-inbox:${storeId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'conversations',
        filter: `store_id=eq.${storeId}`,
      },
      () => onChange(),
    )
    .subscribe()

  return channel
}
