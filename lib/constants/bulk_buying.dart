// The rules of bulk (reseller) buying that both sides must read the same way.

/// The smallest order that counts as bulk buying.
///
/// Ten units. Below that a request is an ordinary purchase — the cart, the
/// normal checkout and the normal delivery/pickup options handle it — so the
/// bulk sheet keeps its Send Request button disabled and says why.
///
/// This mirrors `public.bulk_minimum_quantity()` (migration
/// 20261119250000_bulk_minimum_quantity.sql), which refuses a smaller request
/// with `BULK_MINIMUM_QUANTITY` even if a client tries. The server is the
/// enforcement; this constant is here so the customer is told the rule before
/// they hit it, and so the disabled button and the refusal agree.
const int kBulkMinimumQuantity = 10;

/// How the rule is phrased wherever it is shown to a customer or seller.
/// `10 pairs minimum` — the unit the bulk sheet counts in.
const String kBulkMinimumLabel = '$kBulkMinimumQuantity pairs minimum';
