import { supabase } from './supabase.js'

// The rules live next door; re-exported so screens import "seller
// notifications" once.
export * from './sellerNotificationRules.js'

/**
 * The seller's notification feed — a port of `SellerNotificationService`.
 *
 * ## What was already there
 *
 * `20260715_seller_notifications.sql` created the table, scoped `select` and
 * `update` RLS to the store's owner (`stores.owner_id = auth.uid()`), and added
 * it to the `supabase_realtime` publication. Later migrations added
 * `is_deleted`, `metadata` and a DELETE policy. Rows have been arriving since
 * July — from the app, from `create_gcash_checkout` when a customer submits a
 * GCash proof, and from the batching trigger for messages — with nothing on the
 * web able to read one.
 *
 * ## Three things a naive port gets wrong
 *
 *  1. **Deleted means `is_deleted`, not a missing row.** The soft-delete
 *     migration pairs the flag with an "allow undo" flow, and the app's own
 *     delete is an UPDATE of the flag. Every read filters `is_deleted = false`.
 *  2. **The key is the STORE, not the user.** Unlike `notifications`, this table
 *     has no `user_id`; a seller's rows are found by `store_id`, which is also
 *     what the RLS policy resolves ownership through.
 *  3. **The badge is a `HEAD` count, not a list.** It renders in the portal's bar
 *     on every page, so pulling the whole feed to draw one digit would make the
 *     chrome the most expensive thing in the portal. `{ count: 'exact', head:
 *     true }` asks Postgres for a number.
 *
 * ## Realtime, unlike the customer feed
 *
 * The customer's `notifications` table was never added to the realtime
 * publication, which is why `useNotifications` refetches on focus instead of
 * subscribing — a subscription to an unpublished table silently never fires,
 * and a feed that only *looks* live is worse than one that admits it polls.
 * `seller_notifications` **was** published, so this module subscribes for real.
 */

/** The columns the feed reads. `*` would ship a `store_id` the caller already knows. */
export const SELLER_NOTIFICATION_SELECT =
  'id, store_id, type, title, body, reference_id, is_read, metadata, created_at'

/**
 * One store's notifications, newest first.
 *
 * Not filtered by type in SQL, and that is deliberate: the chip row shows a
 * count per type, so the page needs every row in hand anyway, and an `eq` here
 * would mean a second request for every chip. `limit` is a guard rather than a
 * page size — a store with years of history should get a fast feed, not a
 * thousand rows of HTML.
 */
export async function fetchSellerNotifications(storeId, { limit = 100 } = {}) {
  if (!storeId) return []

  const { data, error } = await supabase
    .from('seller_notifications')
    .select(SELLER_NOTIFICATION_SELECT)
    .eq('store_id', storeId)
    .eq('is_deleted', false)
    .order('created_at', { ascending: false })
    .limit(limit)

  if (error) throw error
  return data ?? []
}

/** How many are unread — the menu row's badge, as a count and not a list. */
export async function fetchUnreadSellerNotificationCount(storeId) {
  if (!storeId) return 0

  const { count, error } = await supabase
    .from('seller_notifications')
    .select('id', { count: 'exact', head: true })
    .eq('store_id', storeId)
    .eq('is_read', false)
    .eq('is_deleted', false)

  if (error) throw error
  return count ?? 0
}

/** Read, or unread again. A one-column UPDATE the RLS policy allows. */
export async function setSellerNotificationRead(notificationId, isRead = true) {
  if (!notificationId) return

  const { error } = await supabase
    .from('seller_notifications')
    .update({ is_read: Boolean(isRead) })
    .eq('id', notificationId)

  if (error) throw error
}

/**
 * Mark every unread row read, optionally just one type — the app's
 * `markAllAsRead`. `is_read = false` in the filter is what keeps it from
 * rewriting the store's whole history on every press.
 */
export async function markAllSellerNotificationsRead(storeId, { type = null } = {}) {
  if (!storeId) return

  let query = supabase
    .from('seller_notifications')
    .update({ is_read: true })
    .eq('store_id', storeId)
    .eq('is_read', false)
    .eq('is_deleted', false)

  /*
    `other` cannot be expressed as an `eq` — it is the portal's word for "a type
    this build does not know", not a value in the column — so the chip for it
    marks read one row at a time through the per-row mutation rather than
    through a filter that would match nothing and report success.
  */
  if (type && type !== 'other') query = query.eq('type', type)

  const { error } = await query
  if (error) throw error
}

/**
 * Hide a notification, and put it back — soft, because that is what the table's
 * undo flow needs and what the app itself does.
 */
export async function setSellerNotificationDeleted(notificationId, isDeleted = true) {
  if (!notificationId) return

  const { error } = await supabase
    .from('seller_notifications')
    .update({ is_deleted: Boolean(isDeleted) })
    .eq('id', notificationId)

  if (error) throw error
}

/**
 * Watch one store's notifications.
 *
 * The callback takes no payload: every event means the same thing to this
 * portal — "the badge and the feed are now stale" — and folding the row in by
 * hand would only be worth it for a listener that rendered them from the
 * event. Returns the channel so the caller can remove it on unmount, and a
 * `filter` on `store_id` keeps a busy marketplace from streaming every store's
 * notifications into one seller's page.
 */
export function subscribeToSellerNotifications(storeId, onChange) {
  if (!storeId) return null

  const channel = supabase
    .channel(`seller-notifications:${storeId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'seller_notifications',
        filter: `store_id=eq.${storeId}`,
      },
      () => onChange(),
    )
    .subscribe()

  return channel
}
