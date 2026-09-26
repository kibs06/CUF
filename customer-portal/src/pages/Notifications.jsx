import { useMemo } from 'react'
import { motion } from 'motion/react'
import { Link, useSearchParams } from 'react-router-dom'
import {
  BadgeCheck,
  BellOff,
  CalendarClock,
  CheckCheck,
  MessageSquare,
  RotateCcw,
  Star,
  Tag,
  Truck,
  Wallet,
  Wrench,
} from 'lucide-react'

import EmptyState from '../components/ui/EmptyState'
import { fadeUp, staggerChildren } from '../components/motion/transitions'
import { useNotificationActions, useNotifications } from '../hooks/useNotifications.js'
import { pluralize } from '../lib/constants'
import {
  NOTIFICATION_CATEGORIES,
  NOTIFICATION_TABS,
  filterNotifications,
  isBatchedNotification,
  notificationCategory,
  notificationCategoryLabel,
  notificationDestination,
  notificationMessageCount,
  notificationPreviews,
  notificationRelativeTime,
  notificationStoreName,
  unreadCountsByCategory,
  unreadNotificationCount,
} from '../lib/notifications.js'

/** How a category is drawn — the same icon everywhere it appears. */
const CATEGORY_ICONS = {
  unpaid: Wallet,
  processing: Wrench,
  shipped: Truck,
  review: Star,
  returns: RotateCcw,
  message: MessageSquare,
  support: Tag,
  approval: BadgeCheck,
  reservations: CalendarClock,
}

/**
 * The notification feed.
 *
 * ## The shape, and why it is three controls
 *
 * The app's screen has a tab bar (All / Catalog / Custom — the order's *source*)
 * and, when it is opened from a profile row, a category filter. They filter
 * different things and both are kept here: the tab is "which kind of order",
 * the chip row is "which kind of news". Collapsing them into one control would
 * mean a customer who wants unread messages about custom orders has to choose
 * which half of their question to ask.
 *
 * Both live in the URL (`?tab=&category=`), like every other filter in the
 * portal, so the back button and a pasted link both work.
 *
 * ## Unread is a state, not a badge
 *
 * An unread card is drawn differently — a rule in the customer's brand colour,
 * a dot, bolder title — because the feed's whole job is to answer "what have I
 * not seen yet". Opening a card marks it read (the app does the same), and
 * "Mark all read" is scoped to the current filter, so clearing the message chips
 * does not quietly clear the order ones.
 *
 * ## What a card does when tapped
 *
 * `notificationDestination` decides, and the answer can be `none`: a `support`
 * card points at the app's MyReportsScreen, which the portal does not have, and
 * an `approval` card has nothing behind it here either. Those cards render
 * without a link rather than pretending — a link to a page that does not exist
 * is worse than a card that admits it has nowhere to go yet.
 */
export default function Notifications() {
  const [params, setParams] = useSearchParams()
  const { data: notifications, isLoading, isError } = useNotifications()
  const { markRead, markAllRead } = useNotificationActions()

  const list = useMemo(() => notifications ?? [], [notifications])
  const tab = NOTIFICATION_TABS.some((option) => option.value === params.get('tab'))
    ? params.get('tab')
    : 'all'
  const category = NOTIFICATION_CATEGORIES.includes(params.get('category'))
    ? params.get('category')
    : null

  const visible = useMemo(
    () => filterNotifications(list, { tab, category }),
    [list, tab, category],
  )

  const unreadTotal = unreadNotificationCount(list)
  const unreadByCategory = useMemo(() => unreadCountsByCategory(list), [list])
  const unreadVisible = unreadNotificationCount(visible)

  const setParam = (key, value) => {
    const next = new URLSearchParams(params)
    if (value) next.set(key, value)
    else next.delete(key)
    setParams(next, { replace: true })
  }

  const hasFilters = tab !== 'all' || Boolean(category)

  return (
    <div className="mx-auto max-w-4xl px-4 py-10 sm:px-6 lg:px-8">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="overline">Your account</p>
          <h1 className="mt-2 font-display text-3xl font-semibold text-ink sm:text-4xl">
            Notifications
          </h1>
          <p className="mt-2 max-w-xl text-sm leading-relaxed text-muted">
            The same updates the CUFMAI app sends you — an order moving along,
            a maker replying, a payment still waiting.
          </p>
        </div>

        {!isLoading && unreadTotal > 0 && (
          <button
            type="button"
            onClick={() => markAllRead.mutate(category)}
            disabled={markAllRead.isPending}
            className="btn btn-outline"
          >
            <CheckCheck size={16} strokeWidth={2} />
            {markAllRead.isPending
              ? 'Marking…'
              : category
                ? `Mark ${notificationCategoryLabel(category)} read`
                : 'Mark all read'}
          </button>
        )}
      </header>

      {/* ── Tabs: which kind of order ─────────────────────────────── */}
      <div className="mt-7 flex flex-wrap items-center gap-2 border-b border-hairline pb-4">
        <div className="flex flex-wrap items-center gap-2" role="group" aria-label="Filter by order source">
          {NOTIFICATION_TABS.map((option) => (
            <Chip
              key={option.value}
              label={option.label}
              active={tab === option.value}
              onClick={() => setParam('tab', option.value === 'all' ? '' : option.value)}
            />
          ))}
        </div>

        {!isLoading && (
          <p className="ml-auto text-xs text-muted">
            {pluralize(visible.length, 'notification')}
            {unreadVisible > 0 ? ` · ${unreadVisible} unread` : ''}
          </p>
        )}
      </div>

      {/* ── Chips: which kind of news, with their own unread counts ── */}
      {!isLoading && list.length > 0 && (
        <div className="mt-4 flex flex-wrap items-center gap-2" role="group" aria-label="Filter by category">
          {NOTIFICATION_CATEGORIES.filter(
            (name) => unreadByCategory[name] > 0 || list.some((row) => notificationCategory(row.category) === name),
          ).map((name) => {
            const Icon = CATEGORY_ICONS[name]
            const unread = unreadByCategory[name]
            return (
              <button
                key={name}
                type="button"
                onClick={() => setParam('category', category === name ? '' : name)}
                aria-pressed={category === name}
                className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-semibold transition-colors duration-200 ease-out-cubic ${
                  category === name
                    ? 'border-clay bg-clay text-ink-inverse'
                    : 'border-hairline text-muted-strong hover:border-card-edge hover:text-ink'
                }`}
              >
                <Icon size={13} strokeWidth={2} />
                {notificationCategoryLabel(name)}
                {unread > 0 && (
                  <span
                    className={`num rounded-full px-1.5 text-[10px] ${
                      category === name ? 'bg-ink-inverse/20' : 'bg-clay/15 text-clay-ink'
                    }`}
                  >
                    {unread}
                  </span>
                )}
              </button>
            )
          })}
        </div>
      )}

      {hasFilters && (
        <button
          type="button"
          onClick={() => setParams({}, { replace: true })}
          className="mt-4 text-xs font-semibold text-clay-ink underline-offset-4 hover:underline"
        >
          Clear filters
        </button>
      )}

      {/* ── The feed ──────────────────────────────────────────────── */}
      <div className="mt-8">
        {isLoading ? (
          <div className="space-y-3">
            {Array.from({ length: 4 }).map((_, index) => (
              <div key={index} className="shimmer h-24 rounded-card" />
            ))}
          </div>
        ) : isError ? (
          <EmptyState
            Icon={BellOff}
            title="Could not load your notifications"
            description="Please check your connection and try again."
          />
        ) : visible.length > 0 ? (
          <motion.ul
            variants={staggerChildren(0.03)}
            initial="hidden"
            animate="show"
            className="space-y-3"
          >
            {visible.map((row) => (
              <motion.li key={row.id} variants={fadeUp}>
                <NotificationCard
                  notification={row}
                  onOpen={() => {
                    if (!row.is_read) markRead.mutate(row.id)
                  }}
                />
              </motion.li>
            ))}
          </motion.ul>
        ) : (
          <EmptyState
            Icon={BellOff}
            title={hasFilters ? 'Nothing under this filter' : 'Nothing yet'}
            description={
              hasFilters
                ? 'Try another tab or category, or clear the filters to see everything.'
                : 'Updates about your orders and messages from makers will appear here.'
            }
          />
        )}
      </div>
    </div>
  )
}

/**
 * One notification.
 *
 * An unread card is marked three ways — a brand-coloured rule down its left
 * edge, a filled dot, and a bolder title — which is deliberate duplication:
 * colour alone is not a state a colour-blind customer can read, and the dot
 * alone is easy to miss in a feed that is mostly read cards. The dot is
 * `aria-hidden` and the state is carried in text for screen readers instead.
 */
function NotificationCard({ notification, onOpen }) {
  const category = notificationCategory(notification.category)
  const Icon = CATEGORY_ICONS[category]
  const destination = notificationDestination(notification)
  const unread = !notification.is_read
  const batched = isBatchedNotification(notification)
  const previews = notificationPreviews(notification)
  const storeName = notificationStoreName(notification)

  const body = (
    <>
      <span
        aria-hidden="true"
        className={`mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-full ${
          unread ? 'bg-clay/12 text-clay-ink' : 'bg-subtle text-muted'
        }`}
      >
        <Icon size={18} strokeWidth={2} />
      </span>

      <div className="min-w-0 flex-1">
        <div className="flex items-baseline gap-2">
          <p className={`min-w-0 flex-1 truncate ${unread ? 'font-semibold text-ink' : 'font-medium text-muted-strong'}`}>
            {notification.title}
          </p>
          <time
            dateTime={notification.created_at ?? undefined}
            className="shrink-0 text-xs text-muted"
          >
            {notificationRelativeTime(notification.created_at)}
          </time>
        </div>

        <p className="mt-1 text-sm leading-relaxed text-muted">{notification.message}</p>

        {batched && previews.length > 0 && (
          <ul className="mt-2.5 space-y-1.5 border-l-2 border-hairline-soft pl-3">
            {previews.map((preview, index) => (
              <li key={`${preview.timestamp ?? index}`} className="text-xs text-muted">
                <span className="font-medium text-muted-strong">
                  {preview.sender || storeName || 'Maker'}:
                </span>{' '}
                {preview.text}
              </li>
            ))}
            <li className="text-xs italic text-muted">
              {notificationMessageCount(notification)} messages in this thread
            </li>
          </ul>
        )}

        <div className="mt-2 flex flex-wrap items-center gap-2 text-[11px] uppercase tracking-[0.08em] text-muted">
          <span>{notificationCategoryLabel(category)}</span>
          {storeName && category === 'message' && (
            <>
              <span aria-hidden="true">·</span>
              <span className="normal-case tracking-normal">{storeName}</span>
            </>
          )}
          {unread && (
            <>
              <span aria-hidden="true">·</span>
              <span className="text-clay-ink">Unread</span>
            </>
          )}
        </div>
      </div>
    </>
  )

  const shell =
    'flex gap-4 rounded-card border bg-raised p-4 shadow-card transition-[transform,border-color,box-shadow] duration-300 ease-out-cubic'
  const unreadEdge = unread ? 'border-l-4 border-l-clay border-y-hairline border-r-hairline' : 'border-hairline'

  if (destination.kind === 'none' || destination.kind === 'reports') {
    /*
      Nothing behind it in the portal yet — a support reply (the app's
      MyReportsScreen has no equivalent here) or an approval with no order.
      Drawn at rest rather than as a link to somewhere unrelated: a card that
      goes to the wrong page is worse than one that does not move.
    */
    return <div className={`${shell} ${unreadEdge}`}>{body}</div>
  }

  const to =
    destination.kind === 'conversation'
      ? `/messages/${destination.conversationId}`
      : `/orders/${destination.orderId}`

  return (
    <Link
      to={to}
      onClick={onOpen}
      className={`${shell} ${unreadEdge} hover:-translate-y-0.5 hover:border-card-edge hover:shadow-card-lift`}
    >
      {body}
    </Link>
  )
}

function Chip({ label, active, onClick }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={`rounded-full border px-3.5 py-1.5 text-xs font-semibold transition-colors duration-200 ease-out-cubic ${
        active
          ? 'border-clay bg-clay text-ink-inverse'
          : 'border-hairline text-muted-strong hover:border-card-edge hover:text-ink'
      }`}
    >
      {label}
    </button>
  )
}
