import '../constants/app_constants.dart';

/// The seller profile's own view of the admin-granted trust flag.
///
/// The Verified Seller badge needs **both** facts: this account is a seller,
/// and the business-docs verdict is `verified`. A verified flag left over on a
/// demoted account must not draw a seller badge, and a seller still under
/// review must not either.
bool showsVerifiedSellerBadge({
  required String role,
  required String businessStatus,
}) =>
    role == AppConstants.roleSeller &&
    businessStatus == AppConstants.bizStatusVerified;

/// How long the profile's cached business-docs verdict stays trusted before a
/// tab re-entry re-reads it. `seller_verified_at` is written by an admin on
/// another device, so without this the header badge would stay stale for the
/// rest of the session.
const Duration sellerTrustRefreshAfter = Duration(seconds: 30);

/// Whether the cached trust state is old enough to re-read on re-entry.
/// `null` means nothing has been fetched yet — the initial load is already in
/// flight, so a re-entry must not start a second one.
bool sellerTrustIsStale(DateTime? fetchedAt, DateTime now) =>
    fetchedAt != null && now.difference(fetchedAt) > sellerTrustRefreshAfter;

/// Whether the Business Verification settings row should still be shown.
///
/// The row exists to let a seller act — submit documents, correct a rejection,
/// or wait for a verdict. Once verified there is nothing left to do, so the row
/// is replaced by the header badge (and the Business Permit row takes its
/// place). `none`, `pending` and `rejected` all keep it: hiding it would strand
/// exactly the sellers who still have work to do.
bool showsBusinessVerificationRow(String businessStatus) =>
    businessStatus != AppConstants.bizStatusVerified;
