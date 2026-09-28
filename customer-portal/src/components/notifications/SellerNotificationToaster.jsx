import { useMemo } from 'react'

import NotificationToaster from './NotificationToaster.jsx'
import { sellerNotificationIcon } from './notificationIcons.js'
import {
  useSellerNotificationActions,
  useSellerNotifications,
} from '../../hooks/useSellerNotifications.js'
import { pluralize } from '../../lib/constants.js'
import { sellerNotificationPath } from '../../lib/notificationPaths.js'
import {
  notificationRelativeTime,
  sellerNotificationMessageCount,
  sellerNotificationTypeLabel,
} from '../../lib/sellerNotifications.js'
import { pickToastNotifications } from '../../lib/notificationToasts.js'

/**
 * The seller's toast centre — the same component the customer side draws, fed by
 * `seller_notifications`.
 *
 * It reads the query the bar's bell and the panel's list already share rather
 * than subscribing itself: the shell owns the realtime channels
 * (`SellerLayout`'s `SellerRealtime`), and a subscription here would be a fourth
 * socket for one table. Because that table *is* published, a seller's toast
 * arrives while they are working rather than when they next alt-tab back — which
 * is the whole reason the two sides feel different.
 *
 * ## Bottom left, because the right-hand side is the panel
 *
 * The seller shell docks `SellerSidePanel` on the right — a flex sibling of the
 * page, not a layer over it — so the bottom-right corner is either the panel (a
 * pinned notifications list and the toast about the same notification, side by
 * side) or empty space that becomes the panel. The left corner never is.
 *
 * ## Opening a toast marks it read; letting it go does not
 *
 * Same rule as the feed's cards, and the same reasoning as the customer side: an
 * auto-dismissed toast is not a seller acknowledging an order.
 */
export default function SellerNotificationToaster({ storeId }) {
  const { data } = useSellerNotifications(storeId)
  const { markRead } = useSellerNotificationActions(storeId)

  const list = useMemo(() => data ?? [], [data])

  const items = useMemo(
    () =>
      pickToastNotifications(list).map((row) => ({
        id: row.id,
        title: row.title,
        message: row.body,
        time: notificationRelativeTime(row.created_at),
        meta: toastMeta(row),
        Icon: sellerNotificationIcon(row),
        to: sellerNotificationPath(row),
      })),
    [list],
  )

  return (
    <NotificationToaster
      items={items}
      position="bottom-left"
      onOpen={(item) => markRead.mutate(item.id)}
    />
  )
}

/**
 * The line under a toast's body: which kind of work this is, and how many
 * messages are folded into it.
 *
 * A seller's card has no "from" name to add — the store *is* the recipient — so
 * the type label is the whole line, which is also what the feed's chips say.
 */
function toastMeta(row) {
  const parts = [sellerNotificationTypeLabel(row.type)]

  const count = sellerNotificationMessageCount(row)
  if (count > 1) parts.push(pluralize(count, 'message'))

  return parts.join(' · ')
}
