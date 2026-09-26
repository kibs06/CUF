import { useOutletContext } from 'react-router-dom'

import { SellerPageBody, SellerPageHeader } from '../../components/seller/SellerPage.jsx'
import SellerConversationList from '../../components/seller/SellerConversationList.jsx'

/**
 * The inbox, as a page.
 *
 * The rows, the counts and the empty state live in `SellerConversationList`,
 * which the side panel draws too — so "3 to answer" means the same thing in both
 * places, and a change to how a thread is summarised happens once.
 *
 * The page keeps its place in the portal for the reason the notification page
 * does: a thread is what a notification about a reply links to, and
 * `/seller/messages/<id>` is the URL a seller can bookmark or paste. Clicking a
 * row here navigates (no `onOpen` is passed); clicking one in the panel opens the
 * thread inside the panel, which is the only difference between the two.
 */
export default function SellerMessages() {
  const { store } = useOutletContext()

  return (
    <SellerPageBody>
      <div className="max-w-3xl">
        <SellerPageHeader
          eyebrow="Your shop"
          title="Messages"
          description="Customers asking about a size, a colour, a delivery or something made to order. One thread per person."
        />

        <div className="mt-6">
          <SellerConversationList storeId={store?.id ?? null} />
        </div>
      </div>
    </SellerPageBody>
  )
}
