import { triggerMessagePush } from './messagePush.js'
import { supabase } from './supabase.js'

// The rules live next door; re-exported so screens import "messages" once.
export * from './messageRules.js'

/**
 * Messaging — a port of `MessageService` from
 * `lib/services/message_service.dart`.
 *
 * ## What was already there
 *
 * `20260713_messaging.sql` created `conversations` (one per `(store_id,
 * customer_id)`, `UNIQUE`), `messages`, RLS letting a customer read and write
 * only their own threads, a trigger maintaining `last_message_at` /
 * `last_message_preview` on every insert, and — importantly — **no client
 * UPDATE policy on either table**. Later migrations added attachments, a batch
 * notification trigger and a delete-own-messages policy. All of it has been
 * live for months with no way to reach it from the web.
 *
 * ## The four things a naive port gets wrong
 *
 *  1. **Marking read is an RPC, not an UPDATE.** There is deliberately no
 *     UPDATE policy on `messages`, so `update({ is_read: true })` matches zero
 *     rows and **reports success** — the same silent-no-op trap `orders.js`
 *     documents for cancelling. The two `SECURITY DEFINER` functions are the
 *     only path: `mark_message_read(message_id)` and
 *     `mark_conversation_read(convo_id, reader_role)`. Note the parameter
 *     names — they are the SQL function's own, not `p_`-prefixed.
 *  2. **`conversations` is never written to by the client.** The app's
 *     `sendMessage` updates `last_message_at` / `last_message_preview` after
 *     inserting — and that update matches zero rows too, for the same missing
 *     policy. It is harmless there because the trigger has already done it, but
 *     porting it would be porting a no-op. The inserts here are the message and
 *     nothing else.
 *  3. **The other party is notified by a trigger.** `notify_on_new_message`
 *     (rewritten in `20260725000000_batch_message_notifications.sql`) upserts
 *     the seller's notification and folds up to three previews into
 *     `metadata.previews`, so a client-side notification insert would
 *     double-post and race the batching.
 *  4. **`sender_type` is hard-coded.** The INSERT policy requires
 *     `sender_type = 'customer'` from a customer, so it comes from
 *     `buildOutgoingMessage` rather than from a call site.
 *
 * ## Realtime
 *
 * `conversations` and `messages` were both added to the `supabase_realtime`
 * publication in the original migration, so these subscriptions actually fire —
 * unlike `notifications`, which was never published and therefore only
 * refetches on focus. Two channels: one per open thread, and one for the
 * customer's inbox (filtered on `conversations.customer_id`, because the inbox
 * only cares that a thread changed, not about every message row).
 */

/** The thread row plus the store it belongs to, in one request. */
export const CONVERSATION_SELECT =
  'id, store_id, customer_id, last_message_at, last_message_preview, created_at, ' +
  'stores(id, name, logo_url, brand_color, location, is_open)'

/** Every column a bubble can draw — attachments included, since a maker may send one. */
export const MESSAGE_SELECT =
  'id, conversation_id, sender_id, sender_type, body, order_reference_id, is_read, ' +
  'created_at, attachment_url, attachment_type, attachment_thumbnail_url'

/** The customer's side of `sender_type`, in one place. */
export const CUSTOMER_SENDER_TYPE = 'customer'

/**
 * The seller's side of `sender_type`. Not used by the customer screens — but
 * both RPCs and both INSERT policies are keyed to it, so it belongs next to its
 * pair rather than as a literal in the seller's own module.
 */
export const SELLER_SENDER_TYPE = 'seller'

/** How many messages a thread loads. The app's own `limit: 50`. */
export const MESSAGE_PAGE_SIZE = 50

/**
 * The customer's threads, newest activity first — `nullsFirst` handled by
 * `sortConversations`, because PostgREST's `nullsfirst` is a per-order flag and
 * a thread opened five seconds ago has no `last_message_at` yet.
 *
 * `unread_count` is filled in by a second query rather than by N+1 counting:
 * one `messages` read for every thread in the list returns `conversation_id`
 * for the unread ones, and the tally is a group-by in JavaScript. RLS scopes
 * that read to the customer's own threads, so the filter is the ids alone.
 */
export async function fetchConversations(userId) {
  if (!userId) return []

  const { data, error } = await supabase
    .from('conversations')
    .select(CONVERSATION_SELECT)
    .eq('customer_id', userId)

  if (error) throw error

  const rows = (data ?? []).map((row) => ({
    ...row,
    store: row.stores ?? null,
    unread_count: 0,
  }))

  const counts = await fetchUnreadCountsByConversation(rows.map((row) => row.id))

  return sortConversations(
    rows.map((row) => ({ ...row, unread_count: counts[row.id] ?? 0 })),
  )
}

/**
 * Unread message counts per conversation, as `{ [conversationId]: n }`.
 *
 * Only messages from the **other** party: a customer's own message stays
 * `is_read = false` until the maker opens the thread, and counting those would
 * badge a conversation the moment the customer wrote in it. The same is true
 * from the other side — a seller's reply stays unread until the customer opens
 * the thread — which is why the counted side is a parameter rather than a
 * constant. The default is the maker's, so every customer call site is
 * unchanged, and the seller's inbox passes `CUSTOMER_SENDER_TYPE`.
 */
export async function fetchUnreadCountsByConversation(
  conversationIds,
  senderType = SELLER_SENDER_TYPE,
) {
  const ids = (conversationIds ?? []).filter(Boolean)
  if (ids.length === 0) return {}

  const { data, error } = await supabase
    .from('messages')
    .select('conversation_id')
    .in('conversation_id', ids)
    .eq('sender_type', senderType)
    .eq('is_read', false)

  if (error) throw error

  return (data ?? []).reduce((counts, row) => {
    const id = row.conversation_id
    counts[id] = (counts[id] ?? 0) + 1
    return counts
  }, {})
}

/**
 * How many threads have something unread — the account-menu badge.
 *
 * A number, not the list: this renders in the header of every page, and pulling
 * every thread with its store join to draw one digit would be the most
 * expensive thing on the site. It is still two requests (the ids, then the
 * unread messages among them) because the answer genuinely depends on both
 * tables — but both columns are indexed and neither returns a body.
 */
export async function fetchUnreadThreadCount(userId) {
  if (!userId) return 0

  const { data, error } = await supabase
    .from('conversations')
    .select('id')
    .eq('customer_id', userId)
    .not('last_message_at', 'is', null)

  if (error) throw error

  const counts = await fetchUnreadCountsByConversation((data ?? []).map((row) => row.id))
  return Object.keys(counts).filter((id) => counts[id] > 0).length
}

/** One thread, with its store — `null` when it is not the customer's (RLS). */
export async function fetchConversation(conversationId) {
  if (!conversationId) return null

  const { data, error } = await supabase
    .from('conversations')
    .select(CONVERSATION_SELECT)
    .eq('id', conversationId)
    .maybeSingle()

  if (error) throw error
  if (!data) return null

  return { ...data, store: data.stores ?? null }
}

/** A thread's messages, oldest first — the order a chat reads in. */
export async function fetchMessages(conversationId, { limit = MESSAGE_PAGE_SIZE } = {}) {
  if (!conversationId) return []

  const { data, error } = await supabase
    .from('messages')
    .select(MESSAGE_SELECT)
    .eq('conversation_id', conversationId)
    .order('created_at', { ascending: true })
    .limit(limit)

  if (error) throw error
  return sortMessages(data ?? [])
}

/**
 * The thread with this maker, creating it if it is the first time.
 *
 * `UNIQUE(store_id, customer_id)` is what makes the lookup-then-insert safe in
 * practice: a double tap that races itself produces one row and one 23505, and
 * the catch below turns that error back into the lookup rather than showing the
 * customer a unique-violation. That is also why this is the only INSERT in the
 * file — every later message goes into the thread this returns.
 */
export async function findOrCreateConversation({ storeId, customerId }) {
  const payload = buildConversation({ storeId, customerId })
  if (!payload) return null

  const { data: existing, error: lookupError } = await supabase
    .from('conversations')
    .select('id')
    .eq('store_id', storeId)
    .eq('customer_id', customerId)
    .maybeSingle()

  if (lookupError) throw lookupError
  if (existing) return existing.id

  const { data: created, error: insertError } = await supabase
    .from('conversations')
    .insert(payload)
    .select('id')
    .single()

  if (!insertError) return created.id

  // A concurrent insert won the race: the row exists, so use it.
  const { data: race, error: raceError } = await supabase
    .from('conversations')
    .select('id')
    .eq('store_id', storeId)
    .eq('customer_id', customerId)
    .maybeSingle()

  if (raceError) throw raceError
  if (race) return race.id

  throw insertError
}

/**
 * Send one message, and return the stored row.
 *
 * The conversation's `last_message_at` / `last_message_preview` and the other
 * party's *in-app* notification are both the database's job (see the notes at
 * the top of this file), so this is a single insert and a `select()` — with the
 * row returned so the caller can put the *stored* message in the thread rather
 * than the one it hoped for.
 *
 * ## …and the one thing that is the client's job
 *
 * The **push** is fired here, from the row the database just gave back. It is
 * the client's job because there is nothing on the server to do it: no `pg_net`
 * trigger on `messages`, and the only call site in the project is the Flutter
 * app's `message_service.dart`, which invokes the function itself once the insert
 * succeeds. A portal reply therefore lit the customer's bell (the
 * `notify_on_new_message` trigger fires for any seller insert, whichever client
 * made it) and never touched their phone.
 *
 * Both directions go through here — the seller's reply and the customer's — and
 * that is deliberate: it is the same event for both sides, the function resolves
 * the recipient from `sender_type`, and a second call site is a second place for
 * one direction to quietly go missing. See `messagePush.js` for why it is fire
 * and forget.
 */
export async function sendMessage(row) {
  if (!row) return null

  const { data, error } = await supabase
    .from('messages')
    .insert(row)
    .select(MESSAGE_SELECT)
    .single()

  if (error) throw error

  triggerMessagePush(data)
  return data
}

/**
 * Mark every message from the maker as read in one call.
 *
 * The RPC's own parameter names (`convo_id`, `reader_role`), because that is
 * what PostgREST matches on. It cannot go through the table: there is no UPDATE
 * policy, and an UPDATE that matches nothing returns `200 OK`.
 */
export async function markConversationRead(conversationId, readerType = CUSTOMER_SENDER_TYPE) {
  if (!conversationId) return

  const { error } = await supabase.rpc('mark_conversation_read', {
    convo_id: conversationId,
    reader_role: readerType,
  })

  if (error) throw error
}

/** Mark one message read — kept for completeness; the thread uses the batch one. */
export async function markMessageRead(messageId) {
  if (!messageId) return

  const { error } = await supabase.rpc('mark_message_read', { message_id: messageId })
  if (error) throw error
}

/**
 * Delete one of the customer's own messages.
 *
 * Unlike the notifications table this is a **real** delete, and the RLS policy
 * (`customer_delete_own_messages`) scopes it to `sender_id = auth.uid()`, so a
 * message that is not theirs matches nothing. It disappears for both parties —
 * `trg_update_conversation_on_message_delete` rolls the inbox preview back to
 * the newest surviving message.
 */
export async function deleteMessage(messageId) {
  if (!messageId) return

  const { error } = await supabase.from('messages').delete().eq('id', messageId)
  if (error) throw error
}

/**
 * Watch one thread.
 *
 * The callback receives `{ eventType, row }` and is folded into the cached list
 * by `mergeMessage` — pure, tested, and idempotent, because Realtime echoes a
 * sender's own INSERT back to them and a resubscribe can replay.
 *
 * Returns the channel so the caller can remove it on unmount. A `filter` on
 * `conversation_id` is applied server-side, which is what keeps a busy
 * marketplace from streaming every message in the world into one chat page.
 */
export function subscribeToConversation(conversationId, onChange) {
  if (!conversationId) return null

  const channel = supabase
    .channel(`messages:${conversationId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'messages',
        filter: `conversation_id=eq.${conversationId}`,
      },
      (payload) => onChange({ eventType: payload.eventType, row: payload.new ?? payload.old }),
    )
    .subscribe()

  return channel
}

/**
 * Watch the inbox.
 *
 * Subscribes to `conversations`, not `messages`: the trigger already moves
 * `last_message_at` on every new message, so a thread changing is exactly the
 * event the list needs, and it is one row per change instead of a stream of
 * every message the customer has ever been sent.
 */
export function subscribeToInbox(customerId, onChange) {
  if (!customerId) return null

  const channel = supabase
    .channel(`inbox:${customerId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'conversations',
        filter: `customer_id=eq.${customerId}`,
      },
      () => onChange(),
    )
    .subscribe()

  return channel
}
