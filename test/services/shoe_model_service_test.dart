import 'dart:io';
import 'dart:typed_data';

import 'package:app/exceptions/shoe_model_integrity_exception.dart';
import 'package:app/services/shoe_model_service.dart';
import 'package:app/utils/shoe_model_resolver.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// `ShoeModelService` is the only thing between the `shoe-models` bucket
/// and the renderer's local file path, so these tests pin the properties a
/// broken cache would violate: no unverified bytes are ever served, a cache
/// hit costs no download, a corrupt entry repairs itself, and the folder
/// respects its byte budget.
void main() {
  late Directory tempRoot;
  late Directory cacheDir;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('shoe_model_cache_test');
    cacheDir = Directory('${tempRoot.path}${Platform.pathSeparator}cache');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Uint8List bytesOf(int length, {int seed = 0}) => Uint8List.fromList(
        List<int>.generate(length, (i) => (i * 7 + seed) % 256),
      );

  String shaOf(List<int> bytes) => sha256.convert(bytes).toString();

  /// A valid lowercase 64-char digest, for rows that never reach download.
  String goodSha([String seed = 'a']) => List.filled(64, seed).join();

  ShoeModelSpec specFor(
    Uint8List bytes, {
    int id = 1,
    int version = 1,
    String storagePath = 'store-1/product-1/model.glb',
  }) =>
      ShoeModelSpec(
        id: id,
        storagePath: storagePath,
        sha256: shaOf(bytes),
        version: version,
      );

  ShoeModelService serviceWith(
    _FakeSource source, {
    int budget = 1 << 20,
  }) =>
      ShoeModelService(
        dataSource: source,
        cacheDirectoryProvider: () async => cacheDir,
        budgetBytes: budget,
      );

  group('download, verify, cache', () {
    test('downloads a model, verifies it and writes it to the cache', () async {
      final bytes = bytesOf(120);
      final spec = specFor(bytes);
      final source = _FakeSource({spec.storagePath: bytes});
      final service = serviceWith(source);

      final file = await service.ensureLocal(spec);

      expect(file.fromCache, isFalse);
      expect(file.bytes, 120);
      expect(file.path, ShoeModelService.cachePathFor(spec, cacheDir));
      expect(File(file.path).existsSync(), isTrue);
      expect(File(file.path).readAsBytesSync(), bytes);
      expect(source.downloads, 1);
    });

    test('a valid cache entry is a hit and costs no download', () async {
      final bytes = bytesOf(64);
      final spec = specFor(bytes);
      final source = _FakeSource({spec.storagePath: bytes});
      final service = serviceWith(source);

      await service.ensureLocal(spec);
      final second = await service.ensureLocal(spec);

      expect(second.fromCache, isTrue);
      expect(source.downloads, 1);
    });

    test('force re-downloads even when a valid entry exists', () async {
      final bytes = bytesOf(64);
      final spec = specFor(bytes);
      final source = _FakeSource({spec.storagePath: bytes});
      final service = serviceWith(source);

      await service.ensureLocal(spec);
      await service.ensureLocal(spec, force: true);

      expect(source.downloads, 2);
    });

    test('a corrupted cache entry is replaced, not served', () async {
      final bytes = bytesOf(200);
      final spec = specFor(bytes);
      final source = _FakeSource({spec.storagePath: bytes});
      final service = serviceWith(source);

      await service.ensureLocal(spec);
      // Simulate a truncated/overwritten file on disk.
      File(ShoeModelService.cachePathFor(spec, cacheDir))
          .writeAsBytesSync(bytesOf(200, seed: 99));

      final repaired = await service.ensureLocal(spec);

      expect(repaired.fromCache, isFalse);
      expect(source.downloads, 2);
      expect(File(repaired.path).readAsBytesSync(), bytes);
    });

    test('concurrent requests for one model download it once', () async {
      final bytes = bytesOf(64);
      final spec = specFor(bytes);
      final source = _FakeSource({spec.storagePath: bytes});
      final service = serviceWith(source);

      final results = await Future.wait([
        service.ensureLocal(spec),
        service.ensureLocal(spec),
      ]);

      expect(source.downloads, 1);
      expect(results.map((r) => r.path).toSet(), {results.first.path});
    });
  });

  group('integrity', () {
    test('refuses bytes that do not match the digest, caching nothing',
        () async {
      final wrongBytes = bytesOf(64, seed: 5);
      // The spec promises a different digest than the bucket will deliver.
      final spec = specFor(bytesOf(64, seed: 8));
      final source = _FakeSource({spec.storagePath: wrongBytes});
      final service = serviceWith(source);

      await expectLater(
        service.ensureLocal(spec),
        throwsA(isA<ShoeModelIntegrityException>()),
      );

      final leftovers = cacheDir.existsSync()
          ? cacheDir
              .listSync()
              .whereType<File>()
              .map((f) => f.path)
              .toList()
          : <String>[];
      expect(
        leftovers,
        isEmpty,
        reason: 'a failed download must not leave a .glb or a .part behind',
      );
    });

    test('a failed forced re-download leaves the verified entry in place',
        () async {
      final goodBytes = bytesOf(80);
      final spec = specFor(goodBytes);
      final source = _FakeSource({spec.storagePath: goodBytes});
      final service = serviceWith(source);

      final first = await service.ensureLocal(spec);
      expect(File(first.path).existsSync(), isTrue);

      // The bucket now returns something else for the same row.
      source.assets[spec.storagePath] = bytesOf(80, seed: 3);
      await expectLater(
        service.ensureLocal(spec, force: true),
        throwsA(isA<ShoeModelIntegrityException>()),
      );

      // The filename is the digest, so the surviving file still matches the
      // row: keeping it costs nothing and saves the next attempt a download.
      expect(File(first.path).existsSync(), isTrue);
      expect(File(first.path).readAsBytesSync(), goodBytes);
    });
  });

  group('byte budget and eviction', () {
    test('evicts the least recently used model when over budget', () async {
      const budget = 250;
      final bytesA = bytesOf(100, seed: 1);
      final bytesB = bytesOf(100, seed: 2);
      final bytesC = bytesOf(100, seed: 3);
      final a = specFor(bytesA, id: 1, storagePath: 's/p/a.glb');
      final b = specFor(bytesB, id: 2, storagePath: 's/p/b.glb');
      final c = specFor(bytesC, id: 3, storagePath: 's/p/c.glb');
      final source = _FakeSource({
        a.storagePath: bytesA,
        b.storagePath: bytesB,
        c.storagePath: bytesC,
      });
      final service = serviceWith(source, budget: budget);

      await service.ensureLocal(a);
      File(ShoeModelService.cachePathFor(a, cacheDir))
          .setLastModifiedSync(DateTime(2020));

      await service.ensureLocal(b);
      File(ShoeModelService.cachePathFor(b, cacheDir))
          .setLastModifiedSync(DateTime(2021));

      // 300 B against a 250 B budget: the oldest (A) goes, the file just
      // used (C) is never a candidate.
      await service.ensureLocal(c);

      expect(File(ShoeModelService.cachePathFor(a, cacheDir)).existsSync(),
          isFalse);
      expect(File(ShoeModelService.cachePathFor(b, cacheDir)).existsSync(),
          isTrue);
      expect(File(ShoeModelService.cachePathFor(c, cacheDir)).existsSync(),
          isTrue);
    });

    test('sweeps leftover .part debris from an interrupted write', () async {
      final partial = File(
        '${cacheDir.path}${Platform.pathSeparator}9_v1_${goodSha()}.glb.part',
      );
      cacheDir.createSync(recursive: true);
      partial.writeAsBytesSync(bytesOf(10));

      final service = serviceWith(_FakeSource(const {}));
      final eviction = await service.enforceBudget();

      expect(partial.existsSync(), isFalse);
      expect(eviction.deletedFiles, 1);
    });
  });

  group('resolveForProduct', () {
    test('prefers the variant override, then the default, then nothing',
        () async {
      final source = _FakeSource(const {});
      source.rows = [
        {
          'id': 1,
          'variant_id': null,
          'storage_path': 's/p/default.glb',
          'sha256': goodSha(),
          'version': 1,
        },
        {
          'id': 2,
          'variant_id': 'variant-7',
          'storage_path': 's/p/black.glb',
          'sha256': goodSha('b'),
          'version': 1,
        },
      ];
      final service = serviceWith(source);

      expect(
        (await service.resolveForProduct('p', variantId: 'variant-7'))?.id,
        2,
      );
      expect(
        (await service.resolveForProduct('p', variantId: 'variant-8'))?.id,
        1,
      );
    });

    test('a malformed row never becomes a returned spec', () async {
      final source = _FakeSource(const {});
      source.rows = [
        {
          'id': 1,
          'storage_path': 's/p/broken.glb',
          'sha256': 'not-a-digest',
        },
      ];
      final service = serviceWith(source);

      expect(await service.resolveForProduct('p'), isNull);
    });
  });
}

class _FakeSource implements ShoeModelDataSource {
  _FakeSource(this.assets);

  final Map<String, Uint8List> assets;
  List<Map<String, dynamic>> rows = const [];
  int downloads = 0;

  @override
  Future<List<Map<String, dynamic>>> activeModelRows(String productId) async =>
      rows;

  @override
  Future<Uint8List> download(String storagePath) async {
    downloads++;
    final bytes = assets[storagePath];
    if (bytes == null) {
      throw StateError('No fake asset registered for "$storagePath"');
    }
    return bytes;
  }
}
