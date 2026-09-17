import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Maps a variant colour NAME (free text written by sellers — "Dark Brown",
/// "Off-white suede", "Carob"…) to a swatch colour for the dot that stands in
/// for it.
///
/// Lives here rather than on the product detail screen because the reservation
/// sheets show the same swatches as the detail page's colour picker: one
/// mapping means the dot beside "Brown" is the same colour in both places.
///
/// Unknown names fall back to a deterministic warm tone keyed off the name, so
/// the same colour never changes between rebuilds and two different colours
/// rarely collide.
Color variantSwatchColor(String name) {
  final n = name.toLowerCase();
  if (n.contains('brown') ||
      n.contains('tan') ||
      n.contains('camel') ||
      n.contains('cognac') ||
      n.contains('clay') ||
      n.contains('leather')) {
    if (n.contains('dark')) return const Color(0xFF4E342E);
    if (n.contains('light')) return const Color(0xFFA1887F);
    return AppConstants.primary;
  }
  if (n.contains('black') || n.contains('charcoal')) {
    return const Color(0xFF26221E);
  }
  if (n.contains('carob')) return const Color(0xFF3E2723);
  if (n.contains('white') ||
      n.contains('cream') ||
      n.contains('beige') ||
      n.contains('off-white') ||
      n.contains('suede')) {
    return const Color(0xFFF1E8DC);
  }
  if (n.contains('gold') || n.contains('mustard') || n.contains('yellow')) {
    return const Color(0xFFB8860B);
  }
  if (n.contains('red') || n.contains('burgundy') || n.contains('maroon')) {
    return const Color(0xFF9B3B2E);
  }
  if (n.contains('green') || n.contains('olive')) {
    return const Color(0xFF5D6B45);
  }
  if (n.contains('blue') || n.contains('navy')) return const Color(0xFF3F4A63);
  if (n.contains('grey') || n.contains('gray')) return const Color(0xFF9E948A);

  // Deterministic warm fallback keyed off the name.
  const palette = [
    Color(0xFF8B5A2B),
    Color(0xFF6B4A2F),
    Color(0xFFA9703C),
    Color(0xFF4E342E),
    Color(0xFF7C5A38),
    Color(0xFFB8860B),
  ];
  return palette[name.hashCode.abs() % palette.length];
}
