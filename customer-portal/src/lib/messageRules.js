/**
 * Messaging rules — a port of `lib/services/message_service.dart`,
 * `lib/models/conversation.dart` / `message.dart`, and the quick-message options
 * in `lib/widgets/order_quick_message_sheet.dart`.
 *
 * ## What was already there
 *
 * `20260713_messaging.sql` created `conversations` (one per `(store_id,
 * customer_id)`) and `messages`, with RLS that lets a customer read and write
 * only their own threads, a trigger maintaining `last_message_at` /
 * `last_message_preview` on every insert, `mark_message_read` and
 * `mark_conversation_read` RPCs (because there is deliberately **no** client
 * UPDATE policy on `messages`), and both tables added to the
 * `supabase_realtime` publication. The app has had a full chat for months. The
 * portal had none of it.
 *
 * ## The four rules that are easy to get wrong
 *
 *  1. **A thread with no messages sorts FIRST, not last.** The app orders by
 *     `last_message_at` descending with `nullsFirst: true` — so a conversation
 *     just opened from a store page sits at the top of the inbox, which is
 *     where the customer who just opened it is looking.
 *  2. **`sender_type` is not `sender_id`.** A deleted account nulls
 *     `messages.sender_id` (`ON DELETE SET NULL`) while `sender_type` survives,
 *     so "who said this" must read the type, and the side of the bubble the
 *     message sits on cannot depend on the id being there.
 *  3. **Unread means unread from the OTHER party.** A customer's own messages
 *     are `is_read = false` until the seller reads them; counting them as the
 *     customer's unread would badge a thread the moment they replied to it.
 *  4. **The preview is 140 characters**, because that is what the trigger
 *     writes (`left(NEW.body, 140)`) — the same width in the list and in the
 *     row, so nothing has to be re-truncated differently.
 *  5. **`body` is nullable.** A later migration made a message
 *     attachment-only (`body IS NOT NULL OR attachment_url IS NOT NULL`), so a
 *     bubble with no text is a normal message rather than a broken one, and
 *     the inbox preview for it is the trigger's own words: `📷 Photo` /
 *     `🎥 Video`.
 */

/** The trigger's `left(NEW.body, 140)`. */
export const MESSAGE_PREVIEW_LENGTH = 140

/** The app's `_activeOrderOptions`, in its order and with its exact wording. */
const ACTIVE_ORDER_MESSAGES = [
  'When will my order ship?',
  'Can I still change the size/color?',
  'Can I update my delivery address?',
  'Is my order still on track?',
]

/** The app's `_completedOrderOptions`. */
const COMPLETED_ORDER_MESSAGES = [
  'I have an issue with my order',
  "I'd like to leave feedback",
]

/**
 * Which quick messages an order offers — the app's `_isCompletedOrder`
 * (`cancelled`, `delivered` or `received`).
 */
export function quickOrderMessages(orderStatus) {
  const status = String(orderStatus ?? '').trim().toLowerCase()
  const completed = status === 'cancelled' || status === 'delivered' || status === 'received'
  return completed ? COMPLETED_ORDER_MESSAGES : ACTIVE_ORDER_MESSAGES
}

/**
 * The inbox, in the app's order: most recent activity first, and a thread with
 * no messages at all at the very top (`nullsFirst`), because the customer who
 * just opened it is looking for it right now.
 */
export function sortConversations(conversations) {
  return [...(conversations ?? [])].sort((a, b) => {
    const aTime = a?.last_message_at ? new Date(a.last_message_at).getTime() : null
    const bTime = b?.last_message_at ? new Date(b.last_message_at).getTime() : null

    if (aTime === null && bTime === null) {
      return new Date(b?.created_at ?? 0) - new Date(a?.created_at ?? 0)
    }
    if (aTime === null) return -1
    if (bTime === null) return 1
    if (bTime !== aTime) return bTime - aTime

    return new Date(b?.created_at ?? 0) - new Date(a?.created_at ?? 0)
  })
}

/** What the inbox row says under the store's name. */
export function conversationPreview(conversation) {
  const preview = String(conversation?.last_message_preview ?? '').trim()
  if (!preview) return 'No messages yet'

  return preview.length > MESSAGE_PREVIEW_LENGTH
    ? `${preview.slice(0, MESSAGE_PREVIEW_LENGTH - 1)}…`
    : preview
}

/**
 * The thread, oldest first — what a chat reads in. Re-sorted here rather than
 * trusted from the query because a realtime insert arrives in whatever order
 * Postgres felt like, and the app sorts client-side for the same reason.
 */
export function sortMessages(messages) {
  return [...(messages ?? [])].sort(
    (a, b) => new Date(a?.created_at ?? 0) - new Date(b?.created_at ?? 0),
  )
}

/**
 * Unread messages from the other party.
 *
 * `readerType` is the reader's own side: a customer counts `seller` messages
 * that are unread, never their own.
 */
export function unreadFromOther(messages, readerType = 'customer') {
  const other = readerType === 'customer' ? 'seller' : 'customer'
  return (messages ?? []).filter((message) => message?.sender_type === other && !message?.is_read)
    .length
}

/** Whether a message is the customer's own — by `sender_type`, not by id. */
export function isMine(message, readerType = 'customer') {
  return message?.sender_type === readerType
}

/** A body worth sending, or null. Whitespace is not a message. */
export function messageBody(value) {
  const body = String(value ?? '').trim()
  return body || null
}

/**
 * The row an outbound message becomes.
 *
 * `sender_type` is hard-coded to the reader's side because the RLS policy
 * requires it (`sender_type = 'customer'` for a customer insert): a payload
 * that got it from anywhere else would be rejected by the database, so building
 * it here means the mistake cannot be made at a call site.
 */
export function buildOutgoingMessage({
  conversationId,
  customerId,
  body,
  orderReferenceId = null,
  readerType = 'customer',
}) {
  const text = messageBody(body)
  if (!conversationId || !customerId || !text) return null

  return {
    conversation_id: conversationId,
    sender_id: customerId,
    sender_type: readerType,
    body: text,
    order_reference_id: orderReferenceId ?? null,
  }
}

/** The row a new thread becomes — `customers may insert` is the RLS rule. */
export function buildConversation({ storeId, customerId }) {
  if (!storeId || !customerId) return null
  return { store_id: storeId, customer_id: customerId }
}

/** A message's text, or null — the column is nullable for attachments. */
export function messageText(message) {
  return messageBody(message?.body)
}

/**
 * A message's attachment, or null.
 *
 * `attachment_url` is a **signed** storage URL with a year on it (the app
 * signs at upload time and stores the URL), so it can go straight into an
 * `img` — the portal never signs anything itself. It also never uploads:
 * taking the photo is a phone's job, and the private bucket's INSERT policy is
 * the app's path.
 */
export function messageAttachment(message) {
  const url = String(message?.attachment_url ?? '').trim()
  if (!url) return null

  const type = String(message?.attachment_type ?? '').trim().toLowerCase()
  const thumbnailUrl = String(message?.attachment_thumbnail_url ?? '').trim()

  return {
    url,
    type: type === 'video' ? 'video' : 'image',
    thumbnailUrl: thumbnailUrl || null,
  }
}

/**
 * What a message reads as in one line — the trigger's own words for an
 * attachment-only message, so the inbox and the bubble agree.
 */
export function messagePreviewText(message) {
  const text = messageText(message)
  if (text) return text

  const attachment = messageAttachment(message)
  if (!attachment) return ''
  return attachment.type === 'video' ? '🎥 Video' : '📷 Photo'
}

/**
 * Fold one realtime event into the thread.
 *
 * Realtime is why the chat needs no refresh button, and it is also why this is
 * a pure function with tests rather than a `setState` inside the subscription
 * callback: a channel can deliver the same row twice (an INSERT echoed back to
 * its own sender, a resubscribe replaying recent changes), and a chat that
 * shows a message twice or out of order reads as broken in a way no error
 * message explains.
 *
 *  * `INSERT` — added when the id is new, replaced when it is not.
 *  * `UPDATE` — patched in place, and *ignored* when the row is not in the list
 *    (an update to a message the customer has not loaded yet is not something
 *    to guess a position for; the next fetch has it).
 *  * `DELETE` — removed. This rarely fires: `messages` has the default replica
 *    identity, so a DELETE event carries only the primary key and cannot be
 *    filtered by `conversation_id` server-side. The thread refetches when the
 *    tab regains focus, which is when the other party's deletion actually
 *    becomes visible.
 */
export function mergeMessage(messages, { eventType, row } = {}) {
  const list = sortMessages(messages)
  const id = row?.id ? String(row.id) : null
  if (!id) return list

  const type = String(eventType ?? '').toUpperCase()

  if (type === 'DELETE') {
    return list.filter((message) => String(message?.id) !== id)
  }

  if (type === 'UPDATE') {
    return list.map((message) => (String(message?.id) === id ? { ...message, ...row } : message))
  }

  const without = list.filter((message) => String(message?.id) !== id)
  return sortMessages([...without, row])
}

/**
 * What a thread can honestly say about the messages it is showing.
 *
 * Four states, and the difference between two of them is the whole point:
 *
 *  * `ready` — the read came back and the list is the conversation.
 *  * `empty` — the read came back and there is genuinely nothing in it.
 *  * `failed` — the read did not come back, and there is nothing to show. The
 *    thread must NOT say "say hello to them" here: that is a lie about a
 *    conversation that may be months long, and it is the kind of lie nobody can
 *    act on. Something has to say the read failed.
 *  * `partial` — the read did not come back, but messages are on screen anyway,
 *    because realtime delivered them. This is the state that produces the
 *    confusing bug report "the history is missing but new messages arrive":
 *    without saying so, a live thread looks like a complete one.
 *
 * RLS is why this exists. A denied read is not an error — PostgREST answers
 * `200 []` — and a *cancelled* read looks the same as one that never happened,
 * so "empty" is the default assumption unless the query itself says otherwise.
 */
export function threadHistoryState({ isError = false, count = 0 } = {}) {
  const messages = Number(count) > 0
  if (isError) return messages ? 'partial' : 'failed'
  return messages ? 'ready' : 'empty'
}

/**
 * Whether the thread needs a `mark_conversation_read` call.
 *
 * Marking read is a write, and a write on every render of a live thread is a
 * write per realtime event. This answers whether there is anything to mark at
 * all, which is the only case worth a round trip.
 */
export function needsMarkRead(messages, readerType = 'customer') {
  return unreadFromOther(messages, readerType) > 0
}

/**
 * The app's `Message.relativeTime` / `Conversation.relativeTime`, which is NOT
 * the notification feed's ladder: these rungs are `Just now`, `${n}m ago`,
 * `${n}h ago`, `${n}d ago` and `${n}mo ago` at 30 days — no week rung, because
 * a week in a chat is still "6d ago" close enough. Kept as its own function
 * rather than reusing the notification one so the two can be tuned apart.
 *
 * `now` is a parameter because a relative string that can only be tested
 * against the clock is a test that passes at 23:59 and fails at 00:00.
 */
export function messageRelativeTime(value, now = Date.now()) {
  // `null` has to be caught before `new Date`, which reads it as the epoch —
  // and "20658d ago" on a thread that has never been written to is worse than
  // no timestamp at all.
  if (value === null || value === undefined || value === '') return ''

  const created = new Date(value).getTime()
  if (!Number.isFinite(created)) return ''

  const seconds = Math.floor((Number(now) - created) / 1000)
  if (seconds < 60) return 'Just now'

  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m ago`

  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`

  const days = Math.floor(hours / 24)
  if (days < 30) return `${days}d ago`
  return `${Math.floor(days / 30)}mo ago`
}

/**
 * The unread count a thread's pill shows — the app's `> 9 ? '9+' : count`.
 *
 * A four-digit badge would push the row's layout around, and "12" and "9+"
 * tell a customer the same thing: there is a pile of unread messages here.
 */
export function unreadBadgeLabel(count) {
  const value = Math.floor(Number(count) || 0)
  if (value <= 0) return null
  return value > 9 ? '9+' : String(value)
}

/**
 * The badge's number: how many *threads* have something unread in them.
 *
 * This is the app's own rule (`loadConversationsForCustomer` counts
 * `if (count > 0) total++`), and it is deliberately not the number of unread
 * messages: the account-menu badge is a "how many conversations need me"
 * number, which is why it can never exceed the size of the inbox.
 */
export function unreadThreadCount(conversations) {
  return (conversations ?? []).filter((row) => (Number(row?.unread_count) || 0) > 0).length
}

/**
 * The key two messages share when they are on the same day — the chat's day
 * separators are drawn when this changes between one message and the next.
 *
 * Local time, not UTC: a message at 08:00 on the 25th in Manila belongs under
 * "25 Sep" for the person reading it, whatever the server's clock says.
 */
export function messageDayKey(value) {
  if (!value) return ''
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`
}

/**
 * `Today` / `Yesterday` / `25 Sep 2026` — the label above a new day.
 *
 * The two words are worth having: a chat read the next morning should not make
 * the reader work out that "25 Sep" was yesterday.
 */
export function messageDayLabel(value, now = new Date()) {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''

  const today = new Date(now)
  const startOf = (input) =>
    new Date(input.getFullYear(), input.getMonth(), input.getDate()).getTime()
  const days = Math.round((startOf(today) - startOf(date)) / 86_400_000)

  if (days === 0) return 'Today'
  if (days === 1) return 'Yesterday'

  return date.toLocaleDateString('en-PH', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  })
}

/**
 * Whether the customer's own last message has been read by the maker — the
 * chat's read receipt. `null` when the last word is not theirs, because a
 * "Read" under the maker's message would mean nothing.
 */
export function readReceiptFor(messages, readerType = 'customer') {
  const list = sortMessages(messages)
  const last = list[list.length - 1]
  if (!last || !isMine(last, readerType)) return null
  return Boolean(last.is_read)
}
