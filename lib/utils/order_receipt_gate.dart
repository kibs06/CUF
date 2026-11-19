/// The receipt rule every seller surface shares: an order cannot be handed
/// over until its customer has the receipt.
///
/// `orders.receipt_emailed_at` is written by the `send-order-receipt` function
/// only after SMTP accepts the message, so an empty value is positive proof the
/// customer does not have it yet — unlike a queued send or a composer that was
/// opened. Keeping the rule here means the order screen and the Orders list
/// cannot drift apart on the one decision that matters at handover.
library;

/// The address a receipt would go to: what the till recorded for this sale
/// (`orders.customer_email`), else the customer's registered profile email
/// (already embedded in the seller's order rows). Null when neither exists.
String? orderReceiptEmail(Map<String, dynamic> order) {
  final typed = order['customer_email']?.toString().trim() ?? '';
  if (typed.isNotEmpty) return typed;
  final profile = order['profiles'];
  if (profile is Map) {
    final email = profile['email']?.toString().trim() ?? '';
    if (email.isNotEmpty) return email;
  }
  return null;
}

/// Whether marking this order Delivered must wait for the receipt.
///
/// Returns false — the handover stays allowed — in the three cases where
/// waiting would be wrong:
/// * the order is not at Ready (there is no handover to guard),
/// * the server does not carry the receipt columns yet (nothing to read),
/// * no address is on file (nothing could be sent).
bool orderNeedsReceiptBeforeDelivery(
  Map<String, dynamic> order,
  String currentStatus,
) {
  if (currentStatus.toLowerCase() != 'ready') return false;
  if (!order.containsKey('receipt_emailed_at')) return false;
  if ((order['receipt_emailed_at']?.toString() ?? '').isNotEmpty) return false;
  return orderReceiptEmail(order) != null;
}
