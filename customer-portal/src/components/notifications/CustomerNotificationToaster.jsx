import { useMemo } from 'react'

import NotificationToaster from './NotificationToaster.jsx'
import { customerNotificationIcon } from './notificationIcons.js'
import { useNotificationActions, useNotifications } from '../../hooks/useNotifications.js'
import { pluralize } from '../../lib/constants.js'
import { customerNotificationPath } from '../../lib/notificationPaths.js'
import {
  notificationCategoryLabel,
  notificationMessageCount,
  notificationRelativeTime,
  notificationStoreName,
} from '../../lib/notificationRules.js'
import { pickToastNotifications } from '../../lib/notificationToasts.js'

/**
 * The customer's toast centre: the feed that `useNotifications` already loads,
 * filtered down to the rows worth interrupting someone for.
 *
 * It adds no query and no subscription of its own — it reads the same cache
 * entry the notifications page and the account-menu badge read, so the three
 * cannot disagree about what is unread, and the badge's number is always at
 * least the number of toasts that were skipped. (The customer's `notifications`
 * table is not in the realtime publication, which is why the feed refetches on
 * window focus rather than subscribing; this rides along with that refetch, so
 * a toast appears when the customer comes back to the tab.)
 *
 * ## Opening a toast marks it read — dismissing one does not
 *
 * That is the feed page's rule, kept here rather than reinvented: opening a
 * notification is the customer saying they have seen it. A toast that
 * auto-dismisses says nothing at all — it was on screen for six seconds and the
 * customer may have been looking at the other monitor — so the row stays unread,
 * the badge keeps its count, and the notification is still waiting on the feed.
 * A "seen it" that the customer did not give is how a badge ends up lying.
 *
 * ## Bottom right, because nothing else lives there
 *
 * The customer shell is a header, a page and a footer; the corner below the
 * fold is the only space on the page that is never a control. The seller side
 * uses the other corner, and says why.
 */
export default function CustomerNotificationToaster() {
  const { data } = useNotifications()
  const { markRead } = useNotificationActions()

  const list = useMemo(() => data ?? [], [data])

  const items = useMemo(
    () =>
      pickToastNotifications(list).map((row) => ({
        id: row.id,
        title: row.title,
        message: row.message,
        time: notificationRelativeTime(row.created_at),
        meta: toastMeta(row),
        Icon: customerNotificationIcon(row),
        to: customerNotificationPath(row),
      })),
    [list],
  )

  return (
    <NotificationToaster
      items={items}
      position="bottom-right"
      onOpen={(item) => markRead.mutate(item.id)}
    />
  )
}

/**
 * The line under a toast's body: what kind of news it is, who it is from, and
 * how many messages are folded into it.
 *
 * The store name is drawn for the same reason the feed card draws it — a
 * marketplace of artisans is a marketplace of *names*, and "New message" with no
 * maker on it tells the customer nothing they did not already know.
 */
function toastMeta(row) {
  const parts = [notificationCategoryLabel(row.category)]

  const store = notificationStoreName(row)
  if (store) parts.push(store)

  const count = notificationMessageCount(row)
  if (count > 1) parts.push(pluralize(count, 'message'))

  return parts.join(' · ')
}
