import 'dart:io';
import 'dart:typed_data';

import 'package:app/utils/glb_validator.dart';
import 'package:app/utils/shoe_model_upload.dart';
import 'package:flutter_test/flutter_test.dart';

/// The seller's model upload is a write into a *public* bucket and a table the
/// renderer trusts, so these tests pin the things a mistake would cost: the
/// object path the storage policy demands, the digest that is simultaneously the
/// filename and the cache key, the version arithmetic the partial unique indexes
/// enforce, the reuse decision that stops a re-upload becoming a duplicate row,
/// and the gate that decides whether a file may be published at all.
///
/// The bytes are the real V0 fixture — the only `.glb` in the repo — because a
/// synthetic byte string would prove nothing about the digest or the report.
void main() {
  late Uint8List fixture;

  setUpAll(() {
    fixture = File('assets/models/placeholder_shoe.glb').readAsBytesSync();
  });

  /// A report that passes: no failing rows is exactly what `passed` means, so an
  /// empty check list is a legitimate stand-in when the *gate* is what is under
  /// test rather than the validator.
  GlbValidationReport passingReport({int bytes = 1024}) => GlbValidationReport(
        options: const GlbValidationOptions(),
        fileSizeBytes: bytes,
      );

  ShoeModelAsset assetOf({
    Uint8List? bytes,
    GlbValidationReport? report,
    double? declaredLengthMm = 270,
    String shoeSide = 'right',
  }) =>
      ShoeModelAsset(
        bytes: bytes ?? fixture,
        report: report ?? passingReport(),
        sourceUrl: 'https://example.test/model.glb',
        declaredExternalLengthMm: declaredLengthMm,
        shoeSide: shoeSide,
      );

  group('the digest is the filename', () {
    test('matches the published SHA-256 vectors', () {
      // Known-answer tests, not a mirror of the implementation: these two
      // digests are the standard FIPS 180-4 vectors.
      expect(shoeModelSha256Hex(Uint8List.fromList(const [])),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(shoeModelSha256Hex(Uint8List.fromList('abc'.codeUnits)),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('is exactly the shape the sha256 CHECK constraint accepts', () {
      final digest = shoeModelSha256Hex(fixture);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(digest), isTrue);
    });

    test('is stable for the same bytes and differs for different ones', () {
      final a = shoeModelSha256Hex(fixture);
      final b = shoeModelSha256Hex(Uint8List.fromList(fixture));
      final other = shoeModelSha256Hex(Uint8List.fromList([...fixture, 0]));

      expect(a, b);
      expect(a, isNot(other));
    });
  });

  group('storage path', () {
    test('is <store>/<product>/<sha>.glb', () {
      final digest = shoeModelSha256Hex(fixture);
      expect(
        shoeModelStoragePath(
            storeId: 'store-1', productId: 'product-1', sha256: digest),
        'store-1/product-1/$digest.glb',
      );
    });

    test('starts with the store id — the bucket policy reads that segment', () {
      // The folder-scoped seller-write policy keys on the FIRST segment being a
      // store the caller owns, so this is the property that makes the write
      // permitted; the order is not cosmetic.
      const storeId = '9c1f-store';
      final path = shoeModelStoragePath(
        storeId: storeId,
        productId: 'product-1',
        sha256: shoeModelSha256Hex(fixture),
      );
      expect(path.split('/').first, storeId);
      expect(path.split('/').length, 3);
      expect(path.endsWith('.glb'), isTrue);
    });

    test('the same bytes can only ever land at one path', () {
      final a = shoeModelStoragePath(
        storeId: 'store-1',
        productId: 'product-1',
        sha256: shoeModelSha256Hex(fixture),
      );
      final b = shoeModelStoragePath(
        storeId: 'store-1',
        productId: 'product-1',
        sha256: shoeModelSha256Hex(Uint8List.fromList(fixture)),
      );
      expect(a, b);
    });
  });

  group('version arithmetic honours the partial unique indexes', () {
    test('an empty product starts at version 1', () {
      expect(nextShoeModelVersion(existingRows: const [], variantId: null), 1);
    });

    test('the default target ignores per-variant rows', () {
      // The unique indexes are (product, version) WHERE variant_id IS NULL and
      // (product, variant_id, version) WHERE variant_id IS NOT NULL — two
      // independent sequences, so a colour's v5 cannot push the default to v6.
      final rows = <Map<String, dynamic>>[
        {'variant_id': 'variant-1', 'version': 5},
        {'variant_id': null, 'version': 2},
      ];
      expect(nextShoeModelVersion(existingRows: rows, variantId: null), 3);
      expect(nextShoeModelVersion(existingRows: rows, variantId: 'variant-1'), 6);
    });

    test('a variant target counts only its own rows', () {
      final rows = <Map<String, dynamic>>[
        {'variant_id': null, 'version': 9},
        {'variant_id': 'variant-2', 'version': 1},
      ];
      expect(nextShoeModelVersion(existingRows: rows, variantId: 'variant-2'), 2);
    });

    test('UUID text and BIGINT numbers address the same target', () {
      // The hosted project stores variant ids as UUIDs and a database rebuilt
      // from this repo's lineage stores BIGINTs; the app must not treat one
      // row as belonging to a different target than the other.
      // The stored value can be either type; the target the app passes is the
      // string its own variant selection produces.
      final rows = <Map<String, dynamic>>[
        {'variant_id': 7, 'version': 3},
        {'variant_id': '7', 'version': 4},
      ];
      expect(nextShoeModelVersion(existingRows: rows, variantId: '7'), 5);
      expect(shoeModelVariantKey(7), shoeModelVariantKey('7'));
    });

    test('an unreadable version does not crash the count', () {
      final rows = <Map<String, dynamic>>[
        {'variant_id': null, 'version': 'not a number'},
        {'variant_id': null},
      ];
      expect(nextShoeModelVersion(existingRows: rows, variantId: null), 2);
    });
  });

  group('reuse — re-publishing the same file is a no-op, not a duplicate row', () {
    final digest = hexFilled('a');

    test('the same digest for the same target is a match', () {
      final rows = <Map<String, dynamic>>[
        {'id': 4, 'variant_id': null, 'sha256': digest, 'version': 1},
      ];
      final match =
          shoeModelReuseMatch(existingRows: rows, sha256: digest, variantId: null);
      expect(match?['id'], 4);
    });

    test('a digest stored in upper case still matches', () {
      // The DB CHECK stores lowercase; a hand-written row (or a future server
      // writer) should not be able to defeat the reuse rule.
      final rows = <Map<String, dynamic>>[
        {
          'id': 4,
          'variant_id': null,
          'sha256': digest.toUpperCase(),
          'version': 1,
        },
      ];
      expect(
          shoeModelReuseMatch(
              existingRows: rows, sha256: digest, variantId: null)?['id'],
          4);
    });

    test('the same digest for a different target is not a match', () {
      // The bytes are shared, but the row is not: a colour override and the
      // default are separate entries pointing at one object.
      final rows = <Map<String, dynamic>>[
        {'id': 4, 'variant_id': 'variant-1', 'sha256': digest, 'version': 1},
      ];
      expect(
          shoeModelReuseMatch(
              existingRows: rows, sha256: digest, variantId: null),
          isNull);
    });

    test('different bytes are not a match', () {
      final rows = <Map<String, dynamic>>[
        {'id': 4, 'variant_id': null, 'sha256': hexFilled('b'), 'version': 1},
      ];
      expect(
          shoeModelReuseMatch(
              existingRows: rows, sha256: digest, variantId: null),
          isNull);
    });
  });

  group('row payload', () {
    test('sends nulls explicitly and normalizes the digest', () {
      final row = shoeModelRow(
        productId: 'product-1',
        storagePath: 'store-1/product-1/${hexFilled('a')}.glb',
        sha256: hexFilled('A'),
        version: 2,
      );

      expect(row['product_id'], 'product-1');
      expect(row['variant_id'], isNull);
      expect(row['sha256'], hexFilled('a'));
      expect(row['version'], 2);
      // The app cannot publish: `active` is written by the server validator
      // (V2.4) and refused to every other role by a database trigger, so there
      // is no argument that could make this payload say anything else.
      expect(row['status'], 'draft');
      // Every nullable column is present as null rather than absent: an omitted
      // column and a column meant to be cleared look identical in an insert.
      expect(row.containsKey('authored_length_mm'), isTrue);
      expect(row['authored_length_mm'], isNull);
      expect(row.containsKey('triangle_count'), isTrue);
      expect(row.containsKey('material_map'), isTrue);
    });

    test('records what the validator measured', () {
      final row = shoeModelRow(
        productId: 'product-1',
        storagePath: 'store-1/product-1/x.glb',
        sha256: hexFilled('a'),
        version: 1,
        authoredLengthMm: 275,
        authoredSizeEu: 42,
        triangleCount: 1536,
        fileSizeBytes: fixture.length,
        shoeSide: 'left',
      );
      expect(row['authored_length_mm'], 275);
      expect(row['authored_size_eu'], 42);
      expect(row['triangle_count'], 1536);
      expect(row['file_size_bytes'], fixture.length);
      expect(row['shoe_side'], 'left');
    });

    test('an empty variant id means the product default, not an empty string', () {
      // `product_models_variant_id_not_blank_check` refuses '' — and worse, an
      // empty string would never match the resolver's null default.
      final row = shoeModelRow(
        productId: 'product-1',
        storagePath: 'store-1/product-1/x.glb',
        sha256: hexFilled('a'),
        version: 1,
        variantId: '   ',
      );
      expect(row['variant_id'], isNull);
    });
  });

  group('the asset', () {
    test('reports the validator\'s own numbers, not reformatted prose', () {
      final report = validateGlb(
        fixture,
        options: const GlbValidationOptions(externalLengthMm: 270),
      );
      final asset = ShoeModelAsset(
        bytes: fixture,
        report: report,
        sourceUrl: 'https://example.test/model.glb',
        declaredExternalLengthMm: 270,
      );

      expect(asset.fileSizeBytes, fixture.length);
      expect(asset.triangleCount, 1536);
      expect(asset.meshExternalLengthMm, isNotNull);
      expect(asset.meshExternalLengthMm!, closeTo(270, 5));
      expect(asset.sha256, shoeModelSha256Hex(fixture));
    });

    test('a passing file with a plausible declaration is publishable', () {
      final report = validateGlb(
        fixture,
        options: const GlbValidationOptions(externalLengthMm: 270),
      );
      expect(assetOf(report: report, declaredLengthMm: 270).isPublishable, isTrue);
    });

    test('a failed report is not publishable, whatever else is true', () {
      // The 15 mm scale disagreement the validator already flags.
      final report = validateGlb(
        fixture,
        options: const GlbValidationOptions(externalLengthMm: 285),
      );
      expect(report.passed, isFalse);
      expect(assetOf(report: report, declaredLengthMm: 285).isPublishable,
          isFalse);
    });

    test('a file over the bucket cap is not publishable', () {
      final bytes = Uint8List(kShoeModelBucketCapBytes + 1);
      expect(assetOf(bytes: bytes).isPublishable, isFalse);
    });
  });

  group('the publish gate says why, in words', () {
    test('nothing checked yet', () {
      final gate = shoeModelUploadGate(
        productId: 'product-1',
        asset: null,
        declaration: const ShoeModelDeclarationResult.empty(),
      );
      expect(gate.ready, isFalse);
      expect(gate.blocker, ShoeModelUploadBlocker.validationFailed);
      expect(gate.message, contains('Check a model first'));
    });

    test('a failed contract lists itself in the refusal', () {
      final report = validateGlb(
        fixture,
        options: const GlbValidationOptions(externalLengthMm: 285),
      );
      final gate = shoeModelUploadGate(
        productId: 'product-1',
        asset: assetOf(report: report, declaredLengthMm: 285),
        declaration: const ShoeModelDeclarationResult.empty(),
      );
      expect(gate.blocker, ShoeModelUploadBlocker.validationFailed);
      expect(gate.message, contains('failed'));
    });

    test('a declaration the seller must fix is reported first', () {
      final gate = shoeModelUploadGate(
        productId: 'product-1',
        asset: assetOf(),
        declaration: ShoeModelDeclarationResult.fromFields(
          externalLengthMm: '27',
          authoredSizeEu: '',
        ),
      );
      expect(gate.blocker, ShoeModelUploadBlocker.declarationInvalid);
      expect(gate.message, contains('millimetres'));
    });

    test('a saved product is required even for a passing file', () {
      final gate = shoeModelUploadGate(
        productId: null,
        asset: assetOf(),
        declaration: ShoeModelDeclarationResult.fromFields(
          externalLengthMm: '275',
          authoredSizeEu: '',
        ),
      );
      expect(gate.blocker, ShoeModelUploadBlocker.noProductId);
      expect(gate.message, contains('Save the product first'));
    });

    test('a passing file on a saved product is ready', () {
      final gate = shoeModelUploadGate(
        productId: 'product-1',
        asset: assetOf(),
        declaration: ShoeModelDeclarationResult.fromFields(
          externalLengthMm: '275',
          authoredSizeEu: '',
        ),
      );
      expect(gate.ready, isTrue);
      expect(gate.message, isEmpty);
    });
  });

  group('the declaration', () {
    test('both blank is not an error — the model simply has no declaration', () {
      final result = ShoeModelDeclarationResult.fromFields(
        externalLengthMm: '',
        authoredSizeEu: '',
      );
      expect(result.isError, isFalse);
      expect(result.externalLengthMm, isNull);
      expect(result.authoredSizeEu, isNull);
    });

    test('reads a complete declaration', () {
      final result = ShoeModelDeclarationResult.fromFields(
        externalLengthMm: '283',
        authoredSizeEu: '42',
      );
      expect(result.isError, isFalse);
      expect(result.externalLengthMm, 283);
      expect(result.authoredSizeEu, 42);
    });

    test('names the centimetre slip rather than accepting 27', () {
      final result = ShoeModelDeclarationResult.fromFields(
        externalLengthMm: '27',
        authoredSizeEu: '',
      );
      expect(result.isError, isTrue);
      expect(result.errorField, ShoeModelField.externalLengthMm);
      expect(result.error, contains('not centimetres'));
      expect(result.error, contains('270'));
    });

    test('refuses a US or UK size by name', () {
      final result = ShoeModelDeclarationResult.fromFields(
        externalLengthMm: '275',
        authoredSizeEu: 'US 9',
      );
      expect(result.errorField, ShoeModelField.authoredSizeEu);
      expect(result.error, contains('EU size'));
    });

    test('refuses an authored size outside the band the CHECK enforces', () {
      final result = ShoeModelDeclarationResult.fromFields(
        externalLengthMm: '275',
        authoredSizeEu: '60',
      );
      expect(result.errorField, ShoeModelField.authoredSizeEu);
      expect(result.error, contains('between 22 and 48'));
    });

    test('refuses a size with no length — the scale check needs the length', () {
      final result = ShoeModelDeclarationResult.fromFields(
        externalLengthMm: '',
        authoredSizeEu: '42',
      );
      expect(result.errorField, ShoeModelField.externalLengthMm);
      expect(result.error, contains('declared external length'));
    });

    test('messageFor targets one field only', () {
      final result = ShoeModelDeclarationResult.fromFields(
        externalLengthMm: '27',
        authoredSizeEu: '',
      );
      expect(result.messageFor(ShoeModelField.externalLengthMm), isNotNull);
      expect(result.messageFor(ShoeModelField.authoredSizeEu), isNull);
    });
  });

  group('the source link', () {
    test('accepts https', () {
      expect(isShoeModelSourceUrlAllowed('https://drive.example/x.glb'), isTrue);
    });

    test('refuses cleartext to a real host', () {
      expect(isShoeModelSourceUrlAllowed('http://example.test/x.glb'), isFalse);
    });

    test('allows loopback so a file can be staged locally', () {
      expect(isShoeModelSourceUrlAllowed('http://localhost:8080/x.glb'), isTrue);
      expect(isShoeModelSourceUrlAllowed('http://127.0.0.1/x.glb'), isTrue);
    });

    test('refuses other schemes and empty input', () {
      expect(isShoeModelSourceUrlAllowed('ftp://example.test/x.glb'), isFalse);
      expect(isShoeModelSourceUrlAllowed('file:///tmp/x.glb'), isFalse);
      expect(isShoeModelSourceUrlAllowed(''), isFalse);
      expect(isShoeModelSourceUrlAllowed('   '), isFalse);
      expect(isShoeModelSourceUrlAllowed('not a url'), isFalse);
    });
  });

  group('report copy', () {
    test('the fixture passes, and the headline says how many checks ran', () {
      final report = validateGlb(
        fixture,
        options: const GlbValidationOptions(externalLengthMm: 270),
      );
      expect(report.passed, isTrue);
      expect(shoeModelReportHeadline(report), 'All ${report.checks.length} checks passed');
      expect(shoeModelReportFailures(report), isEmpty);
    });

    test('a failure is named with its own sentence', () {
      final report = validateGlb(
        fixture,
        options: const GlbValidationOptions(externalLengthMm: 285),
      );
      final failures = shoeModelReportFailures(report);
      expect(failures.length, 1);
      expect(failures.first, contains('scale'));
      expect(shoeModelReportHeadline(report), contains('1 of 11 checks failed'));
    });

    test('a green run still states what it cannot see', () {
      expect(kShoeModelPassedLimitsNote, contains('not that it looks right'));
    });
  });

  /// The declared-vs-mesh sentence is now rendered by TWO surfaces — the
  /// seller's product form (V2.2) and the admin's request queue (V2.11, P2) —
  /// which is why it lives in the library rather than in one of them. A drift
  /// between the two would mean the same report said "within tolerance" on one
  /// screen and "4.6 mm under" on the other.
  group('the declared-vs-mesh sentence', () {
    test('inside the contract tolerance it says so, with the gap', () {
      expect(
        shoeModelLengthDeltaSentence(declaredMm: 270, meshMm: 270.4),
        'within tolerance (0.4 mm apart)',
      );
      // Inclusive at the boundary: ±kLengthToleranceMm is the contract's own
      // tolerance, not slightly inside it.
      expect(
        shoeModelLengthDeltaSentence(declaredMm: 270, meshMm: 275),
        'within tolerance (5.0 mm apart)',
      );
    });

    test('outside it, the direction and the distance are named', () {
      expect(
        shoeModelLengthDeltaSentence(declaredMm: 270, meshMm: 264.6),
        '5.4 mm under the declared length',
      );
      expect(
        shoeModelLengthDeltaSentence(declaredMm: 270, meshMm: 278),
        '8.0 mm over the declared length',
      );
    });

    test('the direction reads the MESH against the declaration, both ways', () {
      expect(
        shoeModelLengthDeltaSentence(declaredMm: 300, meshMm: 290),
        startsWith('10.0 mm under'),
      );
      expect(
        shoeModelLengthDeltaSentence(declaredMm: 290, meshMm: 300),
        startsWith('10.0 mm over'),
      );
    });
  });
}

/// A 64-character lowercase hex digest of a repeated nibble — the shape
/// `product_models.sha256`'s CHECK requires, without a real file.
String hexFilled(String nibble) => List.filled(64, nibble).join();
