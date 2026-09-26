import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'

import {
  fetchNotifications,
  fetchUnreadNotificationCount,
  markAllNotificationsRead,
  setNotificationDeleted,
  setNotificationRead,
} from '../lib/notifications.js'
import { useAuth } from './useAuth.jsx'

/**
 * The notification feed's queries and mutations.
 *
 * Two keys, because they answer two different questions: `notifications` is the
 * feed (the whole list, for the page) and `notifications-unread` is a number
 * (for the account-menu badge). The badge has to be cheap — it renders in the
 * header on every page — so it counts on the server rather than reusing the
 * feed's rows, and the two are invalidated together so the badge can never
 * disagree with the list it is badging.
 */

/** The whole feed, newest first. */
export function useNotifications() {
  const { user } = useAuth()
  const userId = user?.id ?? null

  return useQuery({
    queryKey: ['notifications', userId],
    queryFn: () => fetchNotifications(userId),
    enabled: Boolean(userId),
  })
}

/** The unread count for the badge. */
export function useUnreadNotificationCount() {
  const { user } = useAuth()
  const userId = user?.id ?? null

  return useQuery({
    queryKey: ['notifications-unread', userId],
    queryFn: () => fetchUnreadNotificationCount(userId),
    enabled: Boolean(userId),
  })
}

/**
 * Every write the feed can make.
 *
 * The read/unread and hide mutations are **optimistic**, unlike cancelling an
 * order: marking a notification read is a statement about the customer's own
 * reading list, and waiting a round trip to draw a card as read makes the feed
 * feel broken on a slow connection. The rollback is the cached list, so a failed
 * write puts the card back exactly as it was.
 *
 * `markAll` is deliberately NOT optimistic: it is one request that may touch
 * dozens of rows, and a screen that redrew them all as read before the server
 * agreed would have to put them back one at a time if the write failed.
 */
export function useNotificationActions() {
  const { user } = useAuth()
  const userId = user?.id ?? null
  const queryClient = useQueryClient()

  const feedKey = ['notifications', userId]
  const countKey = ['notifications-unread', userId]

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

  const markRead = useMutation(optimistic({ is_read: true }, (id) => setNotificationRead(id, true)))
  const markUnread = useMutation(
    optimistic({ is_read: false }, (id) => setNotificationRead(id, false)),
  )

  /*
    Hiding a row takes it out of the list rather than patching a flag, because
    the feed never shows hidden rows — `fetchNotifications` filters them out. An
    unread row loses its contribution to the badge too.
  */
  const hide = useMutation({
    mutationFn: (notificationId) => setNotificationDeleted(notificationId, true),
    onMutate: async (notificationId) => {
      await queryClient.cancelQueries({ queryKey: feedKey })
      const previous = queryClient.getQueryData(feedKey)
      const hidden = Array.isArray(previous) ? previous.find((row) => row.id === notificationId) : null

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

  const markAllRead = useMutation({
    mutationFn: (category) => markAllNotificationsRead(userId, { category: category ?? null }),
    onSuccess: invalidate,
  })

  return { markRead, markUnread, hide, markAllRead }
}
