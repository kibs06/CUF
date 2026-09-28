import 'dart:io';
import 'dart:typed_data';

import 'package:app/exceptions/shoe_model_upload_exception.dart';
import 'package:app/services/shoe_model_server_validator.dart';
import 'package:app/services/shoe_model_upload_service.dart';
import 'package:app/utils/glb_validator.dart';
import 'package:app/utils/shoe_model_upload.dart';
import 'package:flutter_test/flutter_test.dart';

/// The upload service is the only thing that writes a model into the public
/// bucket and the table the renderer reads, so these tests pin the properties a
/// mistake here would break for customers: the bytes land **before** the row
/// that points at them (a row with no object is a failed download on every
/// launch), the digest that names the object is the digest stored beside it, a
/// re-publish of the same file cannot become a duplicate row, and a file that
/// failed the contract is never written at all.
///
/// Both seams are fakes, so nothing here touches a socket or a server — and the
/// bytes are the real V0 fixture, because a synthetic string would not exercise
/// the digest, the report or the row's measured numbers.
void main() {
  late Uint8List fixture;
  const url = 'https://example.test/handover/model.glb';

  setUpAll(() {
    fixture = File('assets/models/placeholder_shoe.glb').readAsBytesSync();
  });

  /// The fixture declared at the length it was authored at — the one
  /// configuration that passes every check.
  GlbValidationReport passingReport() => validateGlb(
        fixture,
        options: const GlbValidationOptions(externalLengthMm: 270),
      );

  ShoeModelAsset passingAsset() => ShoeModelAsset(
        bytes: fixture,
        report: passingReport(),
        sourceUrl: url,
        declaredExternalLengthMm: 270,
        authoredSizeEu: 42,
      );

  ShoeModelUploadService serviceWith(
    _FakeBytesSource source,
    _FakeUploadDataSource data, {
    ShoeModelServerVerdict? verdict,
  }) =>
      ShoeModelUploadService(
        bytesSource: source,
        dataSource: data,
        serverValidator: _FakeServerValidator(verdict: verdict),
      );

  group('fetch and check', () {
    test('refuses a link that is not https, without fetching it', () async {
      final source = _FakeBytesSource();
      final service = serviceWith(source, _FakeUploadDataSource());

      await expectLater(
        service.fetchAndValidate(url: 'http://example.test/model.glb'),
        throwsA(isA<ShoeModelUploadException>()),
      );
      expect(source.requested, isEmpty,
          reason: 'a refused scheme must not reach the network');
    });

    test('returns a passing asset for a compliant file', () async {
      final source = _FakeBytesSource()..files[url] = fixture;
      final service = serviceWith(source, _FakeUploadDataSource());

      final asset = await service.fetchAndValidate(
        url: url,
        declaredExternalLengthMm: 270,
      );

      expect(asset.report.passed, isTrue);
      expect(asset.sha256, shoeModelSha256Hex(fixture));
      expect(asset.fileSizeBytes, fixture.length);
      expect(asset.triangleCount, 1536);
      expect(asset.isPublishable, isTrue);
      expect(source.requested, [url]);
    });

    test('a contract failure is a report, not an exception', () async {
      // The seller has to read which rows failed — throwing here would turn the
      // one useful output of the check into a snackbar.
      final source = _FakeBytesSource()..files[url] = fixture;
      final service = serviceWith(source, _FakeUploadDataSource());

      final asset = await service.fetchAndValidate(
        url: url,
        declaredExternalLengthMm: 285,
      );

      expect(asset.report.passed, isFalse);
      expect(shoeModelReportFailures(asset.report).single, contains('scale'));
      expect(asset.isPublishable, isFalse);
    });

    test('a transport failure surfaces the fetcher\'s own sentence', () async {
      final source = _FakeBytesSource()
        ..throwThis = ShoeModelUploadException('That link returned 404.');
      final service = serviceWith(source, _FakeUploadDataSource());

      await expectLater(
        service.fetchAndValidate(url: url),
        throwsA(isA<ShoeModelUploadException>()
            .having((e) => e.message, 'message', contains('404'))),
      );
    });
  });

  group('publish', () {
    test('writes the bytes before the row that points at them', () async {
      final data = _FakeUploadDataSource();
      final service = serviceWith(_FakeBytesSource(), data);

      await service.publish(
        storeId: 'store-1',
        productId: 'product-1',
        asset: passingAsset(),
      );

      expect(data.order, ['put', 'insert'],
          reason: 'a row whose object is missing is a failed download forever');
      expect(data.uploadedBytes.single, fixture);
    });

    test('stores the digest that names the object, and the measured numbers',
        () async {
      final data = _FakeUploadDataSource();
      final service = serviceWith(_FakeBytesSource(), data);
      final digest = shoeModelSha256Hex(fixture);

      final outcome = await service.publish(
        storeId: 'store-1',
        productId: 'product-1',
        asset: passingAsset(),
      );

      expect(outcome.storagePath, 'store-1/product-1/$digest.glb');
      expect(outcome.version, 1);
      expect(outcome.reusedExisting, isFalse);
      // The status now comes from the server's answer, not from the caller.
      expect(outcome.status, 'active');
      expect(outcome.serverVerdict?.outcome, ShoeModelServerOutcome.validated);

      final row = data.inserts.single;
      expect(row['product_id'], 'product-1');
      expect(row['variant_id'], isNull);
      expect(row['storage_path'], outcome.storagePath);
      expect(row['sha256'], digest);
      expect(row['version'], 1);
      expect(
        row['status'],
        'draft',
        reason: 'only the server validator may write active (V2.4)',
      );
      expect(row['authored_length_mm'], 270);
      expect(row['authored_size_eu'], 42);
      expect(row['triangle_count'], 1536);
      expect(row['file_size_bytes'], fixture.length);
      expect(row['shoe_side'], 'right');
    });

    test('a held-back model is written as a draft, and the server is not asked',
        () async {
      final data = _FakeUploadDataSource();
      final validator = _FakeServerValidator();
      final service = ShoeModelUploadService(
        bytesSource: _FakeBytesSource(),
        dataSource: data,
        serverValidator: validator,
      );

      final outcome = await service.publish(
        storeId: 'store-1',
        productId: 'product-1',
        asset: passingAsset(),
        active: false,
      );

      expect(outcome.status, 'draft');
      expect(outcome.serverVerdict, isNull);
      expect(data.inserts.single['status'], 'draft');
      expect(validator.askedModelIds, isEmpty,
          reason: 'a draft is not a decision to publish');
    });

    test('a second, different file becomes version 2 for the same target',
        () async {
      final digest = shoeModelSha256Hex(fixture);
      final data = _FakeUploadDataSource(rows: [
        {
          'id': 1,
          'variant_id': null,
          'sha256': digest,
          'version': 1,
          'storage_path': 'store-1/product-1/$digest.glb',
          'status': 'active',
        },
      ]);
      final service = serviceWith(_FakeBytesSource(), data);

      // Different bytes, so no reuse: a new object, and the version must move.
      // The report is hand-made (no failing rows is what `passed` means) because
      // this test is about version arithmetic — whether the *file* is a valid
      // GLB is what `glb_validator_test.dart` owns, and the bytes here only have
      // to differ from the first file's.
      final changed = Uint8List.fromList([...fixture, 0]);
      expect(shoeModelSha256Hex(changed), isNot(digest));
      final outcome = await service.publish(
        storeId: 'store-1',
        productId: 'product-1',
        asset: ShoeModelAsset(
          bytes: changed,
          report: GlbValidationReport(
            options: const GlbValidationOptions(),
            fileSizeBytes: changed.length,
          ),
          sourceUrl: url,
          declaredExternalLengthMm: 270,
        ),
      );

      expect(outcome.version, 2);
      expect(data.inserts.single['version'], 2);
    });

    test('re-publishing the same bytes is a no-op, not a duplicate row',
        () async {
      final digest = shoeModelSha256Hex(fixture);
      final data = _FakeUploadDataSource(rows: [
        {
          'id': 7,
          'variant_id': null,
          'sha256': digest,
          'version': 1,
          'storage_path': 'store-1/product-1/$digest.glb',
          'status': 'active',
        },
      ]);
      final service = serviceWith(_FakeBytesSource(), data);

      final outcome = await service.publish(
        storeId: 'store-1',
        productId: 'product-1',
        asset: passingAsset(),
      );

      expect(outcome.reusedExisting, isTrue);
      expect(outcome.version, 1);
      expect(data.inserts, isEmpty);
      expect(data.order, isEmpty,
          reason: 'the object is already in the bucket at that digest');
      expect(data.statusUpdates, isEmpty,
          reason: 'the row is already active — nothing to change');
      expect(outcome.summary, contains('reused'));
    });

    test('re-publishing a draft asks the server to judge it in place',
        () async {
      final digest = shoeModelSha256Hex(fixture);
      final data = _FakeUploadDataSource(rows: [
        {
          'id': 7,
          'variant_id': null,
          'sha256': digest,
          'version': 3,
          'storage_path': 'store-1/product-1/$digest.glb',
          'status': 'draft',
        },
      ]);
      final validator = _FakeServerValidator();
      final service = ShoeModelUploadService(
        bytesSource: _FakeBytesSource(),
        dataSource: data,
        serverValidator: validator,
      );

      final outcome = await service.publish(
        storeId: 'store-1',
        productId: 'product-1',
        asset: passingAsset(),
      );

      expect(outcome.reusedExisting, isTrue);
      expect(outcome.status, 'active');
      expect(validator.askedModelIds, [7]);
      expect(data.inserts, isEmpty);
      expect(
        data.statusUpdates,
        isEmpty,
        reason: 'the client does not write active — the server does, and the '
            'database refuses it from a signed-in session',
      );
    });

    test('the server refusing a model is reported, not thrown', () async {
      final data = _FakeUploadDataSource();
      final service = serviceWith(
        _FakeBytesSource(),
        data,
        verdict: const ShoeModelServerVerdict(
          outcome: ShoeModelServerOutcome.rejected,
          status: 'rejected',
          failedChecks: ['materials', 'scale'],
        ),
      );

      final outcome = await service.publish(
        storeId: 'store-1',
        productId: 'product-1',
        asset: passingAsset(),
      );

      expect(outcome.status, 'rejected');
      expect(outcome.serverVerdict?.refused, isTrue);
      expect(outcome.summary, contains('refused'));
      expect(
        outcome.serverVerdict?.sellerMessage,
        contains('materials, scale'),
        reason: 'the seller is told which rows to fix',
      );
      expect(outcome.row['status'], 'rejected');
    });

    test('no verdict from the server leaves the model a draft, with a sentence',
        () async {
      final data = _FakeUploadDataSource();
      final service = serviceWith(
        _FakeBytesSource(),
        data,
        verdict: const ShoeModelServerVerdict.undetermined('HTTP 503'),
      );

      final outcome = await service.publish(
        storeId: 'store-1',
        productId: 'product-1',
        asset: passingAsset(),
      );

      expect(outcome.status, 'draft');
      expect(outcome.serverVerdict?.sellerMessage, contains('HTTP 503'));
      expect(outcome.summary, contains('draft'));
    });

    test('a row that reports no id is never judged, and never active', () async {
      // `insert ... select()` is what returns the id; if a deployment or a
      // change stops returning it, the model must stay hidden rather than be
      // assumed published.
      final data = _FakeUploadDataSource(withoutIds: true);
      final validator = _FakeServerValidator();
      final service = ShoeModelUploadService(
        bytesSource: _FakeBytesSource(),
        dataSource: data,
        serverValidator: validator,
      );

      final outcome = await service.publish(
        storeId: 'store-1',
        productId: 'product-1',
        asset: passingAsset(),
      );

      expect(outcome.status, 'draft');
      expect(validator.askedModelIds, isEmpty);
      expect(outcome.serverVerdict?.sellerMessage, isNotNull);
    });

    test('refuses a file that failed the contract', () async {
      final data = _FakeUploadDataSource();
      final service = serviceWith(_FakeBytesSource(), data);
      final failed = ShoeModelAsset(
        bytes: fixture,
        report: validateGlb(fixture,
            options: const GlbValidationOptions(externalLengthMm: 285)),
        sourceUrl: url,
        declaredExternalLengthMm: 285,
      );

      await expectLater(
        service.publish(
            storeId: 'store-1', productId: 'product-1', asset: failed),
        throwsA(isA<ShoeModelUploadException>()),
      );
      expect(data.order, isEmpty);
    });

    test('refuses a blank store id, because the bucket policy compares it',
        () async {
      final data = _FakeUploadDataSource();
      final service = serviceWith(_FakeBytesSource(), data);

      await expectLater(
        service.publish(
          storeId: '   ',
          productId: 'product-1',
          asset: passingAsset(),
        ),
        throwsA(isA<ShoeModelUploadException>()),
      );
      expect(data.order, isEmpty);
    });

    test('a padded store id is trimmed, so the policy sees the real store id',
        () async {
      // The first path segment is compared against the stored store id, so the
      // path must carry the id itself — refusing whitespace would refuse a write
      // storage would have accepted.
      final data = _FakeUploadDataSource();
      final service = serviceWith(_FakeBytesSource(), data);
      final digest = shoeModelSha256Hex(fixture);

      final outcome = await service.publish(
        storeId: ' store-1 ',
        productId: 'product-1',
        asset: passingAsset(),
      );

      expect(outcome.storagePath, 'store-1/product-1/$digest.glb');
      expect(data.putPaths.single, outcome.storagePath);
    });
  });

  group('the source link', () {
    test('the production wiring exists and is one object', () {
      // Guards the seam the screen falls back to when no service is injected.
      expect(ShoeModelUploadService.createDefault(), isA<ShoeModelUploadService>());
    });
  });
}

/// Bytes for a URL, or a thrown exception — the socket, in memory.
class _FakeBytesSource implements ShoeModelBytesSource {
  final Map<String, Uint8List> files = {};
  final List<String> requested = [];
  Object? throwThis;

  @override
  Future<Uint8List> fetch(String url) async {
    requested.add(url);
    final failure = throwThis;
    if (failure != null) throw failure;
    final bytes = files[url];
    if (bytes == null) {
      throw ShoeModelUploadException('No file at that link.');
    }
    return bytes;
  }
}

/// The server validator (V2.4), in memory. The default is the answer the real
/// function gives for a compliant file, so a test that is about the write path
/// does not have to restate it.
class _FakeServerValidator implements ShoeModelServerValidator {
  final ShoeModelServerVerdict verdict;
  final List<int> askedModelIds = [];

  _FakeServerValidator({ShoeModelServerVerdict? verdict})
      : verdict = verdict ??
            const ShoeModelServerVerdict(
              outcome: ShoeModelServerOutcome.validated,
              status: 'active',
            );

  @override
  Future<ShoeModelServerVerdict> validate({
    required int modelId,
    bool activate = true,
  }) async {
    askedModelIds.add(modelId);
    return verdict;
  }
}

/// The bucket and the table, in memory. Every write is recorded, including the
/// order of them, because "bytes before row" is a property of this service and
/// not of its callers; `withoutIds` models a write that does not report the id
/// it created, which is the case the publisher must refuse to guess about.
class _FakeUploadDataSource implements ShoeModelUploadDataSource {
  final List<Map<String, dynamic>> rows;
  final bool withoutIds;
  final List<String> order = [];
  final List<String> putPaths = [];
  final List<Uint8List> uploadedBytes = [];
  final List<Map<String, dynamic>> inserts = [];
  final List<({int id, String status})> statusUpdates = [];

  _FakeUploadDataSource({List<Map<String, dynamic>>? rows, this.withoutIds = false})
      : rows = rows ?? <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> rowsFor(String productId) async => rows;

  @override
  Future<void> putBytes({
    required String storagePath,
    required Uint8List bytes,
  }) async {
    order.add('put');
    putPaths.add(storagePath);
    uploadedBytes.add(bytes);
  }

  @override
  Future<Map<String, dynamic>> insertRow(Map<String, dynamic> row) async {
    order.add('insert');
    inserts.add(row);
    return withoutIds ? {...row} : {...row, 'id': 11};
  }

  @override
  Future<void> updateStatus({required int id, required String status}) async {
    statusUpdates.add((id: id, status: status));
  }
}
