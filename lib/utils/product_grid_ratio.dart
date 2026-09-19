/// Deterministic image aspect ratio per product card, keyed off the product
/// id, so a card's height stays stable across filtering, re-sorting, and
/// reloads.
///
/// Shared by the Artisan Catalog grid (home), the size shelf, the Recently
/// Viewed grid (profile + full-screen), and any other 2-column product grid.
///
/// Three buckets, chosen to be *visually distinct*: 1.0 (square), 0.78
/// (clearly shorter) and 1.22 (clearly taller). There used to be a fourth at
/// 0.95 — but 5% off square is ~12px on a 2-column card, indistinguishable
/// from 1.0 on screen, and when a section's products all hashed into those
/// two near-twin buckets the whole grid read as uniform rows ("the cards all
/// have the same size"), defeating the stagger the buckets exist for. Two
/// buckets that look the same are not two buckets.
double productGridRatio(dynamic product) {
  const ratios = [1.0, 0.78, 1.22];
  final id = product['id']?.toString() ?? '';
  final key = id.isEmpty ? 0 : id.hashCode;
  return ratios[key.abs() % ratios.length];
}