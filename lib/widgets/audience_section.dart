import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../providers/product_provider.dart';
import '../utils/product_audience.dart';
import 'best_sellers_section.dart';
import 'product_rail_section.dart';

/// One audience rail on the customer home — Men's, Women's or Kids', showing
/// only the products a seller stated are for that audience.
///
/// **This is the first customer-facing pixel of the product-audience feature**,
/// and it is gated behind [AppConstants.productAudienceEnabled] (still `false`
/// through P2 — landing the code and showing it are separate events; the switch
/// is flipped in P5 after QA).
///
/// **Stated, never inferred.** A product with `audience = null` belongs in the
/// catalog grid, in search and in every category; it is only absent from these
/// three rails. That is the whole point of the column existing separately from
/// the size band — EU sizing is unisex, so Men's and Women's share one band and
/// a size could never decide this. [ProductProvider.productsForAudience] owns
/// the rule, including the hard exclusion of `unisex` (a unisex product in all
/// three rails would put one card three times down the feed, plan §4 R4).
///
/// **Absent-safe, exactly like [InYourSizeSection]:** kill switch off, an
/// audience that is not rail-eligible, or nothing in the catalog carrying it →
/// renders nothing at all, with no header and no residual gap. With most of the
/// live catalog still unset (P4 backfill is the phase that changes that), an
/// empty rail is the *normal* case, so "invisible" has to be the default
/// rather than something the home screen has to arrange.
///
/// The title comes from [productAudienceLabel] rather than a string passed in,
/// so `"Men's"` / `"Women's"` / `"Kids'"` are spelled in exactly one file, and
/// a rail can never be labelled with an audience it does not query.
class AudienceSection extends StatelessWidget {
  const AudienceSection({
    super.key,
    required this.audience,
    this.enabled = AppConstants.productAudienceEnabled,
  });

  /// One of [productRailAudiences]. Anything else (including `'unisex'`, which
  /// is a valid audience but never a rail) renders nothing.
  final String audience;

  /// The kill switch, resolved once per build.
  ///
  /// Defaults to [AppConstants.productAudienceEnabled] — no production call
  /// site passes this. It exists because that constant is `false` for all of
  /// P2 (landing the code and showing it are separate events), which would
  /// otherwise make the rail's own behaviour impossible to test while the
  /// feature ships dark.
  final bool enabled;

  /// Strip height — the same 130x180 card rail every other home section uses.
  static const double railHeight = BestSellersSection.railHeight;

  @override
  Widget build(BuildContext context) {
    // Switch first: with the feature off this widget must behave as though it
    // does not exist, so it never even asks the provider for a list.
    if (!enabled) return const SizedBox.shrink();

    final canonical = productAudienceFrom(audience);
    if (canonical == null || canonical == kUnisexAudience) {
      return const SizedBox.shrink();
    }
    final label = productAudienceLabel(canonical);
    if (label == null) return const SizedBox.shrink();

    final products =
        context.select<ProductProvider, List<Map<String, dynamic>>>(
      (p) => p.productsForAudience(canonical),
    );
    if (products.isEmpty) return const SizedBox.shrink();

    return ProductRailSection(title: label, products: products);
  }
}
