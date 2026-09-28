/// Offline GLB validator for the shoe-model pipeline
/// (`docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` V2.7).
///
/// This is the executable form of the authoring contract
/// (`SHOE_MODEL_AUTHORING_GUIDE.md` and `VIRTUAL_FITTING_ARCHITECTURE.md`
/// §2.5.1): a partner runs it on the exported `.glb` and attaches the output
/// to the handover, and the same checks are what the seller upload (V2.3)
/// and the server-side validator (V2.4) repeat — so a file that fails here
/// would be rejected there too.
///
/// It is pure Dart with no `dart:io`: bytes in, a report out, which is what
/// makes the checks themselves unit-testable (the `fit_engine.dart`
/// precedent). `tool/validate_glb.dart` is the thin CLI around it.
///
/// **What it can decide:** GLB structure and single-file embedding, file
/// size, triangle count, material part names, texture dimensions, the
/// compression gate, units, up-axis sanity (the long axis must be +Z),
/// origin/grounding, and the mesh's external length against the declared
/// one ±5 mm.
///
/// **What it cannot decide, and why the guide still has reviewer rows:**
/// whether the toe points at +Z rather than the heel (a bbox is symmetric
/// about that question), whether the albedo was de-lit, whether it *looks*
/// like the shoe, and what frame rate it holds on device. The report says so
/// in its footer rather than implying a green run means acceptance.
library;

import 'dart:convert';
import 'dart:typed_data';

// ─── Contract constants (each cites its source) ────────────────────────────

/// GLB magic `glTF` as a little-endian uint32.
const int kGlbMagic = 0x46546C67;

/// GLB chunk type `JSON`.
const int kJsonChunkType = 0x4E4F534A;

/// GLB chunk type `BIN\0`.
const int kBinChunkType = 0x004E4942;

/// Triangle budget — guide §C4/§C7 / architecture §2.5.1.
const int kMaxTriangles = 60000;

/// The guide's file budget ("≤ 5 MB"). The bucket's hard cap is 8 MiB
/// (`product_models` migration / architecture §2.7.1); the contract is the
/// smaller number, so a file between the two is a contract failure that
/// would still upload.
const int kFileSizeBudgetBytes = 5 * 1024 * 1024;

/// The `shoe-models` bucket's `file_size_limit`.
const int kFileSizeHardCapBytes = 8 * 1024 * 1024;

/// Declared external length tolerance — guide §C2 and acceptance checklist 3
/// ("mesh external length = calipers ±5 mm").
const double kLengthToleranceMm = 5.0;

/// Tolerance for the origin/grounding checks. The contract says "at the
/// origin, resting on the ground plane" without a number; this reuses the
/// same ±5 mm the length check uses, and it is printed in the report so a
/// reviewer can disagree with it explicitly.
const double kOriginToleranceMm = 5.0;

/// Plausible external length band, mirroring the database's
/// `products`-adjacent CHECK on `product_models.authored_length_mm`
/// (100–400 mm). Outside it, the units are wrong — the usual cause is a
/// file authored in millimetres instead of metres.
const double kPlausibleLengthMinMm = 100;
const double kPlausibleLengthMaxMm = 400;

/// Guide §C5/§C7: textures at ≤ 1024².
const int kMaxTextureDimension = 1024;

/// Architecture §2.5.1: "≤ 2 texture sets at ≤ 1024²". A *set* is not
/// derivable from image count alone (a PBR set is 3–4 maps), so this
/// threshold only raises a warning: past it the reviewer is asked to confirm
/// the sets, rather than the validator guessing.
const int kTextureSetWarningImageCount = 8;

/// Guide §C6 — the exact material names a colour swap can target. `midsole`
/// is named in the sole row of that table.
const List<String> kApprovedPartNames = [
  'upper',
  'sole',
  'midsole',
  'laces',
  'lining',
  'heel',
];

/// The two parts every shoe has; a model missing either cannot be
/// colour-swapped properly.
const List<String> kRequiredPartNames = ['upper', 'sole'];

/// Rejected until roadmap V0.7 proves the shipped renderer decodes them
/// (architecture §2.5.1 "Compression" row, decision D6). The spike's
/// `GltfioDecodeTest` is the test that would unblock this list.
const Set<String> kUnapprovedCompressionExtensions = {
  'KHR_draco_mesh_compression',
  'EXT_meshopt_compression',
  'KHR_texture_basisu',
};

// ─── Report types ──────────────────────────────────────────────────────────

enum GlbCheckStatus { pass, fail, warning }

/// One row of the pass/fail table the guide promises at §C9.
class GlbCheck {
  final String name;
  final GlbCheckStatus status;
  final String detail;

  const GlbCheck({required this.name, required this.status, required this.detail});

  Map<String, dynamic> toJson() => {
        'name': name,
        'status': status.name,
        'detail': detail,
      };
}

/// What the caller knows that the file cannot say: the declared external
/// length from the handover's `declaration.txt` (guide §5.1), plus optional
/// identity fields that are echoed into the report.
class GlbValidationOptions {
  final String label;
  final double? externalLengthMm;
  final double? authoredSizeEu;
  final String? shoeSide;

  const GlbValidationOptions({
    this.label = '<memory>',
    this.externalLengthMm,
    this.authoredSizeEu,
    this.shoeSide,
  });
}

class GlbValidationReport {
  final GlbValidationOptions options;
  final int fileSizeBytes;
  final List<GlbCheck> checks = [];
  final List<String> notes = [];

  /// Triangles counted across every triangulated primitive, or null when the
  /// file never got far enough to count them.
  ///
  /// The checks above already state this in prose. It is *also* a field
  /// because `product_models.triangle_count` stores it (roadmap V2.2): the
  /// upload should record the number the validator measured rather than parse
  /// it back out of a sentence, and a server-side validator (V2.4) comparing
  /// its own count against this one is how the two sides stay honest.
  int? triangleCount;

  /// The mesh's heel-to-toe extent along Z in millimetres, or null when no
  /// POSITION accessor carried min/max.
  ///
  /// This is the **external** length of the rendered mesh — the same number
  /// the "scale" check compares against the handover's declared length. It is
  /// NOT `products.last_length_mm`, which is the internal last the fit engine
  /// grades against (architecture §2.7.3). Kept as a field so a caller can
  /// show "declared 275 mm · mesh 271 mm" without reformatting a sentence.
  double? meshExternalLengthMm;

  GlbValidationReport({required this.options, required this.fileSizeBytes});

  bool get passed => !checks.any((c) => c.status == GlbCheckStatus.fail);

  int get failCount =>
      checks.where((c) => c.status == GlbCheckStatus.fail).length;

  int get warningCount =>
      checks.where((c) => c.status == GlbCheckStatus.warning).length;

  void add(String name, GlbCheckStatus status, String detail) =>
      checks.add(GlbCheck(name: name, status: status, detail: detail));

  void note(String message) => notes.add(message);

  /// The wire shape, and it is a wire: `validate-shoe-model` (V2.4) returns
  /// the same keys from its TypeScript mirror, and
  /// `tool/check_glb_validator_parity.mjs` diffs the two, so adding a key on
  /// one side without the other is a failing command rather than a silent
  /// disagreement. `triangleCount` and `meshExternalLengthMm` are the two
  /// fields the server compares against the row (`product_models`), which is
  /// why they are here rather than only in the prose of a check row.
  Map<String, dynamic> toJson() => {
        'label': options.label,
        'fileSizeBytes': fileSizeBytes,
        'passed': passed,
        'triangleCount': triangleCount,
        'meshExternalLengthMm': meshExternalLengthMm,
        'checks': checks.map((c) => c.toJson()).toList(),
        'notes': notes,
      };
}

// ─── Entry point ───────────────────────────────────────────────────────────

/// Validates one `.glb` against the authoring contract.
///
/// Never throws for a malformed file: a file that cannot be parsed produces
/// a report whose `format` row fails, because "explain what is wrong" is the
/// function's whole job.
GlbValidationReport validateGlb(
  Uint8List bytes, {
  GlbValidationOptions options = const GlbValidationOptions(),
}) {
  final report =
      GlbValidationReport(options: options, fileSizeBytes: bytes.length);

  final parsed = _parseGlb(bytes, report);
  if (parsed == null) return report;

  _checkSingleFile(parsed, report);
  _checkFileSize(report);
  _checkTriangles(parsed, report);
  _checkMaterials(parsed, report);
  _checkTextures(parsed, report);
  _checkCompression(parsed, report);

  final bbox = _boundingBox(parsed, report);
  if (bbox == null) {
    report.add(
      'geometry',
      GlbCheckStatus.fail,
      'no POSITION accessor with min/max was found, so scale and origin '
          'cannot be checked — the glTF spec requires min/max on POSITION, '
          'and Blender writes it; a missing value usually means the file was '
          'post-processed by hand',
    );
  } else {
    report.meshExternalLengthMm = bbox.lengthMm;
    _checkUnits(bbox, report);
    _checkOrientation(bbox, report);
    _checkOrigin(bbox, report);
    _checkScale(bbox, report);
  }

  return report;
}

// ─── Parsing ───────────────────────────────────────────────────────────────

class _ParsedGlb {
  final Map<String, dynamic> json;
  final Uint8List? bin;

  const _ParsedGlb({required this.json, required this.bin});

  List<dynamic> get _bufferViews => _asList(json['bufferViews']);

  /// The bytes of one `bufferViews` entry, or null when it is not embedded in
  /// this file's BIN chunk.
  Uint8List? bufferViewBytes(int index) {
    final views = _bufferViews;
    if (index < 0 || index >= views.length) return null;
    final view = views[index];
    if (view is! Map) return null;
    final buffer = view['buffer'];
    // A GLB embeds exactly one buffer (index 0); anything else is external
    // and already failed the single-file check.
    if (buffer is num && buffer.toInt() != 0) return null;
    final offset = _asInt(view['byteOffset']) ?? 0;
    final length = _asInt(view['byteLength']) ?? 0;
    final bin = this.bin;
    if (bin == null || offset < 0 || length <= 0 || offset + length > bin.length) {
      return null;
    }
    return Uint8List.sublistView(bin, offset, offset + length);
  }

  dynamic accessor(int index) {
    final accessors = _asList(json['accessors']);
    if (index < 0 || index >= accessors.length) return null;
    return accessors[index];
  }
}

_ParsedGlb? _parseGlb(Uint8List bytes, GlbValidationReport report) {
  if (bytes.length < 12) {
    report.add('format', GlbCheckStatus.fail,
        'file is ${bytes.length} bytes — too short for the 12-byte GLB header');
    return null;
  }

  final data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != kGlbMagic) {
    report.add(
      'format',
      GlbCheckStatus.fail,
      'not a GLB: the first four bytes are not "glTF" — a .gltf + .bin pair or '
          'a zip of textures is the usual cause (export "glTF Binary (.glb)")',
    );
    return null;
  }

  final version = data.getUint32(4, Endian.little);
  if (version != 2) {
    report.add('format', GlbCheckStatus.fail,
        'glTF version $version — the contract is glTF 2.0');
    return null;
  }

  final declaredLength = data.getUint32(8, Endian.little);
  if (declaredLength != bytes.length) {
    report.add(
      'format',
      GlbCheckStatus.fail,
      'the header declares $declaredLength bytes but the file is '
          '${bytes.length} — a truncated copy, or the file was edited after '
          'export',
    );
    return null;
  }

  Uint8List? jsonBytes;
  Uint8List? bin;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunkLength = data.getUint32(offset, Endian.little);
    final chunkType = data.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    final end = start + chunkLength;
    if (end > bytes.length) {
      report.add('format', GlbCheckStatus.fail,
          'a chunk at byte $offset claims $chunkLength bytes but the file ends first');
      return null;
    }
    if (chunkType == kJsonChunkType) {
      jsonBytes ??= Uint8List.sublistView(bytes, start, end);
    } else if (chunkType == kBinChunkType) {
      bin ??= Uint8List.sublistView(bytes, start, end);
    }
    offset = end;
  }

  if (jsonBytes == null) {
    report.add('format', GlbCheckStatus.fail, 'no JSON chunk found');
    return null;
  }

  final Map<String, dynamic> json;
  try {
    final decoded = jsonDecode(utf8.decode(jsonBytes, allowMalformed: true));
    if (decoded is! Map) {
      report.add('format', GlbCheckStatus.fail,
          'the JSON chunk is not an object');
      return null;
    }
    json = Map<String, dynamic>.from(decoded);
  } catch (e) {
    report.add('format', GlbCheckStatus.fail, 'the JSON chunk does not parse: $e');
    return null;
  }

  final asset = json['asset'];
  final assetVersion = asset is Map ? asset['version']?.toString() : null;
  if (assetVersion != '2.0') {
    report.add('format', GlbCheckStatus.fail,
        'asset.version is ${assetVersion ?? 'missing'} — the contract is "2.0"');
    return null;
  }

  report.add(
    'format',
    GlbCheckStatus.pass,
    'GLB v2 · JSON ${_size(jsonBytes.length)} · '
        'BIN ${bin == null ? 'none' : _size(bin.length)}',
  );
  return _ParsedGlb(json: json, bin: bin);
}

// ─── Checks ────────────────────────────────────────────────────────────────

void _checkSingleFile(_ParsedGlb parsed, GlbValidationReport report) {
  final external = <String>[];

  final buffers = _asList(parsed.json['buffers']);
  for (var i = 0; i < buffers.length; i++) {
    final buffer = buffers[i];
    if (buffer is! Map) continue;
    final uri = buffer['uri']?.toString();
    if (uri != null && uri.trim().isNotEmpty) {
      external.add('buffers[$i].uri = $uri');
    } else if (i > 0) {
      // glTF: only buffer 0 may omit a uri in a GLB (it is the BIN chunk).
      external.add('buffers[$i] has no uri but is not the embedded buffer');
    }
  }

  final images = _asList(parsed.json['images']);
  for (var i = 0; i < images.length; i++) {
    final image = images[i];
    if (image is! Map) continue;
    final uri = image['uri']?.toString();
    if (uri != null && uri.trim().isNotEmpty) {
      external.add('images[$i].uri = $uri');
    }
  }

  if (external.isEmpty) {
    report.add('single file', GlbCheckStatus.pass,
        'everything is inside the .glb — no external .bin or image files');
  } else {
    report.add(
      'single file',
      GlbCheckStatus.fail,
      'external reference(s): ${external.join(', ')} — export as '
          '"glTF Binary (.glb)" with textures embedded (guide §C8)',
    );
  }
}

void _checkFileSize(GlbValidationReport report) {
  final size = report.fileSizeBytes;
  if (size > kFileSizeHardCapBytes) {
    report.add(
      'file size',
      GlbCheckStatus.fail,
      '${_size(size)} exceeds even the bucket hard cap of ${_size(kFileSizeHardCapBytes)} '
          '— the upload would be rejected',
    );
  } else if (size > kFileSizeBudgetBytes) {
    report.add(
      'file size',
      GlbCheckStatus.fail,
      '${_size(size)} is over the ${_size(kFileSizeBudgetBytes)} authoring budget '
          '(the bucket would still accept it — the contract is the smaller number; '
          're-bake textures and retopo, guide §C5/C7)',
    );
  } else {
    report.add('file size', GlbCheckStatus.pass,
        '${_size(size)} (budget ${_size(kFileSizeBudgetBytes)})');
  }
}

void _checkTriangles(_ParsedGlb parsed, GlbValidationReport report) {
  var triangles = 0;
  final notes = <String>[];

  final meshes = _asList(parsed.json['meshes']);
  for (var m = 0; m < meshes.length; m++) {
    final mesh = meshes[m];
    if (mesh is! Map) continue;
    for (final primitive in _asList(mesh['primitives'])) {
      if (primitive is! Map) continue;
      final mode = _asInt(primitive['mode']) ?? 4; // 4 = TRIANGLES
      if (mode != 4) {
        notes.add('a primitive uses mode $mode — only triangles are supported');
        continue;
      }
      final indices = primitive['indices'];
      int? count;
      if (indices is num) {
        final accessor = parsed.accessor(indices.toInt());
        if (accessor is Map) count = _asInt(accessor['count']);
      } else {
        final attributes = primitive['attributes'];
        final position = attributes is Map ? attributes['POSITION'] : null;
        if (position is num) {
          final accessor = parsed.accessor(position.toInt());
          if (accessor is Map) count = _asInt(accessor['count']);
        }
      }
      if (count == null) {
        notes.add('mesh $m has a primitive whose vertex or index count is unreadable');
        continue;
      }
      triangles += count ~/ 3;
    }
  }

  for (final note in notes) {
    report.note(note);
  }

  report.triangleCount = triangles;

  if (triangles > kMaxTriangles) {
    report.add(
      'triangles',
      GlbCheckStatus.fail,
      '${_num(triangles)} triangles exceeds the ${_num(kMaxTriangles)} cap '
          '(target 25,000–45,000 — retopo, guide §C4)',
    );
  } else {
    report.add('triangles', GlbCheckStatus.pass,
        '${_num(triangles)} triangles (cap ${_num(kMaxTriangles)}, target 25,000–45,000)');
  }
}

void _checkMaterials(_ParsedGlb parsed, GlbValidationReport report) {
  final materials = _asList(parsed.json['materials']);
  if (materials.isEmpty) {
    report.add(
      'materials',
      GlbCheckStatus.fail,
      'no materials — the colour swap targets parts by name '
          '(${kApprovedPartNames.join(', ')}); the app cannot repaint a single-material mesh',
    );
    return;
  }

  final names = <String>[];
  for (final material in materials) {
    if (material is! Map) continue;
    names.add(material['name']?.toString().trim() ?? '');
  }

  final problems = <String>[];
  final unnamed = names.where((n) => n.isEmpty).length;
  if (unnamed > 0) {
    problems.add('$unnamed material(s) have no name '
        '("Material.001" in Blender means the rename in §C6 was skipped)');
  }

  final known = names.where((n) => n.isNotEmpty).toList();
  final duplicates = known.toSet().length != known.length;
  if (duplicates) {
    problems.add('duplicate material names (${known.join(', ')}) — each part '
        'must exist exactly once or the colour swap is ambiguous');
  }

  final unapproved = known.where((n) => !kApprovedPartNames.contains(n)).toSet();
  if (unapproved.isNotEmpty) {
    problems.add('names outside the approved set: ${unapproved.join(', ')} '
        '(approved: ${kApprovedPartNames.join(', ')})');
  }

  final missing = kRequiredPartNames.where((n) => !known.contains(n)).toList();
  if (missing.isNotEmpty) {
    problems.add('missing required part(s): ${missing.join(', ')}');
  }

  if (problems.isEmpty) {
    report.add('materials', GlbCheckStatus.pass,
        '${known.join(', ')} — all names approved');
  } else {
    report.add('materials', GlbCheckStatus.fail, problems.join('; '));
  }
}

void _checkTextures(_ParsedGlb parsed, GlbValidationReport report) {
  final images = _asList(parsed.json['images']);
  if (images.isEmpty) {
    report.add('textures', GlbCheckStatus.pass,
        'no image textures (base-colour factors only)');
    return;
  }

  var maxWidth = 0;
  var maxHeight = 0;
  final oversized = <String>[];
  final unreadable = <String>[];

  for (var i = 0; i < images.length; i++) {
    final image = images[i];
    if (image is! Map) continue;
    if (image['uri'] != null) {
      continue; // already failed the single-file check
    }
    final viewIndex = image['bufferView'];
    if (viewIndex is! num) {
      unreadable.add('images[$i] (no bufferView)');
      continue;
    }
    final bytes = parsed.bufferViewBytes(viewIndex.toInt());
    if (bytes == null) {
      unreadable.add('images[$i] (bufferView not embedded)');
      continue;
    }
    final dimensions = _imageDimensions(bytes);
    if (dimensions == null) {
      final mime = image['mimeType']?.toString() ?? 'unknown format';
      unreadable.add('images[$i] ($mime — dimensions unreadable by this validator)');
      continue;
    }
    if (dimensions.width > maxWidth) maxWidth = dimensions.width;
    if (dimensions.height > maxHeight) maxHeight = dimensions.height;
    if (dimensions.width > kMaxTextureDimension ||
        dimensions.height > kMaxTextureDimension) {
      oversized.add(
          'images[$i] ${dimensions.width}×${dimensions.height} (${dimensions.format})');
    }
  }

  for (final item in unreadable) {
    report.note('texture not measurable: $item');
  }

  if (oversized.isNotEmpty) {
    report.add(
      'textures',
      GlbCheckStatus.fail,
      '${oversized.join('; ')} exceeds $kMaxTextureDimension² — re-bake '
          '(guide §C5: base colour, roughness, metallic, normal at 1024² max)',
    );
  } else if (images.length > kTextureSetWarningImageCount) {
    report.add(
      'textures',
      GlbCheckStatus.warning,
      '${images.length} images, largest $maxWidth×$maxHeight — the budget is '
          '≤ 2 texture sets at $kMaxTextureDimension²; image count alone cannot '
          'tell sets from maps, so a reviewer should confirm (guide §C7)',
    );
  } else {
    report.add('textures', GlbCheckStatus.pass,
        '${images.length} image(s), largest $maxWidth×$maxHeight (limit $kMaxTextureDimension²)');
  }
}

void _checkCompression(_ParsedGlb parsed, GlbValidationReport report) {
  final declared = <String>{
    ..._asStringList(parsed.json['extensionsUsed']),
    ..._asStringList(parsed.json['extensionsRequired']),
  };

  final banned =
      declared.where(kUnapprovedCompressionExtensions.contains).toList()..sort();
  final other = declared
      .where((e) => !kUnapprovedCompressionExtensions.contains(e))
      .toList()
    ..sort();

  if (other.isNotEmpty) {
    final required = _asStringList(parsed.json['extensionsRequired']);
    report.note(
      'extension(s) in use: ${other.join(', ')}'
      '${required.any(other.contains) ? ' (required)' : ''} — the renderer must '
      'support these; they are not rejected by the validator',
    );
  }

  if (banned.isNotEmpty) {
    report.add(
      'compression',
      GlbCheckStatus.fail,
      '${banned.join(', ')} is declared, but geometry compression and KTX2 are '
          'not approved until roadmap V0.7 proves the shipped renderer decodes '
          'them (architecture §2.5.1 / decision D6) — export uncompressed',
    );
  } else {
    report.add('compression', GlbCheckStatus.pass,
        'none declared — the asset is uncompressed');
  }
}

class _Bbox {
  final double minX, minY, minZ, maxX, maxY, maxZ;

  const _Bbox({
    required this.minX,
    required this.minY,
    required this.minZ,
    required this.maxX,
    required this.maxY,
    required this.maxZ,
  });

  double get lengthMm => (maxZ - minZ) * 1000;
  double get widthMm => (maxX - minX) * 1000;
  double get heightMm => (maxY - minY) * 1000;
  double get centreXMm => ((minX + maxX) / 2) * 1000;
}

_Bbox? _boundingBox(_ParsedGlb parsed, GlbValidationReport report) {
  // Prefer the meshes the scene actually instantiates; an unreferenced mesh
  // (a leftover copy in the Blender outliner) must not decide the geometry.
  final nodes = _asList(parsed.json['nodes']);
  final referenced = <int>{};
  for (final node in nodes) {
    if (node is! Map) continue;
    final mesh = node['mesh'];
    if (mesh is num) referenced.add(mesh.toInt());
  }

  final meshes = _asList(parsed.json['meshes']);
  final meshIndices = referenced.isEmpty
      ? List<int>.generate(meshes.length, (i) => i)
      : (referenced.toList()..sort());

  if (referenced.isNotEmpty && referenced.length < meshes.length) {
    report.note(
        '${meshes.length - referenced.length} mesh(es) are not referenced by any '
        'node — delete leftovers before export (guide §C3)');
  }

  double? minX, minY, minZ, maxX, maxY, maxZ;
  for (final meshIndex in meshIndices) {
    if (meshIndex < 0 || meshIndex >= meshes.length) continue;
    final mesh = meshes[meshIndex];
    if (mesh is! Map) continue;
    for (final primitive in _asList(mesh['primitives'])) {
      if (primitive is! Map) continue;
      final attributes = primitive['attributes'];
      if (attributes is! Map) continue;
      final position = attributes['POSITION'];
      if (position is! num) continue;
      final accessor = parsed.accessor(position.toInt());
      if (accessor is! Map) continue;
      final min = _asNumList(accessor['min']);
      final max = _asNumList(accessor['max']);
      if (min.length < 3 || max.length < 3) continue;

      minX = minX == null ? min[0] : (min[0] < minX ? min[0] : minX);
      minY = minY == null ? min[1] : (min[1] < minY ? min[1] : minY);
      minZ = minZ == null ? min[2] : (min[2] < minZ ? min[2] : minZ);
      maxX = maxX == null ? max[0] : (max[0] > maxX ? max[0] : maxX);
      maxY = maxY == null ? max[1] : (max[1] > maxY ? max[1] : maxY);
      maxZ = maxZ == null ? max[2] : (max[2] > maxZ ? max[2] : maxZ);
    }
  }

  if (minX == null || minY == null || minZ == null ||
      maxX == null || maxY == null || maxZ == null) {
    return null;
  }
  return _Bbox(
    minX: minX,
    minY: minY,
    minZ: minZ,
    maxX: maxX,
    maxY: maxY,
    maxZ: maxZ,
  );
}

void _checkUnits(_Bbox bbox, GlbValidationReport report) {
  final length = bbox.lengthMm;
  if (length < kPlausibleLengthMinMm || length > kPlausibleLengthMaxMm) {
    report.add(
      'units',
      GlbCheckStatus.fail,
      'the mesh is ${_mm(length)} long along Z — outside the plausible '
          '${_num(kPlausibleLengthMinMm.toInt())}–${_num(kPlausibleLengthMaxMm.toInt())} mm '
          'band. If that is 270-odd thousand, the file is in millimetres: '
          'Scene units must be Metric / Unit Scale 1.0 / Length: Metres before '
          'export (architecture §2.5.5)',
    );
  } else {
    report.add('units', GlbCheckStatus.pass,
        'length ${_mm(length)} — metres, plausible for a shoe');
  }
}

void _checkOrientation(_Bbox bbox, GlbValidationReport report) {
  final length = bbox.lengthMm;
  final width = bbox.widthMm;
  final height = bbox.heightMm;

  // The taller-than-long case is checked first because that is what a Z-up
  // export looks like (the length lands on Y), and naming the actual mistake
  // beats a generic "rotated".
  if (length <= height) {
    report.add(
      'orientation',
      GlbCheckStatus.fail,
      'the mesh is taller (${_mm(height)}) than it is long (${_mm(length)}) — the '
          'long axis is not +Z. That is what a Z-up export looks like; export '
          'with Transform → +Y Up ON (guide §C8)',
    );
  } else if (length <= width) {
    report.add(
      'orientation',
      GlbCheckStatus.fail,
      'the mesh is wider (${_mm(width)}) than it is long (${_mm(length)}) — it is '
          'rotated. The toe must run along +Z: fix the rotation in the Blender '
          'scene, apply transforms, and export with Transform → +Y Up ON '
          '(guide §C8)',
    );
  } else {
    report.add(
      'orientation',
      GlbCheckStatus.pass,
      'the long axis is +Z · L ${_mm(length)} · W ${_mm(width)} · H ${_mm(height)}',
    );
  }
}

void _checkOrigin(_Bbox bbox, GlbValidationReport report) {
  final problems = <String>[];
  final minY = bbox.minY * 1000;
  final minZ = bbox.minZ * 1000;
  final centreX = bbox.centreXMm;

  if (minY.abs() > kOriginToleranceMm) {
    problems.add(
        'the sole is ${_mmSigned(minY)} from the ground plane (y min) — '
        'heel-bottom-centre at the origin, sole resting on it');
  }
  if (minZ.abs() > kOriginToleranceMm) {
    problems.add(
        'the heel sits ${_mmSigned(minZ)} along Z from the origin — the origin '
        'is the heel, not the middle of the shoe');
  }
  if (centreX.abs() > kOriginToleranceMm) {
    problems.add('the mesh is ${_mmSigned(centreX)} off-centre in X');
  }

  if (problems.isEmpty) {
    report.add(
      'origin',
      GlbCheckStatus.pass,
      'grounded (y ${_mm(bbox.minY * 1000)}), heel at ${_mm(bbox.minZ * 1000)} on Z, '
          'centred (x ${_mm(bbox.centreXMm)}) — tolerance ±${_num(kOriginToleranceMm.toInt())} mm',
    );
  } else {
    report.add('origin', GlbCheckStatus.fail, problems.join('; '));
  }
}

void _checkScale(_Bbox bbox, GlbValidationReport report) {
  final declared = report.options.externalLengthMm;
  if (declared == null) {
    report.add(
      'scale',
      GlbCheckStatus.fail,
      'no declared external length. Put external_length_mm in declaration.txt '
          '(guide §5.1) or pass --external-length-mm — the contract is that the '
          'mesh equals the calipers ±${_num(kLengthToleranceMm.toInt())} mm, and '
          'that comparison cannot run without the number',
    );
    return;
  }

  final delta = (bbox.lengthMm - declared).abs();
  if (delta > kLengthToleranceMm) {
    report.add(
      'scale',
      GlbCheckStatus.fail,
      'mesh ${_mm(bbox.lengthMm)} along Z vs declared ${_mm(declared)} — off by '
          '${_mm(delta)} (tolerance ±${_num(kLengthToleranceMm.toInt())} mm). '
          'Re-measure at §C2 and scale numerically before re-export',
    );
  } else {
    report.add(
      'scale',
      GlbCheckStatus.pass,
      'mesh ${_mm(bbox.lengthMm)} vs declared ${_mm(declared)} '
          '(Δ ${_mm(delta)}, tolerance ±${_num(kLengthToleranceMm.toInt())} mm)',
    );
  }
}

// ─── Handover declaration (guide §5.1) ─────────────────────────────────────

/// Parses a handover `declaration.txt` into a lowercase-key map.
///
/// Tolerant on purpose: the template ships with placeholders
/// (`external_length_mm: <mesh Y size, measured>`), a maker may write
/// `285 mm` or `UNKNOWN`, and the validator's job is to say what is missing
/// rather than fail to read the file. Blank lines and `#` comments are
/// skipped.
Map<String, String> parseGlbDeclaration(String text) {
  final values = <String, String>{};
  for (final rawLine in const LineSplitter().convert(text)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    values[line.substring(0, colon).trim().toLowerCase()] =
        line.substring(colon + 1).trim();
  }
  return values;
}

/// The first number in a declaration value, or null when there is none
/// (`UNKNOWN`, an unfilled `<placeholder>`, an empty field).
///
/// Deliberately unit-blind: `285`, `285 mm` and `285mm` all mean the
/// millimetre field they appear in, and `UNKNOWN` must mean "absent" rather
/// than 0.
double? declarationNumber(String? value) {
  if (value == null) return null;
  final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value);
  if (match == null) return null;
  return double.tryParse(match.group(0)!);
}

// ─── Small helpers ─────────────────────────────────────────────────────────

({int width, int height, String format})? _imageDimensions(Uint8List bytes) {
  // PNG: 8-byte signature, then IHDR (width/height as big-endian uint32 at
  // 16 and 20).
  if (bytes.length >= 24 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    final data = ByteData.sublistView(bytes);
    return (
      width: data.getUint32(16, Endian.big),
      height: data.getUint32(20, Endian.big),
      format: 'png',
    );
  }

  // JPEG: walk the markers until a Start-Of-Frame carries the dimensions.
  if (bytes.length > 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    var i = 2;
    while (i + 9 <= bytes.length) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = bytes[i + 1];
      if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      final segmentLength = (bytes[i + 2] << 8) | bytes[i + 3];
      final isStartOfFrame = marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isStartOfFrame) {
        return (
          width: (bytes[i + 7] << 8) | bytes[i + 8],
          height: (bytes[i + 5] << 8) | bytes[i + 6],
          format: 'jpeg',
        );
      }
      if (segmentLength <= 0) break;
      i += 2 + segmentLength;
    }
  }

  return null;
}

List<dynamic> _asList(Object? value) => value is List ? value : const [];

List<double> _asNumList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<num>()
      .map((n) => n.toDouble())
      .toList(growable: false);
}

List<String> _asStringList(Object? value) {
  if (value is! List) return const [];
  return value.map((v) => v.toString()).toList(growable: false);
}

int? _asInt(Object? value) => value is num ? value.toInt() : null;

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';
}

String _num(int value) => value.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );

String _mm(double value) => '${value.toStringAsFixed(1)} mm';

String _mmSigned(double value) =>
    '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)} mm';
