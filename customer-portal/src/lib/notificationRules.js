/**
 * The notification feed's rules — a port of `lib/models/notification_category.dart`
 * and `lib/models/app_notification.dart`, plus the feed filters from
 * `lib/screens/notifications_screen.dart`.
 *
 * The portal had none of this: the `notifications` table has existed since July
 * with select/update RLS scoped to `auth.uid() = user_id`, triggers that write a
 * row on every order status change, and — since the messaging work — a batching
 * trigger that folds several messages from one conversation into a single card
 * with previews. All of that was being generated for customers and read by
 * nobody on the web.
 *
 * ## The two things that make this more than a list
 *
 *  1. **Categories are nine, not five.** The original migration created
 *     `unpaid, processing, shipped, review, returns`; later ones added
 *     `message` (a seller wrote to you), `support` (a reply to a report),
 *     `approval` (a seller application) and `reservations`. The portal has to
 *     understand all nine, because the database will send it all nine.
 *  2. **A card can be a batch.** `metadata.previews` holds up to three
 *     `{sender, text, timestamp}` previews with the newest first, and
 *     `metadata.message_count` says how many are folded in; the app renders the
 *     rest as "N new messages". A card that says "3 new messages" is a
 *     different thing from one that says "You have a message", and the portal
 *     can't tell them apart without this.
 *
 * The `metadata` column arrives from PostgREST as a JSON object, but the app
 * also accepts a JSON *string* (`fromMap` parses both), so both are accepted
 * here: a row written by a hand-run script or an older client is not a crash.
 */

/** Every category the database can send, in the app's enum order. */
export const NOTIFICATION_CATEGORIES = [
  'unpaid',
  'processing',
  'shipped',
  'review',
  'returns',
  'message',
  'support',
  'approval',
  'reservations',
]

/** The app's `notificationCategoryLabel`. */
const CATEGORY_LABELS = {
  unpaid: 'Unpaid',
  processing: 'Processing',
  shipped: 'Shipped',
  review: 'Review',
  returns: 'Returns',
  message: 'Message',
  support: 'Support',
  approval: 'Approval',
  reservations: 'Reservation',
}

/**
 * A category from a row. Anything unrecognised resolves to `unpaid`, which is
 * the app's `_parseCategory` default — not to `null`, because a category drives
 * an icon and a filter chip and an unknown one must still render as *something*
 * rather than vanish from the feed.
 */
export function notificationCategory(value) {
  const name = String(value ?? '').trim().toLowerCase()
  return NOTIFICATION_CATEGORIES.includes(name) ? name : 'unpaid'
}

export function notificationCategoryLabel(value) {
  return CATEGORY_LABELS[notificationCategory(value)]
}

/**
 * The feed's tabs (`notifications_screen.dart`: "Tabs filter by order source:
 * All / Catalog / Custom").
 */
export const NOTIFICATION_TABS = [
  { value: 'all', label: 'All' },
  { value: 'catalog', label: 'Catalog' },
  { value: 'custom', label: 'Custom' },
]

/**
 * Which tab a row belongs to: `order_type`, defaulting to `catalog`.
 *
 * The column is `NOT NULL DEFAULT 'catalog'`, so this only matters for a row
 * written before the column existed — which is a real case, because the
 * migration that added it had to backfill with exactly this default.
 */
export function notificationOrderType(row) {
  return String(row?.order_type ?? '').trim().toLowerCase() === 'custom'
    ? 'custom'
    : 'catalog'
}

/** A row's `metadata`, whether it arrived as an object or as a JSON string. */
export function notificationMetadata(row) {
  const raw = row?.metadata
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) return raw
  if (typeof raw === 'string' && raw.trim()) {
    try {
      const parsed = JSON.parse(raw)
      // An array is an object, and `metadata` must not be one: every reader
      // below indexes it by key, so `[]` would have to be guarded again in each
      // of them rather than once here.
      return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null
    } catch {
      return null
    }
  }
  return null
}

/** How many messages the batching trigger has folded into this card. */
export function notificationMessageCount(row) {
  const raw = notificationMetadata(row)?.message_count
  const count = Number(raw)
  return Number.isFinite(count) && count > 0 ? Math.floor(count) : 1
}

/** The conversation a `message` card points at, if it carries one. */
export function notificationConversationId(row) {
  const value = notificationMetadata(row)?.conversation_id
  return value ? String(value) : null
}

/** The store that wrote to you — used as the card's "from" name. */
export function notificationStoreName(row) {
  const value = notificationMetadata(row)?.store_name
  return value ? String(value) : null
}

/**
 * The folded-in previews, newest first — the app's `previews` getter.
 *
 * Each is `{ sender, text, timestamp }`; anything without text is dropped, so a
 * half-written row cannot add an empty line to a card.
 */
export function notificationPreviews(row) {
  const raw = notificationMetadata(row)?.previews
  if (!Array.isArray(raw)) return []

  return raw
    .map((entry) => {
      if (!entry || typeof entry !== 'object') return null
      const text = String(entry.text ?? '').trim()
      if (!text) return null
      return {
        sender: String(entry.sender ?? '').trim(),
        text,
        timestamp: entry.timestamp ? String(entry.timestamp) : null,
      }
    })
    .filter(Boolean)
}

/** Whether this card stands for more than one message — `isBatched`. */
export function isBatchedNotification(row) {
  return notificationMessageCount(row) > 1
}

/**
 * Where a card goes when it is tapped — the app's `onTap`, in the app's order.
 *
 *   1. a message with a `conversation_id` → the thread;
 *   2. a support reply → the customer's reports (which the portal does NOT have
 *      yet, so this is reported as `reports` and the caller leaves the card
 *      inert rather than sending a customer to a 404);
 *   3. anything with an `order_id` → that order.
 *
 * Returning a description of the destination rather than a path is what lets
 * the page opt out of the one case it cannot serve, and it keeps `Link` out of
 * a rules module.
 */
export function notificationDestination(row) {
  if (notificationCategory(row?.category) === 'message') {
    const conversationId = notificationConversationId(row)
    if (conversationId) return { kind: 'conversation', conversationId }
  }

  if (notificationCategory(row?.category) === 'support') {
    return { kind: 'reports' }
  }

  const orderId = row?.order_id ? String(row.order_id) : null
  if (orderId) return { kind: 'order', orderId }

  // An `approval` or a `reservations` card with no order: there is nothing in
  // the portal behind it yet, and an untappable card is better than a wrong one.
  return { kind: 'none' }
}

/**
 * The feed, filtered the way the screen's tab bar and category chip filter it.
 *
 * Sorted newest first, which is also the order the query asks for — done again
 * here so a caller that merges a realtime insert into the list cannot leave the
 * feed out of order.
 */
export function filterNotifications(notifications, { tab = 'all', category = null } = {}) {
  return [...(notifications ?? [])]
    .filter((row) => {
      if (tab !== 'all' && notificationOrderType(row) !== tab) return false
      if (category && notificationCategory(row.category) !== notificationCategory(category)) {
        return false
      }
      return true
    })
    .sort((a, b) => new Date(b?.created_at ?? 0) - new Date(a?.created_at ?? 0))
}

/** Unread count for the header badge and the per-category chips. */
export function unreadNotificationCount(notifications, { category = null } = {}) {
  return (notifications ?? []).filter(
    (row) =>
      !row?.is_read &&
      (!category || notificationCategory(row.category) === notificationCategory(category)),
  ).length
}

/** Unread per category, as `{ unpaid: 2, message: 1, … }` for every category. */
export function unreadCountsByCategory(notifications) {
  const counts = Object.fromEntries(NOTIFICATION_CATEGORIES.map((name) => [name, 0]))

  for (const row of notifications ?? []) {
    if (row?.is_read) continue
    counts[notificationCategory(row.category)] += 1
  }

  return counts
}

/**
 * The app's `relativeTime`: "Just now", "5m ago", "2h ago", "3d ago", "2w ago",
 * "4mo ago".
 *
 * `now` is a parameter because a relative string that can only be tested against
 * the clock is a test that passes at 23:59 and fails at 00:00.
 */
export function notificationRelativeTime(value, now = Date.now()) {
  // `null` has to be caught before `new Date`, which reads it as the epoch —
  // and "20658d ago" on a blank timestamp is worse than no timestamp at all.
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
  if (days < 7) return `${days}d ago`
  if (days < 30) return `${Math.floor(days / 7)}w ago`
  return `${Math.floor(days / 30)}mo ago`
}
