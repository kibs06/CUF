import 'package:flutter/material.dart';

import '../constants/app_brightness.dart';
import '../constants/app_constants.dart';
import '../constants/app_palette.dart';
import '../providers/product_provider.dart';
import 'product_sort_sheet.dart';

/// The sort control a listing page puts beside its filters: the mode currently
/// in force, in a chip that opens [showProductSortSheet].
///
/// **One widget, because "sort" has to mean one thing.** The search results
/// page, an audience shelf, the size shelf and the sale shelf all order their
/// own list, and they all offer the same orders under the same names — the chip
/// is the entry point to the one sheet, and a second implementation of it is
/// how one page ends up offering a different set (or the same order under a
/// different name).
///
/// **Not a `Chip` and not a fill.** The label sits on a faint clay wash with a
/// hairline, at the sort icon's side, because it is a control rather than a
/// statement; the *list* below it is what is being described. The mode's own
/// words come from [sortModeLabel] — the same words the sheet's options use, so
/// the control and the choice it opens cannot disagree.
///
/// The label is `Flexible` with two lines before it ellipsises: a mode name is a
/// *word* ("Price: Low to High"), and shrinking it means either lying about it
/// ("Price: Lo…") or hiding it — so it wraps first and truncates last, which
/// only ever matters at a large OS text scale on a narrow phone.
class ProductSortChip extends StatelessWidget {
  const ProductSortChip({
    super.key,
    required this.sort,
    required this.onSelected,
  });

  /// The order the page is currently using.
  final SortMode sort;

  /// Called with the chosen order — the page holds it, not the chip (and not
  /// [ProductProvider], which sorts the Home feed).
  final ValueChanged<SortMode> onSelected;

  @override
  Widget build(BuildContext context) {
    // Clay as INK, not as a fill: `AppConstants.primary` is pinned at #8B5A2B
    // and only ~3.3:1 on the dark page — under AA for this 11px label.
    // `AppPalette.primaryInk` is the role token for it; the wash and hairline
    // around it are decoration and keep the brand clay.
    final accentInk = AppPalette.of(AppBrightness.current).primaryInk;

    return GestureDetector(
      onTap: () =>
          showProductSortSheet(context, current: sort, onSelected: onSelected),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppConstants.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppConstants.primary.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort_outlined, size: 14, color: accentInk),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                sortModeLabel(sort),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: accentInk,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
