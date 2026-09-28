import 'dart:io';

import 'package:app/services/shoe_model_service.dart';
import 'package:app/services/try_on_placeholder_model.dart';
import 'package:app/utils/glb_validator.dart';
import 'package:app/utils/shoe_model_resolver.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// V3.5's QA seam, tested at the level where it can actually be wrong.
///
/// The claim `try_on_placeholder_model.dart` makes is not "a model is available"
/// — it is that **the production pipeline runs unchanged** and only the byte
/// source is substituted. So these tests assert the parts a mock of
/// `ShoeModelService` would have hidden: the row survives the real resolver, the
/// digest in the row is the file's own bytes, `ensureLocal` writes the real cache
/// filename through the real `.part`-then-rename path, a second call is a cache
/// hit, and a corrupted cache file is replaced rather than served.
///
/// `rootBundle` needs a binding, and it is the reason the block-out is read the
/// way a built app reads it rather than through a filesystem path that only
/// exists in a checkout.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory cacheRoot;

  setUp(() async {
    cacheRoot = await Directory.systemTemp.createTemp('placeholder_model_test');
  });

  tearDown(() async {
    if (cacheRoot.existsSync()) await cacheRoot.delete(recursive: true);
  });

  ShoeModelService service() => placeholderModelService(
        cacheDirectoryProvider: () async => cacheRoot,
      );

  // The block-out assertions are about the *default* build. A QA build that
  // points the seam elsewhere (`--dart-define=TRY_ON_QA_MODEL=…`) selects another
  // model deliberately, so these are skipped rather than made to fail.
  final blockOutDefault = selectedQaModel.asset == kPlaceholderModelAsset
      ? null
      : 'TRY_ON_QA_MODEL selected ${selectedQaModel.asset}';

  group('the bundled block-out is a model the renderer can use',
      skip: blockOutDefault, () {
    test('it resolves through the real resolver as a product default', () async {
      final spec = await service().resolveForProduct('any-product-id');

      expect(spec, isNotNull);
      expect(spec!.id, kPlaceholderModelId);
      expect(spec.variantId, isNull, reason: 'the product default, not an override');
      expect(spec.storagePath, kPlaceholderModelAsset);
      expect(spec.shoeSide, 'right');
      expect(spec.authoredLengthMm, kPlaceholderAuthoredLengthMm);
      expect(spec.authoredSizeEu, kPlaceholderAuthoredSizeEu);
      expect(spec.version, kPlaceholderModelVersion);
      // The resolver refuses a row whose digest is not 64 lowercase hex, so
      // reaching this line already proves the shape is right.
      expect(spec.sha256, hasLength(64));
    });

    test('the row carries the file\'s own digest, not a constant', () async {
      // A hard-coded digest is right until someone regenerates the block-out with
      // `tool/make_placeholder_shoe.py`, at which point every load fails its
      // integrity check and looks like a broken download. Deriving it is the point.
      final bytes = await placeholderModelBytes();
      final digest = sha256.convert(bytes).toString();

      expect(await placeholderSha256(), digest);
      final spec = await service().resolveForProduct('any-product-id');
      expect(spec!.sha256, digest);
    });

    test('the row reports the file size the renderer will actually read', () async {
      final bytes = await placeholderModelBytes();
      final rows = await const BundledPlaceholderModelDataSource()
          .activeModelRows('any-product-id');
      expect(rows.single['file_size_bytes'], bytes.lengthInBytes);
    });
  });

  group('it rides the production cache', skip: blockOutDefault, () {
    test('ensureLocal writes the real cache file, then hits it', () async {
      final bytes = await placeholderModelBytes();
      final serviceUnderTest = service();
      final spec = (await serviceUnderTest.resolveForProduct('p'))!;

      final first = await serviceUnderTest.ensureLocal(spec);
      expect(first.fromCache, isFalse);
      expect(first.bytes, bytes.lengthInBytes);
      expect(first.path, ShoeModelService.cachePathFor(spec, cacheRoot));
      expect(await File(first.path).readAsBytes(), bytes);

      final second = await serviceUnderTest.ensureLocal(spec);
      expect(second.fromCache, isTrue);
      expect(second.path, first.path);
    });

    test('a corrupted cache file is replaced, never served', () async {
      final serviceUnderTest = service();
      final spec = (await serviceUnderTest.resolveForProduct('p'))!;
      final path = ShoeModelService.cachePathFor(spec, cacheRoot);
      await File(path).writeAsBytes([1, 2, 3]);

      final file = await serviceUnderTest.ensureLocal(spec);

      expect(file.fromCache, isFalse, reason: 'the stale bytes were rejected');
      expect(await File(file.path).readAsBytes(), await placeholderModelBytes());
    });

    test('the in-memory fake is the only substitution: a stale row fails', () async {
      // Proves the digest check is live rather than decorative — a row claiming a
      // digest the bytes do not have must throw, placeholder or not.
      final serviceUnderTest = service();
      final spec = (await serviceUnderTest.resolveForProduct('p'))!;
      final forged = ShoeModelSpec(
        id: spec.id,
        storagePath: spec.storagePath,
        sha256: List.filled(64, 'a').join(),
      );

      await expectLater(
        serviceUnderTest.ensureLocal(forged),
        throwsA(isA<Object>()),
      );
    });
  });

  group('the second bundled model puts the pipeline on real bytes (V2.7/F21)', () {
    // Why a second asset exists at all: the block-out is 1,536 triangles of block
    // geometry with no textures, so it cannot tell a renderer that decodes three
    // PBR maps from one that draws clay — which is the failure a mid-range phone
    // would actually hit. This is the first real partner file to pass the
    // contract, normalised by `tool/prepare_shoe_model.dart`.
    final partner = bundledQaModelFor(kQaPartnerModelAsset);

    test('selection falls back instead of throwing on an unknown build flag', () {
      // A typo in `--dart-define=TRY_ON_QA_MODEL=…` must not look like a renderer
      // bug: the build serves the block-out and the caller can say so.
      expect(bundledQaModelFor('').asset, kPlaceholderModelAsset);
      expect(bundledQaModelFor('assets/models/not_a_model.glb').asset,
          kPlaceholderModelAsset);
      expect(bundledQaModelFor(kQaPartnerModelAsset).asset, kQaPartnerModelAsset);
      expect(
        kBundledQaModels.map((model) => model.asset),
        contains(selectedQaModel.asset),
        reason: 'whatever TRY_ON_QA_MODEL said, the selection is a bundled model',
      );
      expect(qaModelOverrideUnknown, isFalse);
    });

    test('the asset still satisfies the authoring contract it was made to pass', () async {
      // The seam is the *only* thing that would carry a non-conforming file into a
      // renderer, so the contract is asserted here rather than trusted from the
      // day the file was produced.
      final bytes = await placeholderModelBytes(model: partner);
      final report = validateGlb(
        bytes,
        options: const GlbValidationOptions(
          label: kQaPartnerModelAsset,
          externalLengthMm: 270,
          authoredSizeEu: 42,
        ),
      );

      expect(report.passed, isTrue,
          reason: report.checks
              .where((c) => c.status != GlbCheckStatus.pass)
              .map((c) => '${c.name}: ${c.detail}')
              .join('\n'));
      expect(report.triangleCount, partner.triangleCount,
          reason: 'the row the renderer is handed must match the file');
      expect(report.meshExternalLengthMm, closeTo(partner.authoredLengthMm, 0.5));
    });

    test('its row carries its own numbers, not the block-out\'s', () async {
      final bytes = await placeholderModelBytes(model: partner);
      final rows = await BundledPlaceholderModelDataSource(model: partner)
          .activeModelRows('any-product-id');
      final row = rows.single;

      expect(row['id'], isNot(kPlaceholderModelId),
          reason: 'a negative id must identify which bundled file this was');
      expect(row['storage_path'], kQaPartnerModelAsset);
      expect(row['triangle_count'], 49954);
      expect(row['authored_length_mm'], 270);
      expect(row['file_size_bytes'], bytes.lengthInBytes);
      expect(row['sha256'], sha256.convert(bytes).toString());
      expect(bytes.lengthInBytes, greaterThan(1000000),
          reason: 'the point of this asset is that it is not a 29 KB block-out');
    });

    test('it rides the production cache, digest check included', () async {
      final bytes = await placeholderModelBytes(model: partner);
      final serviceUnderTest = placeholderModelService(
        cacheDirectoryProvider: () async => cacheRoot,
        model: partner,
      );
      final spec = (await serviceUnderTest.resolveForProduct('p'))!;

      final first = await serviceUnderTest.ensureLocal(spec);
      expect(first.fromCache, isFalse);
      expect(first.bytes, bytes.lengthInBytes);
      expect(sha256.convert(await File(first.path).readAsBytes()), sha256.convert(bytes),
          reason: 'the file the renderer is handed is byte-identical to the asset');

      final second = await serviceUnderTest.ensureLocal(spec);
      expect(second.fromCache, isTrue);
      expect(second.path, first.path);
    });
  });
}
