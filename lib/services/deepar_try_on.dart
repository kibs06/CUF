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
  // Luxe Cross-Strap Sandals, same as Luna: row id first (Caramel colourway),
  // slug for shared links. The product-name fallback below stays as cover for
  // sibling colourways whose row ids were never recorded.
  '77b8c0a3-0f09-41a6-aa70-fc1db04e4cc1':
      'assets/effects/luxe_cross_strap_sandals.deepar',
  'luxe-cross-strap-sandals':
      'assets/effects/luxe_cross_strap_sandals.deepar',
  // JBC Crown Leather Sandals, same shape: slug for shared links plus the
  // product-name fallback below for rows whose ids were never recorded.
  'jbc-crown-leather-sandals':
      'assets/effects/jbc_crown_leather_sandals.deepar',
  // Espadrille Slip-On Shoes, same shape: slug for shared links plus the
  // product-name fallback below for rows whose ids were never recorded.
  'espadrille-slip-on-shoes':
      'assets/effects/espadrille_slip_on_shoes.deepar',
  // PrimeStep Trail Stitch Sandals, same shape: slug for shared links plus
  // the product-name fallback below for rows whose ids were never recorded.
  'primestep-trail-stitch-sandals':
      'assets/effects/primestep_trail_stitch_sandals.deepar',
  // Velux Classic Leather Sandals, same shape: slug for shared links plus
  // the product-name fallback below for rows whose ids were never recorded.
  'velux-classic-leather-sandals':
      'assets/effects/velux_classic_leather_sandals.deepar',
  // Elara, same shape: slug for shared links plus the product-name
  // fallback below for rows whose ids were never recorded.
  'elara': 'assets/effects/elara.deepar',
  // Tassel Loafer, same shape: slug for shared links plus the
  // product-name fallback below for rows whose ids were never recorded.
  'tassel-loafer': 'assets/effects/tassel_loafer.deepar',
  // Lavender Luxe Double-Strap Sandals, same shape: slug for shared links
  // plus the product-name fallback below for rows whose ids were never
  // recorded. Effect file keeps its Studio export name (`lavander.deepar`);
  // both Lavender/Lavander spellings resolve to it.
  'lavender-luxe-double-strap-sandals': 'assets/effects/lavander.deepar',
  'lavander': 'assets/effects/lavander.deepar',
  // CARCARO Leather Slides, same shape: slug for shared links plus the
  // product-name fallback below for rows whose ids were never recorded.
  'carcaro-leather-slides': 'assets/effects/carcaro_leather_slides.deepar',
  // Crocotex Men's Comfort Slides, same shape: slug for shared links
  // plus the product-name fallback below for rows whose ids were never
  // recorded.
  'crocotex-men-s-comfort-slides':
      'assets/effects/crocotex_men_s_comfort_slides.deepar',
  // EcoStride Double Strap Sandals, same shape: slug for shared links
  // plus the product-name fallback below for rows whose ids were never
  // recorded.
  'ecostride-double-strap-sandals':
      'assets/effects/ecostride_double_strap_sandals.deepar',
  // Classic Red Double-Buckle Comfort Sandals, same shape: slug for
  // shared links plus the product-name fallback below for rows whose
  // ids were never recorded.
  'classic-red-double-buckle-comfort-sandals':
      'assets/effects/classic_red_double_buckle_comfort_sandals.deepar',
};

/// Normalizes a product name to its effect slug: lowercase, non-alphanumerics
/// to single dashes (`Luxe Cross-Strap Sandals` → `luxe-cross-strap-sandals`).
String deepArSlugForName(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// Convention asset path without touching the hardcoded map: drops a Studio
/// export at `assets/effects/<snake>.deepar` (declared in `pubspec.yaml`) and
/// ships the app — the pill appears with no Dart edit. (`JBC Crown Leather
/// Sandals` → `assets/effects/jbc_crown_leather_sandals.deepar`.)
String? deepArConventionAssetForName(String name) {
  final snake = deepArSlugForName(name).replaceAll('-', '_');
  if (snake.isEmpty) return null;
  return 'assets/effects/$snake.deepar';
}

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

/// Whether a product name is the JBC Crown Leather Sandals pair. Same reason
/// as Luxe: the effect was handed over as a file for a named product, so the
/// name is the stable key until a row id is recorded.
bool _isJbcName(String name) {
  final slug = deepArSlugForName(name);
  return slug.contains('jbc') &&
      slug.contains('crown') &&
      slug.contains('leather');
}

/// Whether a product name is the Espadrille Slip-On Shoes pair. Same reason
/// as Luxe/JBC: the effect was handed over as a file for a named product.
bool _isEspadrilleName(String name) {
  final slug = deepArSlugForName(name);
  return slug.contains('espadrille') && slug.contains('slip');
}

/// Whether a product name is the PrimeStep Trail Stitch Sandals pair. Same
/// reason as Luxe/JBC/Espadrille: the effect was handed over as a file for
/// a named product, so the name is the stable key until a row id is recorded.
bool _isPrimeStepName(String name) {
  final slug = deepArSlugForName(name);
  return slug.contains('primestep') && slug.contains('trail');
}

/// Whether a product name is the Velux Classic Leather Sandals pair. Same
/// reason as PrimeStep: the effect was handed over as a file for a named
/// product, so the name is the stable key until a row id is recorded.
bool _isVeluxName(String name) {
  final slug = deepArSlugForName(name);
  return slug.contains('velux') && slug.contains('classic');
}

/// Whether a product name is the Elara pair. Same reason as Velux: the
/// effect was handed over as a file for a named product, so the name is
/// the stable key until a row id is recorded.
bool _isElaraName(String name) {
  final slug = deepArSlugForName(name);
  return slug.contains('elara');
}

/// Whether a product name is the Tassel Loafer pair. Same reason as
/// Elara: the effect was handed over as a file for a named product, so
/// the name is the stable key until a row id is recorded.
bool _isTasselLoaferName(String name) {
  final slug = deepArSlugForName(name);
  return slug.contains('tassel') && slug.contains('loafer');
}

/// Whether a product name is the Lavender Luxe Double-Strap Sandals pair.
/// Same reason as Tassel Loafer: the effect was handed over as a file for
/// a named product. Matches both `lavender` (product name) and `lavander`
/// (Studio export filename) spellings.
bool _isLavenderLuxeName(String name) {
  final slug = deepArSlugForName(name);
  return slug.contains('lavander') ||
      (slug.contains('lavender') && slug.contains('luxe'));
}

/// Whether a product name is the CARCARO Leather Slides pair. Same reason
/// as Lavender Luxe: the effect was handed over as a file for a named
/// product, so the name is the stable key until a row id is recorded.
bool _isCarcaroName(String name) {
  final slug = deepArSlugForName(name);
  return slug.contains('carcaro');
}

/// Whether a product name is the Crocotex Men's Comfort Slides pair. Same
/// reason as CARCARO: the effect was handed over as a file for a named
/// product, so the name is the stable key until a row id is recorded.
bool _isCrocotexName(String name) {
  final slug = deepArSlugForName(name);
  return slug.contains('crocotex') && slug.contains('comfort');
}

/// Whether a product name is the EcoStride Double Strap Sandals pair. Same
/// reason as Crocotex: the effect was handed over as a file for a named
/// product, so the name is the stable key until a row id is recorded.
bool _isEcoStrideName(String name) {
  final slug = deepArSlugForName(name);
  return slug.contains('ecostride') && slug.contains('strap');
}

/// Whether a product name is the Classic Red Double-Buckle Comfort Sandals
/// pair. Same reason as EcoStride: the effect was handed over as a file
/// for a named product, so the name is the stable key until a row id is
/// recorded.
bool _isClassicRedName(String name) {
  final slug = deepArSlugForName(name);
  return slug.contains('classic') &&
      slug.contains('red') &&
      slug.contains('buckle');
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
  if (_isJbcName(name)) {
    return kDeepArBundledEffects['jbc-crown-leather-sandals'];
  }
  if (_isEspadrilleName(name)) {
    return kDeepArBundledEffects['espadrille-slip-on-shoes'];
  }
  if (_isPrimeStepName(name)) {
    return kDeepArBundledEffects['primestep-trail-stitch-sandals'];
  }
  if (_isVeluxName(name)) {
    return kDeepArBundledEffects['velux-classic-leather-sandals'];
  }
  if (_isElaraName(name)) {
    return kDeepArBundledEffects['elara'];
  }
  if (_isTasselLoaferName(name)) {
    return kDeepArBundledEffects['tassel-loafer'];
  }
  if (_isLavenderLuxeName(name)) {
    return kDeepArBundledEffects['lavender-luxe-double-strap-sandals'];
  }
  if (_isCarcaroName(name)) {
    return kDeepArBundledEffects['carcaro-leather-slides'];
  }
  if (_isCrocotexName(name)) {
    return kDeepArBundledEffects['crocotex-men-s-comfort-slides'];
  }
  if (_isEcoStrideName(name)) {
    return kDeepArBundledEffects['ecostride-double-strap-sandals'];
  }
  if (_isClassicRedName(name)) {
    return kDeepArBundledEffects['classic-red-double-buckle-comfort-sandals'];
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
