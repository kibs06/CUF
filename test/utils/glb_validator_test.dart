import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/utils/glb_validator.dart';
import 'package:flutter_test/flutter_test.dart';

/// The validator's job is to reject the files a partner pipeline produces
/// when something is wrong *before* a human reviewer looks at them. These
/// tests pin each contract failure separately, plus one end-to-end pass over
/// the real V0 fixture — the only `.glb` in the repo — so a change to the
/// validator cannot quietly stop checking the thing it exists for.
void main() {
  group('the V0 fixture (the only real GLB in the repo)', () {
    late Uint8List fixture;

    setUpAll(() {
      // Read from disk on purpose: a synthetic copy would stop testing the
      // actual asset the spike and its tests depend on.
      fixture = File('assets/models/placeholder_shoe.glb').readAsBytesSync();
    });

    test('passes every contract check when declared at its authored 270 mm',
        () {
      final report = validateGlb(
        fixture,
        options: const GlbValidationOptions(
          label: 'placeholder_shoe.glb',
          externalLengthMm: 270,
          authoredSizeEu: 42,
          shoeSide: 'right',
        ),
      );

      expect(report.passed, isTrue,
          reason: report.checks
              .where((c) => c.status == GlbCheckStatus.fail)
              .map((c) => '${c.name}: ${c.detail}')
              .join('\n'));
      expect(_check(report, 'triangles')!.detail, contains('1,536'));
      expect(_check(report, 'materials')!.detail, contains('upper'));
      expect(_check(report, 'materials')!.detail, contains('sole'));
      expect(_check(report, 'compression')!.status, GlbCheckStatus.pass);
      expect(_check(report, 'scale')!.status, GlbCheckStatus.pass);
      expect(report.checks.length, 11);
    });

    test('fails scale when the declaration disagrees with the mesh', () {
      final report = validateGlb(
        fixture,
        options: const GlbValidationOptions(externalLengthMm: 285),
      );

      expect(report.passed, isFalse);
      expect(_check(report, 'scale')!.detail, contains('off by 15.0 mm'));
      // Everything but the declared number is still fine — one actionable
      // failure, not a wall of red.
      expect(report.failCount, 1);
    });
  });

  group('format', () {
    test('a file that is not a GLB fails with the export hint', () {
      final glb = _buildGlb(_baseJson());
      glb[0] = 0x50; // 'P' — a .gltf/.zip mistake

      final report = validateGlb(glb);

      expect(report.passed, isFalse);
      expect(_check(report, 'format')!.detail, contains('not a GLB'));
    });

    test('a header-length mismatch fails', () {
      final glb = _buildGlb(_baseJson());
      ByteData.sublistView(glb).setUint32(8, 999, Endian.little);

      final report = validateGlb(glb);

      expect(_check(report, 'format')!.detail, contains('declares 999 bytes'));
    });

    test('a non-2.0 asset version fails', () {
      final json = _baseJson();
      json['asset'] = {'version': '3.0'};

      final report = validateGlb(_buildGlb(json));

      expect(_check(report, 'format')!.detail, contains('asset.version is 3.0'));
    });

    test('a JSON chunk that does not parse fails without throwing', () {
      final report = validateGlb(_buildGlbFromChunks('not json'.codeUnits));

      expect(report.passed, isFalse);
      expect(_check(report, 'format')!.detail, contains('does not parse'));
    });
  });

  group('single file', () {
    test('an external buffer fails', () {
      final json = _baseJson();
      json['buffers'] = [
        {'byteLength': 44, 'uri': 'model.bin'},
      ];

      final report = validateGlb(_buildGlb(json));

      expect(_check(report, 'single file')!.detail, contains('model.bin'));
    });

    test('an external image fails', () {
      final json = _baseJson();
      json['images'] = [
        {'uri': 'textures/upper.png'},
      ];

      final report = validateGlb(_buildGlb(json));

      expect(_check(report, 'single file')!.detail, contains('upper.png'));
    });
  });

  group('budgets', () {
    test('over 60,000 triangles fails', () {
      final json = _baseJson();
      (json['accessors'] as List)[1]['count'] = 180003; // 60,001 triangles

      final report = validateGlb(_buildGlb(json));

      expect(_check(report, 'triangles')!.status, GlbCheckStatus.fail);
      expect(_check(report, 'triangles')!.detail, contains('60,001'));
    });

    test('over the 5 MiB budget fails but over the 8 MiB cap says so', () {
      final overBudget = _buildGlb(
        _baseJson(),
        bin: Uint8List(5 * 1024 * 1024 + 512),
      );
      expect(_check(validateGlb(overBudget), 'file size')!.status,
          GlbCheckStatus.fail);
      expect(_check(validateGlb(overBudget), 'file size')!.detail,
          contains('authoring budget'));

      final overCap = _buildGlb(
        _baseJson(),
        bin: Uint8List(8 * 1024 * 1024 + 512),
      );
      expect(_check(validateGlb(overCap), 'file size')!.detail,
          contains('hard cap'));
    });
  });

  group('materials', () {
    test('a name outside the approved set fails (the Material.001 case)', () {
      final json = _baseJson();
      json['materials'] = [
        {'name': 'upper'},
        {'name': 'Material.001'},
      ];

      final report = validateGlb(_buildGlb(json));

      expect(_check(report, 'materials')!.detail, contains('Material.001'));
    });

    test('a missing required part fails', () {
      final json = _baseJson();
      json['materials'] = [
        {'name': 'upper'},
      ];

      final report = validateGlb(_buildGlb(json));

      expect(_check(report, 'materials')!.detail, contains('sole'));
    });

    test('no materials at all fails with the colour-swap reason', () {
      final json = _baseJson();
      json['materials'] = [];

      final report = validateGlb(_buildGlb(json));

      expect(_check(report, 'materials')!.detail, contains('colour swap'));
    });
  });

  group('textures', () {
    test('a 2048² texture fails', () {
      final json = _baseJson();
      final bin = Uint8List(44 + 24);
      _writePngHeader(bin, 44, 2048, 2048);
      (json['bufferViews'] as List).add(
          {'buffer': 0, 'byteOffset': 44, 'byteLength': 24});
      json['images'] = [
        {'bufferView': 2, 'mimeType': 'image/png'},
      ];

      final report = validateGlb(_buildGlb(json, bin: bin));

      expect(_check(report, 'textures')!.status, GlbCheckStatus.fail);
      expect(_check(report, 'textures')!.detail, contains('2048×2048'));
    });

    test('a 1024² texture passes', () {
      final json = _baseJson();
      final bin = Uint8List(44 + 24);
      _writePngHeader(bin, 44, 1024, 1024);
      (json['bufferViews'] as List).add(
          {'buffer': 0, 'byteOffset': 44, 'byteLength': 24});
      json['images'] = [
        {'bufferView': 2, 'mimeType': 'image/png'},
      ];

      final report = validateGlb(_buildGlb(json, bin: bin));

      expect(_check(report, 'textures')!.status, GlbCheckStatus.pass);
    });
  });

  group('compression gate', () {
    test('Draco is rejected with the V0.7 reason', () {
      final json = _baseJson();
      json['extensionsUsed'] = ['KHR_draco_mesh_compression'];

      final report = validateGlb(_buildGlb(json));

      expect(_check(report, 'compression')!.status, GlbCheckStatus.fail);
      expect(_check(report, 'compression')!.detail, contains('V0.7'));
    });
  });

  group('geometry contract', () {
    test('a millimetre-authored file fails the units check', () {
      final json = _baseJson();
      (json['accessors'] as List)[0]['min'] = [-48, 0, 0];
      (json['accessors'] as List)[0]['max'] = [48, 95, 270];

      final report = validateGlb(_buildGlb(json));

      expect(_check(report, 'units')!.status, GlbCheckStatus.fail);
      expect(_check(report, 'units')!.detail, contains('millimetres'));
    });

    test('a Z-up export fails the orientation check', () {
      final json = _baseJson();
      (json['accessors'] as List)[0]['min'] = [-0.048, 0.0, 0.0];
      (json['accessors'] as List)[0]['max'] = [0.048, 0.270, 0.095];

      final report = validateGlb(_buildGlb(json));

      expect(_check(report, 'orientation')!.status, GlbCheckStatus.fail);
      expect(_check(report, 'orientation')!.detail, contains('long axis is not +Z'));
    });

    test('a sole above the ground plane fails the origin check', () {
      final json = _baseJson();
      (json['accessors'] as List)[0]['min'] = [-0.048, 0.02, 0.0];
      (json['accessors'] as List)[0]['max'] = [0.048, 0.115, 0.27];

      final report = validateGlb(_buildGlb(json));

      expect(_check(report, 'origin')!.status, GlbCheckStatus.fail);
      expect(_check(report, 'origin')!.detail, contains('ground plane'));
    });

    test('an off-centre mesh fails the origin check', () {
      final json = _baseJson();
      (json['accessors'] as List)[0]['min'] = [-0.02, 0.0, 0.0];
      (json['accessors'] as List)[0]['max'] = [0.076, 0.095, 0.27];

      final report = validateGlb(_buildGlb(json));

      expect(_check(report, 'origin')!.detail, contains('off-centre'));
    });

    test('missing POSITION min/max fails rather than silently passing', () {
      final json = _baseJson();
      (json['accessors'] as List)[0].remove('min');
      (json['accessors'] as List)[0].remove('max');

      final report = validateGlb(_buildGlb(json));

      expect(_check(report, 'geometry')!.status, GlbCheckStatus.fail);
      expect(report.passed, isFalse);
    });

    test('a missing declared length fails with the instruction', () {
      final report = validateGlb(
        _buildGlb(_baseJson()),
        options: const GlbValidationOptions(),
      );

      expect(_check(report, 'scale')!.status, GlbCheckStatus.fail);
      expect(_check(report, 'scale')!.detail, contains('external_length_mm'));
    });
  });
}

// ─── Fixture builders ──────────────────────────────────────────────────────

/// A minimal, contract-shaped asset: one triangle, two part names, a
/// 270 mm shoe in metres, grounded and centred.
Map<String, dynamic> _baseJson() => {
      'asset': {'version': '2.0'},
      'scene': 0,
      'scenes': [
        {
          'nodes': [0],
        },
      ],
      'nodes': [
        {'mesh': 0},
      ],
      'meshes': [
        {
          'primitives': [
            {
              'attributes': {'POSITION': 0},
              'indices': 1,
              'material': 0,
            },
          ],
        },
      ],
      'materials': [
        {'name': 'upper'},
        {'name': 'sole'},
      ],
      'accessors': [
        {
          'bufferView': 0,
          'componentType': 5126,
          'count': 3,
          'type': 'VEC3',
          'min': [-0.048, 0.0, 0.0],
          'max': [0.048, 0.095, 0.27],
        },
        {
          'bufferView': 1,
          'componentType': 5123,
          'count': 3,
          'type': 'SCALAR',
        },
      ],
      'bufferViews': [
        {'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
        {'buffer': 0, 'byteOffset': 36, 'byteLength': 6},
      ],
      'buffers': [
        {'byteLength': 44},
      ],
    };

Uint8List _buildGlb(Map<String, dynamic> json, {Uint8List? bin}) =>
    _buildGlbFromChunks(utf8.encode(jsonEncode(json)), bin: bin);

Uint8List _buildGlbFromChunks(List<int> jsonBytes, {Uint8List? bin}) {
  final binary = bin ?? Uint8List(44);
  final paddedJson = [...jsonBytes, ..._padding(jsonBytes.length, ' ')];
  final paddedBin = [...binary, ..._padding(binary.length, '\u0000')];

  final total = 12 +
      8 +
      paddedJson.length +
      (paddedBin.isEmpty ? 0 : 8 + paddedBin.length);
  final out = BytesBuilder();

  final header = ByteData(12)
    ..setUint32(0, kGlbMagic, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, total, Endian.little);
  out.add(header.buffer.asUint8List());

  final jsonHeader = ByteData(8)
    ..setUint32(0, paddedJson.length, Endian.little)
    ..setUint32(4, kJsonChunkType, Endian.little);
  out.add(jsonHeader.buffer.asUint8List());
  out.add(paddedJson);

  if (paddedBin.isNotEmpty) {
    final binHeader = ByteData(8)
      ..setUint32(0, paddedBin.length, Endian.little)
      ..setUint32(4, kBinChunkType, Endian.little);
    out.add(binHeader.buffer.asUint8List());
    out.add(paddedBin);
  }
  return out.toBytes();
}

List<int> _padding(int length, String fill) =>
    List<int>.filled((4 - length % 4) % 4, fill.codeUnitAt(0));

void _writePngHeader(Uint8List bytes, int offset, int width, int height) {
  bytes.setAll(offset, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final data = ByteData.sublistView(bytes);
  data.setUint32(offset + 16, width, Endian.big);
  data.setUint32(offset + 20, height, Endian.big);
}

GlbCheck? _check(GlbValidationReport report, String name) {
  for (final check in report.checks) {
    if (check.name == name) return check;
  }
  return null;
}
