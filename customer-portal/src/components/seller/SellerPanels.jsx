import { useState } from 'react'

import SellerConversationList from './SellerConversationList.jsx'
import SellerNotificationList from './SellerNotificationList.jsx'
import SellerMessageThread from '../../pages/seller/SellerMessageThread.jsx'
import { normalizePanelId } from '../../lib/sellerPanelRules.js'

/**
 * What goes inside the side panel.
 *
 * One switch, in one place, so the shell does not have to know what a panel
 * *contains* — only that one is open and where its edges are. Adding a third
 * panel would be a case here and an entry in `sellerPanelRules`, and nothing
 * else.
 *
 * The two contents are the very components the pages use, which is the point of
 * having extracted them: the panel is a different *frame* around the same feed,
 * never a second implementation of it.
 */
export default function SellerPanelContent({ panel, storeId }) {
  if (normalizePanelId(panel) === 'messages') {
    return <SellerMessagesPanel storeId={storeId} />
  }

  return <SellerNotificationList storeId={storeId} />
}

/**
 * The inbox, with a thread able to open inside it.
 *
 * **The thread is panel state, not a route.** A seller who clicked a customer
 * while a pinned panel sits beside their orders wants to read that thread and
 * keep looking at the order — navigating the page behind the panel would throw
 * away exactly the context the panel exists to preserve. So the panel holds the
 * open thread id, `SellerMessageThread` takes it as a prop, and the rows call
 * back instead of moving the URL.
 *
 * The page still works: `/seller/messages/<id>` renders the same thread from
 * `useParams`, and the rows keep their real `href`s so a middle click still
 * opens it there.
 */
function SellerMessagesPanel({ storeId }) {
  const [openConversation, setOpenConversation] = useState(null)

  if (openConversation) {
    return (
      <SellerMessageThread
        conversationId={openConversation}
        /*
          Passed rather than read from the outlet context: the panel is a
          sibling of `<Outlet>`, so that context is `null` in here. See the
          component's own docblock — this was a crash, not a tidiness point.
        */
        storeId={storeId}
        embedded
        onBack={() => setOpenConversation(null)}
      />
    )
  }

  return <SellerConversationList storeId={storeId} onOpen={setOpenConversation} />
}
