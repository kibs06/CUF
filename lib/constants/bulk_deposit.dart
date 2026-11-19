/// The bulk-reservation deposit: a share of the estimated value
/// (quantity × base product price at approval), rounded UP to a whole peso.
///
/// This number appears in two places that must never drift apart:
///   * the server, which charges it — `public.bulk_reservation_deposit_rate()`
///     in `20261119230000_bulk_deposit_seventy_percent.sql`;
///   * the app, which quotes it before the customer commits (the pre-approval
///     estimate in the reservation sheet) and labels it on the pay screen.
///
/// Change both together; the compile-time constant is here so the app side is
/// one edit.
const double kBulkReservationDepositRate = 0.70;

/// The same rate as copy — "70%". Derived, never typed by hand, so a rate
/// change cannot leave a stale "20%" in a label.
final String kBulkReservationDepositLabel =
    '${(kBulkReservationDepositRate * 100).round()}%';

/// The deposit owed on [value] — the estimate the request sheet quotes.
///
/// [value] is what the customer is actually buying: price × pairs, less any
/// voucher the server priced for this request. Rounded UP to a whole peso, the
/// same rule the server applies at approval, and floored at zero so a discount
/// larger than the value never produces a negative estimate.
double bulkDepositFor(double value) =>
    (value.clamp(0, double.infinity) * kBulkReservationDepositRate)
        .ceilToDouble();
