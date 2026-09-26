import { Link } from 'react-router-dom'
import { MessageSquare, MessageSquareOff, Receipt } from 'lucide-react'

import EmptyState from '../ui/EmptyState'
import { useStoreConversations } from '../../hooks/useSellerMessages.js'
import { getInitials, pluralize } from '../../lib/constants.js'
import {
  conversationPreview,
  messageRelativeTime,
  sellerConversationName,
  unreadBadgeLabel,
  unreadThreadCount,
} from '../../lib/sellerMessages.js'

/**
 * The seller's inbox — one row per customer who has written to this store.
 *
 * **One component, two hosts**, like the notification feed: the page at
 * `/seller/messages` and the side panel both draw this, so the counts, the
 * order of the rows and the wording of an empty inbox cannot differ between
 * them.
 *
 * ## The mirror of the customer's `/messages`, with the sides swapped
 *
 * A customer's inbox lists makers; this lists people, and the name comes from
 * `conversations.customer_name` (denormalised onto the thread by a trigger
 * because profiles RLS made the join return nothing for a seller). `UNIQUE(store_id,
 * customer_id)` makes each row a *person* rather than an order, so a customer
 * asking about a sandal in March and a pair in September has one thread, in date
 * order — the same model as the app, and the reason the header of a row has to
 * be stable across every conversation the store will ever have with them.
 *
 * ## The order of the rows is a rule, not a sort
 *
 * `sortConversations` puts a thread with **no messages** at the top
 * (`nullsFirst`). On the seller's side that is the more interesting case: a
 * customer who opened a thread from the storefront and never typed anything is a
 * customer waiting to be greeted, and it is the row a seller would otherwise
 * never notice.
 *
 * ## Unread is the customer's messages, never the shop's own
 *
 * A seller's reply stays `is_read = false` until the customer opens the thread,
 * so counting "unread" naively badges every thread the moment the shop answers
 * in it. The count comes from the customer's side only and is capped at `9+`.
 *
 * ## `onOpen`, and why the rows are still links
 *
 * The panel passes `onOpen` so a click opens the thread *inside the panel*
 * instead of navigating away from the page the seller was on. The rows are still
 * `Link`s with real `href`s, so a middle click, a ⌘-click or a right-click keeps
 * working and still lands on the real page — the quick view never takes away the
 * thing that can be linked to.
 */
export default function SellerConversationList({ storeId, onOpen, className = '' }) {
  const { data, isLoading, isError } = useStoreConversations(storeId)
  const conversations = data ?? []
  const waiting = unreadThreadCount(conversations)

  if (isLoading) {
    return (
      <div className={`space-y-3 ${className}`}>
        {Array.from({ length: 4 }).map((_, index) => (
          <div key={index} className="shimmer h-20 rounded-card" />
        ))}
      </div>
    )
  }

  if (isError) {
    return (
      <div className={className}>
        <EmptyState
          Icon={MessageSquareOff}
          title="Could not load your messages"
          description="Please check your connection and try again."
        />
      </div>
    )
  }

  if (conversations.length === 0) {
    return (
      <div className={className}>
        <EmptyState
          Icon={MessageSquare}
          title="No messages yet"
          description="When a customer writes to your store — from a product page or from one of their orders — the thread appears here, and you can answer it from this page."
          action={
            <Link to="/seller/orders" className="btn btn-primary">
              <Receipt size={16} strokeWidth={2} />
              Look at your orders
            </Link>
          }
        />
      </div>
    )
  }

  return (
    <div className={className}>
      <p className="text-xs text-muted">
        {pluralize(conversations.length, 'conversation')}
        {waiting > 0 ? ` · ${waiting} to answer` : ''}
      </p>

      <ul className="mt-3 space-y-3">
        {conversations.map((conversation) => (
          <li key={conversation.id}>
            <ConversationRow conversation={conversation} onOpen={onOpen} />
          </li>
        ))}
      </ul>

      <p className="mt-6 text-xs leading-relaxed text-muted">
        A reply reaches the customer in the CUFMAI app and by e-mail, and
        answering here marks their messages read for both of you.
      </p>
    </div>
  )
}

/**
 * One thread.
 *
 * The whole row is the link, including the unread pill: a seller reaching for
 * the number to make it go away should be able to click it, and the row has no
 * other control to compete with.
 *
 * The avatar is the customer's initials on the brand tint rather than a photo —
 * the portal has no customer pictures, and a row of grey circles would say
 * "someone" where two letters say who.
 */
function ConversationRow({ conversation, onOpen }) {
  const name = sellerConversationName(conversation)
  const unread = conversation.unread_count > 0
  const badge = unreadBadgeLabel(conversation.unread_count)

  const to = `/seller/messages/${conversation.id}`

  return (
    <Link
      to={to}
      onClick={(event) => {
        if (!onOpen) return
        /*
          A plain left click is the panel's; anything else — middle click,
          ⌘/ctrl, shift, alt, or a click some other handler already claimed —
          keeps its normal meaning and opens the real page. That is the whole
          reason these rows stayed links.
        */
        if (
          event.defaultPrevented ||
          event.button !== 0 ||
          event.metaKey ||
          event.ctrlKey ||
          event.shiftKey ||
          event.altKey
        ) {
          return
        }
        event.preventDefault()
        onOpen(conversation.id)
      }}
      aria-label={`${name}${badge ? `, ${badge} unread` : ''}`}
      className={`flex items-center gap-4 rounded-card border bg-raised p-4 shadow-card transition-[transform,border-color,box-shadow] duration-300 ease-out-cubic hover:-translate-y-0.5 hover:border-card-edge hover:shadow-card-lift ${
        unread ? 'border-l-4 border-l-clay border-y-hairline border-r-hairline' : 'border-hairline'
      }`}
    >
      <span
        aria-hidden="true"
        className="num flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-clay/10 text-sm font-semibold text-clay-ink"
      >
        {getInitials(name)}
      </span>

      <div className="min-w-0 flex-1">
        <div className="flex items-baseline gap-3">
          <p
            className={`min-w-0 flex-1 truncate ${
              unread ? 'font-semibold text-ink' : 'font-medium text-muted-strong'
            }`}
          >
            {name}
          </p>
          <time
            dateTime={conversation.last_message_at ?? undefined}
            className="shrink-0 text-xs text-muted"
          >
            {messageRelativeTime(conversation.last_message_at)}
          </time>
        </div>

        <p className="mt-1 truncate text-sm text-muted">{conversationPreview(conversation)}</p>
      </div>

      {badge && (
        <span
          aria-hidden="true"
          className="num inline-flex h-6 min-w-[1.5rem] shrink-0 items-center justify-center rounded-full bg-clay px-1.5 text-xs font-semibold text-ink-inverse"
        >
          {badge}
        </span>
      )}
    </Link>
  )
}
