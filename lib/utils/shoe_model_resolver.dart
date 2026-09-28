/// Pure resolution rules for the V2 shoe-model pipeline
/// (`docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` V2.5).
///
/// A product can carry several `product_models` rows: a **product-level
/// default** (`variant_id IS NULL`) and one **per-colour override** per
/// variant. The renderer needs exactly one of them — which one is a
/// decision, and decisions that decide what a customer sees belong in a
/// pure function with table-driven tests, not inside a widget or a
/// network call.
///
/// This file has no Flutter and no Supabase import on purpose, the
/// `fit_engine.dart` / `size_key.dart` precedent: the rules can be read
/// and tested without a harness.
///
/// **The rules, in order (architecture §2.7.2):**
///   1. a row matching the selected variant wins;
///   2. otherwise the product-level default (`variant_id == null`);
///   3. otherwise there is no model — never a different colour's asset.
///
/// Within the winning group the newest `version` wins, ties broken by
/// the higher `id`. That makes the choice deterministic: two rows with
/// the same version can never make the renderer pick at random.
library;

/// Every field the app needs from one `product_models` row.
///
/// Parsed once, at the boundary, by [ShoeModelSpec.fromRow]: callers that
/// hold a spec hold a row whose identity fields are already valid, so a
/// malformed row can never travel deeper as a half-object.
class ShoeModelSpec {
  /// `product_models.id` — part of the device cache key.
  final int id;

  /// `variant_id`; null means the product-level default model.
  ///
  /// **Text, not a number.** The hosted project stores variant ids as UUIDs
  /// and this repo's migration lineage stores them as BIGINTs — a drift the
  /// schema records rather than hides — and the app's own variant selection
  /// (`resolveVariant`) is a `String?` either way. Everything is normalized
  /// through `toString()`, so a row from either side matches the same
  /// selected id.
  final String? variantId;

  /// Object path inside the public `shoe-models` bucket.
  final String storagePath;

  /// Lowercase SHA-256 hex digest of the shipped `.glb` — the cache key's
  /// integrity half. The service refuses bytes that hash differently.
  final String sha256;

  /// Authoring revision. Two versions of the same mesh coexist on device
  /// because the cache filename carries this.
  final int version;

  /// The EU size the mesh was authored at (scale math input, §2.5.2).
  final double? authoredSizeEu;

  /// **External** heel-to-toe length of the physical sample in mm. Drives
  /// render scale; NOT the fit verdict (`products.last_length_mm` is the
  /// internal last).
  final double? authoredLengthMm;

  /// `'left'` or `'right'`; the renderer mirrors it for the other foot.
  final String shoeSide;

  /// Colour name → per-part material overrides, or null when absent.
  final Map<String, dynamic>? materialMap;

  /// Optional `{heelOffsetMm, yawOffsetDeg}`, or null when absent.
  final Map<String, dynamic>? alignmentJson;

  /// `product_models.triangle_count`, when the upload recorded it.
  final int? triangleCount;

  /// `product_models.file_size_bytes`, when the upload recorded it.
  final int? fileSizeBytes;

  const ShoeModelSpec({
    required this.id,
    this.variantId,
    required this.storagePath,
    required this.sha256,
    this.version = 1,
    this.authoredSizeEu,
    this.authoredLengthMm,
    this.shoeSide = 'right',
    this.materialMap,
    this.alignmentJson,
    this.triangleCount,
    this.fileSizeBytes,
  });

  /// Parses one row, or returns null when the row cannot be rendered.
  ///
  /// Three fields are **identity**, and a row missing or malforming any of
  /// them is unusable rather than repairable:
  ///
  ///   * `id` — without it there is no cache key;
  ///   * `storage_path` — without it there is nothing to download;
  ///   * `sha256` — without it a download cannot be verified, and an
  ///     unverifiable model is worse than no model (it would be rendered
  ///     from whatever the network returned).
  ///
  /// `shoe_side` is a correctness field: a present-but-unknown value is
  /// refused rather than defaulted, because mirroring the wrong foot is a
  /// wrong shoe on screen. Everything else degrades — an unreadable
  /// optional number becomes null and the mesh still renders.
  static ShoeModelSpec? fromRow(Map<String, dynamic> row) {
    final id = _asInt(row['id']);
    if (id == null) return null;

    final storagePath = row['storage_path']?.toString().trim() ?? '';
    if (storagePath.isEmpty) return null;

    // Case-insensitive on input, lowercase on the way in: the database
    // CHECK stores lowercase, and normalizing here means a hand-written
    // row in a test or a fixture behaves like the real thing.
    final sha256 = (row['sha256']?.toString() ?? '').trim().toLowerCase();
    if (!_sha256Pattern.hasMatch(sha256)) return null;

    final side = row['shoe_side']?.toString().trim() ?? 'right';
    if (side != 'left' && side != 'right') return null;

    final version = _asInt(row['version']) ?? 1;

    return ShoeModelSpec(
      id: id,
      variantId: _asString(row['variant_id']),
      storagePath: storagePath,
      sha256: sha256,
      version: version < 1 ? 1 : version,
      authoredSizeEu: _asDouble(row['authored_size_eu']),
      authoredLengthMm: _asDouble(row['authored_length_mm']),
      shoeSide: side,
      materialMap: _asMap(row['material_map']),
      alignmentJson: _asMap(row['alignment_json']),
      triangleCount: _asInt(row['triangle_count']),
      fileSizeBytes: _asInt(row['file_size_bytes']),
    );
  }

  @override
  String toString() => 'ShoeModelSpec(id: $id, variant: $variantId, '
      'version: $version, sha: ${sha256.substring(0, 8)}…)';
}

/// Parses a list of rows, dropping the unusable ones.
///
/// Dropping rather than throwing is deliberate: one malformed row for a
/// product must not take out the other colours' assets, and the caller
/// can compare `parsed.length` with the raw length if it wants to report
/// the loss.
List<ShoeModelSpec> parseShoeModelRows(List<Map<String, dynamic>> rows) {
  final specs = <ShoeModelSpec>[];
  for (final row in rows) {
    final spec = ShoeModelSpec.fromRow(row);
    if (spec != null) specs.add(spec);
  }
  return specs;
}

/// Picks the one model to render for [variantId], or null when the product
/// has no usable model (see the file header for the rules).
ShoeModelSpec? resolveShoeModel({
  required List<ShoeModelSpec> models,
  String? variantId,
}) {
  if (models.isEmpty) return null;

  final List<ShoeModelSpec> pool;
  if (variantId != null) {
    final overrides =
        models.where((m) => m.variantId == variantId).toList(growable: false);
    // No override for this colour ⇒ fall back to the default model, never
    // to another colour's asset.
    pool = overrides.isNotEmpty
        ? overrides
        : models.where((m) => m.variantId == null).toList(growable: false);
  } else {
    pool = models.where((m) => m.variantId == null).toList(growable: false);
  }

  if (pool.isEmpty) return null;

  final sorted = [...pool]..sort((a, b) {
      final byVersion = b.version.compareTo(a.version);
      return byVersion != 0 ? byVersion : b.id.compareTo(a.id);
    });
  return sorted.first;
}

/// Lowercase SHA-256 hex digest, exactly as `product_models.sha256`'s
/// CHECK constraint requires.
final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

/// Variant ids arrive as a UUID string on the hosted project and as a number
/// on a database built from the BIGINT lineage; both normalize to the same
/// trimmed text, and an empty string is treated as absent.
String? _asString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return null;
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}
