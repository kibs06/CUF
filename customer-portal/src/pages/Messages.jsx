import { Link } from 'react-router-dom'
import { motion } from 'motion/react'
import { MessageSquare, MessageSquareOff, Store } from 'lucide-react'

import EmptyState from '../components/ui/EmptyState'
import Reveal from '../components/ui/Reveal'
import StoreAvatar from '../components/ui/StoreAvatar'
import { fadeUp, staggerChildren } from '../components/motion/transitions'
import { useConversations } from '../hooks/useMessages.js'
import { pluralize } from '../lib/constants.js'
import {
  conversationPreview,
  messageRelativeTime,
  unreadBadgeLabel,
} from '../lib/messages.js'

/**
 * The inbox — one row per maker the customer has written to.
 *
 * ## One thread per maker, not per order
 *
 * `conversations` is `UNIQUE(store_id, customer_id)`, so a customer who asked
 * Janella about a sandal in March and about a repair in September has **one**
 * thread, in date order. That is the app's model too, and it is why the row is a
 * maker rather than an order: the header of the row has to be stable across
 * every conversation the customer will ever have with them.
 *
 * ## The order of the rows is a rule, not a sort
 *
 * `sortConversations` puts a thread with **no messages** at the top
 * (`nullsFirst`), because the customer who just tapped "Message the maker" is
 * looking for the thread they just opened. Newest activity first for everyone
 * else.
 *
 * ## Unread is the maker's messages, never the customer's own
 *
 * Their own message stays `is_read = false` in the database until the maker
 * opens the thread, so counting "unread" naively badges a thread the moment the
 * customer writes into it. The count comes from `unreadFromOther`'s side only
 * and is capped at `9+`, which keeps a busy thread from pushing the row's
 * layout around.
 *
 * ## It is live
 *
 * The list subscribes to `conversations` — the trigger moves `last_message_at`
 * on every new message, so "a thread changed" is the only event the list needs.
 * A reply from a maker therefore re-orders the inbox and updates the badge
 * without a reload.
 */
export default function Messages() {
  const { data, isLoading, isError } = useConversations()
  const conversations = data ?? []
  const unreadThreads = conversations.filter((row) => row.unread_count > 0).length

  return (
    <div className="mx-auto max-w-4xl px-4 py-10 sm:px-6 lg:px-8">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="overline">Your account</p>
          <h1 className="mt-2 font-display text-3xl font-semibold text-ink sm:text-4xl">
            Messages
          </h1>
          <p className="mt-2 max-w-xl text-sm leading-relaxed text-muted">
            Talk to a maker about a pair — a size, a colour, a delivery, or
            something you would like made. One thread per workshop.
          </p>
        </div>

        {!isLoading && conversations.length > 0 && (
          <p className="text-xs text-muted">
            {pluralize(conversations.length, 'conversation')}
            {unreadThreads > 0 ? ` · ${unreadThreads} unread` : ''}
          </p>
        )}
      </header>

      <div className="mt-8">
        {isLoading ? (
          <div className="space-y-3">
            {Array.from({ length: 4 }).map((_, index) => (
              <div key={index} className="shimmer h-20 rounded-card" />
            ))}
          </div>
        ) : isError ? (
          <EmptyState
            Icon={MessageSquareOff}
            title="Could not load your messages"
            description="Please check your connection and try again."
          />
        ) : conversations.length > 0 ? (
          <motion.ul
            variants={staggerChildren(0.03)}
            initial="hidden"
            animate="show"
            className="space-y-3"
          >
            {conversations.map((conversation) => (
              <motion.li key={conversation.id} variants={fadeUp}>
                <ConversationRow conversation={conversation} />
              </motion.li>
            ))}
          </motion.ul>
        ) : (
          <EmptyState
            Icon={MessageSquare}
            title="No messages yet"
            description="Open a maker's page, or one of your orders, and write to them — the thread will appear here."
            action={
              <Link to="/makers" className="btn btn-primary">
                <Store size={16} strokeWidth={2} />
                Browse makers
              </Link>
            }
          />
        )}
      </div>

      {!isLoading && conversations.length > 0 && (
        <Reveal className="mt-10 rounded-card border border-hairline bg-subtle/50 p-5">
          <p className="text-xs leading-relaxed text-muted">
            Messages are also delivered to the CUFMAI app and to your email, and
            a reply from a maker arrives as a notification — so you do not have
            to keep this page open.
          </p>
        </Reveal>
      )}
    </div>
  )
}

/**
 * One thread.
 *
 * The whole row is the link, including the unread pill: a customer reaching for
 * the number to make it go away should be able to click it, and the row has no
 * other control to compete with.
 *
 * The state is a rule down the left edge AND a bold name AND the pill — the
 * same three-way marking the notification feed uses, because colour alone is
 * not a state a colour-blind customer can read. The row's screen-reader label
 * says "3 unread" in words.
 */
function ConversationRow({ conversation }) {
  const unread = conversation.unread_count > 0
  const badge = unreadBadgeLabel(conversation.unread_count)
  const store = conversation.store
  const name = store?.name ?? 'A maker'

  return (
    <Link
      to={`/messages/${conversation.id}`}
      aria-label={`${name}${badge ? `, ${badge} unread` : ''}`}
      className={`flex items-center gap-4 rounded-card border bg-raised p-4 shadow-card transition-[transform,border-color,box-shadow] duration-300 ease-out-cubic hover:-translate-y-0.5 hover:border-card-edge hover:shadow-card-lift ${
        unread ? 'border-l-4 border-l-clay border-y-hairline border-r-hairline' : 'border-hairline'
      }`}
    >
      <StoreAvatar store={store} size={44} />

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

        <p className="mt-1 truncate text-sm text-muted">
          {conversationPreview(conversation)}
        </p>
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
