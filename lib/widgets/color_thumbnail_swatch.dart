import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Circular, thumbnail-based color swatch for a product variant color name.
///
/// Shows the color's first image as a small round thumbnail, falling back to
/// a flat colored dot when no image exists.
///
/// **It always draws a hairline ring** ([AppConstants.borderGray] at 0.5
/// alpha) so light swatches — white / cream / beige / off-white / suede —
/// stay visible on a white card. The selection ring is drawn separately,
/// further out, and only when [selected]. Both rings live OUTSIDE the
/// [ClipOval] so they are never clipped. This mirrors the seller-side
/// swatches (`_SmallColorDot` / `_ColorSwatchChip` in
/// `add_edit_product_screen.dart`).
class ColorThumbnailSwatch extends StatelessWidget {
  final String name;
  final Color fallbackColor;
  final bool selected;
  final String? imageUrl;
  final VoidCallback onTap;

  const ColorThumbnailSwatch({
    super.key,
    required this.name,
    required this.fallbackColor,
    required this.selected,
    this.imageUrl,
    required this.onTap,
  });

  /// The always-on hairline ring. Exposed so widget tests can assert that a
  /// light swatch keeps a visible border (a regression that is easy to
  /// reintroduce).
  static const Key hairlineRingKey = Key('color-swatch-hairline-ring');

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thumbnail with selection ring
            Container(
              width: 48,
              height: 48,
              // Padding 1 (not 2) keeps the swatch content box identical
              // (40x40) now that the always-on hairline ring below insets by
              // its own 1px.
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppConstants.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              // Always-on hairline ring so white/cream/beige swatches stay
              // visible against a white card. It must sit OUTSIDE the
              // ClipOval or it gets clipped.
              child: Container(
                key: hairlineRingKey,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppConstants.borderGray.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: ClipOval(
                  child: imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                            color: fallbackColor,
                          ),
                          errorWidget: (_, _, _) => Container(
                            color: fallbackColor,
                            child: const Icon(Icons.image,
                                size: 16, color: Colors.white),
                          ),
                        )
                      : Container(
                          color: fallbackColor,
                          child: selected
                              ? const Icon(Icons.check,
                                  size: 16, color: Colors.white)
                              : null,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Color name label
            Text(
              name,
              style: AppConstants.bodyStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? AppConstants.primary : AppConstants.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
