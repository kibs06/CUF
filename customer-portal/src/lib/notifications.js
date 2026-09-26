import { supabase } from './supabase.js'

// The rules live next door; re-exported so screens import "notifications" once.
export * from './notificationRules.js'

/**
 * The customer's notification feed — a port of `NotificationService`.
 *
 * ## What was already there
 *
 * The table, its RLS and its triggers all shipped with the app: `select` and
 * `update` are scoped to `auth.uid() = user_id`, and an `AFTER INSERT` /
 * `AFTER UPDATE OF status` trigger on `orders` writes a row for every step of
 * the buying path (`pending → placed → preparing → ready → received`). A
 * customer's notifications have therefore been accumulating since July with no
 * way to read them on the web. Nothing in this file changes the backend.
 *
 * ## Three things the app's service knows that a naive port would miss
 *
 *  1. **`is_deleted`, not a `DELETE`.** The migration that added it pairs it
 *     with an "allow undo" flow, and there is deliberately **no** client DELETE
 *     policy on the table — so a hard delete would silently match zero rows and
 *     report success, which is the same trap `orders.js` documents for
 *     cancelling. Every read filters `is_deleted = false`.
 *  2. **`category` and `order_type` filters are server-side.**
 *     `notification_category` is a Postgres enum, so filtering in SQL avoids
 *     shipping rows the customer will never see.
 *  3. **The unread badge is a `HEAD` count, not a list.** Fetching every
 *     notification to count the unread ones would make the header — on every
 *     page — download the whole feed. `{ count: 'exact', head: true }` asks
 *     Postgres for a number.
 *
 * ## Realtime
 *
 * Deliberately not wired up, and it is not an oversight: the messaging tables
 * were explicitly added to the `supabase_realtime` publication and
 * `notifications` was not (its delivery path is push, via
 * `push_notification_service.dart`). Subscribing to a table that is not
 * published gives a subscription that silently never fires — worse than none,
 * because the feed would look live. The feed refetches on window focus instead,
 * which is when a customer actually comes back to it.
 */

/** The columns the feed reads. `*` would ship `user_id` and a metadata blob we do not need. */
export const NOTIFICATION_SELECT =
  'id, order_id, category, title, message, order_type, is_read, metadata, created_at'

/**
 * Every notification for one customer, newest first.
 *
 * `userId` is passed explicitly as well as being enforced by RLS: the filter
 * matches the index (`user_id, created_at DESC`), and a query that relies on a
 * policy for its *shape* reads as if it fetched the whole table.
 *
 * `limit` is a guard rather than a page size — a customer with years of orders
 * should get a fast feed, not a thousand rows of HTML.
 */
export async function fetchNotifications(userId, { category = null, orderType = null, limit = 100 } = {}) {
  if (!userId) return []

  let query = supabase
    .from('notifications')
    .select(NOTIFICATION_SELECT)
    .eq('user_id', userId)
    .eq('is_deleted', false)

  if (category) query = query.eq('category', category)
  if (orderType) query = query.eq('order_type', orderType)

  const { data, error } = await query
    .order('created_at', { ascending: false })
    .limit(limit)

  if (error) throw error
  return data ?? []
}

/** How many are unread — the account-menu badge, as a count and not a list. */
export async function fetchUnreadNotificationCount(userId) {
  if (!userId) return 0

  const { count, error } = await supabase
    .from('notifications')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId)
    .eq('is_read', false)
    .eq('is_deleted', false)

  if (error) throw error
  return count ?? 0
}

/** Read, or unread again. Both are a one-column UPDATE the RLS policy allows. */
export async function setNotificationRead(notificationId, isRead = true) {
  const { error } = await supabase
    .from('notifications')
    .update({ is_read: Boolean(isRead) })
    .eq('id', notificationId)

  if (error) throw error
}

/**
 * Mark everything unread as read, optionally just one category — the app's
 * `markAllAsRead`. `is_read = false` in the filter is what keeps it from
 * rewriting every row in the customer's history on every press.
 */
export async function markAllNotificationsRead(userId, { category = null } = {}) {
  if (!userId) return

  let query = supabase
    .from('notifications')
    .update({ is_read: true })
    .eq('user_id', userId)
    .eq('is_read', false)
    .eq('is_deleted', false)

  if (category) query = query.eq('category', category)

  const { error } = await query
  if (error) throw error
}

/**
 * Hide a notification, and put it back — soft, because that is the only kind
 * the table permits and because "undo" needs the row to still be there.
 */
export async function setNotificationDeleted(notificationId, isDeleted = true) {
  const { error } = await supabase
    .from('notifications')
    .update({ is_deleted: Boolean(isDeleted) })
    .eq('id', notificationId)

  if (error) throw error
}
