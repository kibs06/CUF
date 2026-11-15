/// Per-colour 3D paint (the swipe-the-colour mission).
///
/// One model per product, painted by the app: each product colour carries one
/// real paint value (`product_color_paint.paint_hex`), and the viewers tint
/// the shared mesh with it live. A colour with no paint renders the model
/// as-authored — an untinted shoe is honest, a guessed tint is a colour that
/// exists nowhere in reality.
///
/// This file is pure (no Flutter, no Supabase): the hex the database CHECK
/// already enforces (`^#[0-9A-Fa-f]{6}$`) becomes the 0..1 factors both
/// engines take, and the active colour becomes its paint or null. Tested
/// without a harness in `test/utils/shoe_paint_test.dart`.
library;

/// Parses a `#RRGGBB` paint hex into `[r, g, b]` 0..1 factors, or null when
/// the value is not a paint (null, misformatted, wrong length).
///
/// Strict on purpose: the only producer is the `product_color_paint` CHECK,
/// so anything else here is a caller bug, and a caller bug must render
/// as-authored rather than as a half-parsed colour.
List<double>? parsePaintHex(String? hex) {
  if (hex == null) return null;
  final match = RegExp(r'^#([0-9A-Fa-f]{6})$').firstMatch(hex.trim());
  if (match == null) return null;
  final digits = match.group(1)!;
  return [
    int.parse(digits.substring(0, 2), radix: 16) / 255.0,
    int.parse(digits.substring(2, 4), radix: 16) / 255.0,
    int.parse(digits.substring(4, 6), radix: 16) / 255.0,
  ];
}

/// The paint for [colorName] out of `product_color_paint` rows
/// (`{color_name, paint_hex}` maps), or null when the colour has none.
///
/// Matching is trimmed-exact on the stored spelling: paint rows are written
/// from the product's own colour list, so a case-insensitive rescue would
/// only ever reunite spellings no writer produces — while risking uniting
/// two colours a seller meant as distinct ("Brown" vs "brown" from two
/// imports). Null in, null out: no colour, no paint.
String? paintHexForColor(List<Map<String, dynamic>> paintRows, String? colorName) {
  final want = colorName?.trim();
  if (want == null || want.isEmpty) return null;
  for (final row in paintRows) {
    final name = row['color_name']?.toString().trim();
    if (name == want) {
      final hex = row['paint_hex']?.toString().trim();
      return (hex == null || hex.isEmpty) ? null : hex;
    }
  }
  return null;
}
