import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../models/foot_measurement.dart';
import '../providers/auth_provider.dart';
import '../providers/foot_measurement_provider.dart';
import '../providers/product_provider.dart';
import '../screens/customer/size_listing_screen.dart';
import '../utils/size_key.dart';
import '../utils/size_match.dart';
import 'fit_card.dart';
import 'product_grid_section.dart';
import 'see_more_card.dart';

/// How many products the home preview shows before it hands over to the
/// **See more** card.
///
/// Ten, because the tile that opens the grid is a cell too: 1 + 10 + 1 = 12
/// cells, six full rows on a two-column feed, so the section ends on a clean
/// edge instead of a half row. A preview is a taste, not a second catalog — the
/// rest of the shelf is one tap away, and The Workshop Collection still sits
/// below
/// this section on the same page.
///
/// The card is **not** conditional on the shelf being longer than the preview:
/// it renders whenever this section does. On a small catalog the preview is the
/// whole shelf, and the card is still the door to that shelf — a page that
/// keeps existing while the feed scrolls on, and grows on its own as sellers
/// add stock. Making it a "there is more" promise instead would hide the only
/// way in whenever the shelf happens to be short.
const int kHomePreviewCount = 10;

/// "Based on your size" on the customer home — only the products that stock the
/// customer's saved size right now, laid out **in The Workshop Collection's
/// own
/// 2-column grid** rather than as a horizontal strip.
///
/// This is the first surface that makes the foot profile do something while
/// shopping: the app has measured the customer's feet since the AR scanner
/// shipped, and until now nothing on the browse side read the result. The grid
/// answers the question the catalog could not — *which of these pairs actually
/// come in my size?* — and it answers it in the shape the customer already
/// reads the catalog in, so the section is a shelf of the feed instead of a
/// carousel to swipe through.
///
/// **The heading is a poster, not a line of text.** A [FitCard] the size of a
/// product card takes the grid's first cell (top-left) and says the section's
/// name at poster scale — "Based / on your / size" over the customer's own
/// number on the `EU` label. That is what replaced the old text header: the
/// section's name is now as loud as the products it introduces, and the size it
/// was reporting in muted 12px meta is the card's hero value. The tile has no
/// destination yet, so it does not pretend to be tappable.
///
/// **The poster bleeds to the card's edge** — `padding: 0`, and its height is
/// its own content's, where every other [FitCard] keeps its 16 and takes a
/// caller-imposed box. The poster's whole job is to carry the block, so it gets
/// no band of card around the words and no fixed proportion to fight: each line
/// is measured against the card's full width and the card grows to whatever the
/// copy comes to at that width, which is the only way "Based / on your / size"
/// and the number under it reach **both** edges. Capping it instead (the
/// reference `505/800`) left the copy taller than the box, so `FitCard`'s own
/// `scaleDown` shrank the poster as a block — every line stopping short of the
/// right edge by the same amount, and the number floating off the bottom. The
/// card's radius, fill and hairline are untouched.
///
/// **The grid closes with the shelf's door.** A [SeeMoreCard] — the same poster
/// saying `See` / `more` over a painted arrow — takes the grid's last cell and
/// pushes the full [SizeListingScreen]. It renders whenever this section does:
/// on a shelf longer than the preview it is the way to the rest of it, and on a
/// short one it is still the way to the shelf as a place, so the section never
/// ends on products with no way to say "all of mine live here".
///
/// Where "my size" comes from: [shoppingEuSizeFrom] — the profile snapshot
/// first (written by both the scan and the manual picker), then a scan already
/// in memory as the fallback. No fetch: a browse surface must never wait on a
/// network call, and the snapshot is already loaded for a signed-in customer.
///
/// **Absent-safe by design.** It renders nothing when the kill switch is off,
/// when the customer has no size on file, or when nothing in the catalog
/// stocks it — never a guessed size, never a stale stamp (plan §8 R6). It also
/// carries its own bottom spacing (via [ProductGridSection]), so a hidden
/// section leaves no gap behind.
///
/// The match rule is not local: it is [stocksMySize] via
/// [ProductProvider.productsInSize], so this section and any later size surface
/// agree by construction. Availability follows the same authoritative
/// `inventory` source as the buy button, so a card here can never turn out to
/// be unbuyable (plan §8 R4).
///
/// The rendering is [ProductGridSection] — the same body the catalog's cards
/// are built from. This widget decides whether there is anything to show, what
/// size to name, and how much of the shelf the feed previews before the
/// [SeeMoreCard] hands over to the full [SizeListingScreen]; a personal shelf
/// that grew without limit would be a second catalog above the real one.
class InYourSizeSection extends StatelessWidget {
  const InYourSizeSection({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppConstants.sizeAwareShoppingEnabled) return const SizedBox.shrink();

    final profile = context.watch<AuthProvider>().profile;
    // Read-only on purpose: this widget never triggers a measurement load.
    final measurement = context
        .select<FootMeasurementProvider, FootMeasurement?>(
          (p) => p.latestMeasurement,
        );
    final euSize = shoppingEuSizeFrom(profile, measurement: measurement);
    if (euSize == null) return const SizedBox.shrink();

    // The WHOLE shelf: the preview length is decided below, and the provider
    // no longer pre-truncates — the "See more" card opens the rest of this
    // list, so the order it opens must be this list's order (the shuffled
    // catalog order the provider hands back).
    final products = context
        .select<ProductProvider, List<Map<String, dynamic>>>(
          (p) => p.productsInSize(euSize, limit: 0),
        );
    if (products.isEmpty) return const SizedBox.shrink();

    final preview = products.length > kHomePreviewCount
        ? products.sublist(0, kHomePreviewCount)
        : products;

    // The card names the size the section was built on (so a wrong one is
    // visible and correctable in Settings → Size Your Foot): `euSizeValue`
    // prints the number alone and the label above it carries the unit, rather
    // than the label's usual "EU 42" repeating the system on both lines.
    return ProductGridSection(
      // NO `AspectRatio`, and no inset: the poster is its own box. Capping the
      // tile at [FitCard.aspectRatio] left the copy taller than the box, so the
      // card's outer `FittedBox(scaleDown)` shrank the WHOLE poster to fit —
      // each line short of the right edge by the same band, from the top-left
      // it scales toward. Bleeding needs the height to follow the copy at the
      // cell's width (class doc), which is what makes the words span the cell.
      tile: FitCard(
        padding: 0,
        lines: const ['Based', 'on your', 'size'],
        // The unit read back off the label rather than spelled here, the same
        // way every other size surface avoids its own 'EU' literal.
        heroLabel: sizeSystem(euSizeLabel(euSize)),
        heroValue: euSizeValue(euSize),
      ),
      products: preview,
      // The last cell, always: the shelf's door, not a "there is more" promise.
      // It is a sibling of the size poster, one cell wide and in the right
      // column, so the grid closes the way it opens. No `AspectRatio` here:
      // the grid measures this card against the anchor product's bottom and
      // hands it exactly that box (the poster gives up its reference proportion
      // to close the section on one edge).
      trailing: SeeMoreCard(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SizeListingScreen())),
      ),
    );
  }
}
