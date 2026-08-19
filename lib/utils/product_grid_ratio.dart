/// Deterministic image aspect ratio per product card, keyed off the product
/// id, so a card's height stays stable across filtering, re-sorting, and
/// reloads.
///
/// Shared by the Artisan Catalog grid (home), the Recently Viewed grid
/// (profile + full-screen), and any other 2-column product grid.
double productGridRatio(dynamic product) {
  const ratios = [1.0, 0.78, 1.22, 0.95];
  final id = product['id']?.toString() ?? '';
  final key = id.isEmpty ? 0 : id.hashCode;
  return ratios[key.abs() % ratios.length];
}