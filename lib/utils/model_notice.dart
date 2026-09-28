/// What a "your 3D model…" notice is allowed to take the seller to.
///
/// Pure Dart — no Flutter — so the rule is unit-testable (the
/// `shoe_model_request.dart` precedent), and so the two halves of the tap can
/// be read in one place: what the notice names, and the row that names it.
///
/// WHY THIS EXISTS (roadmap V2.14):
///
/// V2.12 and V2.13 made both endings of a model request audible — the seller's
/// feed says "ready" or "the team could not make one", in the admin's own
/// words, without the seller having to open a product to find out. Tapping one
/// of those cards then did nothing at all: it marked the notice read and
/// stopped, because every navigation branch in the feed keys on `order_id`
/// and a model notice has none. The metadata has carried `product_id` since
/// V2.12 — pinned by a pgTAP assertion that exists precisely because nothing
/// read it — so the link was one lookup away and the notice was a dead end.
///
/// ⚠️ THE METADATA KEYS ARE A CONTRACT WITH SQL, NOT A LOCAL DETAIL.
/// `fulfil_shoe_model_request` and `decline_shoe_model_request` build that
/// object with `jsonb_build_object('request_id', …, 'product_id', …)`, and
/// nothing in Dart or SQL would fail to compile if either side renamed a key —
/// the notice would simply stop being tappable, silently, in the one place
/// nobody looks. `test/services/model_notice_contract_test.dart` reads this
/// file's keys back out of the migration for that reason.
///
/// The keys here are the whole of the rule. There is deliberately **no**
/// branch on which ending the notice carries: both endings tell the seller
/// something about a product they asked about, and both should land on that
/// product's actions — where the request row itself explains the rest.
///
/// ⚠️ AND THERE ARE TWO CHANNELS, BECAUSE ONE OF THEM NOBODY READS (V2.14).
/// The per-user row in `public.notifications` is written to the seller who
/// asked and rendered only by the customer shell's feed — a surface a seller's
/// session never reaches. The seller's own bell reads `seller_notifications`,
/// store-scoped rows with a `type` and a `reference_id`. So the database
/// writes both (see the migration) and this file resolves both:
/// [modelNoticeTarget] for the per-user row, [modelNoticeTargetFromSellerRow]
/// for the bell. The two functions return the same shape on purpose — one
/// landing, one place for the seller to be taken to.
library;

import '../models/notification_category.dart';

/// The product a model notice is about.
///
/// Built only from what the notice actually carries: a notice with a blank or
/// missing `product_id` yields **null** rather than a target that would open
/// the seller's catalog at random, which is the difference between a link that
/// does nothing and a link that does the wrong thing.
class ModelNoticeTarget {
  /// The product to open the actions sheet for.
  final String productId;

  /// The request the notice is about, when the notice carries one.
  ///
  /// Nothing reads this yet — the sheet has one request row per product, so
  /// the product is enough to open the right thing (the same "carried, not yet
  /// used" position the SQL assertion pins). It is parsed here so the day a
  /// second surface wants to point at the request itself, the notice already
  /// answers the question.
  final String? requestId;

  const ModelNoticeTarget({required this.productId, this.requestId});

  @override
  String toString() =>
      'ModelNoticeTarget(productId: $productId, requestId: $requestId)';
}

/// The target this notice points at, or null when it points nowhere.
///
/// [category] is required rather than assumed: `metadata` is a free-form jsonb
/// column shared by every notification in the app, so a `product_id` on a
/// *shipping* notice must not be mistaken for this flow's. That is also why the
/// check is on the parsed enum and not on the raw wire string.
ModelNoticeTarget? modelNoticeTarget({
  required NotificationCategory category,
  Map<String, dynamic>? metadata,
}) {
  if (category != NotificationCategory.models) return null;
  final productId = _usableId(metadata?['product_id']);
  if (productId == null) return null;
  return ModelNoticeTarget(
    productId: productId,
    requestId: _usableId(metadata?['request_id']),
  );
}

/// A metadata value that can be used as an id, or null.
///
/// Tolerant of a numeric id (`jsonb` keeps numbers as numbers) and of
/// surrounding whitespace, since the value arrives from the database rather
/// than from a form. A blank string is not an id and never becomes one: a
/// notice with `product_id: ''` must fail here rather than match the first row
/// whose id is also empty.
String? _usableId(Object? raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  return value.isEmpty ? null : value;
}

/// The `seller_notifications.type` a model notice carries.
///
/// ⚠️ A wire value shared with a plpgsql CHECK constraint, which is why it is a
/// named constant rather than a literal in a `switch`: the migration that adds
/// this type has to admit it in `seller_notifications_type_check`, and a type
/// the database refuses is not a missing notification — the insert runs inside
/// the transaction that CLOSES the seller's ask, so a refused type would leave
/// the ask open. `model_notice_contract_test.dart` reads both sides.
const String kModelRequestSellerType = 'model_request';

/// The target a seller-bell row points at, or null when it points nowhere.
///
/// The seller's notification centre is store-scoped: a row there carries a
/// `type` and a `reference_id`, not a `metadata` object (see
/// [modelNoticeTarget] for the per-user shape the feed uses). Both are the same
/// news about the same product, so both resolve to the same
/// [ModelNoticeTarget] and land in the same place.
ModelNoticeTarget? modelNoticeTargetFromSellerRow({
  required String type,
  String? referenceId,
}) {
  if (type != kModelRequestSellerType) return null;
  final productId = _usableId(referenceId);
  if (productId == null) return null;
  return ModelNoticeTarget(productId: productId);
}

/// The catalog row [productId] names, or null when the seller's catalog does
/// not hold it.
///
/// Compared as strings because the two sides arrive from different places: the
/// catalog's `id` is a uuid from Postgres (a string in Dart, but not
/// guaranteed to be one in every list this screen holds) and the notice's id
/// is a string out of `jsonb`. A row without an `id` is skipped rather than
/// matched on `null.toString()`.
Map<String, dynamic>? linkedProduct(
  List<Map<String, dynamic>> catalog,
  String productId,
) {
  final wanted = productId.trim();
  if (wanted.isEmpty) return null;
  for (final product in catalog) {
    final id = product['id'];
    if (id == null) continue;
    if (id.toString() == wanted) return product;
  }
  return null;
}
