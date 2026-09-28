import 'dart:io';
import 'dart:typed_data';

import 'package:app/services/shoe_model_service.dart';
import 'package:app/services/try_on_prefetch.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// The prefetch warms a cache while the customer is reading a product page, so
/// its one non-negotiable property is that **nothing it can be given makes it
/// throw**: not a missing table, not a dead network, not a hash mismatch, not an
/// unwritable cache folder. `ShoeModelService` is strict on purpose (serving an
/// unverified model is worse than serving none) — this class is the policy that
/// makes that strictness invisible to a page the customer is using.
///
/// The second property is that a failure is still a *result*: every outcome the
/// page ignores is one a log can read, so "silent" never means "unexplained".
void main() {
  late Directory tempRoot;
  late Directory cacheDir;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('try_on_prefetch_test');
    cacheDir = Directory('${tempRoot.path}${Platform.pathSeparator}cache');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) await tempRoot.delete(recursive: true);
  });

  Uint8List bytesOf(int length) =>
      Uint8List.fromList(List<int>.generate(length, (i) => (i * 11) % 256));

  String shaOf(List<int> bytes) => sha256.convert(bytes).toString();

  /// A `product_models` row shaped like the hosted table's.
  Map<String, dynamic> rowFor(Uint8List bytes, {int id = 1, int version = 1}) => {
        'id': id,
        'variant_id': null,
        'storage_path': 'store-1/product-1/model.glb',
        'sha256': shaOf(bytes),
        'version': version,
        'shoe_side': 'right',
      };

  TryOnPrefetch prefetchWith(
    _FakeModelSource source, {
    bool enabled = true,
    Future<Directory> Function()? cache,
  }) =>
      TryOnPrefetch(
        enabled: enabled,
        models: ShoeModelService(
          dataSource: source,
          cacheDirectoryProvider: cache ?? () async => cacheDir,
        ),
      );

  group('the switch is the first gate', () {
    test('off means no read and no download', () async {
      final source = _FakeModelSource()..rows = [rowFor(bytesOf(64))];

      final result = await prefetchWith(source, enabled: false)
          .prefetch(productId: 'product-1');

      expect(result.outcome, TryOnPrefetchOutcome.disabled);
      expect(result.hasLocalModel, isFalse);
      expect(source.rowsCalls, 0,
          reason: 'a disabled prefetch must not touch the model table');
      expect(source.downloadCalls, 0);
      expect(result.summary, contains('off'));
    });
  });

  group('the happy path', () {
    test('downloads, verifies and caches a model', () async {
      final bytes = bytesOf(128);
      final source = _FakeModelSource()
        ..rows = [rowFor(bytes)]
        ..files = {'store-1/product-1/model.glb': bytes};

      final result = await prefetchWith(source).prefetch(productId: 'product-1');

      expect(result.outcome, TryOnPrefetchOutcome.downloaded);
      expect(result.hasLocalModel, isTrue);
      expect(result.spec?.version, 1);
      expect(File(result.path!).existsSync(), isTrue);
      expect(File(result.path!).readAsBytesSync(), bytes);
      expect(source.downloadCalls, 1);
    });

    test('a second prefetch is a cache hit, not a second download', () async {
      final bytes = bytesOf(128);
      final source = _FakeModelSource()
        ..rows = [rowFor(bytes)]
        ..files = {'store-1/product-1/model.glb': bytes};
      final prefetch = prefetchWith(source);

      await prefetch.prefetch(productId: 'product-1');
      final second = await prefetch.prefetch(productId: 'product-1');

      expect(second.outcome, TryOnPrefetchOutcome.alreadyCached);
      expect(source.downloadCalls, 1);
      expect(second.summary, contains('already cached'));
    });

    test('concurrent prefetches for one selection share one read', () async {
      final bytes = bytesOf(64);
      final source = _FakeModelSource()
        ..rows = [rowFor(bytes)]
        ..files = {'store-1/product-1/model.glb': bytes};
      final prefetch = prefetchWith(source);

      final results = await Future.wait([
        prefetch.prefetch(productId: 'product-1'),
        prefetch.prefetch(productId: 'product-1'),
        prefetch.prefetch(productId: 'product-1'),
      ]);

      expect(results.map((r) => r.outcome).toSet().length, 1);
      expect(source.rowsCalls, 1,
          reason: 'one page view must not become three table reads');
    });
  });

  group('every failure is a result, never an exception', () {
    test('a product with no models', () async {
      final result = await prefetchWith(_FakeModelSource())
          .prefetch(productId: 'product-1');

      expect(result.outcome, TryOnPrefetchOutcome.noModel);
      expect(result.hasLocalModel, isFalse);
      expect(result.cause, isNull);
    });

    test('the table not being applied — the shipped state of V2', () async {
      // `42P01: relation "product_models" does not exist`, which is exactly what
      // a build with the upload switch on but the migration un-applied would hit.
      final source = _FakeModelSource()
        ..rowsError = Exception('relation "product_models" does not exist');

      final result = await prefetchWith(source).prefetch(productId: 'product-1');

      expect(result.outcome, TryOnPrefetchOutcome.failed);
      expect(result.cause, isNotNull);
      expect(result.summary, contains('prefetch failed'));
    });

    test('a network failure while reading the rows', () async {
      final source = _FakeModelSource()
        ..rowsError = const SocketException('no route to host');

      final result = await prefetchWith(source).prefetch(productId: 'product-1');

      expect(result.outcome, TryOnPrefetchOutcome.failed);
    });

    test('a storage download that 404s', () async {
      final source = _FakeModelSource()
        ..rows = [rowFor(bytesOf(64))];

      final result = await prefetchWith(source).prefetch(productId: 'product-1');

      expect(result.outcome, TryOnPrefetchOutcome.failed);
      expect(result.spec, isNotNull,
          reason: 'the model resolved; the download is what failed');
      expect(result.hasLocalModel, isFalse);
    });

    test('bytes that do not hash to their row', () async {
      // The row promises one digest, storage serves another — the case that must
      // never become a cache hit.
      final good = bytesOf(64);
      final swapped = bytesOf(64);
      swapped[0] = swapped[0] ^ 0xFF;
      final source = _FakeModelSource()
        ..rows = [rowFor(good)]
        ..files = {'store-1/product-1/model.glb': swapped};

      final result = await prefetchWith(source).prefetch(productId: 'product-1');

      expect(result.outcome, TryOnPrefetchOutcome.failed);
      expect(result.path, isNull);
      expect(cacheDir.existsSync() ? cacheDir.listSync() : const [], isEmpty,
          reason: 'nothing unverified is ever written to the cache');
    });

    test('a cache directory that cannot be created', () async {
      final bytes = bytesOf(64);
      final source = _FakeModelSource()
        ..rows = [rowFor(bytes)]
        ..files = {'store-1/product-1/model.glb': bytes};

      final result = await prefetchWith(
        source,
        cache: () async => throw const FileSystemException('read-only'),
      ).prefetch(productId: 'product-1');

      expect(result.outcome, TryOnPrefetchOutcome.failed);
    });

    test('a row the resolver drops is not a model, and not an error', () async {
      // A malformed digest cannot be verified, so it cannot be rendered — the
      // resolver drops it and the product simply has no model.
      final source = _FakeModelSource()
        ..rows = [
          {
            'id': 1,
            'storage_path': 'store-1/product-1/model.glb',
            'sha256': 'not-a-digest',
            'version': 1,
          },
        ];

      final result = await prefetchWith(source).prefetch(productId: 'product-1');

      expect(result.outcome, TryOnPrefetchOutcome.noModel);
    });
  });
}

/// The read seam, in memory: rows from a list, bytes from a map, and an
/// optional error for each side so a test can make either one fail.
class _FakeModelSource implements ShoeModelDataSource {
  List<Map<String, dynamic>> rows = [];
  Map<String, Uint8List> files = {};
  Object? rowsError;
  Object? downloadError;
  int rowsCalls = 0;
  int downloadCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> activeModelRows(String productId) async {
    rowsCalls++;
    final failure = rowsError;
    if (failure != null) throw failure;
    return rows;
  }

  @override
  Future<Uint8List> download(String storagePath) async {
    downloadCalls++;
    final failure = downloadError;
    if (failure != null) throw failure;
    final bytes = files[storagePath];
    if (bytes == null) {
      throw Exception('Object not found: $storagePath');
    }
    return bytes;
  }
}
