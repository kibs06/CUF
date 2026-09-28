/// Fetch a handover `.glb`, check it, then publish it — the write half of the
/// V2 model pipeline (`docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` V2.2/V2.3).
///
/// **What this is the other half of.** `ShoeModelService` (`v2.5`) reads models
/// back: resolve → download → verify → cache, and it is what the renderer will
/// call. This service is the only thing that *writes* them, and the two meet at
/// one invariant — `sha256` is the filename in the bucket, the column in the
/// table and the filename in the device cache. Because the digest is the object
/// path, an upload is naturally idempotent: the same bytes can only ever land at
/// one place, so re-publishing a file the seller already shipped is a no-op
/// rather than a second row (see `shoeModelReuseMatch`).
///
/// **Three seams, all injectable.** [ShoeModelBytesSource] is the network half
/// (a link, fetched with a byte cap that cancels mid-download rather than after
/// the phone has already buffered 200 MB), [ShoeModelUploadDataSource] is the
/// Supabase half (storage object + table row), and [ShoeModelServerValidator] is
/// the server verdict (V2.4). Tests inject fakes for all three, so the
/// interesting rules — the gate, the digest, the version arithmetic, the reuse
/// decision, and which of the server's three answers a publish can end on — are
/// exercised without a server or a socket. That is the same shape
/// `ShoeModelService` uses for its cache logic (§2.15's testing note).
///
/// **Why the client checks a file that the server will check too.** Client
/// validation is *not* a security boundary (§2.5.4): it exists so an artisan
/// gets a sentence in seconds instead of an opaque API rejection. The server-side
/// validator is the gate that protects the catalog — and it is the **only**
/// writer of `status='active'`, because
/// `20260928120000_gate_product_model_active.sql` refuses that transition from
/// any PostgREST role but the service role. So every row this service writes is
/// a `draft`: the bytes land, the row claims them, and the server then decides
/// whether it may be served. A build that could skip the call would produce
/// models nobody can ever publish.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../exceptions/shoe_model_upload_exception.dart';
import '../utils/glb_validator.dart';
import '../utils/shoe_model_upload.dart';
import 'shoe_model_server_validator.dart';

/// The network half: bytes for a link. One method, so a test can hand over
/// bytes from memory and a future file-picker source can slot in beside it.
abstract class ShoeModelBytesSource {
  Future<Uint8List> fetch(String url);
}

/// Dio, with a hard byte cap enforced *during* the download.
///
/// The cap matters more than it looks: a link that is not a `.glb` at all (a
/// Drive preview page, a wrong share) can be arbitrarily large, and buffering it
/// whole before refusing would be a memory failure on the cheapest phones in
/// this market. Cancelling at the cap turns that into a sentence.
class DioShoeModelBytesSource implements ShoeModelBytesSource {
  final Dio _dio;
  final int maxBytes;

  DioShoeModelBytesSource({Dio? dio, this.maxBytes = kShoeModelBucketCapBytes})
      : _dio = dio ?? Dio();

  @override
  Future<Uint8List> fetch(String url) async {
    final cancel = CancelToken();
    var cancelledForSize = false;

    void checkSize(int received, int total) {
      if (cancelledForSize) return;
      if (received > maxBytes || (total > 0 && total > maxBytes)) {
        cancelledForSize = true;
        cancel.cancel('too-large');
      }
    }

    try {
      final response = await _dio.get<List<int>>(
        url,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          maxRedirects: 5,
          receiveTimeout: const Duration(seconds: 60),
        ),
        onReceiveProgress: checkSize,
      );

      final data = response.data;
      if (data == null || data.isEmpty) {
        throw ShoeModelUploadException(
          'The link returned an empty file. Check that it points at the '
          'exported .glb and that sharing is set to anyone with the link.',
          detail: 'empty body from $url',
        );
      }

      final bytes = data is Uint8List ? data : Uint8List.fromList(data);
      if (bytes.length > maxBytes) {
        throw ShoeModelUploadException(
          _tooLargeMessage(bytes.length),
          detail: 'downloaded ${bytes.length} B from $url',
        );
      }
      return bytes;
    } on DioException catch (e) {
      if (cancelledForSize) {
        throw ShoeModelUploadException(
          _tooLargeMessage(maxBytes),
          detail: 'aborted mid-download from $url at the size cap',
        );
      }
      throw ShoeModelUploadException(
        _describeDioFailure(e, url),
        detail: 'DioException ${e.type.name}'
            '${e.response?.statusCode == null ? '' : ' HTTP ${e.response!.statusCode}'}'
            ' from $url',
      );
    }
  }

  String _tooLargeMessage(int bytes) =>
      'The file is over the 8 MB the model bucket accepts '
      '(${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB). Re-bake the textures '
      'and retopo, then export again (guide §C5/C7).';

  /// One sentence per cause a seller can actually do something about.
  String _describeDioFailure(DioException e, String url) {
    final status = e.response?.statusCode;
    if (status == 404) {
      return 'That link returned 404 — check it is shared publicly and still '
          'exists.';
    }
    if (status == 403) {
      return 'That link is private. Set sharing to "anyone with the link" and '
          'check again.';
    }
    if (status != null) {
      return 'The link returned HTTP $status instead of a file.';
    }
    return 'Could not reach that link. Check the connection, then the link.';
  }
}

/// The Supabase half: the table rows and the storage object.
abstract class ShoeModelUploadDataSource {
  /// Every `product_models` row for one product, whatever its status — the
  /// upload needs to see drafts and rejected rows too, because a reuse match or
  /// a version number depends on all of them.
  Future<List<Map<String, dynamic>>> rowsFor(String productId);

  /// Writes the object. `upsert` because the filename **is** the digest: a
  /// retry of the same bytes is the same object, and a `409` there would be a
  /// lie about what went wrong.
  Future<void> putBytes({
    required String storagePath,
    required Uint8List bytes,
  });

  /// Inserts the row and returns it **as the database stored it**, which is
  /// what the server validator is then called with: publishing moves a row by
  /// its id, so the id has to come back from the write rather than be assumed.
  Future<Map<String, dynamic>> insertRow(Map<String, dynamic> row);

  /// Flips one row back to `draft` — how a seller takes a reused model down
  /// without deleting it. It never writes `active`: that is the server's call
  /// (V2.4), and the database refuses it from here anyway.
  Future<void> updateStatus({required int id, required String status});
}

/// The real backend: public-read `shoe-models` bucket + `product_models`.
class SupabaseShoeModelUploadDataSource implements ShoeModelUploadDataSource {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<List<Map<String, dynamic>>> rowsFor(String productId) async {
    final rows = await _client
        .from('product_models')
        .select()
        .eq('product_id', productId);
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  @override
  Future<void> putBytes({
    required String storagePath,
    required Uint8List bytes,
  }) async {
    await _client.storage.from(kShoeModelBucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            contentType: kShoeModelContentType,
            upsert: true,
          ),
        );
  }

  @override
  Future<Map<String, dynamic>> insertRow(Map<String, dynamic> row) async {
    final inserted = await _client
        .from('product_models')
        .insert(row)
        .select()
        .single();
    return Map<String, dynamic>.from(inserted);
  }

  @override
  Future<void> updateStatus({required int id, required String status}) async {
    await _client.from('product_models').update({'status': status}).eq('id', id);
  }
}

/// What one publish did, so the UI can say it plainly.
class ShoeModelPublishOutcome {
  /// True when the bucket and the table already held these exact bytes, so
  /// nothing was written except possibly a status change.
  final bool reusedExisting;

  /// The object path inside the bucket.
  final String storagePath;

  /// The version that is now live for this target.
  final int version;

  /// The status the row carries after this call: `active` once the server
  /// published it, `rejected` when the server refused it, `draft` when the
  /// seller held it back or no verdict arrived.
  final String status;

  /// The row that was inserted, or the existing row that was reused.
  final Map<String, dynamic> row;

  /// The server's answer (V2.4), or null when the seller saved a draft and the
  /// server was never asked. The screen reads [ShoeModelServerVerdict.
  /// sellerMessage] from it, which is why a refusal and a missing verdict are
  /// two different sentences rather than one "not published".
  final ShoeModelServerVerdict? serverVerdict;

  const ShoeModelPublishOutcome({
    required this.reusedExisting,
    required this.storagePath,
    required this.version,
    required this.status,
    required this.row,
    this.serverVerdict,
  });

  /// One log-safe line — and the sentence the seller reads, because the screen
  /// prefixes it with "3D model".
  String get summary {
    final verb = reusedExisting ? 'reused' : 'uploaded';
    switch (status) {
      case 'active':
        return '$verb v$version — live for customers ($storagePath)';
      case 'rejected':
        return '$verb v$version — the server refused it, so it stays hidden '
            '($storagePath)';
      default:
        return '$verb v$version as a draft — not shown to customers yet '
            '($storagePath)';
    }
  }
}

/// Fetch → validate → publish → let the server decide.
class ShoeModelUploadService {
  final ShoeModelBytesSource bytesSource;
  final ShoeModelUploadDataSource dataSource;

  /// The server gate. Defaulted rather than optional, because a publish that
  /// silently skipped it would upload models that can never go live.
  final ShoeModelServerValidator serverValidator;

  ShoeModelUploadService({
    required this.bytesSource,
    required this.dataSource,
    ShoeModelServerValidator? serverValidator,
  }) : serverValidator = serverValidator ?? SupabaseShoeModelServerValidator();

  /// Downloads [url] and runs the authoring contract over the bytes.
  ///
  /// Returns the asset either way — a report with failures is a result, not an
  /// exception, because the seller needs to read the failing rows. Only a
  /// *transport* problem (bad link, wrong scheme, unreachable host) throws.
  Future<ShoeModelAsset> fetchAndValidate({
    required String url,
    double? declaredExternalLengthMm,
    double? authoredSizeEu,
    String shoeSide = 'right',
    String label = '<upload>',
  }) async {
    final trimmed = url.trim();
    if (!isShoeModelSourceUrlAllowed(trimmed)) {
      throw ShoeModelUploadException(
        'Paste a direct https link to the .glb. Links that open a page (Drive '
        'previews, sharing pages) do not return the file itself.',
        detail: 'refused source url "$trimmed"',
      );
    }

    final bytes = await bytesSource.fetch(trimmed);

    final report = validateGlb(
      bytes,
      options: GlbValidationOptions(
        label: label,
        externalLengthMm: declaredExternalLengthMm,
        authoredSizeEu: authoredSizeEu,
      ),
    );

    return ShoeModelAsset(
      bytes: bytes,
      report: report,
      sourceUrl: trimmed,
      declaredExternalLengthMm: declaredExternalLengthMm,
      authoredSizeEu: authoredSizeEu,
      shoeSide: shoeSide,
    );
  }

  /// Publishes a passing asset against [productId].
  ///
  /// Order is deliberate: **the bytes land in the bucket before the row points
  /// at them**, and the row lands as a **draft** before the server is asked
  /// about it. A row whose object is missing renders as "no model" at best and
  /// as a failed download every launch at worst; an object with no row is simply
  /// invisible — the same asymmetry `ShoeModelService`'s `.part`-then-rename
  /// write protects on the read side. The draft-first part is the same idea
  /// applied to `active`: between the insert and the server's answer, the only
  /// state the catalog can observe is a hidden one.
  ///
  /// [active] means "the seller asked for this to go live", not "write
  /// active". Only the server validator may, so this method's job ends at
  /// handing it a row and a verdict comes back — three possible answers, all
  /// handled: validated (published), refused (rejected), no answer (still a
  /// draft, and the seller is told).
  Future<ShoeModelPublishOutcome> publish({
    required String storeId,
    required String productId,
    required ShoeModelAsset asset,
    String? variantId,
    bool active = true,
  }) async {
    final gate = shoeModelUploadGate(
      productId: productId,
      asset: asset,
      declaration: const ShoeModelDeclarationResult.empty(),
    );
    if (!gate.ready) {
      throw ShoeModelUploadException(gate.message);
    }

    final digest = asset.sha256;
    final existing = await dataSource.rowsFor(productId);

    final reusable = shoeModelReuseMatch(
      existingRows: existing,
      sha256: digest,
      variantId: variantId,
    );
    if (reusable != null) {
      final id = shoeModelRowId(reusable['id']);
      if (id == null) {
        throw ShoeModelUploadException(
          'The stored model record is missing its id, so it cannot be '
          'published. Upload the model again.',
          detail: 'reuse match without an id for "$digest"',
        );
      }
      final currentStatus = reusable['status']?.toString() ?? 'draft';
      final storagePath = reusable['storage_path']?.toString() ??
          shoeModelStoragePath(
            storeId: storeId.trim(),
            productId: productId,
            sha256: digest,
          );
      final version = (reusable['version'] as num?)?.toInt() ?? 1;

      // Held back: take it down without deleting the work. A non-service-role
      // caller may always write `draft` or `rejected` (the gate only guards the
      // way *into* `active`), so this needs no server round trip.
      if (!active) {
        if (currentStatus != 'draft') {
          await dataSource.updateStatus(id: id, status: 'draft');
        }
        reusable['status'] = 'draft';
        return ShoeModelPublishOutcome(
          reusedExisting: true,
          storagePath: storagePath,
          version: version,
          status: 'draft',
          row: reusable,
        );
      }

      // Already live: the database lets only the server write `active`, so the
      // status is itself the record that these exact bytes passed it. Asking
      // again would spend a download to be told what the row already says.
      if (currentStatus == 'active') {
        return ShoeModelPublishOutcome(
          reusedExisting: true,
          storagePath: storagePath,
          version: version,
          status: 'active',
          row: reusable,
        );
      }

      // A draft or a rejected row: re-publishing is exactly the retry, and the
      // bytes are already in the bucket at their digest, so nothing is written —
      // only judged.
      return _judgeByServer(
        reusedExisting: true,
        storagePath: storagePath,
        version: version,
        row: reusable,
        modelId: id,
      );
    }

    final version = nextShoeModelVersion(
      existingRows: existing,
      variantId: variantId,
    );

    // The bucket's write policy reads the **first path segment** as a store the
    // caller owns, and compares it to the stored id — so the segment must be the
    // real id, trimmed of any incidental whitespace. Refusing a padded id would
    // be the wrong fix: the padding is not the seller's mistake and storage
    // would accept the trimmed value happily.
    final storeSegment = storeId.trim();
    if (storeSegment.isEmpty) {
      throw ShoeModelUploadException(
        'This product is not linked to a store this account owns, so the model '
        'cannot be attached. Contact admin if that looks wrong.',
        detail: 'blank store id for product "$productId"',
      );
    }

    final storagePath = shoeModelStoragePath(
      storeId: storeSegment,
      productId: productId,
      sha256: digest,
    );

    // Always a draft — `shoeModelRow` writes nothing else, and `active` is
    // written by the server validator and by nothing else (see the header).
    final row = shoeModelRow(
      productId: productId,
      variantId: variantId,
      storagePath: storagePath,
      sha256: digest,
      version: version,
      authoredLengthMm: asset.declaredExternalLengthMm,
      authoredSizeEu: asset.authoredSizeEu,
      shoeSide: asset.shoeSide,
      triangleCount: asset.triangleCount,
      fileSizeBytes: asset.fileSizeBytes,
    );

    await dataSource.putBytes(storagePath: storagePath, bytes: asset.bytes);
    final inserted = await dataSource.insertRow(row);

    if (!active) {
      return ShoeModelPublishOutcome(
        reusedExisting: false,
        storagePath: storagePath,
        version: version,
        status: 'draft',
        row: inserted,
      );
    }

    final modelId = shoeModelRowId(inserted['id']);
    if (modelId == null) {
      // The server moves a row by its id, and this write did not report one.
      // The bytes and the row are both safely in place and hidden; publishing
      // again is the retry.
      return ShoeModelPublishOutcome(
        reusedExisting: false,
        storagePath: storagePath,
        version: version,
        status: 'draft',
        row: inserted,
        serverVerdict: const ShoeModelServerVerdict.undetermined(
          'the saved model record did not report its id',
        ),
      );
    }

    return _judgeByServer(
      reusedExisting: false,
      storagePath: storagePath,
      version: version,
      row: inserted,
      modelId: modelId,
    );
  }

  /// Hands one existing row to the server validator and turns its answer into
  /// an outcome. Writes nothing itself: the verdict is the server's, and the
  /// row's new status comes back in the response.
  Future<ShoeModelPublishOutcome> _judgeByServer({
    required bool reusedExisting,
    required String storagePath,
    required int version,
    required Map<String, dynamic> row,
    required int modelId,
  }) async {
    final verdict = await serverValidator.validate(modelId: modelId);
    final status = switch (verdict.outcome) {
      ShoeModelServerOutcome.validated => verdict.status,
      ShoeModelServerOutcome.rejected => 'rejected',
      ShoeModelServerOutcome.undetermined => 'draft',
    };
    row['status'] = status;
    return ShoeModelPublishOutcome(
      reusedExisting: reusedExisting,
      storagePath: storagePath,
      version: version,
      status: status,
      row: row,
      serverVerdict: verdict,
    );
  }

  /// The production wiring: dio over the link, Supabase for the two writes.
  static ShoeModelUploadService createDefault() => ShoeModelUploadService(
        bytesSource: DioShoeModelBytesSource(),
        dataSource: SupabaseShoeModelUploadDataSource(),
      );
}
