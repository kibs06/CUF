/**
 * The push that tells the other side a message arrived — the payload rules.
 *
 * ## Why this is the portal's job at all
 *
 * The database does half of it and none of the other half. `notify_on_new_message`
 * (see `20260725000000_batch_message_notifications.sql`) writes the customer's
 * in-app notification row when a **seller** inserts a message, and that trigger
 * has no idea which client inserted it, which is exactly why the portal's replies
 * light the customer's bell.
 *
 * The **push** is not in the database at all. There is no `pg_net` trigger on
 * `messages` — the only call site anywhere is `message_service.dart`, which
 * invokes `send-message-push` itself after a successful insert, fire and forget.
 * So the app pushes and the portal did not, and a customer whose phone was in
 * their pocket when the shop answered heard nothing: the bell lit, the phone
 * stayed quiet, and so did the seller's side when a customer wrote from the web.
 *
 * ## What it deliberately does not decide
 *
 * **Who** the push goes to, and **what it says**. The function looks up the
 * conversation, finds the store owner or the customer by `sender_type`, and takes
 * the title from the database's own `stores.name` or `profiles.full_name`. That
 * is why the payload is four fields: an id, a sender, a side and some text. A
 * client that assembled a title here would be a second source for a name the
 * server already has, and the one on the phone would be the one that goes stale.
 *
 * **How long the body may be.** The function truncates at 100 characters, as does
 * the notification trigger before it. Two places doing that would be two answers
 * to "how much of a message does a lock screen show".
 */

/** The Edge Function, named once so a test can assert the call site. */
export const MESSAGE_PUSH_FUNCTION = 'send-message-push'

/**
 * The sides the function accepts, in its own words.
 *
 * It skips anything else with a log line, so a payload built with a third value
 * would be a request whose only possible outcome is silence.
 */
export const MESSAGE_PUSH_SENDER_TYPES = ['customer', 'seller']

/** A trimmed string, or `''` — every field here arrives from a row or from a caller. */
function text(value) {
  return String(value ?? '').trim()
}

/**
 * The body to POST, or `null` when there is nobody to push to.
 *
 * `null` means "do not make the request", and every case that returns it is a
 * request that could not have worked: no conversation to look up, no sender to
 * name, or a side the function refuses. `sender_id` matters even though the
 * function only reads it to title a customer→seller push — a seller's push takes
 * the store's name, but a *missing* id there is still a row assembled wrong, and
 * a row assembled wrong is worth being loud about rather than pushing a message
 * from nobody.
 *
 * The `body` key is left off when empty rather than sent as `''`: the function
 * already has a fallback for a message with no text, and sending an empty string
 * would take that decision away from it while making the same choice anyway.
 */
export function messagePushPayload(row) {
  const conversationId = text(row?.conversation_id ?? row?.conversationId)
  const senderId = text(row?.sender_id ?? row?.senderId)
  const senderType = text(row?.sender_type ?? row?.senderType).toLowerCase()

  if (!conversationId || !senderId) return null
  if (!MESSAGE_PUSH_SENDER_TYPES.includes(senderType)) return null

  const payload = {
    conversation_id: conversationId,
    sender_id: senderId,
    sender_type: senderType,
  }

  const body = text(row?.body)
  if (body) payload.body = body

  return payload
}
