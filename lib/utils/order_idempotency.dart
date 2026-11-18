import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// The index that turns a retried cash checkout into "you already placed this",
/// rather than a second order. Kept in one place so the service, the checkout
/// screen and the tests cannot drift from the migration that created it.
const String orderIdempotencyIndex = 'uq_orders_customer_idempotency_key';

/// One key per checkout intent. The screen generates it once and reuses it for
/// every retry of the same submit, then rotates it as soon as an order exists —
/// reusing it after that would hand the customer their previous order.
String newOrderIdempotencyKey([Uuid uuid = const Uuid()]) => uuid.v4();

/// True when the insert failed because this exact key already produced an
/// order — i.e. the earlier attempt committed and its response was lost.
///
/// Only that constraint counts. Any other 23505 (the GCash one-open-checkout
/// cap, a foreign key, a stock invariants index) must still reach the caller
/// as the error it is.
bool isOrderIdempotencyConflict(Object? error) {
  if (error is! PostgrestException) return false;
  if (error.code != '23505') return false;
  final haystack = '${error.message} ${error.details} ${error.hint}'
      .toLowerCase();
  return haystack.contains(orderIdempotencyIndex);
}
