import { notificationDestination } from './notificationRules.js'
import { sellerNotificationDestination } from './sellerNotificationRules.js'

/**
 * Where a notification actually goes, as a path — the last step after each
 * side's destination rules.
 *
 * The two rules modules deliberately answer *what* a card points at
 * (`{ kind: 'order', orderId }`) rather than a URL, so that `Link` and the
 * portal's route table stay out of them. This is the other half of that split,
 * in one module for both sides, because there are now two callers per side: the
 * feed card, and the toast that pops over whatever page the customer is on. Two
 * copies of this switch would be two chances for a toast to open a different
 * page than the card sitting in the feed beside it.
 *
 * `null` means "this portal has nowhere to put it", which is a real answer and
 * not an error: the customer's support reply lives in the app's reports screen,
 * and a seller's custom order request has no web equivalent. Both callers draw
 * that case inert rather than linking somewhere unrelated.
 */

/** `/messages/:id` or `/orders/:id`; `null` when there is nowhere to go. */
export function customerNotificationPath(row) {
  const destination = notificationDestination(row)

  if (destination.kind === 'conversation') return `/messages/${destination.conversationId}`
  if (destination.kind === 'order') return `/orders/${destination.orderId}`

  // `reports` and `none`: the portal has no such screen.
  return null
}

/** The seller's `/seller/*` paths. Falls back to a list when a row names no id. */
export function sellerNotificationPath(row) {
  const destination = sellerNotificationDestination(row)

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
