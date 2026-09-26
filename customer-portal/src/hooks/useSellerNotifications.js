import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'

import {
  fetchSellerNotifications,
  fetchUnreadSellerNotificationCount,
  markAllSellerNotificationsRead,
  setSellerNotificationDeleted,
  setSellerNotificationRead,
} from '../lib/sellerNotifications.js'

/**
 * The seller notification feed's queries and mutations.
 *
 * Two keys, because they answer two different questions: `seller-notifications`
 * is the feed (the whole list, for the page) and `seller-notifications-unread`
 * is a number (for the menu row's badge). The badge has to be cheap — it renders in
 * the seller's bar on every page — so it counts on the server rather than
 * reusing the feed's rows, and the two are invalidated together so the badge can
 * never disagree with the list it is badging.
 *
 * Each hook takes the `storeId` its caller already has (the page from
 * `useOutletContext`, the bar from the shell) rather than calling `useMyStore`
 * itself, which is how every other seller data hook works. Both are gated on that
 * id being real: `fetchSellerNotifications(undefined)` reads as "no
 * notifications" and would paint an empty feed over a page that simply has not
 * loaded, so `enabled` is the difference between a pending query and a lie.
 */

/** The whole feed, newest first. */
export function useSellerNotifications(storeId) {
  return useQuery({
    queryKey: ['seller-notifications', storeId ?? null],
    queryFn: () => fetchSellerNotifications(storeId),
    enabled: Boolean(storeId),
  })
}

/**
 * The unread count a badge draws — the bar's bell and the menu's row both read
 * it, and they share one cache entry because they ask the same question.
 *
 * The realtime subscription is **not** here: three components now draw this
 * number (an icon, a menu row, and the panel header), and a subscription per
 * mount would be three channels invalidating the same two keys. The shell owns
 * the channels instead, in `SellerLayout`'s `SellerRealtime`, because the shell
 * is the only part of the portal that is always mounted.
 */
export function useUnreadSellerNotificationCount(storeId) {
  return useQuery({
    queryKey: ['seller-notifications-unread', storeId ?? null],
    queryFn: () => fetchUnreadSellerNotificationCount(storeId),
    enabled: Boolean(storeId),
  })
}

/**
 * Every write the feed can make.
 *
 * Read/unread and hide are **optimistic**, unlike changing an order's status:
 * marking a notification read is a statement about the seller's own reading
 * list, and waiting a round trip to draw a card as read makes the feed feel
 * broken on a slow connection. The rollback is the cached list, so a failed
 * write puts the card back exactly as it was.
 *
 * `markAll` is deliberately NOT optimistic: it is one request that may touch
 * dozens of rows, and a screen that redrew them all as read before the server
 * agreed would have to put them back one at a time if the write failed.
 */
export function useSellerNotificationActions(storeId) {
  const queryClient = useQueryClient()

  const feedKey = ['seller-notifications', storeId]
  const countKey = ['seller-notifications-unread', storeId]

  const invalidate = () => {
    queryClient.invalidateQueries({ queryKey: feedKey })
    queryClient.invalidateQueries({ queryKey: countKey })
  }

  /**
   * Write to the cache first, then to the server.
   *
   * `patch` is applied to the one row; the badge is moved by the same patch, so
   * the two cached views cannot drift apart while the write is in flight.
   */
  const optimistic = (patch, write) => ({
    mutationFn: (notificationId) => write(notificationId),
    onMutate: async (notificationId) => {
      await queryClient.cancelQueries({ queryKey: feedKey })
      const previous = queryClient.getQueryData(feedKey)

      queryClient.setQueryData(feedKey, (current) =>
        Array.isArray(current)
          ? current.map((row) => (row.id === notificationId ? { ...row, ...patch } : row))
          : current,
      )

      if ('is_read' in patch) {
        queryClient.setQueryData(countKey, (current) => {
          if (typeof current !== 'number') return current
          return patch.is_read ? Math.max(0, current - 1) : current + 1
        })
      }

      return { previous }
    },
    onError: (_error, _id, context) => {
      if (context?.previous !== undefined) queryClient.setQueryData(feedKey, context.previous)
    },
    onSettled: invalidate,
  })

  const markRead = useMutation(
    optimistic({ is_read: true }, (id) => setSellerNotificationRead(id, true)),
  )
  const markUnread = useMutation(
    optimistic({ is_read: false }, (id) => setSellerNotificationRead(id, false)),
  )

  /*
    Hiding a row takes it out of the list rather than patching a flag, because
    the feed never shows hidden rows — `fetchSellerNotifications` filters them
    out. An unread row loses its contribution to the badge too.
  */
  const hide = useMutation({
    mutationFn: (notificationId) => setSellerNotificationDeleted(notificationId, true),
    onMutate: async (notificationId) => {
      await queryClient.cancelQueries({ queryKey: feedKey })
      const previous = queryClient.getQueryData(feedKey)
      const hidden = Array.isArray(previous)
        ? previous.find((row) => row.id === notificationId)
        : null

      queryClient.setQueryData(feedKey, (current) =>
        Array.isArray(current) ? current.filter((row) => row.id !== notificationId) : current,
      )
      if (hidden && !hidden.is_read) {
        queryClient.setQueryData(countKey, (current) =>
          typeof current === 'number' ? Math.max(0, current - 1) : current,
        )
      }

      return { previous }
    },
    onError: (_error, _id, context) => {
      if (context?.previous !== undefined) queryClient.setQueryData(feedKey, context.previous)
    },
    onSettled: invalidate,
  })

  /**
   * Put a hidden row back — the other half of `hide`.
   *
   * Not optimistic, because there is nothing to be optimistic *with*: the row
   * was removed from the cache, so the cache has no copy of it to restore. The
   * list is refetched instead, which puts the row back in its correct place in
   * time rather than wherever it happened to be when it was hidden.
   */
  const restore = useMutation({
    mutationFn: (notificationId) => setSellerNotificationDeleted(notificationId, false),
    onSuccess: invalidate,
  })

  /**
   * Mark every unread row read, optionally just one type.
   *
   * `type` is passed straight through to the UPDATE, so the feed's "mark all
   * read" with no filter on it clears the whole store and the same button under
   * a chip clears only that chip. The one type it cannot express in SQL is the
   * portal's own `other` — that is a word this build invented for a type it does
   * not know, not a value in the column — and the page marks those read one card
   * at a time rather than issuing a filter that would match nothing and report
   * success.
   */
  const markAllRead = useMutation({
    mutationFn: (type) => markAllSellerNotificationsRead(storeId, { type: type ?? null }),
    onSuccess: invalidate,
  })

  return { markRead, markUnread, hide, restore, markAllRead }
}
