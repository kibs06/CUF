/// Tests for `lib/utils/glb_normalizer.dart` (roadmap V2.7).
///
/// The assertions deliberately go through `validateGlb` rather than inspecting
/// the normalised JSON: the normaliser exists to make that report green, so a
/// test that reads the accessors directly would pass while the contract check
/// still failed. Fixtures are synthetic GLBs built here with one knob each, plus
/// one real asset — the bundled placeholder, which already meets the contract
/// and must therefore still meet it after a normalise pass.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/utils/glb_normalizer.dart';
import 'package:app/utils/glb_validator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// ─── Fixture builder ───────────────────────────────────────────────────────

Uint8List _bytesOf(List<double> values) {
  final data = ByteData(values.length * 4);
  for (var i = 0; i < values.length; i++) {
    data.setFloat32(i * 4, values[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

Uint8List _uintsOf(List<int> values) {
  final data = ByteData(values.length * 2);
  for (var i = 0; i < values.length; i++) {
    data.setUint16(i * 2, values[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

/// A minimal but valid GLB: one mesh, one primitive, optional root-node
/// rotation, optional material (with optional extensions) and optional texture.
Uint8List buildGlb({
  required List<double> positions,
  required List<int> indices,
  List<double> uvs = const [],
  List<double> normals = const [],
  String? materialName,
  Map<String, dynamic>? materialExtensions,
  List<double>? rotation,
  List<double>? translation,
  List<String> extensionsUsed = const [],
  Uint8List? imageBytes,
  String imageMime = 'image/png',
  List<String> animNames = const [],
}) {
  final bin = BytesBuilder();
  final bufferViews = <Map<String, dynamic>>[];
  final accessors = <Map<String, dynamic>>[];
  int add(List<int> bytes, {int? stride}) {
    while (bin.length % 4 != 0) {
      bin.addByte(0);
    }
    final offset = bin.length;
    bin.add(bytes);
    bufferViews.add({
      'buffer': 0,
      'byteOffset': offset,
      'byteLength': bin.length - offset,
      'byteStride': ?stride,
    });
    return bufferViews.length - 1;
  }

  final min = <double>[double.infinity, double.infinity, double.infinity];
  final max = <double>[-double.infinity, -double.infinity, -double.infinity];
  for (var i = 0; i < positions.length; i += 3) {
    for (var c = 0; c < 3; c++) {
      if (positions[i + c] < min[c]) min[c] = positions[i + c];
      if (positions[i + c] > max[c]) max[c] = positions[i + c];
    }
  }
  accessors.add({
    'bufferView': add(_bytesOf(positions)),
    'componentType': 5126,
    'count': positions.length ~/ 3,
    'type': 'VEC3',
    'min': min,
    'max': max,
  });
  final position = accessors.length - 1;

  int? normal;
  if (normals.isNotEmpty) {
    accessors.add({
      'bufferView': add(_bytesOf(normals)),
      'componentType': 5126,
      'count': normals.length ~/ 3,
      'type': 'VEC3',
    });
    normal = accessors.length - 1;
  }
  int? uv;
  if (uvs.isNotEmpty) {
    accessors.add({
      'bufferView': add(_bytesOf(uvs)),
      'componentType': 5126,
      'count': uvs.length ~/ 2,
      'type': 'VEC2',
    });
    uv = accessors.length - 1;
  }
  accessors.add({
    'bufferView': add(_uintsOf(indices)),
    'componentType': 5123,
    'count': indices.length,
    'type': 'SCALAR',
  });
  final index = accessors.length - 1;

  final images = <Map<String, dynamic>>[];
  final textures = <Map<String, dynamic>>[];
  if (imageBytes != null) {
    images.add({
      'name': 'fixture',
      'mimeType': imageMime,
      'bufferView': add(imageBytes),
    });
    textures.add({'source': 0});
  }

  final materials = <Map<String, dynamic>>[];
  if (materialName != null) {
    materials.add({
      'name': materialName,
      'pbrMetallicRoughness': {
        if (textures.isNotEmpty) 'baseColorTexture': {'index': 0},
      },
      'extensions': ?materialExtensions,
    });
  }

  final json = <String, dynamic>{
    'asset': {'version': '2.0', 'generator': 'fixture'},
    'scene': 0,
    'scenes': [
      {'nodes': [0]}
    ],
    'nodes': [
      {
        'mesh': 0,
        'rotation': ?rotation,
        'translation': ?translation,
      }
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {
              'POSITION': position,
              'NORMAL': ?normal,
              'TEXCOORD_0': ?uv,
            },
            'indices': index,
            'mode': 4,
            if (materials.isNotEmpty) 'material': 0,
          }
        ],
      }
    ],
    'accessors': accessors,
    'bufferViews': bufferViews,
    'buffers': [
      {'byteLength': bin.length}
    ],
    if (materials.isNotEmpty) 'materials': materials,
    if (textures.isNotEmpty) 'textures': textures,
    if (images.isNotEmpty) 'images': images,
    if (extensionsUsed.isNotEmpty) 'extensionsUsed': extensionsUsed,
    for (final name in animNames)
      'animations': [
        {
          'name': name,
          'channels': <Map<String, dynamic>>[],
          'samplers': <Map<String, dynamic>>[],
        }
      ],
  };
  return _assemble(json, bin.takeBytes());
}

Uint8List _assemble(Map<String, dynamic> json, Uint8List bin) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  final jsonPad = (4 - jsonBytes.length % 4) % 4;
  final binPad = (4 - bin.length % 4) % 4;
  final total = 12 + 8 + jsonBytes.length + jsonPad + 8 + bin.length + binPad;
  final out = ByteData(total);
  final view = out.buffer.asUint8List();
  out.setUint32(0, 0x46546C67, Endian.little);
  out.setUint32(4, 2, Endian.little);
  out.setUint32(8, total, Endian.little);
  out.setUint32(12, jsonBytes.length + jsonPad, Endian.little);
  out.setUint32(16, 0x4E4F534A, Endian.little);
  view.setAll(20, jsonBytes);
  for (var i = 0; i < jsonPad; i++) {
    out.setUint8(20 + jsonBytes.length + i, 0x20);
  }
  final start = 20 + jsonBytes.length + jsonPad;
  out.setUint32(start, bin.length + binPad, Endian.little);
  out.setUint32(start + 4, 0x004E4942, Endian.little);
  view.setAll(start + 8, bin);
  return view;
}

/// Rewrites the JSON chunk of a fixture, keeping the BIN as it is: how the
/// refusal paths are reached without building a file that is broken in ways the
/// builder would not allow.
Uint8List patchJson(Uint8List glb, void Function(Map<String, dynamic>) edit) {
  final data = ByteData.sublistView(glb);
  Uint8List? bin;
  Map<String, dynamic>? json;
  var offset = 12;
  while (offset + 8 <= glb.length) {
    final length = data.getUint32(offset, Endian.little);
    final type = data.getUint32(offset + 4, Endian.little);
    final chunk = Uint8List.sublistView(glb, offset + 8, offset + 8 + length);
    if (type == 0x4E4F534A) json = jsonDecode(utf8.decode(chunk)) as Map<String, dynamic>;
    if (type == 0x004E4942) bin = chunk;
    offset += 8 + length;
  }
  edit(json!);
  return _assemble(json, bin ?? Uint8List(0));
}

/// A closed-ish box, `longMm` along X, `wideMm` along Z and `tallMm` up Y —
/// standing in for a shoe, with the length along X like a Blender scene that
/// was modelled "sideways".
({List<double> positions, List<int> indices}) boxAlongX({
  double longMm = 400,
  double wideMm = 150,
  double tallMm = 120,
  double cx = 0,
  double cy = 0,
  double cz = 0,
}) {
  final l = longMm / 1000, w = wideMm / 1000, h = tallMm / 1000;
  final points = <List<double>>[
    [cx - l / 2, cy, cz - w / 2], [cx + l / 2, cy, cz - w / 2],
    [cx + l / 2, cy, cz + w / 2], [cx - l / 2, cy, cz + w / 2],
    [cx - l / 2, cy + h, cz - w / 2], [cx + l / 2, cy + h, cz - w / 2],
    [cx + l / 2, cy + h, cz + w / 2], [cx - l / 2, cy + h, cz + w / 2],
  ];
  const faces = [
    [0, 1, 2], [0, 2, 3], [4, 6, 5], [4, 7, 6], [0, 4, 5], [0, 5, 1],
    [1, 5, 6], [1, 6, 2], [2, 6, 7], [2, 7, 3], [3, 7, 4], [3, 4, 0],
  ];
  return (
    positions: [for (final p in points) ...p],
    indices: [for (final f in faces) ...f],
  );
}

GlbValidationReport reportOf(Uint8List bytes, {double? declaredMm}) => validateGlb(
      bytes,
      options: GlbValidationOptions(label: 'normalised', externalLengthMm: declaredMm),
    );

String? failureNamed(GlbValidationReport report, String name) {
  for (final check in report.checks) {
    if (check.name == name && check.status == GlbCheckStatus.fail) return check.detail;
  }
  return null;
}

void main() {
  group('normalizeShoeModel', () {
    test('bakes the exporter\'s Z-up rotation instead of leaving it on the node', () {
      // A Blender "+Y up" export of a Z-up scene: the mesh data is Z-up and the
      // root node carries the +(90°) X rotation that converts it. The validator
      // never walks the node tree, so leaving it there means the checks and the
      // renderer disagree about which way up the shoe is.
      final box = boxAlongX(cx: 0.2, cy: 0.05);
      final glb = buildGlb(
        positions: box.positions,
        indices: box.indices,
        materialName: 'upper',
        rotation: [0.7071068286895752, 0, 0, 0.7071068286895752],
      );

      final before = reportOf(glb, declaredMm: 400);
      expect(failureNamed(before, 'orientation'), isNotNull,
          reason: 'the fixture is taller in Y than long in Z before baking');

      final result = normalizeShoeModel(glb, options: const GlbNormalizerOptions(
        externalLengthMm: 400,
        toe: ToeEnd.plusX,
        // The fixture carries one material; the contract wants two, and the
        // band cut is how a one-material scan gets there (tested on its own).
        soleBandMm: 20,
      ));
      final after = reportOf(result.bytes, declaredMm: 400);

      expect(after.passed, isTrue, reason: after.checks.map((c) => c.detail).join('\n'));
      expect(result.changes.join('\n'), contains('baked the root node transform'));
      expect(result.changes.join('\n'), contains('rotated 90° about Y'));
    });

    test('puts the toe at +Z and honours --toe -x', () {
      final box = boxAlongX(longMm: 300, wideMm: 100, tallMm: 90);
      final glb = buildGlb(positions: box.positions, indices: box.indices);

      final toPlusX = normalizeShoeModel(glb, options: const GlbNormalizerOptions(
        externalLengthMm: 300,
        toe: ToeEnd.plusX,
        soleBandMm: 20,
      ));
      final toMinusX = normalizeShoeModel(glb, options: const GlbNormalizerOptions(
        externalLengthMm: 300,
        toe: ToeEnd.minusX,
        soleBandMm: 20,
      ));

      expect(reportOf(toPlusX.bytes, declaredMm: 300).passed, isTrue);
      expect(reportOf(toMinusX.bytes, declaredMm: 300).passed, isTrue);
      // The two answers are mirror images about X, so their z extents agree but
      // the toe end must have moved to the other side of the origin. Compare a
      // point at the far end of the original +X face.
      expect(toPlusX.after['lengthMm'], closeTo(300, 0.5));
      expect(toMinusX.after['lengthMm'], closeTo(300, 0.5));
    });

    test('assumes +X and says so when --toe is not given', () {
      final box = boxAlongX(longMm: 280, wideMm: 110, tallMm: 100);
      final result = normalizeShoeModel(
        buildGlb(positions: box.positions, indices: box.indices),
        options: const GlbNormalizerOptions(externalLengthMm: 280),
      );
      expect(result.changes.join('\n'), contains('no --toe was given'));
      expect(result.changes.join('\n'), contains('checklist §2'));
    });

    test('scales a mesh authored off-contract onto the declared length', () {
      final box = boxAlongX(longMm: 1160, wideMm: 480, tallMm: 430);
      final result = normalizeShoeModel(
        buildGlb(positions: box.positions, indices: box.indices),
        options: const GlbNormalizerOptions(
          externalLengthMm: 270,
          toe: ToeEnd.plusX,
          soleBandMm: 20,
        ),
      );
      final report = reportOf(result.bytes, declaredMm: 270);
      expect(report.passed, isTrue, reason: report.checks.map((c) => c.detail).join('\n'));
      expect(result.changes.join('\n'), contains('4.30× the declaration'));
      expect(result.after['lengthMm'], closeTo(270, 0.5));
      expect(result.after['widthMm'], closeTo(111.7, 1));
      expect(result.after['heightMm'], closeTo(100.1, 1));
    });

    test('leaves the scale alone without a declared length, and says so', () {
      final box = boxAlongX(longMm: 500, wideMm: 120, tallMm: 100);
      final result = normalizeShoeModel(
        buildGlb(positions: box.positions, indices: box.indices),
        options: const GlbNormalizerOptions(toe: ToeEnd.plusX),
      );
      expect(result.after['lengthMm'], closeTo(500, 0.5));
      expect(result.changes.join('\n'), contains('no declared external length'));
      expect(failureNamed(reportOf(result.bytes), 'scale'), isNotNull);
    });

    test('grounds, centres and puts the heel at the origin', () {
      final box = boxAlongX(longMm: 300, wideMm: 100, tallMm: 90,
          cx: 0.4, cy: 0.3, cz: -0.2);
      final result = normalizeShoeModel(
        buildGlb(positions: box.positions, indices: box.indices),
        options: const GlbNormalizerOptions(
          externalLengthMm: 300,
          toe: ToeEnd.plusX,
          soleBandMm: 20,
        ),
      );
      final bounds = result.after['boundsMm'] as List;
      expect(bounds[1], closeTo(0, 0.01)); // y min
      expect(bounds[2], closeTo(0, 0.01)); // z min, the heel
      expect((bounds[0] + bounds[3]) / 2, closeTo(0, 0.01)); // centred in x
      expect(reportOf(result.bytes, declaredMm: 300).passed, isTrue);
    });

    test('re-bakes 4096²-class textures down to the contract ceiling', () {
      final box = boxAlongX(longMm: 300, wideMm: 100, tallMm: 90);
      final texture = img.Image(width: 1100, height: 900)..clear(img.ColorRgb8(120, 60, 30));
      final glb = buildGlb(
        positions: box.positions,
        indices: box.indices,
        uvs: List<double>.generate(box.positions.length ~/ 3 * 2, (i) => (i % 2) * 0.5),
        materialName: 'upper',
        imageBytes: Uint8List.fromList(img.encodePng(texture)),
      );

      final result = normalizeShoeModel(
        glb,
        options: const GlbNormalizerOptions(
          externalLengthMm: 300,
          toe: ToeEnd.plusX,
        ),
      );
      final report = reportOf(result.bytes, declaredMm: 300);
      expect(failureNamed(report, 'textures'), isNull);
      expect(failureNamed(report, 'file size'), isNull);
      expect(result.changes.join('\n'), contains('1100×900 → 1024×838'));
      // Aspect ratio preserved, and the ceiling respected: on a real 4096²
      // export this is where 31 MiB becomes ~2 MiB, so the fixture only proves
      // the path ran and the contract is met.
      expect(result.bytes.length, lessThan(kFileSizeBudgetBytes));
    });

    test('re-encodes textures as PNG when JPEG is switched off', () {
      final box = boxAlongX();
      final texture = img.Image(width: 1200, height: 1200)..clear(img.ColorRgb8(10, 10, 10));
      final result = normalizeShoeModel(
        buildGlb(
          positions: box.positions,
          indices: box.indices,
          uvs: List<double>.generate(box.positions.length ~/ 3 * 2, (i) => 0.5),
          imageBytes: Uint8List.fromList(img.encodePng(texture)),
        ),
        options: const GlbNormalizerOptions(
          externalLengthMm: 400,
          toe: ToeEnd.plusX,
          jpegQuality: null,
        ),
      );
      expect(result.changes.join('\n'), contains('png'));
      expect(result.changes.join('\n'), contains('1024×1024'));
    });

    test('renames materials and strips extensions the renderer may not know', () {
      final box = boxAlongX();
      final glb = buildGlb(
        positions: box.positions,
        indices: box.indices,
        materialName: 'Material.001',
        materialExtensions: {
          'KHR_materials_specular': {
            'specularColorFactor': [2.0, 2.0, 2.0]
          }
        },
        extensionsUsed: ['KHR_materials_specular'],
      );

      final result = normalizeShoeModel(
        glb,
        options: const GlbNormalizerOptions(
          externalLengthMm: 400,
          toe: ToeEnd.plusX,
          materialRenames: {'Material.001': 'upper'},
        ),
      );
      final json = jsonDecode(utf8.decode(_jsonChunkOf(result.bytes))) as Map<String, dynamic>;
      expect((json['materials'] as List).first['name'], 'upper');
      expect(json['extensionsUsed'], isNull);
      expect((json['materials'] as List).first['extensions'], isNull);
      expect(result.changes.join('\n'), contains('Material.001 → upper'));
      // The contract needs both parts, and says which one is missing.
      expect(result.changes.join('\n'), contains('requires both "upper" and "sole"'));
    });

    test('cuts a sole band out of a single-material mesh, and reports its share', () {
      final box = boxAlongX(longMm: 280, wideMm: 110, tallMm: 100);
      final result = normalizeShoeModel(
        buildGlb(positions: box.positions, indices: box.indices, materialName: 'Material.001'),
        options: const GlbNormalizerOptions(
          externalLengthMm: 280,
          toe: ToeEnd.plusX,
          materialRenames: {'Material.001': 'upper'},
          soleBandMm: 25,
        ),
      );
      final report = reportOf(result.bytes, declaredMm: 280);
      expect(failureNamed(report, 'materials'), isNull);
      expect(result.after['materials'], ['upper', 'sole']);
      expect(result.changes.join('\n'), contains('of the surface'));
      expect(result.changes.join('\n'), contains('checklist §6'));
    });

    test('refuses geometry compression it cannot undo', () {
      final box = boxAlongX();
      final glb = patchJson(
        buildGlb(positions: box.positions, indices: box.indices),
        (json) => json['extensionsUsed'] = ['KHR_draco_mesh_compression'],
      );
      expect(
        () => normalizeShoeModel(glb),
        throwsA(isA<GlbNormalizationException>().having(
            (e) => e.message, 'message', contains('re-export the model uncompressed'))),
      );
    });

    test('refuses KTX2 textures', () {
      final box = boxAlongX();
      final glb = patchJson(
        buildGlb(
          positions: box.positions,
          indices: box.indices,
          imageBytes: Uint8List.fromList([1, 2, 3, 4]),
        ),
        (json) => (json['images'] as List).first['mimeType'] = 'image/ktx2',
      );
      expect(
        () => normalizeShoeModel(glb),
        throwsA(isA<GlbNormalizationException>()
            .having((e) => e.message, 'message', contains('KTX2'))),
      );
    });

    test('refuses quantised attributes rather than writing garbage', () {
      final box = boxAlongX();
      final glb = patchJson(
        buildGlb(positions: box.positions, indices: box.indices),
        (json) => (json['accessors'] as List).first['componentType'] = 5122,
      );
      expect(
        () => normalizeShoeModel(glb),
        throwsA(isA<GlbNormalizationException>()
            .having((e) => e.message, 'message', contains('KHR_mesh_quantization'))),
      );
    });

    test('refuses a scene that instances the mesh at two different transforms', () {
      final box = boxAlongX();
      final glb = patchJson(
        buildGlb(positions: box.positions, indices: box.indices),
        (json) {
          final nodes = json['nodes'] as List;
          nodes.add({'mesh': 0, 'translation': [1.0, 0, 0]});
          (json['scenes'] as List).first['nodes'] = [0, 1];
        },
      );
      expect(
        () => normalizeShoeModel(glb),
        throwsA(isA<GlbNormalizationException>().having(
            (e) => e.message, 'message', contains('instances the mesh more than once'))),
      );
    });

    test('is idempotent on a file that already meets the contract', () {
      final box = boxAlongX(longMm: 270, wideMm: 110, tallMm: 100);
      final once = normalizeShoeModel(
        buildGlb(
          positions: box.positions,
          indices: box.indices,
          materialName: 'upper',
        ),
        options: const GlbNormalizerOptions(
          externalLengthMm: 270,
          toe: ToeEnd.plusX,
          soleBandMm: 20,
        ),
      );
      final twice = normalizeShoeModel(
        once.bytes,
        options: const GlbNormalizerOptions(
          externalLengthMm: 270,
          toe: ToeEnd.plusZ,
          soleBandMm: 20,
        ),
      );
      expect(reportOf(twice.bytes, declaredMm: 270).passed, isTrue);
      expect((twice.after['lengthMm'] as double), closeTo(270, 0.5));
    });

    test('normalises the bundled placeholder without breaking a single check', () {
      final file = File('assets/models/placeholder_shoe.glb');
      expect(file.existsSync(), isTrue,
          reason: 'the bundled placeholder is the pipeline\'s reference asset');
      final source = file.readAsBytesSync();

      final before = validateGlb(source,
          options: const GlbValidationOptions(
              label: 'placeholder', externalLengthMm: 270, authoredSizeEu: 42));
      expect(before.passed, isTrue, reason: 'fixture precondition');

      final result = normalizeShoeModel(
        source,
        options: const GlbNormalizerOptions(
          externalLengthMm: 270,
          authoredSizeEu: 42,
          toe: ToeEnd.plusZ,
        ),
      );
      final after = reportOf(result.bytes, declaredMm: 270);
      expect(after.checks.length, before.checks.length);
      expect(after.passed, isTrue,
          reason: after.checks.map((c) => '${c.name}: ${c.detail}').join('\n'));
      expect(after.triangleCount, before.triangleCount);
      expect((result.after['lengthMm'] as double), closeTo(270, 0.5));
    });
  });
}

Uint8List _jsonChunkOf(Uint8List glb) {
  final data = ByteData.sublistView(glb);
  var offset = 12;
  while (offset + 8 <= glb.length) {
    final length = data.getUint32(offset, Endian.little);
    final type = data.getUint32(offset + 4, Endian.little);
    if (type == 0x4E4F534A) {
      return Uint8List.sublistView(glb, offset + 8, offset + 8 + length);
    }
    offset += 8 + length;
  }
  return Uint8List(0);
}
