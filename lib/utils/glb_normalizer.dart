/// Turns a partner's exported `.glb` into one the contract accepts
/// (`docs/RoadMap/SHOE_MODEL_AUTHORING_GUIDE.md`, roadmap V2.7).
///
/// **Why this exists.** `glb_validator.dart` states the contract; partners
/// still hand over files that miss it for reasons that are *mechanical*: a root
/// node left carrying Blender's Z-up→Y-up conversion instead of the transform
/// being applied, the length running along X instead of Z, the mesh authored at
/// the wrong unit, the origin at the middle of the shoe instead of the heel,
/// textures baked at 4096², the material still called `Material.001`, and a
/// `KHR_materials_specular` block the shipped renderer may not know. None of
/// that is a modelling defect; all of it is a rejection. This function is the
/// fixer, and it reports every change it made so the handover can be reviewed
/// instead of trusted.
///
/// **What it deliberately cannot decide.**
/// * Which end of the long axis is the toe. A bounding box is symmetric about
///   that question, so `--toe` has to say it out loud; a wrong guess is a shoe
///   pointing backwards on the wearer's foot.
/// * The declared external length. Scaling to an invented number would defeat
///   the ±5 mm check that the number exists to enforce, so a file without one
///   is re-axed and re-grounded but left at its authored scale, and the change
///   log says the scale check will still fail.
/// * Whether the albedo was de-lit, whether the mesh *looks* like the product,
///   and what it does to frame rate on device — reviewer rows in the guide,
///   exactly as the validator's footer says.
///
/// Deliberately *not* transparent about two things, because a silent fix would
/// be a lie: geometry compressed with Draco/meshopt cannot be decompressed here
/// (it is refused with the re-export instruction), and a mesh instanced more
/// than once cannot be merged into one baked transform (also refused).
///
/// Pure Dart and no `dart:io` — bytes in, bytes out — so it is unit-testable
/// the way `fit_engine.dart` and `glb_validator.dart` are.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// ─── Constants ─────────────────────────────────────────────────────────────

const int _kGlbMagic = 0x46546C67;
const int _kJsonChunkType = 0x4E4F534A;
const int _kBinChunkType = 0x004E4942;

/// The contract's texture ceiling (`SHOE_MODEL_AUTHORING_GUIDE.md` §C5).
const int kNormalizerTextureSize = 1024;

/// JPEG quality used when textures are re-encoded. High enough that a leather
/// albedo keeps its stitching, low enough that three 1024² maps leave room for
/// the geometry inside the 5 MiB budget.
const int kNormalizerJpegQuality = 88;

/// Material extensions the shipped renderer has no proven support for
/// (architecture §2.5.1). They are removed from the material that declares them
/// *and* from `extensionsUsed`, since a declared extension that nothing uses
/// still costs the renderer a support check.
const Set<String> kNormalizerStrippedExtensions = {
  'KHR_materials_specular',
  'KHR_materials_ior',
  'KHR_materials_sheen',
  'KHR_materials_clearcoat',
  'KHR_materials_transmission',
  'KHR_materials_volume',
  'KHR_materials_iridescence',
  'KHR_materials_anisotropy',
  'KHR_materials_emissive_strength',
};

/// Geometry compression this tool cannot undo. Refused rather than mishandled.
const Set<String> kNormalizerUnsupportedCompression = {
  'KHR_draco_mesh_compression',
  'EXT_meshopt_compression',
  'KHR_texture_basisu',
};

// ─── Options and result ────────────────────────────────────────────────────

/// Which end of the file's long axis the toe sits at.
enum ToeEnd { plusX, minusX, plusZ, minusZ }

/// Everything the file cannot say for itself.
class GlbNormalizerOptions {
  /// The handover's declaration (guide §5.1). Scaling only happens when this is
  /// given: the contract's ±5 mm check compares the mesh against *this* number.
  final double? externalLengthMm;

  /// Assumed toe end. Null means "assume the positive end of the long axis",
  /// which the change log states rather than doing quietly.
  final ToeEnd? toe;

  /// Declared reference size, echoed into the metrics for the handover.
  final double? authoredSizeEu;

  /// Longest side any texture may have after re-baking.
  final int maxTextureSize;

  /// JPEG quality for re-baked textures, or null to keep PNG.
  final int? jpegQuality;

  /// Original material name → approved part name (`upper`, `sole`, …).
  /// Materials absent from the map keep their name.
  final Map<String, String> materialRenames;

  /// When set, triangles whose every vertex sits within this many millimetres
  /// of the ground are given the `sole` material in their own primitive — for
  /// single-material scans, where the contract's two required parts do not
  /// exist as separate materials. The cut line is an approximation and the
  /// change log says so; the reviewer confirms it (checklist §6).
  final double? soleBandMm;

  /// Name for a primitive that arrived with no material at all.
  final String defaultMaterialName;

  const GlbNormalizerOptions({
    this.externalLengthMm,
    this.toe,
    this.authoredSizeEu,
    this.maxTextureSize = kNormalizerTextureSize,
    this.jpegQuality = kNormalizerJpegQuality,
    this.materialRenames = const {},
    this.soleBandMm,
    this.defaultMaterialName = 'upper',
  });
}

/// What changed, in the order it was done, plus the numbers either side.
class GlbNormalizationResult {
  final Uint8List bytes;
  final List<String> changes;
  final Map<String, dynamic> before;
  final Map<String, dynamic> after;

  const GlbNormalizationResult({
    required this.bytes,
    required this.changes,
    required this.before,
    required this.after,
  });
}

/// Thrown when the file cannot be normalised at all. The message is written to
/// be shown to whoever sent the file.
class GlbNormalizationException implements Exception {
  final String message;
  const GlbNormalizationException(this.message);
  @override
  String toString() => message;
}

// ─── Entry point ───────────────────────────────────────────────────────────

/// Normalises one `.glb` towards the authoring contract; returns the new bytes
/// and a log of every change.
GlbNormalizationResult normalizeShoeModel(
  Uint8List input, {
  GlbNormalizerOptions options = const GlbNormalizerOptions(),
}) {
  final changes = <String>[];
  final source = _parse(input);
  _refuseWhatCannotBeFixed(source);

  final geometry = _readGeometry(source, changes);
  final before = _metrics(geometry, source.materialNames(), input.length);

  // 1. Bake the node transform. A root rotation is how Blender's "+Y up"
  //    export leaves a Z-up scene, and `glb_validator.dart` reads accessor
  //    min/max without walking the node tree — so a rotation that is not baked
  //    is invisible to the checks and to the server while still moving the shoe
  //    in the renderer. Baking makes the two agree.
  _bakeNodeTransform(geometry, source, changes);

  // 2. Axis: after baking, up is +Y; the length may still run along X.
  _reorient(geometry, options, changes);

  // 3. Scale to the declared external length...
  _scaleToDeclaredLength(geometry, options, changes);

  // 4. ...then ground and centre, which is what the origin check wants:
  //    heel-bottom-centre at the origin, sole resting on it.
  _placeAtOrigin(geometry, changes);

  final textures = _rebakeTextures(source, options, changes);
  final materials = _rebuildMaterials(source, geometry, options, changes);
  final bytes = _write(geometry, source, textures, materials, changes);

  final written = _parse(bytes);
  final after = _metrics(_readGeometry(written, <String>[]), written.materialNames(),
      bytes.length);
  changes.add('file size ${_size(input.length)} → ${_size(bytes.length)}');

  return GlbNormalizationResult(
    bytes: bytes,
    changes: changes,
    before: before,
    after: after,
  );
}

// ─── Parsing ───────────────────────────────────────────────────────────────

class _Glb {
  final Map<String, dynamic> json;
  final Uint8List bin;
  const _Glb(this.json, this.bin);

  List<dynamic> list(String key) =>
      json[key] is List ? json[key] as List : const [];

  Map<String, dynamic> at(String key, int index) {
    final values = list(key);
    if (index < 0 || index >= values.length || values[index] is! Map) {
      return <String, dynamic>{};
    }
    return Map<String, dynamic>.from(values[index] as Map);
  }
}

_Glb _parse(Uint8List bytes) {
  if (bytes.length < 12) {
    throw const GlbNormalizationException('the file is too short to be a GLB');
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != _kGlbMagic) {
    throw const GlbNormalizationException(
        'not a GLB: the first four bytes are not "glTF" — export "glTF Binary (.glb)"');
  }
  if (data.getUint32(4, Endian.little) != 2) {
    throw const GlbNormalizationException('glTF version is not 2');
  }
  if (data.getUint32(8, Endian.little) != bytes.length) {
    throw const GlbNormalizationException(
        'the GLB header length does not match the file — it was edited after export');
  }

  Uint8List? jsonBytes;
  Uint8List? bin;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final length = data.getUint32(offset, Endian.little);
    final type = data.getUint32(offset + 4, Endian.little);
    if (offset + 8 + length > bytes.length) {
      throw const GlbNormalizationException('a GLB chunk runs past the end of the file');
    }
    final chunk = Uint8List.sublistView(bytes, offset + 8, offset + 8 + length);
    if (type == _kJsonChunkType) jsonBytes ??= chunk;
    if (type == _kBinChunkType) bin ??= chunk;
    offset += 8 + length;
  }
  if (jsonBytes == null) {
    throw const GlbNormalizationException('no JSON chunk in the GLB');
  }
  final decoded = jsonDecode(utf8.decode(jsonBytes, allowMalformed: true));
  if (decoded is! Map) {
    throw const GlbNormalizationException('the JSON chunk is not an object');
  }
  return _Glb(Map<String, dynamic>.from(decoded), bin ?? Uint8List(0));
}

void _refuseWhatCannotBeFixed(_Glb glb) {
  final declared = <String>{
    ...glb.list('extensionsUsed').map((e) => e.toString()),
    ...glb.list('extensionsRequired').map((e) => e.toString()),
  };
  final compression =
      declared.where(kNormalizerUnsupportedCompression.contains).toList();
  if (compression.isNotEmpty) {
    throw GlbNormalizationException(
        '${compression.join(', ')} cannot be undone offline — re-export the model '
        'uncompressed ("Export → Compression: off", guide §C8)');
  }
  for (final raw in glb.list('images')) {
    final mime = (raw as Map)['mimeType']?.toString() ?? '';
    if (mime.contains('ktx') || mime.contains('basis')) {
      throw const GlbNormalizationException(
          'KTX2/Basis textures are not approved and cannot be decoded here — '
          're-export with plain PNG or JPEG textures (guide §C8)');
    }
  }
}

// ─── Geometry ──────────────────────────────────────────────────────────────

class _Geometry {
  final List<double> positions; // xyz per vertex
  final List<double> normals; // xyz per vertex, or empty
  final List<double> uvs; // uv per vertex, or empty
  final List<int> indices;
  final List<int> triangleMaterial; // material index per triangle
  final List<String> materialNames;

  _Geometry({
    required this.positions,
    required this.normals,
    required this.uvs,
    required this.indices,
    required this.triangleMaterial,
    required this.materialNames,
  });

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;

  List<double> bounds() {
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
    for (var i = 0; i < positions.length; i += 3) {
      minX = math.min(minX, positions[i]);
      maxX = math.max(maxX, positions[i]);
      minY = math.min(minY, positions[i + 1]);
      maxY = math.max(maxY, positions[i + 1]);
      minZ = math.min(minZ, positions[i + 2]);
      maxZ = math.max(maxZ, positions[i + 2]);
    }
    return [minX, minY, minZ, maxX, maxY, maxZ];
  }
}

List<double> _readFloats(_Glb glb, int accessorIndex, int components) {
  final accessor = glb.at('accessors', accessorIndex);
  final componentType = (accessor['componentType'] as num?)?.toInt() ?? 5126;
  if (componentType != 5126) {
    throw GlbNormalizationException(
        'an attribute uses componentType $componentType (quantised), which this tool '
        'does not rewrite — export without KHR_mesh_quantization (guide §C8)');
  }
  final count = (accessor['count'] as num?)?.toInt() ?? 0;
  final bufferView = glb.at('bufferViews', (accessor['bufferView'] as num?)?.toInt() ?? -1);
  final stride = (bufferView['byteStride'] as num?)?.toInt();
  final start = ((bufferView['byteOffset'] as num?)?.toInt() ?? 0) +
      ((accessor['byteOffset'] as num?)?.toInt() ?? 0);
  final elementSize = 4 * components;
  final step = stride ?? elementSize;
  final data = ByteData.sublistView(glb.bin);
  final out = List<double>.filled(count * components, 0);
  for (var i = 0; i < count; i++) {
    for (var c = 0; c < components; c++) {
      out[i * components + c] = data.getFloat32(start + i * step + c * 4, Endian.little);
    }
  }
  return out;
}

List<int> _readIndices(_Glb glb, int accessorIndex, int vertexCount) {
  final accessor = glb.at('accessors', accessorIndex);
  final count = (accessor['count'] as num?)?.toInt() ?? 0;
  final componentType = (accessor['componentType'] as num?)?.toInt() ?? 5123;
  final bufferView = glb.at('bufferViews', (accessor['bufferView'] as num?)?.toInt() ?? -1);
  final start = ((bufferView['byteOffset'] as num?)?.toInt() ?? 0) +
      ((accessor['byteOffset'] as num?)?.toInt() ?? 0);
  final data = ByteData.sublistView(glb.bin);
  final out = List<int>.filled(count, 0);
  for (var i = 0; i < count; i++) {
    out[i] = switch (componentType) {
      5121 => data.getUint8(start + i),
      5123 => data.getUint16(start + i * 2, Endian.little),
      5125 => data.getUint32(start + i * 4, Endian.little),
      _ => 0,
    };
  }
  if (vertexCount > 0 && out.any((i) => i >= vertexCount)) {
    throw const GlbNormalizationException(
        'an index points past the end of the vertex list — the file is corrupt');
  }
  // A primitive may be non-indexed (implicit 0,1,2,…); `count` is then the
  // vertex count and the caller has already checked it divides by three.
  return out;
}

_Geometry _readGeometry(_Glb glb, List<String> changes) {
  final materialNames = <String>[];
  for (final raw in glb.list('materials')) {
    materialNames.add(((raw as Map)['name'] ?? '').toString());
  }

  final positions = <double>[];
  final normals = <double>[];
  final uvs = <double>[];
  final indices = <int>[];
  final triangleMaterial = <int>[];
  var hasNormals = true;
  var hasUvs = true;

  for (final rawMesh in glb.list('meshes')) {
    final primitives = (rawMesh as Map)['primitives'];
    for (final rawPrimitive in primitives is List ? primitives : const []) {
      final primitive = rawPrimitive as Map;
      final attributes = (primitive['attributes'] as Map?) ?? const {};
      final positionIndex = (attributes['POSITION'] as num?)?.toInt();
      if (positionIndex == null) {
        throw const GlbNormalizationException(
            'a primitive has no POSITION attribute — there is nothing to normalise');
      }
      final mode = (primitive['mode'] as num?)?.toInt() ?? 4;
      if (mode != 4) {
        throw GlbNormalizationException(
            'a primitive uses draw mode $mode; only triangles can be normalised');
      }

      final base = positions.length ~/ 3;
      final vertexCount =
          (glb.at('accessors', positionIndex)['count'] as num?)?.toInt() ?? 0;
      positions.addAll(_readFloats(glb, positionIndex, 3));

      final normalIndex = (attributes['NORMAL'] as num?)?.toInt();
      if (normalIndex == null) {
        hasNormals = false;
        normals.addAll(List<double>.filled(vertexCount * 3, 0));
      } else {
        normals.addAll(_readFloats(glb, normalIndex, 3));
      }
      final uvIndex = (attributes['TEXCOORD_0'] as num?)?.toInt();
      if (uvIndex == null) {
        hasUvs = false;
        uvs.addAll(List<double>.filled(vertexCount * 2, 0));
      } else {
        uvs.addAll(_readFloats(glb, uvIndex, 2));
      }

      final indexIndex = (primitive['indices'] as num?)?.toInt();
      final local = indexIndex == null
          ? List<int>.generate(vertexCount, (i) => i)
          : _readIndices(glb, indexIndex, vertexCount);
      final material = (primitive['material'] as num?)?.toInt() ?? -1;
      for (var i = 0; i + 2 < local.length; i += 3) {
        indices..add(base + local[i])..add(base + local[i + 1])..add(base + local[i + 2]);
        triangleMaterial.add(material);
      }
    }
  }

  if (indices.isEmpty) {
    throw const GlbNormalizationException('the file contains no triangles');
  }
  if (!hasNormals) {
    changes.add('note: the mesh has no normals; the renderer will light it flat');
  }
  if (!hasUvs) {
    changes.add('note: the mesh has no UVs, so any texture map has nothing to sample');
  }

  final ignored = <String>[];
  for (final key in const [
    'animations',
    'skins',
    'cameras',
    'morphTargets',
  ]) {
    if (glb.list(key).isNotEmpty) ignored.add(key);
  }
  if (ignored.isNotEmpty) {
    changes.add('dropped ${ignored.join(', ')} — a try-on model carries only the shoe');
  }

  return _Geometry(
    positions: positions,
    normals: hasNormals ? normals : <double>[],
    uvs: hasUvs ? uvs : <double>[],
    indices: indices,
    triangleMaterial: triangleMaterial,
    materialNames: materialNames,
  );
}

// ─── Matrices ──────────────────────────────────────────────────────────────

/// A 3×3 rotation/scale with a translation, row-major, 12 numbers:
/// `[m00,m01,m02,m10,m11,m12,m20,m21,m22,tx,ty,tz]`.
typedef _Affine = List<double>;

const _Affine _identityAffine = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0];

_Affine _multiply(_Affine a, _Affine b) {
  final out = List<double>.filled(12, 0);
  for (var r = 0; r < 3; r++) {
    for (var c = 0; c < 3; c++) {
      var sum = 0.0;
      for (var k = 0; k < 3; k++) {
        sum += a[r * 3 + k] * b[k * 3 + c];
      }
      out[r * 3 + c] = sum;
    }
    out[9 + r] = a[r * 3] * b[9] + a[r * 3 + 1] * b[10] + a[r * 3 + 2] * b[11] + a[9 + r];
  }
  return out;
}

List<double> _applyPoint(_Affine m, List<double> p) => [
      m[0] * p[0] + m[1] * p[1] + m[2] * p[2] + m[9],
      m[3] * p[0] + m[4] * p[1] + m[5] * p[2] + m[10],
      m[6] * p[0] + m[7] * p[1] + m[8] * p[2] + m[11],
    ];

List<double> _applyDirection(_Affine m, List<double> p) => [
      m[0] * p[0] + m[1] * p[1] + m[2] * p[2],
      m[3] * p[0] + m[4] * p[1] + m[5] * p[2],
      m[6] * p[0] + m[7] * p[1] + m[8] * p[2],
    ];

/// The node transform, read as TRS or as a column-major `matrix`, converted to
/// the row-major `_Affine` layout above.
_Affine _nodeAffine(Map<String, dynamic> node) {
  final matrix = node['matrix'];
  if (matrix is List && matrix.length == 16) {
    final m = matrix.map((v) => (v as num).toDouble()).toList();
    return [
      m[0], m[4], m[8], //
      m[1], m[5], m[9],
      m[2], m[6], m[10],
      m[12], m[13], m[14],
    ];
  }
  final q = (node['rotation'] as List?)?.map((v) => (v as num).toDouble()).toList() ??
      const [0.0, 0.0, 0.0, 1.0];
  final t = (node['translation'] as List?)?.map((v) => (v as num).toDouble()).toList() ??
      const [0.0, 0.0, 0.0];
  final s = (node['scale'] as List?)?.map((v) => (v as num).toDouble()).toList() ??
      const [1.0, 1.0, 1.0];
  final x = q[0], y = q[1], z = q[2], w = q[3];
  final r = [
    1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
    2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
    2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y),
  ];
  return [
    r[0] * s[0], r[1] * s[1], r[2] * s[2],
    r[3] * s[0], r[4] * s[1], r[5] * s[2],
    r[6] * s[0], r[7] * s[1], r[8] * s[2],
    t[0], t[1], t[2],
  ];
}

/// Composes the transform of the one node chain that instances geometry.
///
/// A shoe model is one mesh under one node chain. More than one instance means
/// the merge this function does would be wrong (two copies at two transforms),
/// so it refuses instead of producing a silently mangled file.
_Affine _sceneAffine(_Glb glb, List<String> changes) {
  final nodes = glb.list('nodes');
  if (nodes.isEmpty) return _identityAffine;
  final scenes = glb.list('scenes');
  final sceneIndex = (glb.json['scene'] as num?)?.toInt() ?? (scenes.isEmpty ? -1 : 0);
  final roots = sceneIndex >= 0 && sceneIndex < scenes.length
      ? (scenes[sceneIndex] as Map)['nodes']
      : null;
  final rootIndices = roots is List
      ? roots.map((v) => (v as num).toInt()).toList()
      : List<int>.generate(nodes.length, (i) => i);

  final instances = <_Affine>[];
  void walk(int index, _Affine parent) {
    if (index < 0 || index >= nodes.length) return;
    final node = Map<String, dynamic>.from(nodes[index] as Map);
    final composed = _multiply(parent, _nodeAffine(node));
    if (node['mesh'] != null) instances.add(composed);
    for (final child in (node['children'] as List?) ?? const []) {
      walk((child as num).toInt(), composed);
    }
  }

  for (final root in rootIndices) {
    walk(root, _identityAffine);
  }
  if (instances.isEmpty) return _identityAffine;
  if (instances.length > 1) {
    final differs = instances.any((m) {
      for (var i = 0; i < 12; i++) {
        if ((m[i] - instances.first[i]).abs() > 1e-9) return true;
      }
      return false;
    });
    if (differs) {
      throw const GlbNormalizationException(
          'the scene instances the mesh more than once at different transforms — '
          'apply the transforms and delete the extra copies before handover (guide §C3)');
    }
    changes.add('the scene has ${instances.length} identical instances of the mesh; '
        'merged into one');
  }
  return instances.first;
}

void _bakeNodeTransform(_Geometry geometry, _Glb glb, List<String> changes) {
  final affine = _sceneAffine(glb, changes);
  var moved = false;
  for (var i = 0; i < 12; i++) {
    if ((affine[i] - _identityAffine[i]).abs() > 1e-9) moved = true;
  }
  if (!moved) return;
  _applyAffine(geometry, affine);
  changes.add('baked the root node transform into the vertices '
      '(${_describeAffine(affine)}) — the validator reads accessor bounds, not the node tree');
}

void _applyAffine(_Geometry geometry, _Affine affine) {
  final positions = geometry.positions;
  for (var i = 0; i < positions.length; i += 3) {
    final p = _applyPoint(affine, [positions[i], positions[i + 1], positions[i + 2]]);
    positions[i] = p[0];
    positions[i + 1] = p[1];
    positions[i + 2] = p[2];
  }
  final normals = geometry.normals;
  for (var i = 0; i < normals.length; i += 3) {
    final n = _applyDirection(affine, [normals[i], normals[i + 1], normals[i + 2]]);
    final length = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
    if (length == 0) continue;
    normals[i] = n[0] / length;
    normals[i + 1] = n[1] / length;
    normals[i + 2] = n[2] / length;
  }
}

String _describeAffine(_Affine m) {
  final labels = <String>[];
  for (var i = 0; i < 3; i++) {
    final axis = <double>[];
    for (var c = 0; c < 3; c++) {
      axis.add(m[i * 3 + c]);
    }
    final named = _nameAxis(axis);
    if (named != null) labels.add('${'xyz'[i]}←$named');
  }
  final translation = (m[9].abs() + m[10].abs() + m[11].abs());
  return '${labels.join(', ')}${translation > 1e-9 ? ', translated' : ''}';
}

String? _nameAxis(List<double> axis) {
  const names = ['+x', '-x', '+y', '-y', '+z', '-z'];
  const signs = [
    [1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]
  ];
  for (var i = 0; i < signs.length; i++) {
    if ((axis[0] - signs[i][0]).abs() < 1e-6 &&
        (axis[1] - signs[i][1]).abs() < 1e-6 &&
        (axis[2] - signs[i][2]).abs() < 1e-6) {
      return names[i];
    }
  }
  return null;
}

// ─── Axis, scale, placement ────────────────────────────────────────────────

void _reorient(_Geometry geometry, GlbNormalizerOptions options, List<String> changes) {
  final bounds = geometry.bounds();
  final extentX = bounds[3] - bounds[0];
  final extentY = bounds[4] - bounds[1];
  final extentZ = bounds[5] - bounds[2];

  if (extentY >= extentX && extentY >= extentZ) {
    throw const GlbNormalizationException(
        'the mesh is taller than it is long, so its up axis is not +Y — this is what '
        'a Z-up scene looks like when the exporter\'s rotation was baked the wrong way. '
        'Open it, apply rotations (Ctrl+A → Rotation) and re-export with '
        'Transform → +Y Up ON (guide §C8)');
  }

  if (extentX > extentZ) {
    final toeAtPlusX = switch (options.toe) {
      null => true,
      ToeEnd.plusX => true,
      ToeEnd.minusX => false,
      ToeEnd.plusZ => throw const GlbNormalizationException(
          'the long axis of this mesh runs along X, so --toe +z/-z cannot apply — '
          'say --toe +x or --toe -x'),
      ToeEnd.minusZ => throw const GlbNormalizationException(
          'the long axis of this mesh runs along X, so --toe +z/-z cannot apply — '
          'say --toe +x or --toe -x'),
    };
    if (options.toe == null) {
      changes.add('note: the length runs along X and no --toe was given, so the toe is '
          'assumed to be at +X; pass --toe -x if the shoe would end up backwards '
          '(the validator cannot tell, checklist §2)');
    }
    // Ry(-90°) sends +x to +z; Ry(+90°) sends -x to +z.
    final angle = (toeAtPlusX ? -1.0 : 1.0) * math.pi / 2;
    final c = math.cos(angle).abs() < 1e-12 ? 0.0 : math.cos(angle);
    final s = math.sin(angle);
    _applyAffine(geometry, <double>[
      c, 0, s, //
      0, 1, 0,
      -s, 0, c,
      0, 0, 0,
    ]);
    changes.add('rotated 90° about Y so the length runs along Z with the toe at +Z');
    return;
  }

  if (options.toe == null) {
    changes.add('note: the length already runs along Z and no --toe was given, so the '
        'toe is assumed to be at +Z (checklist §2)');
  }
  if (options.toe == ToeEnd.minusZ) {
    _applyAffine(geometry, [
      -1, 0, 0, //
      0, 1, 0,
      0, 0, -1,
      0, 0, 0,
    ]);
    changes.add('turned the model 180° about Y so the toe sits at +Z');
  }
}

void _scaleToDeclaredLength(
    _Geometry geometry, GlbNormalizerOptions options, List<String> changes) {
  final declared = options.externalLengthMm;
  if (declared == null) {
    changes.add('note: no declared external length, so the mesh keeps its authored '
        'scale — the scale check compares it against that number and will fail until '
        'the handover supplies one (guide §5.1)');
    return;
  }
  final bounds = geometry.bounds();
  final lengthMm = (bounds[5] - bounds[2]) * 1000;
  if (lengthMm <= 0) {
    throw const GlbNormalizationException('the mesh has no length along Z');
  }
  final factor = declared / lengthMm;
  if ((factor - 1).abs() < 1e-9) return;
  _applyAffine(geometry, [
    factor, 0, 0, //
    0, factor, 0,
    0, 0, factor,
    0, 0, 0,
  ]);
  changes.add('scaled by ${factor.toStringAsFixed(4)} so the mesh measures '
      '${declared.toStringAsFixed(1)} mm — it was ${lengthMm.toStringAsFixed(1)} mm, '
      '${(lengthMm / declared).toStringAsFixed(2)}× the declaration');
}

void _placeAtOrigin(_Geometry geometry, List<String> changes) {
  final bounds = geometry.bounds();
  final dx = -(bounds[0] + bounds[3]) / 2;
  final dy = -bounds[1];
  final dz = -bounds[2];
  _applyAffine(geometry, [
    1, 0, 0, //
    0, 1, 0,
    0, 0, 1,
    dx, dy, dz,
  ]);
  changes.add('moved the mesh so the heel-bottom-centre sits at the origin: '
      'x ${(-dx * 1000).toStringAsFixed(1)} mm, '
      'y ${(-dy * 1000).toStringAsFixed(1)} mm and '
      'z ${(-dz * 1000).toStringAsFixed(1)} mm off, now grounded and centred');
}

// ─── Textures ──────────────────────────────────────────────────────────────

class _EncodedImage {
  final String? name;
  final String mimeType;
  final Uint8List bytes;
  _EncodedImage(this.name, this.mimeType, this.bytes);
}

List<_EncodedImage> _rebakeTextures(
    _Glb glb, GlbNormalizerOptions options, List<String> changes) {
  final images = <_EncodedImage>[];
  for (var i = 0; i < glb.list('images').length; i++) {
    final image = glb.at('images', i);
    final bufferViewIndex = (image['bufferView'] as num?)?.toInt();
    if (bufferViewIndex == null) {
      throw GlbNormalizationException(
          'images[$i] is not embedded in the .glb — export with textures embedded '
          '(guide §C8)');
    }
    final bufferView = glb.at('bufferViews', bufferViewIndex);
    final start = (bufferView['byteOffset'] as num?)?.toInt() ?? 0;
    final length = (bufferView['byteLength'] as num?)?.toInt() ?? 0;
    final raw = Uint8List.sublistView(glb.bin, start, start + length);
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      throw GlbNormalizationException(
          'images[$i] (${image['mimeType']}) could not be decoded — re-export the '
          'textures as plain PNG or JPEG (guide §C8)');
    }
    final max = options.maxTextureSize;
    final scale = math.min(1.0, max / math.max(decoded.width, decoded.height));
    final width = math.max(1, (decoded.width * scale).round());
    final height = math.max(1, (decoded.height * scale).round());
    final resized = scale < 1.0
        ? img.copyResize(decoded, width: width, height: height,
            interpolation: img.Interpolation.average)
        : decoded;
    final quality = options.jpegQuality;
    final encoded = quality == null
        ? Uint8List.fromList(img.encodePng(resized))
        : Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    final mime = quality == null ? 'image/png' : 'image/jpeg';
    final sizeChange = '${_size(length)} → ${_size(encoded.length)}';
    changes.add('images[$i] ${image['name'] ?? ''} ${decoded.width}×${decoded.height} → '
        '$width×$height ${mime.replaceFirst('image/', '')} $sizeChange');
    images.add(_EncodedImage(image['name']?.toString(), mime, encoded));
  }
  return images;
}

// ─── Materials ─────────────────────────────────────────────────────────────

class _Part {
  final String name;
  final int sourceMaterial; // index into the source material list, -1 = none
  final List<int> triangles; // triangle ordinals
  _Part(this.name, this.sourceMaterial, this.triangles);
}

List<_Part> _rebuildMaterials(_Glb glb, _Geometry geometry,
    GlbNormalizerOptions options, List<String> changes) {
  final names = <String>[];
  for (var i = 0; i < glb.list('materials').length; i++) {
    var name = glb.at('materials', i)['name']?.toString() ?? '';
    if (name.isEmpty) name = options.defaultMaterialName;
    names.add(options.materialRenames[name] ?? name);
  }

  final byMaterial = <String, _Part>{};
  void add(int index, int triangle) {
    final name = index >= 0 && index < names.length ? names[index] : options.defaultMaterialName;
    final part = byMaterial.putIfAbsent(
        name, () => _Part(name, index, <int>[]));
    part.triangles.add(triangle);
  }

  final soleBandMm = options.soleBandMm;
  if (soleBandMm != null) {
    final band = soleBandMm / 1000;
    final sole = _Part('sole', geometry.materialNames.isEmpty ? -1 : 0, <int>[]);
    final upper = _Part('upper', geometry.materialNames.isEmpty ? -1 : 0, <int>[]);
    for (var t = 0; t < geometry.triangleCount; t++) {
      var below = true;
      for (var k = 0; k < 3; k++) {
        final vertex = geometry.indices[t * 3 + k];
        if (geometry.positions[vertex * 3 + 1] > band) below = false;
      }
      (below ? sole : upper).triangles.add(t);
    }
    // Area, not triangle count, is what the colour swap actually shows: a
    // densely tessellated sole band can be most of the triangles and a small
    // part of the shoe.
    final totalArea = _areaOf(geometry, null);
    final soleArea = _areaOf(geometry, sole.triangles);
    changes.add('split the single material geometrically at the '
        '${soleBandMm.toStringAsFixed(1)} mm line: "upper" gets '
        '${upper.triangles.length} triangles (${_percent(totalArea - soleArea, totalArea)} '
        'of the surface), "sole" gets ${sole.triangles.length} '
        '(${_percent(soleArea, totalArea)}) — an approximation for a one-material '
        'scan, and the cut line stays a reviewer question (checklist §6)');
    return [upper, sole].where((p) => p.triangles.isNotEmpty).toList();
  }

  for (var t = 0; t < geometry.triangleCount; t++) {
    add(geometry.triangleMaterial[t], t);
  }
  final parts = byMaterial.values.toList();
  final renamed = <String>[];
  for (var i = 0; i < names.length; i++) {
    if ((glb.at('materials', i)['name']?.toString() ?? '') != names[i]) {
      renamed.add('${glb.at('materials', i)['name']} → ${names[i]}');
    }
  }
  if (renamed.isNotEmpty) {
    changes.add('renamed material(s): ${renamed.join(', ')}');
  }
  final stripped = <String>{};
  for (var i = 0; i < glb.list('materials').length; i++) {
    for (final key in (glb.at('materials', i)['extensions'] as Map?)?.keys ?? const <String>[]) {
      if (kNormalizerStrippedExtensions.contains(key.toString())) stripped.add(key.toString());
    }
  }
  if (stripped.isNotEmpty) {
    changes.add('removed extension(s) the renderer has no proven support for: '
        '${stripped.join(', ')}');
  }
  if (parts.length == 1) {
    changes.add('note: the model has ${parts.length} material named "${parts.first.name}" — '
        'the contract requires both "upper" and "sole"; pass --sole-band-mm to cut a '
        'sole band, or split the parts in the modelling tool (guide §C6)');
  }
  return parts;
}

// ─── Writing ───────────────────────────────────────────────────────────────

Uint8List _write(
  _Geometry geometry,
  _Glb glb,
  List<_EncodedImage> images,
  List<_Part> parts,
  List<String> changes,
) {
  final bin = BytesBuilder();
  final bufferViews = <Map<String, dynamic>>[];
  final accessors = <Map<String, dynamic>>[];

  int appendBytes(List<int> bytes, {required int stride}) {
    while (bin.length % 4 != 0) {
      bin.addByte(0);
    }
    final offset = bin.length;
    bin.add(bytes);
    final view = <String, dynamic>{
      'buffer': 0,
      'byteOffset': offset,
      'byteLength': bin.length - offset,
    };
    if (stride > 0) view['byteStride'] = stride;
    bufferViews.add(view);
    return bufferViews.length - 1;
  }

  Uint8List floats(List<double> values) {
    final out = ByteData(values.length * 4);
    for (var i = 0; i < values.length; i++) {
      out.setFloat32(i * 4, values[i], Endian.little);
    }
    return out.buffer.asUint8List();
  }

  Uint8List unsigned(List<int> values, int bytes) {
    final out = ByteData(values.length * bytes);
    for (var i = 0; i < values.length; i++) {
      if (bytes == 2) {
        out.setUint16(i * 2, values[i], Endian.little);
      } else {
        out.setUint32(i * 4, values[i], Endian.little);
      }
    }
    return out.buffer.asUint8List();
  }

  final primitives = <Map<String, dynamic>>[];
  for (final part in parts) {
    // One vertex pool per part: triangles that share a vertex share it here,
    // which keeps the file the size the contract's budget assumes.
    final remap = <int, int>{};
    final positions = <double>[];
    final normals = <double>[];
    final uvs = <double>[];
    final indices = <int>[];
    for (final triangle in part.triangles) {
      for (var k = 0; k < 3; k++) {
        final vertex = geometry.indices[triangle * 3 + k];
        final mapped = remap.putIfAbsent(vertex, () {
          final local = positions.length ~/ 3;
          positions..add(geometry.positions[vertex * 3])
              ..add(geometry.positions[vertex * 3 + 1])
              ..add(geometry.positions[vertex * 3 + 2]);
          if (geometry.normals.isNotEmpty) {
            normals..add(geometry.normals[vertex * 3])
                ..add(geometry.normals[vertex * 3 + 1])
                ..add(geometry.normals[vertex * 3 + 2]);
          }
          if (geometry.uvs.isNotEmpty) {
            uvs..add(geometry.uvs[vertex * 2])..add(geometry.uvs[vertex * 2 + 1]);
          }
          return local;
        });
        indices.add(mapped);
      }
    }

    final min = <double>[double.infinity, double.infinity, double.infinity];
    final max = <double>[-double.infinity, -double.infinity, -double.infinity];
    for (var i = 0; i < positions.length; i += 3) {
      for (var c = 0; c < 3; c++) {
        min[c] = math.min(min[c], positions[i + c]);
        max[c] = math.max(max[c], positions[i + c]);
      }
    }

    final positionView = appendBytes(floats(positions), stride: 0);
    accessors.add({
      'bufferView': positionView,
      'componentType': 5126,
      'count': positions.length ~/ 3,
      'type': 'VEC3',
      'min': min,
      'max': max,
    });
    final positionAccessor = accessors.length - 1;

    int? normalAccessor;
    if (normals.isNotEmpty) {
      final view = appendBytes(floats(normals), stride: 0);
      accessors.add({
        'bufferView': view,
        'componentType': 5126,
        'count': normals.length ~/ 3,
        'type': 'VEC3',
      });
      normalAccessor = accessors.length - 1;
    }
    int? uvAccessor;
    if (uvs.isNotEmpty) {
      final view = appendBytes(floats(uvs), stride: 0);
      accessors.add({
        'bufferView': view,
        'componentType': 5126,
        'count': uvs.length ~/ 2,
        'type': 'VEC2',
      });
      uvAccessor = accessors.length - 1;
    }
    final use16 = positions.length ~/ 3 <= 65535;
    final indexView = appendBytes(unsigned(indices, use16 ? 2 : 4), stride: 0);
    accessors.add({
      'bufferView': indexView,
      'componentType': use16 ? 5123 : 5125,
      'count': indices.length,
      'type': 'SCALAR',
    });
    final indexAccessor = accessors.length - 1;

    changes.add('part "${part.name}": ${indices.length ~/ 3} triangles, '
        '${positions.length ~/ 3} vertices');
    primitives.add({
      'attributes': {
        'POSITION': positionAccessor,
        'NORMAL': ?normalAccessor,
        'TEXCOORD_0': ?uvAccessor,
      },
      'indices': indexAccessor,
      'mode': 4,
      'material': parts.indexOf(part),
    });
  }

  final jsonImages = <Map<String, dynamic>>[];
  for (final image in images) {
    final view = appendBytes(image.bytes, stride: 0);
    jsonImages.add({
      if (image.name != null && image.name!.isNotEmpty) 'name': image.name,
      'mimeType': image.mimeType,
      'bufferView': view,
    });
  }

  // Materials are cloned from the source so factors, samplers and texture
  // references survive; only the name and the stripped extensions change.
  final materials = <Map<String, dynamic>>[];
  final extensionsUsed = <String>{};
  for (final part in parts) {
    final cloned = part.sourceMaterial >= 0
        ? Map<String, dynamic>.from(glb.at('materials', part.sourceMaterial))
        : <String, dynamic>{'pbrMetallicRoughness': <String, dynamic>{}};
    cloned['name'] = part.name;
    final extensions = cloned['extensions'];
    if (extensions is Map) {
      final kept = <String, dynamic>{};
      extensions.forEach((key, value) {
        if (kNormalizerStrippedExtensions.contains(key.toString())) return;
        kept[key.toString()] = value;
        extensionsUsed.add(key.toString());
      });
      if (kept.isEmpty) {
        cloned.remove('extensions');
      } else {
        cloned['extensions'] = kept;
      }
    }
    cloned.remove('extras');
    materials.add(cloned);
  }

  final textures = glb.list('textures').map((t) => Map<String, dynamic>.from(t as Map)).toList();
  final samplers = glb.list('samplers').map((s) => Map<String, dynamic>.from(s as Map)).toList();

  while (bin.length % 4 != 0) {
    bin.addByte(0);
  }

  final json = <String, dynamic>{
    'asset': {
      'version': '2.0',
      'generator': 'solevision glb normalizer',
    },
    'scene': 0,
    'scenes': [
      {'nodes': [0]}
    ],
    'nodes': [
      {
        'mesh': 0,
        'name': glb.list('nodes').isNotEmpty
            ? (glb.at('nodes', 0)['name']?.toString() ?? 'shoe')
            : 'shoe',
      }
    ],
    'meshes': [
      {'name': 'shoe', 'primitives': primitives}
    ],
    'accessors': accessors,
    'bufferViews': bufferViews,
    'buffers': [
      {'byteLength': bin.length}
    ],
    'materials': materials,
    if (textures.isNotEmpty) 'textures': textures,
    if (samplers.isNotEmpty) 'samplers': samplers,
    if (jsonImages.isNotEmpty) 'images': jsonImages,
    if (extensionsUsed.isNotEmpty) 'extensionsUsed': extensionsUsed.toList()..sort(),
  };
  return _assemble(json, bin.takeBytes());
}

Uint8List _assemble(Map<String, dynamic> json, Uint8List bin) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  final jsonPad = (4 - jsonBytes.length % 4) % 4;
  final binPad = (4 - bin.length % 4) % 4;
  final total = 12 + 8 + jsonBytes.length + jsonPad + 8 + bin.length + binPad;
  final out = ByteData(total);
  out.setUint32(0, _kGlbMagic, Endian.little);
  out.setUint32(4, 2, Endian.little);
  out.setUint32(8, total, Endian.little);
  out.setUint32(12, jsonBytes.length + jsonPad, Endian.little);
  out.setUint32(16, _kJsonChunkType, Endian.little);
  Uint8List.sublistView(out.buffer.asUint8List(), 20, 20 + jsonBytes.length)
      .setAll(0, jsonBytes);
  for (var i = 0; i < jsonPad; i++) {
    out.setUint8(20 + jsonBytes.length + i, 0x20);
  }
  final binStart = 20 + jsonBytes.length + jsonPad;
  out.setUint32(binStart, bin.length + binPad, Endian.little);
  out.setUint32(binStart + 4, _kBinChunkType, Endian.little);
  Uint8List.sublistView(out.buffer.asUint8List(), binStart + 8, binStart + 8 + bin.length)
      .setAll(0, bin);
  return out.buffer.asUint8List();
}

// ─── Metrics ───────────────────────────────────────────────────────────────

Map<String, dynamic> _metrics(_Geometry geometry, List<String> materialNames, int byteLength) {
  final bounds = geometry.bounds();
  return {
    'bytes': byteLength,
    'triangles': geometry.triangleCount,
    'vertices': geometry.vertexCount,
    'materials': materialNames,
    'boundsMm': [for (final value in bounds) value * 1000],
    'lengthMm': (bounds[5] - bounds[2]) * 1000,
    'widthMm': (bounds[3] - bounds[0]) * 1000,
    'heightMm': (bounds[4] - bounds[1]) * 1000,
  };
}

/// Surface area of the given triangles, or of the whole mesh when null.
///
/// Areas are in the file's current units (metres after scaling); only the ratio
/// is reported, so the unit does not matter.
String _percent(double part, double whole) =>
    whole <= 0 ? 'n/a' : '${(100 * part / whole).toStringAsFixed(1)}%';

double _areaOf(_Geometry geometry, List<int>? triangles) {
  var total = 0.0;
  final count = triangles?.length ?? geometry.triangleCount;
  for (var t = 0; t < count; t++) {
    final triangle = triangles?[t] ?? t;
    final a = geometry.indices[triangle * 3];
    final b = geometry.indices[triangle * 3 + 1];
    final c = geometry.indices[triangle * 3 + 2];
    final ux = geometry.positions[b * 3] - geometry.positions[a * 3];
    final uy = geometry.positions[b * 3 + 1] - geometry.positions[a * 3 + 1];
    final uz = geometry.positions[b * 3 + 2] - geometry.positions[a * 3 + 2];
    final vx = geometry.positions[c * 3] - geometry.positions[a * 3];
    final vy = geometry.positions[c * 3 + 1] - geometry.positions[a * 3 + 1];
    final vz = geometry.positions[c * 3 + 2] - geometry.positions[a * 3 + 2];
    final cx = uy * vz - uz * vy;
    final cy = uz * vx - ux * vz;
    final cz = ux * vy - uy * vx;
    total += math.sqrt(cx * cx + cy * cy + cz * cz) / 2;
  }
  return total;
}

extension on _Glb {
  /// The source `materials[].name` list, for the before/after metrics.
  List<String> materialNames() => list('materials')
      .map((m) => (m as Map)['name']?.toString() ?? '')
      .toList();
}

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';
}
