import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../constants/app_constants.dart';
import '../../../utils/sale_price.dart';
import '../../../utils/variant_swatch_color.dart';

/// Shared pieces of the two reservation sheets.
///
/// `pickup_reservation_sheet.dart` (small, free, 24-hour holds) and
/// `bulk_reservation_sheet.dart` (deposit-gated reseller holds) open from the
/// same product page and must read as one family. The drag handle, the "what
/// am I reserving" summary, the colour chips and the ± steppers therefore live
/// here once, instead of drifting apart in two private copies.
///
/// WHAT THE CUSTOMER IS RESERVING — the two facts a hold used to leave
/// implicit — is the whole point of [ReservationProductRow] (the product) and
/// [ReservationColorChips]/[ReservationSizeChip] (the variant): both requests
/// are keyed on `product_id` alone, so without this the seller had to infer
/// the rest from a free-text note.

/// The little drag handle at the top of both sheets.
class ReservationSheetHandle extends StatelessWidget {
  const ReservationSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppConstants.secondary.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// The colours a product actually offers, in first-seen order.
///
/// [stockByColor] is keyed by colour name, with the empty string standing in
/// for "this product has no colour variants" — so an empty result means the
/// colour picker stays hidden.
List<String> reservationColors(Map<String, Map<String, int>> stockByColor) =>
    stockByColor.keys.where((c) => c.isNotEmpty).toList();

/// The single image that represents what is being reserved: the selected
/// colour's photo when the seller uploaded one, else the product's first.
String? reservationImageUrl(Map<String, dynamic> product, String? color) {
  if (color != null && color.isNotEmpty) {
    final colorImages = product['product_color_images'] as List? ?? [];
    for (final img in colorImages) {
      if (img is Map && img['color_name']?.toString() == color) {
        final url = img['url']?.toString();
        if (url != null && url.isNotEmpty) return url;
      }
    }
  }
  final images = product['product_images'] as List? ?? [];
  String? best;
  var bestOrder = 1 << 30;
  for (final img in images) {
    if (img is! Map) continue;
    final url = img['image_url']?.toString();
    if (url == null || url.isEmpty) continue;
    final order = img['display_order'] as int? ?? 0;
    if (order < bestOrder) {
      bestOrder = order;
      best = url;
    }
  }
  return best;
}

/// Thumbnail + name + "Colour · ₱price each" — the answer to "what am I
/// asking the store to hold?".
class ReservationProductRow extends StatelessWidget {
  final Map<String, dynamic> product;

  /// The colour currently selected in the sheet (null on colourless products).
  final String? color;

  const ReservationProductRow({
    super.key,
    required this.product,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = reservationImageUrl(product, color);
    final price = effectivePrice(product);
    final subtitle = [
      if (color != null && color!.isNotEmpty) color!,
      '₱${price.toStringAsFixed(0)} each',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppConstants.surfaceSubtle,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 48,
              height: 48,
              child: imageUrl == null
                  ? ColoredBox(
                      color: AppConstants.secondary.withValues(alpha: 0.06),
                      child: Icon(
                        Icons.image_outlined,
                        size: 20,
                        color: AppConstants.secondary.withValues(alpha: 0.35),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => ColoredBox(
                        color: AppConstants.secondary.withValues(alpha: 0.06),
                      ),
                      errorWidget: (_, _, _) => ColoredBox(
                        color: AppConstants.secondary.withValues(alpha: 0.06),
                        child: Icon(
                          Icons.image_outlined,
                          size: 20,
                          color: AppConstants.secondary.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product['name']?.toString() ?? 'This product',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: AppConstants.secondary.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Single-select colour chips (a dot + the seller's colour name).
///
/// Hidden by the caller when the product has one colour or none.
class ReservationColorChips extends StatelessWidget {
  final List<String> colors;
  final String selected;
  final ValueChanged<String> onSelect;

  const ReservationColorChips({
    super.key,
    required this.colors,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final color in colors)
          InkWell(
            onTap: () => onSelect(color),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color == selected
                    ? AppConstants.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: color == selected
                      ? AppConstants.primary
                      : AppConstants.borderGray.withValues(alpha: 0.7),
                  width: color == selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: variantSwatchColor(color),
                      shape: BoxShape.circle,
                      // Light swatches (white/cream) need the hairline ring to
                      // stay visible on the cream sheet.
                      border: Border.all(
                        color: AppConstants.borderGray.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    color,
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      fontWeight:
                          color == selected ? FontWeight.bold : FontWeight.w500,
                      color: color == selected
                          ? AppConstants.primary
                          : AppConstants.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A size pill with its live stock ("EU 39  (97)"), single-select.
class ReservationSizeChip extends StatelessWidget {
  final String label;
  final int stock;
  final bool selected;
  final VoidCallback onTap;

  const ReservationSizeChip({
    super.key,
    required this.label,
    required this.stock,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppConstants.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppConstants.primary
                : AppConstants.borderGray.withValues(alpha: 0.7),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          '$label  ($stock)',
          style: AppConstants.bodyStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? AppConstants.primary : AppConstants.secondary,
          ),
        ),
      ),
    );
  }
}

/// The ± button: filled when it can act, muted when it cannot.
class ReservationStepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const ReservationStepButton({super.key, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: onTap != null
              ? AppConstants.primary.withValues(alpha: 0.08)
              : AppConstants.secondary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap != null
              ? AppConstants.primary
              : AppConstants.secondary.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
