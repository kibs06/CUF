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
    'Sofia Mendoza',
    'Kevin Garcia',
    'Bianca Ramos',
    'Daniel Cruz',
    'Jessa Villamor',
    'Jomari Flores',
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
      'Nindot kaayo ang quality para sa presyo. Humok ang lapalapa ug dili '
          'danlog. Ikaduha na nako ni nga pares.'
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
    (
      5,
      'Worth every peso! Yung strap hindi sumasakit sa paa kahit whole day '
          'lakad. Ordered one for my sister too.',
    ),
    (
      5,
      'Lig-on gyud. Naulanan na, nabasa na, pero walay natangtang. '
          'Highly recommended sa mga commuters!'
    ),
    (
      4,
      'Comfy and stylish, goes well with shorts and dresses. A little on '
          'the heavy side but manageable. Four stars!'
    ),
    (
      5,
      'Perfect fit! Sinunod ko yung size guide and sakto talaga. Ang lambot '
          'ng insole, parang naka-cushion.',
    ),
    (
      4,
      'Nindot ang tahi, walay nagbitay nga sinulid. Gamayng break-in lang sa '
          'strap unya okay na. Sulit!'
    ),
    (
      5,
      'My third order from this shop and hindi pa rin ako nadidisappoint. '
          'Consistent yung quality. Five stars!',
    ),
    (
      3,
      'Decent pair for the price. The color is a bit lighter in person but '
          'overall it is fine. Still comfy.'
    ),
    (
      5,
      'Dili danlog bisan sa tiles! Dako kaayo nig tabang kay pirmi ko '
          'nagdali. Salamat seller!'
    ),
    (
      4,
      'Ganda ng packaging, may dust bag pa. Yung pair mismo maganda, '
          'medyo stiff lang yung sole nung una.',
    ),
    (
      5,
      'Lami sa tiil, murag wala kay gisul-ob. Pang-adlaw-adlaw na nako ni '
          'sa opisina. Highly recommended!'
    ),
    (
      2,
      'Sayang, luag kaayo sa akong tiil bisan sakto ang size nga akong gi-order. '
          'Okay ra ang quality pero dili gyud mo-fit. Magpa-exchange ko.',
    ),
    (
      5,
      'Ang bilis ng shipping, 2 days lang nasa akin na! Sakto yung size '
          'and ang ganda ng finish. Ulitin ko!',
    ),
    (
      4,
      'Lightweight and easy to clean. Got caught in the rain, just wiped it '
          'and it was fine. Taking off one star because the strap feels thin.'
    ),
    (
      5,
      'Best purchase ko this year! Walang blisters kahit first wear. '
          'Yung arch support ramdam mo talaga.',
    ),
    (
      3,
      'Average for me — comfortable but the design is a bit plain. '
          'Good for daily errands though.'
    ),
    (
      5,
      'Gipalit nako para sa akong mama kay naa siyay arthritis, ug ganahan '
          'kaayo siya! Humok ug dili sakit sa lutahan. Salamat!'
    ),
    (
      4,
      'Good value for money. Matibay yung sole and hindi maingay maglakad. '
          'Will buy again in black.',
    ),
    (
      5,
      'Grabe ka gaan, murag walay sul-ob! Perfect pang-beach ug pang-laag. '
          'Kapila na ko nag-order diri.'
    ),
    (
      1,
      'The strap snapped after two weeks of light use. Very disappointed — '
          'I expected better stitching at this price. Returning mine.',
    ),
    (
      4,
      'Stylish and comfy, I even got compliments! Needed a small strap '
          'adjustment at first but now it fits perfectly.'
    ),
  ];

  // 20 reviews per product with a realistic but store-friendly spread:
  // ~15 good (5★), ~3 neutral (3–4★), ~2 bad (1–2★). The template below
  // fixes the shape so EVERY product shows all three kinds AND the average
  // stays 4.0+; only the pool entries and names rotate per product.
  const count = 20;
  const shape = [5, 5, 4, 5, 5, 5, 4, 5, 2, 5, 5, 3, 5, 5, 1, 5, 4, 5, 5, 5];
  final now = DateTime.now();
  final reviews = <Map<String, dynamic>>[];

  // Per-rating cursors so each star value rotates through its own pool
  // entries with the seed. Exact-match only: the card at position [i]
  // always carries shape[i] as its rating, so the breakdown bars and the
  // average are identical on every product (14×5★, 3×4★, 1×3★, 1×2★,
  // 1×1★ → 4.40 avg) and only the comments/names rotate.
  final cursors = <int, int>{
    5: seed,
    4: seed ~/ 2,
    3: seed ~/ 3,
    2: seed ~/ 7,
    1: seed ~/ 11,
  };
  int nextOf(int target) {
    final stride = target == 5 ? 1 : (target == 4 ? 3 : 7);
    for (var step = 0; step < pool.length; step++) {
      final idx = (cursors[target]! + step * stride) % pool.length;
      if (pool[idx].$1 == target) {
        cursors[target] = idx + 1;
        return idx;
      }
    }
    return (seed + target) % pool.length; // unreachable: every value exists
  }

  for (var i = 0; i < count; i++) {
    final target = shape[i];
    final entry = pool[nextOf(target)];
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

/// Deterministic demo sold count, derived from the demo review count so
/// the two can never contradict each other (sold is always comfortably
/// above reviews — not everyone leaves a review — and the SAME function
/// feeds the home card and the detail page, so both surfaces agree).
/// Seeded by [productId] for stable per-product variety (≈4–8× reviews).
int buildDemoSoldCount(String productId, {int reviewCount = 20}) {
  final seed = productId.hashCode.abs();
  final mult = 4 + (seed % 5); // 4…8
  return reviewCount * mult + (seed % 37); // 20 reviews → ~80…197
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
