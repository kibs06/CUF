/// Where a push notification should land when its payload carries a `type`
/// but no `screen`.
///
/// Every sender we control sets `screen` explicitly (see
/// `ReservationService._push*`). This map exists for the payloads that do not:
/// notifications re-sent from a DB trigger, and pushes queued before `screen`
/// was added. Without it those taps opened the app on whatever tab was last
/// used, which reads as "the notification is not tappable".
///
/// Kept free of Flutter/Firebase imports so the mapping can be tested directly.
String? screenForPushType(String? type) {
  switch (type) {
    // Seller-facing: someone acted on a bulk reservation request.
    case 'bulk_reservation_request':
    case 'bulk_reservation_deposit_proof':
    // Bell-row types, in case one is ever pushed as well as written in-app.
    case 'bulk_reservation':
    case 'bulk_reservation_deposit':
      return 'seller_reservations';

    // Customer-facing: the store moved their reservation forward.
    case 'bulk_reservation_approved':
    case 'bulk_reservation_declined':
    case 'bulk_reservation_deposit_declined':
    case 'bulk_reservation_deposit_confirmed':
      return 'my_reservations';

    // Unknown types keep today's behaviour (mark read, no navigation).
    default:
      return null;
  }
}
