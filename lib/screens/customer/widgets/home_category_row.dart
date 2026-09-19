import 'package:flutter/material.dart';

import '../../../constants/app_constants.dart';
import '../../../utils/product_audience.dart';

/// The Home hero's category row: the catalog's filter chips, plus the audience
/// chips (Men's / Women's / Kids' / Unisex) that open a shelf of their own.
///
/// Styled for the hero's dark, image-backed band — white ink on the banner —
/// which is why it takes plain values rather than reading
/// [ProductProvider] itself: the hero owns the provider reads, this owns the
/// row, and a widget test can drive it without a Supabase client.
///
/// **Row order, and why:** `All` first (the default filter, where customers
/// expect it), then the audience chips, then the product categories and the
/// `On Sale` / `Best Sellers` pseudo-categories. The audiences sit second
/// because they are the only entries that leave this feed for another page —
/// the further right they sit, the more likely a customer never learns they
/// exist.
///
/// The two chip kinds look alike on purpose (a row of two visually distinct
/// control types reads as a toolbar, not a row), and differ in the one way that
/// matters: a category chip becomes the active filter and grows an underline,
/// an audience chip never does — it navigates, and the page it opens names the
/// shelf in its own header.
class HomeCategoryRow extends StatelessWidget {
  const HomeCategoryRow({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onSelect,
    this.audiences = const [],
    this.onAudienceTap,
    this.audienceChipsEnabled = AppConstants.productAudienceEnabled,
  });

  /// The filter chips, `'All'` first (as `ProductProvider.categories` returns
  /// them), followed by the pseudo-categories.
  final List<String> categories;

  /// The active filter, or null/'All' for the whole catalog.
  final String? selectedCategory;

  /// Selects a category — the feed narrows in place.
  final ValueChanged<String> onSelect;

  /// The audiences to offer, in display order — in practice
  /// `ProductProvider.audiencesInCatalog`, which only lists audiences the
  /// catalog actually holds products for.
  final List<String> audiences;

  /// Opens one audience's listing page, with its canonical value.
  final ValueChanged<String>? onAudienceTap;

  /// Whether the audience chips are offered at all — the feature switch
  /// ([AppConstants.productAudienceEnabled]), as a parameter so both of this
  /// row's behaviours can be tested. No production call site passes it: the
  /// default IS the switch, so flipping the constant is the whole rollout (and
  /// the whole rollback).
  final bool audienceChipsEnabled;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      // categories[0] is always 'All' — the provider seeds its set with it.
      if (categories.isNotEmpty)
        _categoryChip(categories.first, selectedCategory, onSelect),
      if (audienceChipsEnabled)
        for (final audience in audiences) _audienceChip(audience),
      for (final cat in categories.skip(1))
        _categoryChip(cat, selectedCategory, onSelect),
    ];

    // A horizontally scrolling Row rather than a fixed-height `ListView`: the
    // chips are TEXT, and the strip used to be a hard 44px, which clipped the
    // label by 4px on a 1.3x text scale. Sizing to its content makes that
    // impossible instead of tuning the constant (there are ~10 chips — nothing
    // here needs a virtualised list).
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            chips[i],
          ],
        ],
      ),
    );
  }

  /// A filter chip: selects a category and shows an underline while it is the
  /// active one.
  Widget _categoryChip(
    String cat,
    String? selectedCategory,
    ValueChanged<String> onSelect,
  ) {
    final isSelected = selectedCategory == cat;
    return GestureDetector(
      onTap: () => onSelect(cat),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              cat,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 4),
            // Underline — grows from center on select.
            //
            // `inkInverse`, not `surfaceLight`: this row sits on the hero's
            // image band, which is dark in BOTH brightnesses, so the indicator
            // must be a pinned light colour. `surfaceLight` is brightness-aware
            // and resolves to the near-black *page* on dark — an active tab
            // whose indicator vanished into the photo behind it.
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              height: 2,
              width: isSelected ? _measureTextWidth(cat) : 0,
              decoration: BoxDecoration(
                color: AppConstants.inkInverse,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A shelf chip: opens that audience's listing page.
  ///
  /// **Never underlined**, because it is never the active filter — tapping it
  /// leaves this feed instead of narrowing it. The 2px spacer keeps its box the
  /// same height as a category chip's underline (4 + 2), so the two kinds sit on
  /// one baseline, and the tap target matches too.
  Widget _audienceChip(String audience) {
    final label = productAudienceLabel(audience);
    // An unrecognised value has no label, and a chip with no label is not a
    // chip — render nothing rather than an empty tap target.
    if (label == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => onAudienceTap?.call(audience),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  /// Measure the rendered width of [text] at the tab style, so the underline
  /// spans exactly the label.
  double _measureTextWidth(String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: AppConstants.bodyStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w;
  }
}
