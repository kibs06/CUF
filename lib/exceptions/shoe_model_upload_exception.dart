/// Thrown when the seller's model upload cannot proceed.
///
/// Carries a **seller-facing** sentence, because every failure in this path
/// ends in a snackbar the artisan reads: a bad link, a link that is not a
/// `.glb`, a file the bucket will refuse, a product that is not saved yet. The
/// messages therefore say what to do next rather than which line threw — the
/// house rule from `fit_spec_form.dart`, applied to a network boundary.
///
/// It is deliberately not fatal to the *product* save: a model that fails to
/// attach leaves the product saved and usable, exactly like a fit verdict with
/// no specs simply does not appear (the D8 degradation rule).
class ShoeModelUploadException implements Exception {
  /// What the seller should read.
  final String message;

  /// Log-safe detail — status codes, the URL, the storage path. Never shown.
  final String? detail;

  ShoeModelUploadException(this.message, {this.detail});

  @override
  String toString() =>
      'ShoeModelUploadException: $message${detail == null ? '' : ' ($detail)'}';
}
