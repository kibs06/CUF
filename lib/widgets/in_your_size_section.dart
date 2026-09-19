import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../models/foot_measurement.dart';
import '../providers/auth_provider.dart';
import '../providers/foot_measurement_provider.dart';
import '../providers/product_provider.dart';
import 'best_sellers_section.dart';
import 'product_rail_section.dart';
import '../utils/size_match.dart';

/// "In your size" strip on the customer home — only the products that stock
/// the customer's saved size right now, as a horizontally-scrolling rail.
///
/// This is the first surface that makes the foot profile do something while
/// shopping: the app has measured the customer's feet since the AR scanner
/// shipped, and until now nothing on the browse side read the result. The rail
/// answers the question the catalog could not — *which of these pairs actually
/// come in my size?*
///
/// Where "my size" comes from: [shoppingEuSizeFrom] — the profile snapshot
/// first (written by both the scan and the manual picker), then a scan already
/// in memory as the fallback. No fetch: a browse surface must never wait on a
/// network call, and the snapshot is already loaded for a signed-in customer.
///
/// **Absent-safe by design.** It renders nothing when the kill switch is off,
/// when the customer has no size on file, or when nothing in the catalog
/// stocks it — never a guessed size, never a stale stamp (plan §8 R6). It also
/// carries its own bottom spacing (via [ProductRailSection]), so a hidden rail
/// leaves no gap behind.
///
/// The match rule is not local: it is [stocksMySize] via
/// [ProductProvider.productsInSize], so this rail and any later size surface
/// agree by construction. Availability follows the same authoritative
/// `inventory` source as the buy button, so a card here can never turn out to
/// be unbuyable (plan §8 R4).
///
/// The rendering is [ProductRailSection], shared with the audience rails — this
/// widget decides only whether there is anything to show, and what size to
/// name.
class InYourSizeSection extends StatelessWidget {
  const InYourSizeSection({super.key});

  /// Strip height — the same 130x180 [HorizontalProductCard] rail the Best
  /// Sellers / Buy Again / Recently Viewed sections use.
  static const double railHeight = BestSellersSection.railHeight;

  @override
  Widget build(BuildContext context) {
    if (!AppConstants.sizeAwareShoppingEnabled) return const SizedBox.shrink();

    final profile = context.watch<AuthProvider>().profile;
    // Read-only on purpose: this widget never triggers a measurement load.
    final measurement =
        context.select<FootMeasurementProvider, FootMeasurement?>(
      (p) => p.latestMeasurement,
    );
    final euSize = shoppingEuSizeFrom(profile, measurement: measurement);
    if (euSize == null) return const SizedBox.shrink();

    final products =
        context.select<ProductProvider, List<Map<String, dynamic>>>(
      (p) => p.productsInSize(euSize),
    );
    if (products.isEmpty) return const SizedBox.shrink();

    // The size names what drove the rail (so a wrong one is visible and
    // correctable in Settings → Size Your Foot) without competing with the
    // section title for attention.
    return ProductRailSection(
      title: 'In your size',
      meta: euSizeLabel(euSize),
      products: products,
    );
  }
}
