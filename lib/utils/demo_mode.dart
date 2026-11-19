// Demo-mode helpers — the two values a demo build needs to get past a payment
// gate without money moving.
//
// These live outside the screens so the rules stay in one place and can be
// tested: a GCash reference must be 13 digits and unique (the database rejects
// a reused reference on a paid order, across orders AND deposit proofs), and a
// deposit proof's screenshot path must start with the reservation id or the
// submit RPC refuses it outright.
//
// Nothing here is reachable unless a build passed `--dart-define=DEMO_MODE=true`
// — see `AppConstants.demoModeEnabled`.

/// A sequence counter, so two references generated inside the same microsecond
/// are still different. `DateTime.now()` is not guaranteed to advance between
/// two calls on a fast device.
int _sequence = 0;

/// A 13-digit GCash reference for a demo payment.
///
/// Shaped like a real one on purpose — the database checks the digits and
/// enforces single use across the order, proof and deposit ledgers, so a demo
/// reference has to be able to stand where a real one would. It is NOT
/// recognisable as fake from the number alone; the demo banner on screen is
/// what tells the operator, and no real GCash app will recognise it.
String demoGcashReference({DateTime? now}) {
  final micros = (now ?? DateTime.now()).microsecondsSinceEpoch;
  _sequence = (_sequence + 1) % 100;
  final body = (micros % 9999999999).toString().padLeft(10, '0');
  return '9$body${_sequence.toString().padLeft(2, '0')}';
}

/// The screenshot path a demo deposit proof records.
///
/// `submit_bulk_reservation_deposit_proof` requires the path's first segment to
/// be the reservation id (the same `{reservation_id}/{file}` convention the
/// private bucket uses), so the fake path has to satisfy it. Nothing is
/// uploaded: the seller's review sheet shows its "Screenshot unavailable"
/// state, and the demo tells the operator why.
String demoDepositScreenshotPath(String reservationId) =>
    '$reservationId/demo-mode-no-screenshot.jpg';
