import { useOutletContext } from 'react-router-dom'

import { SellerPageBody, SellerPageHeader } from '../../components/seller/SellerPage.jsx'
import SellerNotificationList from '../../components/seller/SellerNotificationList.jsx'

/**
 * The notification feed, as a page.
 *
 * Almost nothing is left here, and that is the point: the feed itself lives in
 * `SellerNotificationList`, which the right-hand side panel also draws. The page
 * adds the heading and the width; everything about *what a notification is* —
 * the chips, the counts, the cards, the hide-and-undo — belongs to the component
 * both hosts share, so the two can never show different numbers.
 *
 * The page is still worth having, and the panel says so with a link in its own
 * header: a notification is a thing that gets linked to ("look at this order"),
 * and a drawer that only exists inside a session is a drawer that cannot be
 * pasted into a message. `/seller/notifications?type=low_stock` works when
 * someone sends it, and lands on this page with the chip already chosen —
 * because the filter is in the URL and the URL is read by the shared component.
 */
export default function SellerNotifications() {
  const { store } = useOutletContext()

  return (
    <SellerPageBody>
      <div className="max-w-3xl">
        <SellerPageHeader
          eyebrow="Your shop"
          title="Notifications"
          description="What has happened and what is waiting on you — an order in, a size nearly gone, a customer writing in."
        />

        <div className="mt-6">
          <SellerNotificationList storeId={store?.id ?? null} />
        </div>

        <p className="mt-8 text-xs leading-relaxed text-muted">
          The same notifications are delivered to the CUFMAI app, where the
          deeper screens live — a custom order request is reviewed there.
        </p>
      </div>
    </SellerPageBody>
  )
}
