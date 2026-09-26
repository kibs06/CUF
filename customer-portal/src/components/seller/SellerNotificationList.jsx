import { useMemo, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import {
  BellOff,
  CheckCheck,
  CircleAlert,
  Clock,
  EyeOff,
  MessageSquare,
  PackageMinus,
  Receipt,
  RotateCcw,
  Ruler,
} from 'lucide-react'

import EmptyState from '../ui/EmptyState'
import {
  useSellerNotificationActions,
  useSellerNotifications,
} from '../../hooks/useSellerNotifications.js'
import { pluralize } from '../../lib/constants.js'
import {
  OTHER_SELLER_NOTIFICATION_TYPE,
  filterSellerNotifications,
  isBatchedSellerNotification,
  notificationPreviews,
  notificationRelativeTime,
  sellerNotificationDestination,
  sellerNotificationMessageCount,
  sellerNotificationType,
  sellerNotificationTypeLabel,
  sellerNotificationTypesPresent,
  unreadCountsBySellerType,
  unreadSellerNotificationCount,
} from '../../lib/sellerNotifications.js'

/** How each type is drawn, in one place so a chip and a card cannot disagree. */
const TYPE_ICONS = {
  new_order: Receipt,
  stale_order: Clock,
  low_stock: PackageMinus,
  custom_order_request: Ruler,
  new_message: MessageSquare,
  // A type this build has never seen: a question mark rather than a guess at
  // which of the five above it might have been.
  [OTHER_SELLER_NOTIFICATION_TYPE]: CircleAlert,
}

/**
 * The seller's notification feed — the app's `SellerNotificationCenterScreen`.
 *
 * **One component, two hosts.** It is drawn inside `/seller/notifications` and
 * inside the right-hand side panel, which is why it owns its own filter chips,
 * its own mark-all button and its own empty states rather than receiving them
 * from a page header: both places need all of them, and the second copy of a
 * feed is the one that ends up disagreeing with the first.
 *
 * ## What this is for
 *
 * Everything that asks a seller to do something, in one list: an order came in,
 * an order has been sitting unopened, a size is nearly gone, a customer sent a
 * message, a payment proof is waiting. The rows have been arriving in
 * `seller_notifications` since July and this is the first place on the web that
 * can read one.
 *
 * ## The filter is the URL, and it is one control
 *
 * `?type=` rather than a tab bar, because a seller's notifications are not
 * divided into neat axes the way a customer's orders are: a low-stock warning
 * and a new order are the same *kind* of thing — work — and the only question
 * worth asking is which kind is showing. It lives in the URL like every other
 * filter in the portal, so the back button and a pasted link both work, and the
 * panel and the page therefore always show the same slice.
 *
 * ## Unread is a state, not a badge
 *
 * An unread card is drawn three ways — a rule in the brand colour down its left
 * edge, a tinted icon, a bolder title — because the feed's job is to answer
 * "what have I not seen yet" and colour alone is not a state everyone can read.
 * Opening a card marks it read, which is what the app does.
 *
 * ## Hiding is reversible, so it is offered
 *
 * A low-stock warning for a product the seller has decided not to restock is
 * noise, and clearing it is the one way to make this list useful again. But the
 * delete is soft and neither host has a "hidden" view, so a hide without an undo
 * would be a lost row — hence the strip, which offers the row back for as long
 * as the seller stays on the page. Leaving the page is what makes it permanent,
 * and that is said in the strip rather than discovered later.
 */
export default function SellerNotificationList({ storeId, className = '' }) {
  const [params, setParams] = useSearchParams()
  const { data, isLoading, isError } = useSellerNotifications(storeId)
  const { markRead, markUnread, hide, restore, markAllRead } =
    useSellerNotificationActions(storeId)

  const list = useMemo(() => data ?? [], [data])
  const present = useMemo(() => sellerNotificationTypesPresent(list), [list])

  const requested = params.get('type')
  const type = present.includes(requested) ? requested : null

  const visible = useMemo(() => filterSellerNotifications(list, { type }), [list, type])
  const unreadTotal = unreadSellerNotificationCount(list)
  const unreadByType = useMemo(() => unreadCountsBySellerType(list), [list])
  const unreadVisible = unreadSellerNotificationCount(visible, { type })

  /* The last hidden row, held only so the undo strip can name it. */
  const [hidden, setHidden] = useState(null)

  const setType = (next) => {
    const nextParams = new URLSearchParams(params)
    if (next) nextParams.set('type', next)
    else nextParams.delete('type')
    setParams(nextParams, { replace: true })
  }

  const onHide = (row) => {
    setHidden({ id: row.id, title: row.title })
    hide.mutate(row.id)
  }

  /*
    `other` is a word this build invented for a type it does not know, so a
    scoped "mark all read" cannot express it as a filter — it would match
    nothing and report success. Those cards are cleared one at a time by opening
    them, which is why the button is simply absent under that chip.
  */
  const canMarkAll = type !== OTHER_SELLER_NOTIFICATION_TYPE

  return (
    <div className={className}>
      {!isLoading && list.length > 0 && (
        <>
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div className="flex flex-wrap items-center gap-1.5" role="group" aria-label="Filter by type">
              <Chip label="Everything" active={type === null} onClick={() => setType('')} />
              {present.map((name) => {
                const Icon = TYPE_ICONS[name]
                const unread = unreadByType[name]

                return (
                  <button
                    key={name}
                    type="button"
                    onClick={() => setType(type === name ? '' : name)}
                    aria-pressed={type === name}
                    className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-semibold transition-colors duration-200 ease-out-cubic ${
                      type === name
                        ? 'border-clay bg-clay text-ink-inverse'
                        : 'border-hairline text-muted-strong hover:border-card-edge hover:text-ink'
                    }`}
                  >
                    <Icon size={13} strokeWidth={2} aria-hidden="true" />
                    {sellerNotificationTypeLabel(name)}
                    {unread > 0 && (
                      <span
                        className={`num rounded-full px-1.5 text-[10px] ${
                          type === name ? 'bg-ink-inverse/20' : 'bg-clay/15 text-clay-ink'
                        }`}
                      >
                        {unread}
                      </span>
                    )}
                  </button>
                )
              })}
            </div>

            {unreadVisible > 0 && canMarkAll && (
              <button
                type="button"
                onClick={() => markAllRead.mutate(type)}
                disabled={markAllRead.isPending}
                className="inline-flex items-center gap-1.5 rounded-full border border-hairline px-3 py-1.5 text-xs font-semibold text-muted-strong transition-colors duration-200 ease-out-cubic hover:border-card-edge hover:text-ink"
              >
                <CheckCheck size={13} strokeWidth={2} aria-hidden="true" />
                {markAllRead.isPending
                  ? 'Marking…'
                  : type
                    ? `Mark ${sellerNotificationTypeLabel(type)} read`
                    : 'Mark all read'}
              </button>
            )}
          </div>

          <p className="mt-2 text-xs text-muted">
            {pluralize(visible.length, 'notification')}
            {unreadVisible > 0 ? ` · ${unreadVisible} unread` : ''}
            {unreadTotal > unreadVisible ? ` · ${unreadTotal} unread in all` : ''}
          </p>
        </>
      )}

      {/* ── Undo, while the seller is still on this page ──────────── */}
      {hidden && (
        <div
          role="status"
          className="mt-4 flex flex-wrap items-center gap-3 rounded-card border border-hairline bg-subtle/60 px-4 py-3 text-xs text-muted"
        >
          <span className="min-w-0 flex-1 truncate">Hidden “{hidden.title}”.</span>
          <button
            type="button"
            onClick={() => {
              restore.mutate(hidden.id)
              setHidden(null)
            }}
            className="inline-flex items-center gap-1.5 font-semibold text-clay-ink underline-offset-4 hover:underline"
          >
            <RotateCcw size={13} strokeWidth={2} />
            Undo
          </button>
        </div>
      )}

      {/* ── The feed ──────────────────────────────────────────────── */}
      <div className="mt-4">
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
          <ul className="space-y-3">
            {visible.map((row) => (
              <li key={row.id}>
                <NotificationCard
                  notification={row}
                  onOpen={() => {
                    if (!row.is_read) markRead.mutate(row.id)
                  }}
                  onToggleRead={() =>
                    row.is_read ? markUnread.mutate(row.id) : markRead.mutate(row.id)
                  }
                  onHide={() => onHide(row)}
                />
              </li>
            ))}
          </ul>
        ) : (
          <EmptyState
            Icon={BellOff}
            title={type ? 'Nothing under this filter' : 'Nothing yet'}
            description={
              type
                ? 'Try another kind, or show everything.'
                : 'Orders, low stock and messages from customers will appear here as they happen.'
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
 * The card is a panel with a stretched link inside it when there is somewhere to
 * go, and a plain panel when there is not — see `sellerNotificationDestination`,
 * which answers `none` for a custom order request (that screen is in the app)
 * and for any type this build does not know. A card that goes to the wrong page
 * is worse than one that admits it does not move.
 *
 * The two small controls sit above the link rather than inside it: a `button`
 * nested in an `a` is invalid, and a click on "hide" would also navigate.
 */
function NotificationCard({ notification, onOpen, onToggleRead, onHide }) {
  const type = sellerNotificationType(notification.type)
  const Icon = TYPE_ICONS[type] ?? CircleAlert
  const unread = !notification.is_read
  const batched = isBatchedSellerNotification(notification)
  const previews = notificationPreviews(notification)
  const destination = sellerNotificationDestination(notification)
  const to = destinationTo(destination)

  /*
    The two controls are always drawn, unlike the chat bubble's delete button.
    A control that is only revealed by hovering is a control that does not exist
    on a touch screen — and these two are not invisible there, they are invisible
    *and tappable*, which is how a thumb aiming at the card hides a notification
    instead. `pr-16` on the title row reserves the space, so they never overlap
    the timestamp.
  */
  const controls = (
    <div className="absolute right-3 top-3 z-20 flex items-center gap-0.5">
      <button
        type="button"
        onClick={onToggleRead}
        title={unread ? 'Mark as read' : 'Mark as unread'}
        className="flex h-7 w-7 items-center justify-center rounded-full text-muted transition-colors duration-200 ease-out-cubic hover:bg-subtle hover:text-ink"
      >
        <CheckCheck size={14} strokeWidth={2} />
        <span className="sr-only">{unread ? 'Mark as read' : 'Mark as unread'}</span>
      </button>
      <button
        type="button"
        onClick={onHide}
        title="Hide this notification"
        className="flex h-7 w-7 items-center justify-center rounded-full text-muted transition-colors duration-200 ease-out-cubic hover:bg-subtle hover:text-ink"
      >
        <EyeOff size={14} strokeWidth={2} />
        <span className="sr-only">Hide this notification</span>
      </button>
    </div>
  )

  const body = (
    <>
      <span
        aria-hidden="true"
        className={`mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-full ${
          unread ? 'bg-clay/10 text-clay-ink' : 'bg-subtle text-muted'
        }`}
      >
        <Icon size={18} strokeWidth={1.9} />
      </span>

      <div className="min-w-0 flex-1">
        <div className="flex items-baseline gap-2 pr-16">
          <p
            className={`min-w-0 flex-1 truncate ${
              unread ? 'font-semibold text-ink' : 'font-medium text-muted-strong'
            }`}
          >
            {notification.title}
          </p>
          <time
            dateTime={notification.created_at ?? undefined}
            className="shrink-0 text-xs text-muted"
          >
            {notificationRelativeTime(notification.created_at)}
          </time>
        </div>

        <p className="mt-1 text-sm leading-relaxed text-muted">{notification.body}</p>

        {batched && previews.length > 0 && (
          <ul className="mt-2.5 space-y-1.5 border-l-2 border-hairline-soft pl-3">
            {previews.map((preview, index) => (
              <li key={`${preview.timestamp ?? index}`} className="text-xs text-muted">
                <span className="font-medium text-muted-strong">
                  {preview.sender || 'Customer'}:
                </span>{' '}
                {preview.text}
              </li>
            ))}
            <li className="text-xs italic text-muted">
              {sellerNotificationMessageCount(notification)} messages in this thread
            </li>
          </ul>
        )}

        <div className="mt-2 flex flex-wrap items-center gap-2 text-[11px] uppercase tracking-[0.08em] text-muted">
          <span>{sellerNotificationTypeLabel(notification.type)}</span>
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
    'relative flex gap-4 rounded-card border bg-raised p-4 shadow-card transition-[transform,border-color,box-shadow] duration-300 ease-out-cubic'
  const unreadEdge = unread
    ? 'border-l-4 border-l-clay border-y-hairline border-r-hairline'
    : 'border-hairline'

  /* Nothing to open: the card is a panel, and its two controls are the only
     interactive things in it. */
  if (!to) {
    return (
      <div className={`${shell} ${unreadEdge}`}>
        {controls}
        {body}
      </div>
    )
  }

  return (
    <div
      className={`${shell} ${unreadEdge} hover:-translate-y-0.5 hover:border-card-edge hover:shadow-card-lift`}
    >
      <Link
        to={to}
        onClick={onOpen}
        aria-label={notification.title}
        className="absolute inset-0 z-10 rounded-card"
      />
      {controls}
      {body}
    </div>
  )
}

/**
 * A destination, as a path — or `null` when this portal has nowhere to send it.
 *
 * Kept out of the rules module for the reason `sellerNotificationDestination`
 * gives (no `Link`, no paths in a pure rules file), and kept in one function
 * here so the card and the empty state cannot drift.
 */
function destinationTo(destination) {
  switch (destination.kind) {
    case 'order':
      return `/seller/orders/${destination.orderId}`
    case 'orders':
      return '/seller/orders'
    case 'product':
      return `/seller/products/${destination.productId}`
    case 'products':
      return '/seller/products'
    case 'conversation':
      return `/seller/messages/${destination.conversationId}`
    case 'messages':
      return '/seller/messages'
    default:
      return null
  }
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
