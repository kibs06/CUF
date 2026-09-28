import {
  BadgeCheck,
  CalendarClock,
  CircleAlert,
  Clock,
  MessageSquare,
  PackageMinus,
  Receipt,
  RotateCcw,
  Ruler,
  Star,
  Tag,
  Truck,
  Wallet,
  Wrench,
} from 'lucide-react'

import { notificationCategory } from '../../lib/notificationRules.js'
import {
  OTHER_SELLER_NOTIFICATION_TYPE,
  sellerNotificationType,
} from '../../lib/sellerNotificationRules.js'

/**
 * How each kind of notification is drawn, for every surface that draws one.
 *
 * The customer feed, the seller feed and the toast centre all put an icon on a
 * card, and the only thing worse than one of them picking a strange icon is all
 * three disagreeing about it — a "Low stock" warning that is a box on the page
 * and a clock in the corner reads as two different notifications. So the maps
 * live here and the callers pass a whole row in.
 *
 * ## The fallbacks are the two rules modules' own defaults
 *
 * A customer category this build does not recognise is `unpaid` — that is what
 * `notificationCategory` says, and the feed already draws it as a wallet. A
 * seller type it does not recognise is `other`, which is the one case drawn as a
 * question mark: the type was never guessed at, so the icon is not either.
 */

/** Keyed by `notificationCategory()`, in the app's enum order. */
export const CUSTOMER_CATEGORY_ICONS = {
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

/** Keyed by `sellerNotificationType()`, including the `other` fallback. */
export const SELLER_TYPE_ICONS = {
  new_order: Receipt,
  stale_order: Clock,
  low_stock: PackageMinus,
  custom_order_request: Ruler,
  new_message: MessageSquare,
  [OTHER_SELLER_NOTIFICATION_TYPE]: CircleAlert,
}

/** The icon for a customer notification row. */
export function customerNotificationIcon(row) {
  return CUSTOMER_CATEGORY_ICONS[notificationCategory(row?.category)] ?? Wallet
}

/** The icon for a seller notification row. */
export function sellerNotificationIcon(row) {
  const type = sellerNotificationType(row?.type)
  return SELLER_TYPE_ICONS[type] ?? CircleAlert
}
