/// Every photo a product carries, in the order the seller arranged it.
///
/// The product map reaches the UI in two shapes and the card has to read both:
///
///   • a raw Supabase row keeps `product_images` — maps of
///     `{image_url, display_order}`, in no particular order, and
///   • the mapped model (`SupabaseService._mapProduct`) also carries the same
///     photos flattened into `images` — plain URL strings, already sorted.
///
/// Both are read here, in one place, so every surface that shows a product's
/// photos (the card's pager, and anything else that grows one) agrees on the
/// order the seller chose rather than each re-deriving it.
///
/// Never null, never contains a blank URL, and never repeats one — a product
/// with no photo at all comes back empty, which is the caller's cue to fall back
/// to its own placeholder image.
List<String> productImageUrls(dynamic product) {
  if (product == null) return const <String>[];

  final List<String> urls = [];

  void add(Object? value) {
    final url = value?.toString().trim() ?? '';
    if (url.isEmpty || urls.contains(url)) return;
    urls.add(url);
  }

  // The authoritative list: the row's own photos, ordered by the seller.
  final raw = product['product_images'];
  if (raw is List && raw.isNotEmpty) {
    final images = raw.whereType<Map>().toList()
      ..sort(
        (a, b) => ((a['display_order'] as num?) ?? 0).compareTo(
          (b['display_order'] as num?) ?? 0,
        ),
      );
    for (final image in images) {
      add(image['image_url']);
    }
  }

  // The mapped model's flat list. Its entries are URL strings; a map is still
  // accepted because a few call sites hand the row's shape straight through.
  if (urls.isEmpty) {
    final flat = product['images'];
    if (flat is List) {
      for (final image in flat) {
        add(image is Map ? image['image_url'] : image);
      }
    }
  }

  return List<String>.unmodifiable(urls);
}
