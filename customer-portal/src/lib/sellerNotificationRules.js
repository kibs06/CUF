/**
 * The seller notification feed's rules — a port of
 * `lib/screens/seller/seller_notification_center_screen.dart` and the five
 * creation helpers in `lib/services/seller_notification_service.dart`.
 *
 * `seller_notifications` is the seller's own table: keyed by `store_id` (not by
 * user), written by the app, by the `create_gcash_checkout` RPC when a payment
 * proof is submitted, and — since July — readable and updatable by the store's
 * owner through RLS. Every row has been accumulating for months with nothing on
 * the web able to read one.
 *
 * ## The five types, and why an unknown one is not a crash
 *
 * `new_order`, `stale_order`, `low_stock`, `custom_order_request`, `new_message`
 * are the five the app creates. The column's original CHECK constraint only
 * listed four — `new_message` was added by the service without a migration that
 * relaxes it — so the portal has to survive a type it has never heard of, and
 * an unrecognised one is drawn with a label made from its own name rather than
 * dropped from the feed. A missing notification is a seller not being told
 * something; a card with a slightly generic label is not.
 *
 * ## A destination, not a path
 *
 * `sellerNotificationDestination` returns a *description* of where a card goes
 * (`{ kind: 'order', orderId }`) rather than a URL, so `Link` stays out of a
 * rules module and the page decides which of the answers it can serve. The app
 * switches on the type in its `_handleTap`, and this is that switch — including
 * the two cases the portal cannot honour yet: a custom order request (there is
 * no custom-orders screen here) and any type it does not know, which are inert
 * rather than wrong.
 */

import {
  notificationMessageCount,
  notificationMetadata,
  notificationPreviews,
  notificationRelativeTime,
} from './notificationRules.js'

// Re-exported so a screen imports "seller notifications" from one place. These
// two are generic — the batching trigger writes the same `metadata.previews`
// shape into this table and into the customer one, so the reader is shared
// rather than copied.
export { notificationPreviews, notificationRelativeTime }

/** Every type the app can create, in the order the app's centre lists them. */
export const SELLER_NOTIFICATION_TYPES = [
  'new_order',
  'stale_order',
  'low_stock',
  'custom_order_request',
  'new_message',
]

/** The label a type it does not know is drawn with. */
export const OTHER_SELLER_NOTIFICATION_TYPE = 'other'

const TYPE_LABELS = {
  new_order: 'New order',
  stale_order: 'Needs attention',
  low_stock: 'Low stock',
  custom_order_request: 'Custom order',
  new_message: 'Message',
}

function normalize(value) {
  return String(value ?? '').trim().toLowerCase()
}

/**
 * A row's type, or `other`.
 *
 * Deliberately **not** defaulting to one of the five the way the customer side
 * defaults an unknown category to `unpaid`: `unpaid` is a category a row could
 * honestly have, while here every type means something specific about the work
 * ("a customer ordered", "a size is nearly gone"). Guessing would put a colour
 * and an icon on a card that says something untrue about it.
 */
export function sellerNotificationType(value) {
  const type = normalize(value)
  return SELLER_NOTIFICATION_TYPES.includes(type) ? type : OTHER_SELLER_NOTIFICATION_TYPE
}

/**
 * What a type is called on a chip and on a card.
 *
 * An unknown type gets its own name, separators removed and the first word
 * capitalised (`payment_confirmed` → "Payment confirmed") instead of a shrug
 * like "Other": the raw value is the only true thing anyone can say about it,
 * and it is exactly what a seller would need to quote when asking why they got
 * one. Sentence case, not title case, because that is what every other label
 * here uses.
 */
export function sellerNotificationTypeLabel(value) {
  const type = sellerNotificationType(value)
  if (type !== OTHER_SELLER_NOTIFICATION_TYPE) return TYPE_LABELS[type]

  const raw = normalize(value)
  if (!raw) return 'Update'

  const words = raw.split(/[^a-z0-9]+/).filter(Boolean)
  const sentence = words.join(' ')
  return sentence.charAt(0).toUpperCase() + sentence.slice(1)
}

/** The order, product or conversation a row points at — `reference_id`. */
export function sellerNotificationReferenceId(row) {
  const value = row?.reference_id
  return value === null || value === undefined || value === '' ? null : String(value)
}

/**
 * The thread a `new_message` row points at.
 *
 * Both places are checked because the two writers disagree: the app's
 * `createNewMessage` puts the conversation in `reference_id`, and the batching
 * paths in SQL put it in `metadata.conversation_id`. A card that links to the
 * inbox because it read only one of them is a card that did not do its job.
 */
export function sellerNotificationConversationId(row) {
  const fromMetadata = notificationMetadata(row)?.conversation_id
  if (fromMetadata) return String(fromMetadata)

  return sellerNotificationType(row?.type) === 'new_message'
    ? sellerNotificationReferenceId(row)
    : null
}

/** How many messages the batching trigger has folded into this card. */
export function sellerNotificationMessageCount(row) {
  return notificationMessageCount(row)
}

/** Whether this card stands for more than one message. */
export function isBatchedSellerNotification(row) {
  return sellerNotificationMessageCount(row) > 1
}

/**
 * Where a card goes when it is tapped — the app's `_handleTap`, as data.
 *
 *   1. `new_order` / `stale_order` → the order, or the orders list when the row
 *      carries no reference (the list is the honest fallback: the seller still
 *      needs to find it, and "which order?" is answerable there);
 *   2. `low_stock` → the product's own page, which is where stock is edited, or
 *      the catalogue when there is no product to point at;
 *   3. `new_message` → the thread, or the inbox;
 *   4. `custom_order_request` → nowhere. The app opens
 *      `CustomOrdersScreen`, which this portal does not have; a link to a page
 *      that does not exist is worse than a card that admits it is inert.
 *
 * An unknown type is `none` for the same reason, and that matches the app's own
 * `switch`, which has no `default` branch either.
 */
export function sellerNotificationDestination(row) {
  const type = sellerNotificationType(row?.type)
  const referenceId = sellerNotificationReferenceId(row)

  if (type === 'new_order' || type === 'stale_order') {
    return referenceId ? { kind: 'order', orderId: referenceId } : { kind: 'orders' }
  }

  if (type === 'low_stock') {
    return referenceId ? { kind: 'product', productId: referenceId } : { kind: 'products' }
  }

  if (type === 'new_message') {
    const conversationId = sellerNotificationConversationId(row)
    return conversationId ? { kind: 'conversation', conversationId } : { kind: 'messages' }
  }

  return { kind: 'none' }
}

/**
 * The feed, filtered the way the chip row filters it, newest first.
 *
 * Sorted here as well as in the query, for the reason the customer feed is: a
 * row merged in from a realtime event has no guaranteed position, and a feed
 * that is sometimes in order is worse than one that is visibly unsorted.
 */
export function filterSellerNotifications(notifications, { type = null } = {}) {
  const wanted = type ? sellerNotificationType(type) : null

  return [...(notifications ?? [])]
    .filter((row) => !wanted || sellerNotificationType(row?.type) === wanted)
    .sort(
      (a, b) => new Date(b?.created_at ?? 0) - new Date(a?.created_at ?? 0),
    )
}

/**
 * Unread count for the badge and the chips.
 *
 * `type` is matched through `sellerNotificationType` so `other` is a filter the
 * chips can actually use — it is how a seller sees the one card they cannot
 * otherwise isolate.
 */
export function unreadSellerNotificationCount(notifications, { type = null } = {}) {
  const wanted = type ? sellerNotificationType(type) : null

  return (notifications ?? []).filter(
    (row) => !row?.is_read && (!wanted || sellerNotificationType(row?.type) === wanted),
  ).length
}

/**
 * Unread per type, as `{ new_order: 2, low_stock: 1, … }`.
 *
 * Includes `other`, which is what makes the chips' counts agree with the badge:
 * a count built from the five known types alone would silently lose an unknown
 * one and the badge would sit at 1 with nothing on screen to clear it.
 */
export function unreadCountsBySellerType(notifications) {
  const counts = Object.fromEntries(
    [...SELLER_NOTIFICATION_TYPES, OTHER_SELLER_NOTIFICATION_TYPE].map((type) => [type, 0]),
  )

  for (const row of notifications ?? []) {
    if (row?.is_read) continue
    counts[sellerNotificationType(row?.type)] += 1
  }

  return counts
}

/**
 * The types actually present in a feed, known ones first and in the app's
 * order, so the chip row cannot grow a chip for every type in the schema on a
 * store that has only ever had orders.
 */
export function sellerNotificationTypesPresent(notifications) {
  const seen = new Set((notifications ?? []).map((row) => sellerNotificationType(row?.type)))
  const known = SELLER_NOTIFICATION_TYPES.filter((type) => seen.has(type))

  return seen.has(OTHER_SELLER_NOTIFICATION_TYPE)
    ? [...known, OTHER_SELLER_NOTIFICATION_TYPE]
    : known
}
