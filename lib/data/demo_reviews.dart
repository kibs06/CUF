// ═══════════════════════════════════════════════════════════════════
// ⚠️  DEMO ONLY — MOCK REVIEWS & RATINGS  ⚠️
// ═══════════════════════════════════════════════════════════════════
// This file fabricates customer reviews on-device so the demo shows
// populated ratings, breakdown bars, and review cards for products that
// have no real reviews yet. NOTHING here touches the database: no rows
// are written, product aggregates are untouched, and demo reviews can
// never be voted on, edited, or replied to (see `is_demo` guards in
// `SoleReviewCard` and `ReviewProvider.loadReviews`).
//
// ── HOW TO REMOVE FOR REAL DEPLOYMENT ─────────────────────────────
//   Option A (quick): set [kDemoReviewsEnabled] = false below.
//   Option B (clean): delete this file AND remove the two marked
//     `DEMO ONLY` blocks in:
//       • lib/providers/review_provider.dart  (demo fallback)
//       • lib/screens/customer/product_detail_screen.dart (rating fallback)
//       • lib/widgets/sole_review_card.dart   (Demo badge + vote guard)
//   Demo cards also render a visible "Demo" pill so they are never
//   mistaken for real customer feedback during the demo.
// ═══════════════════════════════════════════════════════════════════

/// Master kill-switch. Set to false (or delete this file) before the
/// real deployment to strip every trace of mock reviews from the app.
const bool kDemoReviewsEnabled = true;

/// Builds a deterministic set of mock reviews for a product. The lineup
/// varies per product (seeded by [productId]) so sibling products don't
/// show identical feedback, but it is stable across rebuilds.
List<Map<String, dynamic>> buildDemoReviewsForProduct(String productId) {
  final seed = productId.hashCode.abs();

  const names = [
    'Maria Santos',
    'Juan Dela Cruz',
    'Angel Reyes',
    'Mark Villanueva',
    'Jenny Lim',
    'Paolo Aquino',
    'Katrina Uy',
    'Ramon Torres',
  ];

  // (rating, comment) pairs — honest-looking spread, mostly positive.
  const pool = [
    (
      5,
      'Super comfortable! Wore them the whole day sa mall and walang masakit. '
          'True to size din. Highly recommended!'
    ),
    (
      5,
      'Ganda ng quality for the price. Malambot yung sole and hindi madulas. '
          'Second pair ko na ito.',
    ),
    (
      4,
      'Nice design and comfy, medyo masikip lang nung una pero after a few wears '
          'lumambot na. Good buy overall.',
    ),
    (
      5,
      'Ang gaan sa paa! Perfect pang daily use. Mabilis din yung delivery. '
          'Will order again in another color.',
    ),
    (
      4,
      'Looks exactly like the photos. Sole is sturdy and the stitching is '
          'clean. Sana more colors pa.',
    ),
    (
      3,
      'Okay naman, medyo narrow lang for wide feet like mine. Buti na lang '
          'nag-size up ako. Quality is fine.',
    ),
  ];

  final count = 3 + (seed % 2); // 3–4 reviews per product
  final now = DateTime.now();
  final reviews = <Map<String, dynamic>>[];

  for (var i = 0; i < count; i++) {
    final entry = pool[(seed + i * 2) % pool.length];
    final created = now.subtract(Duration(days: (seed % 20) + i * 4 + 1));
    reviews.add({
      // Stable fake id (never in the DB) + explicit demo flag.
      'id': 'demo-$seed-$i',
      'is_demo': true,
      'rating': entry.$1,
      'comment': entry.$2,
      'body': entry.$2,
      'title': null,
      'reviewer_name': names[(seed + i * 3) % names.length],
      'reviewer_avatar': null,
      'is_verified': true,
      'created_at': created.toIso8601String(),
      'review_images': <Map<String, dynamic>>[],
      'seller_reply': i == 0
          ? 'Thank you for the support! Enjoy your new pair — message us '
              'anytime if you need anything. 🙏'
          : null,
      'seller_reply_at':
          i == 0 ? created.add(const Duration(days: 1)).toIso8601String() : null,
      'is_pinned': false,
    });
  }
  return reviews;
}

/// Synthesizes the rating-summary shape `ReviewProvider` expects
/// (`avg_rating`, `review_count`, `breakdown`) from demo reviews so the
/// summary bar, breakdown bars, and price-row stars match the mock list.
Map<String, dynamic> buildDemoRatingSummary(
    List<Map<String, dynamic>> demoReviews) {
  final breakdown = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
  var total = 0;
  for (final r in demoReviews) {
    final rating = (r['rating'] as num?)?.toInt() ?? 0;
    if (rating >= 1 && rating <= 5) {
      breakdown[rating] = (breakdown[rating] ?? 0) + 1;
      total += rating;
    }
  }
  final count = demoReviews.length;
  return {
    'avg_rating': count == 0 ? 0.0 : total / count,
    'review_count': count,
    'breakdown': breakdown,
  };
}
