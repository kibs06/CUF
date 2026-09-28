/// Thrown when a downloaded shoe model does not hash to the `sha256` its
/// `product_models` row declares.
///
/// This is deliberately fatal to that one attempt and silent to the
/// customer-facing flow: the caller keeps the simulated try-on screen (the
/// D8 degradation rule), and nothing is written to the cache — a partial or
/// swapped asset must never become a cache hit later.
///
/// The causes worth distinguishing when reading logs: a truncated download,
/// an asset replaced in the bucket without the row being re-pointed, or a
/// row whose digest was pasted wrong during upload. All three are upload/
/// pipeline problems, never renderer problems.
class ShoeModelIntegrityException implements Exception {
  /// Object path inside the bucket, e.g. `<store>/<product>/<sha>.glb`.
  final String storagePath;

  /// The digest the database row promised.
  final String expectedSha256;

  /// The digest the received bytes actually produce.
  final String actualSha256;

  ShoeModelIntegrityException({
    required this.storagePath,
    required this.expectedSha256,
    required this.actualSha256,
  });

  /// Short, log-safe description. Not shown to customers.
  String get message =>
      'Shoe model integrity check failed for "$storagePath": expected '
      '$expectedSha256, got $actualSha256.';

  @override
  String toString() => 'ShoeModelIntegrityException: $message';
}
