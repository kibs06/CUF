/// A **bundled stand-in model** for exercising the V3 try-on path with no
/// `product_models` row and no partner asset
/// (`docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` V3.5).
///
/// ## Why this exists
///
/// V3's native half (`ArTryOnPlugin` / `ArTryOnView`) renders a `.glb` handed to
/// it as a **local file path**, and everything upstream of that path —
/// `ShoeModelService.resolveForProduct` → `ensureLocal` → sha256 → `.part` rename
/// → LRU budget — is production code. What V3 could not do as of 2026-09-28 was
/// *reach* any of it: `product_models` holds **0 rows** (the table is applied and
/// verified, but V2.8/V2.9 need a partner's exported shoe), so the capability gate
/// answers `modelMissing` on every product and the real renderer is unreachable
/// even on a device that supports AR. A pipeline that cannot be run cannot be
/// debugged, and "it compiles" was the whole claim V3.2 could make.
///
/// So this file substitutes **one boundary**: where the bytes come from. It is a
/// `ShoeModelDataSource` — the same seam `SupabaseShoeModelDataSource` implements
/// and the same one every service test already fakes — that serves a bundled
/// `.glb` as if it were an uploaded model. Two are bundled: the V0 block-out
/// (`assets/models/placeholder_shoe.glb`, 29,340 B, the default) and
/// [`kQaPartnerModelAsset`], the first real partner file to pass the authoring
/// contract, which exists because 1,536 triangles of untextured block geometry
/// cannot exercise texture decoding or a mid-range phone's fill rate — the two
/// things most likely to be wrong when the renderer meets a real product.
///
/// Which one is served is a **build** decision:
/// `--dart-define=TRY_ON_QA_MODEL=assets/models/qa_partner_shoe_v1.glb`. An
/// unknown value falls back to the block-out and [`qaModelOverrideUnknown`] lets
/// a caller report the typo, because a silent fallback would look like a renderer
/// bug.
///
/// **Nothing else is faked, and that is the point.** The row it returns goes
/// through `ShoeModelSpec.fromRow` and the same resolver, the bytes go through the
/// real digest check, the cache file is written by the real `.part`-then-rename
/// path under the real `<support>/shoe_models` folder, and the native side is
/// handed a real path. If any of that is broken, this exercises the break — which
/// is precisely what a mock of `ShoeModelService` would have hidden.
///
/// ## The swap is a boundary, not a shortcut
///
/// `download()` ignores its `storagePath`: there is no bucket, no network and no
/// row, so the digital identity is **derived from the file itself**. The digest in
/// the returned row is computed from the bundled bytes at read time
/// ([placeholderSha256]), so it can never drift from the file the way a
/// hard-coded constant would the first time someone regenerates the block-out
/// with `tool/make_placeholder_shoe.py`.
///
/// ## What it is not
///
/// It is **not** a shipping path and it does not change the fallback rules: with
/// `AppConstants.tryOnPlaceholderModelEnabled` off (the default) nothing here is
/// constructed, and even switched on the gate still needs ARCore to answer before
/// the customer sees a render. It is a QA/development seam — the same shape as the
/// V0 spike's dev flag — and it is the thing to delete when V2.9 lands a real
/// asset, along with `assets/models/placeholder_shoe.glb` and the spike itself
/// (findings §9's retirement checklist).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'shoe_model_service.dart';

/// The block-out the repository already ships. Not a product asset: V0's
/// contract-shaped fixture (metres, Y-up, toe +Z, heel-bottom-centre at origin,
/// part-named materials — findings §2).
const String kPlaceholderModelAsset = 'assets/models/placeholder_shoe.glb';

/// The first **real** partner asset to pass the contract
/// (`docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` V2.7, findings F21).
///
/// A marketplace/AI-generated shoe that failed 7 of the 11 checks as exported —
/// the exporter's rotation left on the node, the length on X, 4.30× life size,
/// three 4096² textures and one `Material.001`. `dart run
/// tool/prepare_shoe_model.dart` produced this file: 31.48 MiB → 1.66 MiB,
/// 270.0 × 111.7 × 100.7 mm, 11/11 PASS, parts `upper` + `sole`.
///
/// It is here for one reason the block-out cannot serve: the block-out is 1,536
/// triangles of block geometry, so it cannot tell a renderer that decodes three
/// 1024² texture maps from one that renders grey clay — the failure that matters
/// most on a mid-range phone. This asset has the texture sets, the 49,954
/// triangles and the 1.66 MiB file size a real product would.
///
/// It is **not** licensable product content and not the partner's declared
/// dimension: `kQaPartnerAuthoredLengthMm` is assumed (the handover has not given
/// one), which is why it is a stop labelled as one rather than a shippable row.
const String kQaPartnerModelAsset = 'assets/models/qa_partner_shoe_v1.glb';

/// The authored external length of the block-out, in mm.
///
/// 270 mm is the fixture's own contract (findings §2 and the `GltfioDecodeTest`
/// assertion that the decoded bounding box is ~270 mm long), so the renderer's
/// authored-length scale correction has a true value to work against rather than
/// a guess.
const double kPlaceholderAuthoredLengthMm = 270;

/// The EU size the block-out was authored at. 42 is the demo spec's size
/// (`VIRTUAL_FITTING_ROADMAP.md` V1), so a size change on the try-on screen
/// exercises §2.6's grading step against the same reference a real row would use.
const double kPlaceholderAuthoredSizeEu = 42;

/// Which bundled file the seam serves, and the row numbers that go with it.
///
/// The numbers are per-asset rather than global because they are *read by the
/// renderer*: `authored_length_mm` drives the native scale correction and
/// `triangle_count` is what a QA run compares against what the asset actually
/// loaded. Sharing the block-out's 1,536 triangles with a 49,954-triangle asset
/// would make that comparison meaningless.
class BundledQaModel {
  final String asset;
  final String label;
  final double authoredLengthMm;
  final double authoredSizeEu;
  final int triangleCount;
  final int modelId;
  final int version;

  const BundledQaModel({
    required this.asset,
    required this.label,
    required this.authoredLengthMm,
    required this.authoredSizeEu,
    required this.triangleCount,
    required this.modelId,
    required this.version,
  });
}

/// The two bundled QA models, by asset path.
const List<BundledQaModel> kBundledQaModels = [
  BundledQaModel(
    asset: kPlaceholderModelAsset,
    label: 'V0 block-out',
    authoredLengthMm: kPlaceholderAuthoredLengthMm,
    authoredSizeEu: kPlaceholderAuthoredSizeEu,
    triangleCount: kPlaceholderTriangleCount,
    modelId: -1,
    version: 1,
  ),
  BundledQaModel(
    asset: kQaPartnerModelAsset,
    label: 'partner asset (V2.7 normalised)',
    // Assumed, and the assumption is recorded: the handover has not declared
    // this shoe's external length, so the artifact was normalised against the
    // same 270 mm / EU 42 the block-out uses. Re-run the normaliser with the real
    // number and this value changes with it.
    authoredLengthMm: 270,
    authoredSizeEu: 42,
    triangleCount: 49954,
    modelId: -2,
    version: 1,
  ),
];

/// Build-time selection of which bundled model the QA seam serves:
/// `--dart-define=TRY_ON_QA_MODEL=assets/models/qa_partner_shoe_v1.glb`.
///
/// Defaults to the block-out, so a build that says nothing behaves exactly as
/// before and the 1.66 MiB partner asset is *bundled but never read* unless asked
/// for. Declared here as a constant rather than read at runtime because the
/// choice is a build decision — a QA run should not be able to pick a different
/// asset than the one it was built against.
const String _kQaModelOverride = String.fromEnvironment('TRY_ON_QA_MODEL');

/// The model the seam serves for this build: the override when it names a known
/// bundled asset, otherwise the block-out.
///
/// An override that names something unknown falls back rather than throwing, and
/// [qaModelOverrideUnknown] lets a caller say so out loud — a typo in a build flag
/// must not turn into a silent block-out render that looks like a renderer bug.
BundledQaModel get selectedQaModel => bundledQaModelFor(_kQaModelOverride);

/// True when `TRY_ON_QA_MODEL` was set to something that is not a bundled model.
bool get qaModelOverrideUnknown =>
    _kQaModelOverride.isNotEmpty &&
    !kBundledQaModels.any((model) => model.asset == _kQaModelOverride);

/// The bundled model for an asset path, or the block-out when the path is empty
/// or unknown.
BundledQaModel bundledQaModelFor(String asset) {
  if (asset.isEmpty) return kBundledQaModels.first;
  for (final model in kBundledQaModels) {
    if (model.asset == asset) return model;
  }
  return kBundledQaModels.first;
}

/// Digests of the bundled assets, computed once per process each.
///
/// Read through `rootBundle`, so they work in a widget test, in `flutter test` and
/// on a device without a filesystem path to the asset.
final Map<String, Future<String>> _digests = {};

Future<String> placeholderSha256({BundledQaModel? model}) {
  final selected = model ?? selectedQaModel;
  return _digests.putIfAbsent(selected.asset, () => _computeDigest(selected));
}

Future<String> _computeDigest(BundledQaModel model) async {
  final bytes = await placeholderModelBytes(model: model);
  return sha256.convert(bytes).toString();
}

/// The bundled bytes, or throws when the asset is missing from the build.
///
/// A mismatch between this and `pubspec.yaml` is a configuration error and is
/// surfaced as one: silently rendering nothing would be indistinguishable from a
/// renderer bug, which is the thing this file exists to rule out.
Future<Uint8List> placeholderModelBytes({BundledQaModel? model}) async {
  final data = await rootBundle.load((model ?? selectedQaModel).asset);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// A `ShoeModelDataSource` that serves the bundled block-out as a `draft`-less,
/// single-row product.
///
/// Row identity is deliberately recognisable in a log: `id: kPlaceholderModelId`
/// is a **negative** id, which no `product_models` row can have (the column is a
/// positive BIGSERIAL), so a cache filename or a native handover that came from
/// this file is obvious at a glance rather than looking like a real model that
/// mysteriously stopped existing.
class BundledPlaceholderModelDataSource implements ShoeModelDataSource {
  /// Null serves whichever model the build selected ([selectedQaModel]); an
  /// explicit model is how a test (or a future picker) chooses one.
  final BundledQaModel? model;

  const BundledPlaceholderModelDataSource({this.model});

  BundledQaModel get _selected => model ?? selectedQaModel;

  @override
  Future<List<Map<String, dynamic>>> activeModelRows(String productId) async {
    final selected = _selected;
    final bytes = await placeholderModelBytes(model: selected);
    return [
      {
        'id': selected.modelId,
        'variant_id': null,
        'storage_path': selected.asset,
        'sha256': await placeholderSha256(model: selected),
        'version': selected.version,
        'authored_size_eu': selected.authoredSizeEu,
        'authored_length_mm': selected.authoredLengthMm,
        'shoe_side': 'right',
        'triangle_count': selected.triangleCount,
        'file_size_bytes': bytes.lengthInBytes,
      },
    ];
  }

  /// There is no bucket to read from, so the path is answered from the bundle.
  ///
  /// The integrity check downstream still runs — against
  /// [placeholderSha256] — so the `.part`-then-rename write, the digest
  /// verification and the cache-hit path are all the real ones.
  @override
  Future<Uint8List> download(String storagePath) =>
      placeholderModelBytes(model: _selected);
}

/// The synthetic row id. Negative on purpose: see
/// [BundledPlaceholderModelDataSource].
const int kPlaceholderModelId = -1;

/// Authoring revision, matching what a seller's first upload would be.
const int kPlaceholderModelVersion = 1;

/// The block-out's triangle count, as `tool/make_placeholder_shoe.py` reports it
/// (findings §2) — carried so a QA run can compare what the seller-side report
/// would have said with what the renderer actually loaded.
const int kPlaceholderTriangleCount = 1536;

/// A ready-to-inject service: the production [ShoeModelService] pointed at the
/// bundled bytes.
///
/// This is the whole seam the try-on screen uses under
/// `AppConstants.tryOnPlaceholderModelEnabled`, and it takes the cache directory
/// as an argument so a test can point it at a temp folder.
ShoeModelService placeholderModelService({
  Future<Directory> Function()? cacheDirectoryProvider,
  BundledQaModel? model,
}) =>
    ShoeModelService(
      dataSource: BundledPlaceholderModelDataSource(model: model),
      cacheDirectoryProvider: cacheDirectoryProvider,
    );
