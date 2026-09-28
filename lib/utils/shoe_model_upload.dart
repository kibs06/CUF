/// The seller's model upload, as rules instead of screen code (roadmap V2.2 /
/// V2.3).
///
/// Pure Dart — no Flutter, no Supabase, no `dart:io` (`crypto` is pure) — so
/// every rule below is unit-testable, the `fit_spec_form.dart` /
/// `shoe_model_resolver.dart` precedent. What the screen holds, what the
/// service writes and what the database CHECKs live here together, so a file
/// that passes [validateGlb] and then fails on insert is a bug in one of the
/// three, not a judgement call.
///
/// **Where the bytes come from, and why a link.** The app has no file picker:
/// `image_picker` cannot select a `.glb`, and no general file picker is a
/// dependency of this project. A handover file therefore arrives as a link the
/// studio shares (guide §5.1 — Drive, WeTransfer, the partner drive), which is
/// also what a seller on a phone can actually act on. Adding a picker later is
/// a second source feeding the same [ShoeModelAsset]; it changes nothing below.
///
/// **What this file deliberately does not do.** V2.2's row also lists a
/// material-part → colour map. It is not built here, and the reason is a
/// missing input rather than missing time: `product_models.material_map` stores
/// `{part: {baseColorHex, metallic, roughness}}`, the product's colours are
/// free-text **names** with no paint value (`product_color_images` carries only
/// a photo URL), and `variant_swatch_color.dart` — the one name→colour map in
/// the repo — is a UI swatch with a *synthetic* fallback for unknown names. That
/// fallback would paint a shoe a colour nobody chose, which is the same mistake
/// the fit card refuses to make. The column, `ShoeModelSpec.materialMap` and the
/// validator's approved-part check stay ready for a real paint value.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'glb_validator.dart';

/// The public-read bucket `product_models.storage_path` points into.
const String kShoeModelBucket = 'shoe-models';

/// The bucket's own `file_size_limit` (`20260927180000_add_try_on_models.sql`).
///
/// A file over the authoring budget but under this cap *would* upload — the
/// validator fails it on the budget instead (guide §C5) — so this constant
/// exists only to say what the storage layer will refuse outright.
const int kShoeModelBucketCapBytes = kFileSizeHardCapBytes;

/// The MIME type the bucket allowlist permits, and the one the upload must
/// claim. A `.glb` served as `application/octet-stream` is rejected by the
/// bucket, and the error is opaque, so the content type is set explicitly.
const String kShoeModelContentType = 'model/gltf-binary';

/// Which declaration field an error belongs to, so the form can show it inline.
enum ShoeModelField { externalLengthMm, authoredSizeEu }

/// The handover declaration (`declaration.txt`, guide §5.1) as two text fields.
///
/// The external length is the number the validator's scale check compares the
/// mesh against, so a missing one is not a cosmetic gap: without it the check
/// cannot run at all, and the guide's whole point is that the declared length
/// and the mesh agree before anyone ships.
class ShoeModelDeclarationResult {
  /// Declared **external** heel-to-toe length in mm, or null when blank.
  final double? externalLengthMm;

  /// EU size the mesh was authored at, or null when blank. Feeds the renderer's
  /// scale math (§2.5.2) and is optional, exactly like `fit_ref_size_eu`.
  final double? authoredSizeEu;

  /// The sentence to show the seller, or null when there is nothing to fix.
  final String? error;

  /// The field [error] belongs to; null when there is no error.
  final ShoeModelField? errorField;

  const ShoeModelDeclarationResult._({
    this.externalLengthMm,
    this.authoredSizeEu,
    this.error,
    this.errorField,
  });

  /// Both fields blank — the seller has not read the declaration off yet.
  const ShoeModelDeclarationResult.empty()
      : externalLengthMm = null,
        authoredSizeEu = null,
        error = null,
        errorField = null;

  /// Reads the two raw field values.
  factory ShoeModelDeclarationResult.fromFields({
    required String externalLengthMm,
    required String authoredSizeEu,
  }) {
    final lengthText = externalLengthMm.trim();
    final sizeText = authoredSizeEu.trim();

    if (lengthText.isEmpty && sizeText.isEmpty) {
      return const ShoeModelDeclarationResult.empty();
    }

    // Each field is checked for its own problem first, so a mistyped size is
    // never reported as "add the length".
    final size = _parseEuSize(sizeText);
    if (size.error != null) {
      return ShoeModelDeclarationResult._(
        error: size.error,
        errorField: ShoeModelField.authoredSizeEu,
      );
    }

    final length = _parseMm(
      lengthText,
      what: 'the declared external length',
      min: kPlausibleLengthMinMm,
      max: kPlausibleLengthMaxMm,
    );
    if (length.error != null) {
      return ShoeModelDeclarationResult._(
        error: length.error,
        errorField: ShoeModelField.externalLengthMm,
      );
    }

    // A size without a length is a declaration the scale check still cannot
    // run, which is the one shape worth refusing outright.
    if (length.value == null && size.value != null) {
      return const ShoeModelDeclarationResult._(
        error: 'Add the declared external length — it is what the mesh is '
            'measured against, and an authored size on its own cannot check '
            'scale (guide §5.1).',
        errorField: ShoeModelField.externalLengthMm,
      );
    }

    return ShoeModelDeclarationResult._(
      externalLengthMm: length.value,
      authoredSizeEu: size.value,
    );
  }

  /// The sentence for one field, or null when that field is fine — what the
  /// inline validators call.
  String? messageFor(ShoeModelField field) =>
      errorField == field ? error : null;

  /// True when the seller has something to fix.
  bool get isError => error != null;
}

/// One `.glb` the seller has fetched, checked and is holding ready to publish.
///
/// A failed report is representable on purpose: the screen shows the pass/fail
/// table for a file that did not pass, and that file must not be publishable.
/// [isPublishable] is the only thing that says which is which.
class ShoeModelAsset {
  /// The file's bytes, exactly as fetched.
  final Uint8List bytes;

  /// What [validateGlb] said about them.
  final GlbValidationReport report;

  /// The declared external length the report's scale check used, if given.
  final double? declaredExternalLengthMm;

  /// The EU size the mesh was authored at, if given.
  final double? authoredSizeEu;

  /// `'left'` or `'right'` — the renderer mirrors it for the other foot.
  final String shoeSide;

  /// Where the bytes came from, for the log and for a retry.
  final String sourceUrl;

  const ShoeModelAsset({
    required this.bytes,
    required this.report,
    required this.sourceUrl,
    this.declaredExternalLengthMm,
    this.authoredSizeEu,
    this.shoeSide = 'right',
  });

  /// Lowercase SHA-256 hex of [bytes] — the storage filename, the cache key
  /// and the integrity check, all one number (`product_models.sha256`).
  String get sha256 => shoeModelSha256Hex(bytes);

  /// Bytes on disk — `product_models.file_size_bytes`.
  int get fileSizeBytes => bytes.length;

  /// Triangles the validator counted — `product_models.triangle_count`, or
  /// null when the file never got far enough to count them.
  int? get triangleCount => report.triangleCount;

  /// The mesh's own external length — the number the declaration is compared
  /// against. Shown beside the declared value, never instead of it.
  double? get meshExternalLengthMm => report.meshExternalLengthMm;

  /// True when the file passed every check **and** a plausible declaration
  /// exists to have checked it against.
  bool get isPublishable =>
      report.passed &&
      (declaredExternalLengthMm == null ||
          (declaredExternalLengthMm! >= kPlausibleLengthMinMm &&
              declaredExternalLengthMm! <= kPlausibleLengthMaxMm)) &&
      bytes.isNotEmpty &&
      bytes.length <= kShoeModelBucketCapBytes;
}

/// Why an upload cannot go ahead, or [none] when it can.
enum ShoeModelUploadBlocker {
  none,

  /// No product row yet — the model hangs off one (add mode before save).
  noProductId,

  /// Nothing fetched/validated, or the report has failures.
  validationFailed,

  /// The file is over the bucket's hard cap, which storage would refuse.
  overBucketCap,

  /// A declaration field is filled in wrongly.
  declarationInvalid,
}

/// The answer to "may this upload?" with the sentence to show when it may not.
class ShoeModelUploadGate {
  final ShoeModelUploadBlocker blocker;

  /// Seller-facing copy. Empty when ready.
  final String message;

  const ShoeModelUploadGate._(this.blocker, this.message);

  static const ShoeModelUploadGate _ready =
      ShoeModelUploadGate._(ShoeModelUploadBlocker.none, '');

  bool get ready => blocker == ShoeModelUploadBlocker.none;
}

/// Decides whether [asset] may be published, and says why when it may not.
///
/// [declaration] is passed separately rather than folded into the asset because
/// the seller can fix a bad declaration after the fetch: the file is still on
/// screen, and re-downloading 3 MB to accept a corrected number would be silly.
ShoeModelUploadGate shoeModelUploadGate({
  required String? productId,
  required ShoeModelAsset? asset,
  required ShoeModelDeclarationResult declaration,
}) {
  if (declaration.isError) {
    return ShoeModelUploadGate._(
      ShoeModelUploadBlocker.declarationInvalid,
      declaration.error!,
    );
  }

  if (asset == null) {
    return const ShoeModelUploadGate._(
      ShoeModelUploadBlocker.validationFailed,
      'Check a model first — the upload publishes a file that has passed the '
          'authoring contract.',
    );
  }

  if (asset.bytes.isEmpty) {
    return const ShoeModelUploadGate._(
      ShoeModelUploadBlocker.validationFailed,
      'The downloaded file is empty. Re-check the link and try again.',
    );
  }

  if (asset.bytes.length > kShoeModelBucketCapBytes) {
    return const ShoeModelUploadGate._(
      ShoeModelUploadBlocker.overBucketCap,
      'The file is larger than the 8 MB the model bucket accepts. Re-bake the '
          'textures and retopo (guide §C5/C7), then check it again.',
    );
  }

  if (!asset.report.passed) {
    return ShoeModelUploadGate._(
      ShoeModelUploadBlocker.validationFailed,
      '${shoeModelReportHeadline(asset.report)} — fix the failing rows and '
          'check the file again.',
    );
  }

  if (productId == null || productId.isEmpty) {
    return const ShoeModelUploadGate._(
      ShoeModelUploadBlocker.noProductId,
      'Save the product first — a model is attached to a product.',
    );
  }

  return ShoeModelUploadGate._ready;
}

/// One line naming what happened, for the summary above the check table.
String shoeModelReportHeadline(GlbValidationReport report) {
  final failures = report.failCount;
  final warnings = report.warningCount;
  final total = report.checks.length;

  if (failures > 0) {
    return '$failures of $total checks failed';
  }
  if (warnings > 0) {
    return '$total checks passed, $warnings for a human to confirm';
  }
  return 'All $total checks passed';
}

/// The failing rows, one sentence each, in contract order — the list the seller
/// actually acts on. Passing rows are deliberately left to the detail view: a
/// wall of green buries the two lines that matter.
List<String> shoeModelReportFailures(GlbValidationReport report) => report
    .checks
    .where((c) => c.status == GlbCheckStatus.fail)
    .map((c) => '${c.name} — ${c.detail}')
    .toList(growable: false);

/// The rows a human still has to judge, in contract order.
List<String> shoeModelReportWarnings(GlbValidationReport report) => report
    .checks
    .where((c) => c.status == GlbCheckStatus.warning)
    .map((c) => '${c.name} — ${c.detail}')
    .toList(growable: false);

/// What a green run does **not** prove, in one sentence.
///
/// The validator's own footer says it in eight lines because a partner reads
/// that; this is the seller-sized version, and it ships in the UI so a passed
/// check is never read as "this is the shoe".
const String kShoeModelPassedLimitsNote =
    'A green run means the file is buildable, not that it looks right: the toe '
    'direction, the de-lit colour and the likeness still need a human eye '
    '(guide §5.2).';

/// Object path inside the bucket: `<store>/<product>/<sha>.glb`.
///
/// The order is load-bearing, not cosmetic — the bucket's seller-write policy
/// keys on the **first** path segment being a store the caller owns (guide
/// migration §3), so a path built any other way is refused by storage. The
/// filename is the digest, which is what makes an upload idempotent: the same
/// bytes can only ever land at the same path.
String shoeModelStoragePath({
  required String storeId,
  required String productId,
  required String sha256,
}) =>
    '$storeId/$productId/$sha256.glb';

/// `product_models.id` out of a row, or null when the row does not carry one.
///
/// The id is what the server validator is called with (V2.4): publishing is a
/// transition *on a row*, so a write that did not report its id leaves the
/// model unjudged — which is why this returns null rather than a guess, and why
/// its caller treats null as "draft, tell the seller" rather than as an error.
/// Tolerant of the three shapes a PostgREST row can hand back (`int`, `num`,
/// numeric text) because `bigint` arrives as a string over JSON in some clients
/// and as a number in others.
int? shoeModelRowId(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// Lowercase SHA-256 hex digest, exactly as `product_models.sha256`'s CHECK
/// demands (`^[0-9a-f]{64}$`).
String shoeModelSha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

/// The next `version` to write for one target, given the rows already there.
///
/// `version` is an authoring revision, not a retry counter: the partial unique
/// indexes are `(product_id, version) WHERE variant_id IS NULL` and
/// `(product_id, variant_id, version) WHERE variant_id IS NOT NULL`, so the
/// same target can never be written twice at one version. Re-uploading
/// **unchanged** bytes does not need a new version at all — see
/// [shoeModelReuseMatch].
int nextShoeModelVersion({
  required List<Map<String, dynamic>> existingRows,
  String? variantId,
}) {
  final key = shoeModelVariantKey(variantId);
  var highest = 0;
  for (final row in existingRows) {
    if (shoeModelVariantKey(row['variant_id']) != key) continue;
    final version = _asInt(row['version']) ?? 1;
    if (version > highest) highest = version;
  }
  return highest + 1;
}

/// The existing row that already holds these exact bytes for this target, or
/// null when this is a genuinely new file.
///
/// Publishing the same file twice is a no-op rather than a new version: the
/// digest is the filename, so the object is already in the bucket, and adding a
/// second row pointing at the same object would give the resolver two candidates
/// for one asset. Returns the whole row so the caller can report *what* it
/// reused, not just that it did.
Map<String, dynamic>? shoeModelReuseMatch({
  required List<Map<String, dynamic>> existingRows,
  required String sha256,
  String? variantId,
}) {
  final key = shoeModelVariantKey(variantId);
  final digest = sha256.trim().toLowerCase();
  for (final row in existingRows) {
    if (shoeModelVariantKey(row['variant_id']) != key) continue;
    final rowSha = row['sha256']?.toString().trim().toLowerCase();
    if (rowSha == digest) return row;
  }
  return null;
}

/// Variant ids are UUID text on the hosted project and numbers on a database
/// built from this repo's BIGINT lineage; both normalize to the same key, and
/// an empty value means the product-level default — the same normalization
/// `shoe_model_resolver.dart` uses, so "which rows are this target's" cannot
/// mean two things.
String shoeModelVariantKey(Object? variantId) {
  if (variantId == null) return '';
  return variantId.toString().trim();
}

/// The `product_models` insert payload.
///
/// Nulls are sent explicitly (the `_fitSpecColumns` convention in
/// `ProductService`): an absent optional number is a fact about the asset, and
/// a column left out of an insert is indistinguishable from one that was meant
/// to be cleared.
///
/// **`status` is always `draft`, and there is deliberately no way to ask for
/// another value.** The app cannot write `active` (V2.4): the transition is
/// refused by a database trigger to every role but the service role, so a
/// payload that asked for it would fail with `42501` — and before that trigger
/// exists it would be worse, not better, because it would *succeed* and publish
/// a model the server never judged. Publishing is `ShoeModelUploadService`
/// handing this row to `validate-shoe-model`, which writes `active` or
/// `rejected` itself. `rejected` is likewise never written from here: it is a
/// record of a server-side refusal, and a file this path would have rejected
/// never gets as far as an insert.
Map<String, dynamic> shoeModelRow({
  required String productId,
  required String storagePath,
  required String sha256,
  required int version,
  String? variantId,
  double? authoredLengthMm,
  double? authoredSizeEu,
  String shoeSide = 'right',
  int? triangleCount,
  int? fileSizeBytes,
  Map<String, dynamic>? materialMap,
  Map<String, dynamic>? alignmentJson,
}) =>
    {
      'product_id': productId,
      'variant_id': shoeModelVariantKey(variantId).isEmpty
          ? null
          : shoeModelVariantKey(variantId),
      'storage_path': storagePath,
      'sha256': sha256.trim().toLowerCase(),
      'version': version,
      'authored_size_eu': authoredSizeEu,
      'authored_length_mm': authoredLengthMm,
      'shoe_side': shoeSide,
      'material_map': materialMap,
      'alignment_json': alignmentJson,
      'triangle_count': triangleCount,
      'file_size_bytes': fileSizeBytes,
      // The server validator's call, not this one's — see the doc comment.
      'status': 'draft',
    };

/// Whether a link is one this feature will fetch.
///
/// **HTTPS only, except loopback.** A 3D asset fetched over cleartext is a
/// supply-chain hole, not a convenience: the bytes become what customers see on
/// their feet, and an intercepted response would be indistinguishable from a
/// good one. Android's default network security config would block it anyway;
/// this makes the refusal explainable instead of a mystery exception. Loopback
/// stays allowed so a developer can stage a file locally without a certificate.
bool isShoeModelSourceUrlAllowed(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return false;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return false;
  if (uri.scheme == 'https') return true;
  if (uri.scheme != 'http') return false;

  final host = uri.host.toLowerCase();
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}

// ─── Shared parsing (mirrors `fit_spec_form.dart`) ─────────────────────────

/// The EU band the database CHECK and `fit_engine.dart` both use for a
/// *reference* size.
const double kShoeModelAuthoredSizeMinEu = 22;
const double kShoeModelAuthoredSizeMaxEu = 48;

_FieldResult<double> _parseMm(
  String text, {
  required String what,
  required double min,
  required double max,
}) {
  if (text.isEmpty) return const _FieldResult();
  final value = double.tryParse(text);
  if (value == null) {
    return _FieldResult(
      error: 'Write $what as a number in millimetres (e.g. 275).',
    );
  }
  if (value <= 0) {
    return _FieldResult(error: 'Write $what as a positive number of millimetres.');
  }
  // The centimetre guard: a length under 100 that is not absurd as centimetres
  // is the single most likely typo, and it is worth naming (the fit form's
  // 27.5-vs-275 rule, same reasoning).
  if (value < min) {
    if (value * 10 >= min && value * 10 <= max) {
      return _FieldResult(
        error: 'Write $what in millimetres, not centimetres — ${value % 1 == 0 ? value.toInt() : value} '
            'looks like ${(value * 10) % 1 == 0 ? (value * 10).toInt() : value * 10} mm.',
      );
    }
    return _FieldResult(
        error: 'Write $what in millimetres — ${min.toInt()}–${max.toInt()} mm is plausible for a shoe.');
  }
  if (value > max) {
    return _FieldResult(
        error: 'Write $what in millimetres — ${min.toInt()}–${max.toInt()} mm is plausible for a shoe.');
  }
  return _FieldResult(value: value);
}

_FieldResult<double> _parseEuSize(String text) {
  if (text.isEmpty) return const _FieldResult();
  final upper = text.toUpperCase();
  // A US/UK size is the same trap the fit form refuses by name.
  if (upper.contains('US') || upper.contains('UK') || upper.contains('CM')) {
    return const _FieldResult(
      error: 'Use the EU size the mesh was authored at (e.g. 42) — US and UK '
          'numbers are different sizes.',
    );
  }
  final value = double.tryParse(text);
  if (value == null) {
    return const _FieldResult(error: 'Write the authored EU size as a number (e.g. 42).');
  }
  if (value < kShoeModelAuthoredSizeMinEu ||
      value > kShoeModelAuthoredSizeMaxEu) {
    return _FieldResult(
      error: 'Write the authored EU size between '
          '${kShoeModelAuthoredSizeMinEu.toInt()} and '
          '${kShoeModelAuthoredSizeMaxEu.toInt()}.',
    );
  }
  return _FieldResult(value: value);
}

class _FieldResult<T> {
  final T? value;
  final String? error;
  const _FieldResult({this.value, this.error});
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}
