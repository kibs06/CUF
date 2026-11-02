/// **DeepAR shoe try-on spike — config only, no native SDK yet.**
///
/// Why this file exists: the custom ARCore + Filament tracker never worked on
/// device, so we are spiking DeepAR instead (Lens Studio replacement). The
/// native DeepAR SDK (`deepar.aar` + `deepar_flutter_plus`) is NOT in the
/// build yet — it needs a license key from developer.deepar.ai and the .aar
/// in `android/app/libs/`, which this repo deliberately does not commit.
///
/// This file is the Dart half of that spike:
///   * reads the license keys from `--dart-define` (never committed),
///   * answers "can we launch DeepAR yet?" without touching native code,
///   * resolves which `.deepar` effect file to load for a product.
///
/// Once the Studio effect is exported (`assets/effects/<product>.deepar` or
/// a hosted URL), the native plugin takes these values and calls
/// `switchEffect`. Until then every caller falls back to the existing 3D
/// viewer / Snap lens — a missing key is a sentence, never a crash.
library;

/// Android license key from https://developer.deepar.ai
/// (`Project` → `Android` key). Empty means "not configured".
const String kDeepArAndroidKey = String.fromEnvironment(
  'DEEPAR_ANDROID_KEY',
  defaultValue: '',
);

/// iOS license key (same project, `iOS` key). Empty means "not configured".
const String kDeepArIosKey = String.fromEnvironment(
  'DEEPAR_IOS_KEY',
  defaultValue: '',
);

/// Whether the native DeepAR SDK can be initialized on this build.
///
/// Both keys travel via `--dart-define` so the repo never pins the real
/// values. A build with no keys behaves exactly like a build without the
/// plugin: the DeepAR entry stays hidden and the existing viewer remains.
bool get deepArConfigured =>
    kDeepArAndroidKey.isNotEmpty || kDeepArIosKey.isNotEmpty;

/// Bundled spike effects: productId (or slug) → asset path.
///
/// Step 1 shipped one effect: Luna Loafers
/// (`0aebaa64-4d9e-44f8-8876-6b3ee9855fae`, also matched by slug
/// `luna-loafers` for the portal). Luxe Cross-Strap Sandals follows the same
/// shape. Add more rows as Studio exports land.
const Map<String, String> kDeepArBundledEffects = {
  '0aebaa64-4d9e-44f8-8876-6b3ee9855fae':
      'assets/effects/luna_loafers.deepar',
  'luna-loafers': 'assets/effects/luna_loafers.deepar',
  'luxe-cross-strap-sandals':
      'assets/effects/luxe_cross_strap_sandals.deepar',
};

/// Normalizes a product name to its effect slug: lowercase, non-alphanumerics
/// to single dashes (`Luxe Cross-Strap Sandals` → `luxe-cross-strap-sandals`).
String deepArSlugForName(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// Whether a product name is the Luxe Cross-Strap Sandals pair. Name-based
/// rather than id-based on purpose: the effect was handed over as a file for
/// a named product, and its row id was never recorded — matching the id would
/// mean a lookup round trip for a string the caller already holds.
bool _isLuxeName(String name) {
  final slug = deepArSlugForName(name);
  return slug.contains('luxe') &&
      slug.contains('cross') &&
      slug.contains('strap');
}

/// Resolves the `.deepar` effect path for a product.
///
/// `productName` is the escape hatch for effects filed by product name rather
/// than row id (Luxe): when the id has no row, the name is slug-matched.
/// Returns null when there is no effect yet — the caller keeps the 3D box.
String? deepArEffectForProduct(
  String productId, {
  Set<String>? published,
  String? productName,
}) {
  final id = productId.trim();
  if (id.isEmpty && (productName ?? '').trim().isEmpty) return null;
  if (id.isNotEmpty) {
    if (published != null && !published.contains(id)) return null;
    final direct = kDeepArBundledEffects[id];
    if (direct != null) return direct;
  }
  final name = (productName ?? '').trim();
  if (name.isEmpty) return null;
  if (_isLuxeName(name)) {
    return kDeepArBundledEffects['luxe-cross-strap-sandals'];
  }
  final slugHit = kDeepArBundledEffects[deepArSlugForName(name)];
  return slugHit;
}

/// Human sentence for the unconfigured / no-effect states.
///
/// The screen owns the English (same rule as the AR fallback); this keeps
/// the wording in one place so the spike and the docs cannot drift.
String deepArUnavailableMessage({required bool configured}) {
  if (!configured) {
    return 'DeepAR try-on is not set up in this build yet.';
  }
  return 'No DeepAR shoe effect is published for this product yet.';
}
