import 'package:app/utils/shoe_model_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// The resolver decides *which* shoe a customer sees. These tests pin the
/// two halves of that decision: what makes a row usable at all, and what
/// wins when several usable rows exist.
void main() {
  /// A lowercase 64-char digest. `product_models.sha256`'s CHECK requires
  /// exactly this shape.
  String goodSha([String seed = 'a']) => List.filled(64, seed).join();

  Map<String, dynamic> row({
    Object? id = 1,
    Object? variantId,
    Object? storagePath = 'store-1/product-1/model.glb',
    Object? sha256,
    Object? version,
    Object? authoredSizeEu = 42,
    Object? authoredLengthMm = 285,
    Object? shoeSide = 'right',
    Object? materialMap,
    Object? alignmentJson,
    Object? triangleCount = 12400,
    Object? fileSizeBytes = 2100000,
  }) {
    return <String, dynamic>{
      'id': id,
      'variant_id': variantId,
      'storage_path': storagePath,
      'sha256': sha256 ?? goodSha(),
      'version': version,
      'authored_size_eu': authoredSizeEu,
      'authored_length_mm': authoredLengthMm,
      'shoe_side': shoeSide,
      'material_map': materialMap,
      'alignment_json': alignmentJson,
      'triangle_count': triangleCount,
      'file_size_bytes': fileSizeBytes,
    };
  }

  group('ShoeModelSpec.fromRow', () {
    test('parses a complete row field by field', () {
      final spec = ShoeModelSpec.fromRow(
        row(
          id: 7,
          variantId: 'variant-21',
          version: 3,
          storagePath: 'store-1/product-1/abc.glb',
          sha256: goodSha('f'),
          materialMap: {
            'Black': {
              'upper': {'baseColorHex': '#111111', 'metallic': 0.1},
            },
          },
          alignmentJson: {'heelOffsetMm': 2.5, 'yawOffsetDeg': -4},
          triangleCount: 42000,
          fileSizeBytes: 3145728,
        ),
      );

      expect(spec, isNotNull);
      expect(spec!.id, 7);
      expect(spec.variantId, 'variant-21');
      expect(spec.storagePath, 'store-1/product-1/abc.glb');
      expect(spec.sha256, goodSha('f'));
      expect(spec.version, 3);
      expect(spec.authoredSizeEu, 42);
      expect(spec.authoredLengthMm, 285);
      expect(spec.shoeSide, 'right');
      expect(spec.materialMap, isNotNull);
      expect(spec.alignmentJson, isNotNull);
      expect(spec.triangleCount, 42000);
      expect(spec.fileSizeBytes, 3145728);
    });

    test('normalizes an uppercase digest and trims a padded path', () {
      final spec = ShoeModelSpec.fromRow(
        row(sha256: goodSha('A'), storagePath: '  store-1/p/sha.glb  '),
      );

      expect(spec, isNotNull);
      expect(spec!.sha256, goodSha('a'));
      expect(spec.storagePath, 'store-1/p/sha.glb');
    });

    test('refuses rows that cannot render, one reason at a time', () {
      final cases = <String, Map<String, dynamic>>{
        'no id': row(id: null),
        'id is not a number': row(id: 'seven'),
        'blank storage path': row(storagePath: '   '),
        'no storage path': row(storagePath: null),
        'digest too short': row(sha256: 'abc123'),
        'digest with non-hex characters':
            row(sha256: List.filled(64, 'z').join()),
        'unknown shoe side': row(shoeSide: 'middle'),
      };

      cases.forEach((why, badRow) {
        expect(
          ShoeModelSpec.fromRow(badRow),
          isNull,
          reason: '$why must make the row unusable, not repairable',
        );
      });
    });

    test('defaults version to 1 and repairs a nonsensical one', () {
      expect(ShoeModelSpec.fromRow(row())!.version, 1);
      expect(ShoeModelSpec.fromRow(row(version: 0))!.version, 1);
      expect(ShoeModelSpec.fromRow(row(version: 'nope'))!.version, 1);
      expect(ShoeModelSpec.fromRow(row(version: 4))!.version, 4);
    });

    test('normalizes a numeric variant id from the BIGINT lineage', () {
      // The hosted project stores variant ids as UUIDs and a database built
      // from this repo's migrations stores them as BIGINTs; the app carries
      // both as strings, so both must resolve to the same value.
      expect(ShoeModelSpec.fromRow(row(variantId: 12))!.variantId, '12');
      expect(
        ShoeModelSpec.fromRow(row(variantId: '  '))!.variantId,
        isNull,
        reason: 'an empty override is absent, not a match-anything id',
      );
    });

    test('defaults shoe_side to right when the column is absent', () {
      expect(ShoeModelSpec.fromRow(row(shoeSide: null))!.shoeSide, 'right');
    });

    test('degrades unreadable optional fields to null and still parses', () {
      final spec = ShoeModelSpec.fromRow(
        row(
          authoredSizeEu: '42',
          authoredLengthMm: null,
          triangleCount: 12.75,
          fileSizeBytes: 'big',
          materialMap: 'not a map',
          alignmentJson: 5,
        ),
      );

      expect(spec, isNotNull);
      expect(spec!.authoredSizeEu, isNull);
      expect(spec.authoredLengthMm, isNull);
      expect(spec.triangleCount, 12);
      expect(spec.fileSizeBytes, isNull);
      expect(spec.materialMap, isNull);
      expect(spec.alignmentJson, isNull);
    });
  });

  group('resolveShoeModel', () {
    ShoeModelSpec spec(int id, {String? variantId, int version = 1}) =>
        ShoeModelSpec(
          id: id,
          variantId: variantId,
          storagePath: 'store/p/$id.glb',
          sha256: List.filled(64, 'a').join(),
          version: version,
        );

    test('a per-colour override wins over the product default', () {
      final chosen = resolveShoeModel(
        models: [spec(1), spec(2, variantId: 'v-7')],
        variantId: 'v-7',
      );
      expect(chosen?.id, 2);
    });

    test('a colour without its own override falls back to the default', () {
      final chosen = resolveShoeModel(
        models: [spec(1), spec(2, variantId: 'v-7')],
        variantId: 'v-8',
      );
      expect(chosen?.id, 1);
    });

    test('never borrows another colour\'s asset', () {
      final chosen = resolveShoeModel(
        models: [spec(2, variantId: 'v-7')],
        variantId: 'v-8',
      );
      expect(chosen, isNull);
    });

    test('with no variant selected, only the default is a candidate', () {
      final chosen = resolveShoeModel(
        models: [spec(2, variantId: 'v-7')],
        variantId: null,
      );
      expect(chosen, isNull);
    });

    test('no models at all resolves to nothing', () {
      expect(resolveShoeModel(models: const [], variantId: 'v-7'), isNull);
    });

    test('the newest version wins within the chosen group', () {
      final chosen = resolveShoeModel(
        models: [
          spec(1, variantId: 'v-7', version: 2),
          spec(2, variantId: 'v-7', version: 5),
          spec(3, variantId: 'v-7', version: 4),
        ],
        variantId: 'v-7',
      );
      expect(chosen?.id, 2);
    });

    test('same version is broken deterministically by the higher id', () {
      final chosen = resolveShoeModel(
        models: [spec(3, version: 2), spec(9, version: 2)],
        variantId: null,
      );
      expect(chosen?.id, 9);
    });
  });

  group('parseShoeModelRows', () {
    test('drops unusable rows without dropping the rest', () {
      final specs = parseShoeModelRows([
        row(id: 1),
        row(id: null), // unusable
        row(id: 2, sha256: 'nope'), // unusable
        row(id: 3, variantId: 'v-9'),
      ]);

      expect(specs.map((s) => s.id), [1, 3]);
    });
  });
}
