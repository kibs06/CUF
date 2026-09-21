import 'package:flutter/material.dart';

import 'fit_card.dart';

/// The "ON SALE" poster — the On Sale section's name on the front, the best
/// discount in the catalog underneath it, and the section's first grid cell.
///
/// **It is a [FitCard], and nothing else.** The card brings the whole design
/// (the block, the words scaled to the cell's width, the `UP TO` caption, the
/// hero value and its mark, the corner, the fill, the ripple); this widget only
/// answers *what goes in it* — `ON` / `SALE` over `UP TO` and the number. That
/// is the same division as every other poster in the feed, and the reason there
/// is no second card component here.
///
/// **Full bleed, like the size poster.** `padding: 0`, so the words run to the
/// card's own edges and the type is sized against the whole cell rather than
/// against a cell with a 16px frame inside it. That is the "Based on your size"
/// poster's treatment (`in_your_size_section.dart`) and the Workshop poster's,
/// and the two posters in a feed are the same design: with the padding left on,
/// this one's type sat ~21% smaller than the size poster's at the same cell
/// width and its block did not fill the cell.
///
/// **The sign is not part of the number.** `UP TO` is the card's ordinary small
/// caption, the discount is the value and takes the cell's width, and `%` is
/// handed over as [FitCard.heroValueSuffix], which draws it small and raised on
/// the top of the digits: `61%` as one string shares the width three ways, while
/// `61` + a mark gives the number itself the whole line. At the On Sale grid's
/// `childAspectRatio: 0.58` cell (taller than the copy this poster has to fill
/// it with) that larger number is also what closes most of the band `FitCard`
/// otherwise opens between the words and the closer.
///
/// **The number is derived, never written down.** [discountPercent] comes from
/// `maxDiscountPercent(...)` over the products that are on sale *right now*, so
/// it moves with the catalog: a refresh, a seller changing a price or a sale
/// expiring re-renders the card with the new figure. Nothing here caches,
/// formats or rounds — the caller owns the rule, this owns the layout.
///
/// **Absent-safe by construction.** A card cannot be built without a percent,
/// and the caller is the one that decides there is one (null when nothing valid
/// is on sale, or while the catalog is still loading) — so a poster that says
/// "up to 0% off" or shows a stale number from the previous load is not a state
/// this widget can reach.
///
/// The whole card is one tap target, and it is the way to the full sale list
/// (`OnSaleListingScreen`) — the poster opens the shelf it names, exactly like
/// "Based on your size" opens its own.
class OnSaleCard extends StatelessWidget {
  const OnSaleCard({
    super.key,
    required this.discountPercent,
    required this.onTap,
  });

  /// `ON` and `SALE` — two lines, each scaled to the card's full inner width,
  /// so the shorter word is the louder one. Kept as separate strings (rather
  /// than one line) because that is what makes each one carry its own width.
  static const List<String> lines = ['ON', 'SALE'];

  /// The caption above the number — the card's ordinary caption, not a sized-up
  /// one: the big thing on this poster is the number, and the `UP TO` above it
  /// only says how to read it.
  static const String label = 'UP TO';

  /// The sign the card draws small and raised on the top of the digits
  /// ([FitCard.heroValueSuffix]) — `%`, never part of [value].
  static const String valueSuffix = '%';

  /// The best discount on the shelf right now, as a whole percent — the caller
  /// derives it from live product data, never a constant.
  final int discountPercent;

  /// Opens the full sale list. The whole card is the target; the number is not
  /// a separate control.
  final VoidCallback onTap;

  /// The hero value — the digits alone, `30`. The sign travels separately as
  /// [valueSuffix], so the number is scaled to the cell's width on its own: a
  /// three-digit figure (`100`) still scales down like any other value, with no
  /// special case, and the mark costs it only its own fraction of the width.
  String get value => '$discountPercent';

  /// The single label the card announces, derived from the number it shows.
  ///
  /// One node, not fragments: read aloud, the card's copy ("ON SALE UP TO 30%")
  /// arrives as the sentence a customer would say, and it also says what the
  /// tap does — the percentage is the point, so a screen reader must get the
  /// real figure rather than a decoration of it.
  static String semanticsLabelFor(int discountPercent) =>
      'On sale, up to $discountPercent percent off. '
      'Double tap to see all sale items.';

  @override
  Widget build(BuildContext context) {
    return FitCard(
      // Full bleed, like the size poster and the Workshop poster: the type is
      // measured against the cell itself, not a cell with a frame inside it.
      padding: 0,
      lines: lines,
      heroLabel: label,
      heroValue: value,
      heroValueSuffix: valueSuffix,
      semanticsLabel: semanticsLabelFor(discountPercent),
      onTap: onTap,
    );
  }
}
