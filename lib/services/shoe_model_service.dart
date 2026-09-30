/// Resolve → download → verify → cache, for V2 shoe models
/// (`docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` V2.5).
///
/// The renderer never does HTTP (architecture §2.8): Dart hands the native
/// side a **local file path**, so this service is the only thing that talks
/// to the `shoe-models` bucket. Its job is to make that path exist, be the
/// right bytes, and not fill the phone.
///
/// **The cache, in one paragraph.** Files live in
/// `<app support>/shoe_models/<modelId>_v<version>_<sha256>.glb`. The
/// filename carries the digest, so two authoring revisions coexist without
/// either being able to impersonate the other; a cache hit is only a hit
/// if the file's bytes still hash to that digest, so a corrupted or
/// truncated file is re-downloaded instead of rendered. Writes go to a
/// `.part` file first and are renamed into place, so an interrupted write
/// can never be read as a hit. When the folder exceeds its byte budget the
/// least-recently-*used* files go first (a hit touches the file, and the
/// sort reads mtimes) and the file just used is never a candidate. The
/// `.part` leftovers of a crash are treated as garbage and swept.
///
/// **Why `getApplicationSupportDirectory` and not documents:** models are
/// internal cache, not user documents — nothing here should show up in a
/// file browser, and on Android the support directory is not backed up the
/// way documents are. The diag log uses documents precisely because a human
/// exports it; this file has no human.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../exceptions/shoe_model_integrity_exception.dart';
import '../utils/shoe_model_resolver.dart';

/// The two I/O operations the service needs, behind one seam.
///
/// Tests inject a fake and never touch Supabase or the network; the default
/// implementation is [SupabaseShoeModelDataSource]. The split is
/// deliberate — the interesting logic (resolve, verify, cache, evict) is
/// testable without a server, which is the architecture's testing note for
/// this service (§2.15).
abstract class ShoeModelDataSource {
  /// Active `product_models` rows for one product, in whatever order the
  /// backend returns them. Parsing and choosing is the resolver's job.
  Future<List<Map<String, dynamic>>> activeModelRows(String productId);

  /// The object's bytes. Throws on network/HTTP failure.
  Future<Uint8List> download(String storagePath);
}

/// The real backend: Supabase select + Storage download.
class SupabaseShoeModelDataSource implements ShoeModelDataSource {
  /// Public-read bucket that `product_models.storage_path` points into.
  static const String bucket = 'shoe-models';

  /// Only the columns the app consumes. `status` is filtered server-side
  /// anyway (RLS serves active rows to customers), but the explicit filter
  /// keeps the contract readable and cost-free.
  static const String _columns =
      'id, variant_id, storage_path, sha256, version, authored_size_eu, '
      'authored_length_mm, shoe_side, material_map, alignment_json, '
      'triangle_count, file_size_bytes';

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<List<Map<String, dynamic>>> activeModelRows(String productId) async {
    final rows = await _client
        .from('product_models')
        .select(_columns)
        .eq('product_id', productId)
        .eq('status', 'active');
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  @override
  Future<Uint8List> download(String storagePath) =>
      _client.storage.from(bucket).download(storagePath);
}

/// A model that exists on disk, ready to hand to the native side.
class ShoeModelFile {
  /// Absolute path of the verified `.glb`.
  final String path;

  /// True when the file was already cached and verified (no download).
  final bool fromCache;

  /// Size of the file on disk.
  final int bytes;

  const ShoeModelFile({
    required this.path,
    required this.fromCache,
    required this.bytes,
  });

  @override
  String toString() => 'ShoeModelFile($path, '
      '${fromCache ? 'cache' : 'download'}, $bytes B)';
}

/// What one budget pass did — returned so tests (and a future cache screen)
/// can see eviction without scraping the filesystem.
class ShoeModelEviction {
  final int deletedFiles;
  final int freedBytes;
  final int remainingBytes;

  const ShoeModelEviction({
    required this.deletedFiles,
    required this.freedBytes,
    required this.remainingBytes,
  });

  static const ShoeModelEviction none = ShoeModelEviction(
    deletedFiles: 0,
    freedBytes: 0,
    remainingBytes: 0,
  );
}

class ShoeModelService {
  ShoeModelService({
    ShoeModelDataSource? dataSource,
    Future<Directory> Function()? cacheDirectoryProvider,
    this.budgetBytes = kShoeModelCacheBudgetBytes,
  })  : _dataSource = dataSource ?? SupabaseShoeModelDataSource(),
        _cacheDirectoryProvider =
            cacheDirectoryProvider ?? _defaultCacheDirectory;

  /// Total `.glb` bytes allowed on disk before eviction starts. The
  /// roadmap's V2 budget is 50 MB (~10 superhero models at the authoring
  /// guide's < 5 MB target).
  static const int kShoeModelCacheBudgetBytes = 50 * 1024 * 1024;

  /// Folder under the app support directory that holds every cached model.
  static const String cacheFolderName = 'shoe_models';

  static const String _fileExtension = '.glb';
  static const String _partialExtension = '.part';

  final ShoeModelDataSource _dataSource;
  final Future<Directory> Function() _cacheDirectoryProvider;

  /// Byte budget for the cache folder; injectable so tests can evict with
  /// a handful of bytes instead of megabytes.
  final int budgetBytes;

  /// De-dupes concurrent requests for the same file (a product-detail
  /// prefetch racing the customer's tap would otherwise download twice and
  /// race two renames onto one path).
  final Map<String, Future<ShoeModelFile>> _inFlight = {};

  /// Active models for a product, parsed. Malformed rows are dropped by
  /// the resolver, so holding this list means every entry is renderable.
  Future<List<ShoeModelSpec>> activeModelsFor(String productId) async {
    final rows = await _dataSource.activeModelRows(productId);
    return parseShoeModelRows(rows);
  }

  /// The one model to render for [variantId] — per-colour override, then
  /// the product default, then null. See `shoe_model_resolver.dart`.
  ///
  /// [anyVariant] is the "is there *a* model on this product?" question rather
  /// than "which shoe does this customer see?" — the seller's viewer asks it, so
  /// a product whose models are all colour-scoped does not answer "no model".
  Future<ShoeModelSpec?> resolveForProduct(
    String productId, {
    String? variantId,
    bool anyVariant = false,
  }) async {
    final models = await activeModelsFor(productId);
    return resolveShoeModel(
      models: models,
      variantId: variantId,
      anyVariant: anyVariant,
    );
  }

  /// The cache folder. Created on demand by [ensureLocal], never here, so
  /// reading the path does not touch the filesystem.
  Future<Directory> cacheDirectory() => _cacheDirectoryProvider();

  /// Returns a verified local path for [spec], downloading it if needed.
  ///
  /// [force] re-downloads even when a valid cache entry exists (the
  /// "reload model" path a dev screen or a repair flow needs).
  ///
  /// Throws [ShoeModelIntegrityException] when the bytes do not match
  /// [ShoeModelSpec.sha256]. Nothing of the failed download is written:
  /// the bytes are verified before the `.part` rename, so a mismatch
  /// leaves the cache exactly as it was — including an existing verified
  /// entry, which is kept rather than deleted. That is the safe direction:
  /// the filename *is* the digest, so any file at this path has already
  /// proven itself, and destroying it would cost the next try-on a
  /// download. A file that fails its own hash check is the one exception —
  /// it is corrupt, so it is removed before the retry.
  Future<ShoeModelFile> ensureLocal(
    ShoeModelSpec spec, {
    bool force = false,
  }) {
    final key = '${force ? 'force:' : ''}${cacheFileNameFor(spec)}';
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future = _ensureLocal(spec, force: force);
    _inFlight[key] = future;
    // Drop the entry once the work finishes — but only while it is still the
    // same future, so a late completion can never evict a newer call's entry.
    // `.ignore()` keeps the cleanup chain's own error silent: callers await
    // `future`, and a second unhandled copy of the same error would be noise.
    future
        .whenComplete(() {
          if (identical(_inFlight[key], future)) _inFlight.remove(key);
        })
        .ignore();
    return future;
  }

  /// Enforces [budgetBytes] across the cache folder.
  ///
  /// Eviction order is mtime ascending — a lower bound on true LRU that
  /// needs no index file: [ensureLocal] touches every hit, so the least
  /// recently *used* file is the oldest by mtime unless another process
  /// wrote to the folder. [keepPath] (the file just returned) is never
  /// deleted, so a single-model app can always operate at least one model.
  ///
  /// In-progress `.part` files are deleted unconditionally: they are the
  /// debris of an interrupted write, and a half-written model is never a
  /// cache hit.
  Future<ShoeModelEviction> enforceBudget({String? keepPath}) async {
    final dir = await cacheDirectory();
    if (!await dir.exists()) return ShoeModelEviction.none;

    final files = <File>[];
    final partials = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (entity.path.endsWith(_partialExtension)) {
        partials.add(entity);
      } else if (entity.path.endsWith(_fileExtension)) {
        files.add(entity);
      }
    }

    var deletedFiles = 0;
    var freedBytes = 0;

    for (final partial in partials) {
      freedBytes += await _sizeOf(partial);
      if (await _deleteQuietly(partial)) deletedFiles++;
    }

    var total = 0;
    final entries = <({File file, DateTime modified, int size})>[];
    for (final file in files) {
      final stat = await file.stat();
      entries.add((file: file, modified: stat.modified, size: stat.size));
      total += stat.size;
    }

    if (total > budgetBytes) {
      entries.sort((a, b) {
        final byTime = a.modified.compareTo(b.modified);
        return byTime != 0 ? byTime : a.file.path.compareTo(b.file.path);
      });
      for (final entry in entries) {
        if (total <= budgetBytes) break;
        if (keepPath != null && entry.file.path == keepPath) continue;
        if (await _deleteQuietly(entry.file)) {
          deletedFiles++;
          freedBytes += entry.size;
          total -= entry.size;
        }
      }
    }

    return ShoeModelEviction(
      deletedFiles: deletedFiles,
      freedBytes: freedBytes,
      remainingBytes: total,
    );
  }

  /// The cache filename for [spec] — public because tests, log lines and
  /// any future cache screen all need to name the same file.
  static String cacheFileNameFor(ShoeModelSpec spec) =>
      '${spec.id}_v${spec.version}_${spec.sha256}$_fileExtension';

  /// One spec's path inside [directory], used by tests and diagnostics.
  static String cachePathFor(ShoeModelSpec spec, Directory directory) =>
      '${directory.path}${Platform.pathSeparator}${cacheFileNameFor(spec)}';

  Future<ShoeModelFile> _ensureLocal(
    ShoeModelSpec spec, {
    required bool force,
  }) async {
    final directory = await cacheDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final file = File(cachePathFor(spec, directory));

    if (!force && await file.exists()) {
      final cachedDigest = await _sha256OfFile(file);
      if (cachedDigest == spec.sha256) {
        await _touch(file);
        await enforceBudget(keepPath: file.path);
        return ShoeModelFile(
          path: file.path,
          fromCache: true,
          bytes: await file.length(),
        );
      }
      // Stale or corrupt: remove it so a failed replacement cannot leave
      // the old bytes behind to be served as a "hit" later.
      await _deleteQuietly(file);
    }

    final bytes = await _dataSource.download(spec.storagePath);
    final actualDigest = sha256.convert(bytes).toString();
    if (actualDigest != spec.sha256) {
      throw ShoeModelIntegrityException(
        storagePath: spec.storagePath,
        expectedSha256: spec.sha256,
        actualSha256: actualDigest,
      );
    }

    // Write to `.part` then rename: rename within a directory is atomic on
    // the platforms we ship, so a crash mid-write leaves debris (swept by
    // enforceBudget) rather than a file that looks cached.
    final partial = File('${file.path}$_partialExtension');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(file.path);
    await _touch(file);
    await enforceBudget(keepPath: file.path);

    return ShoeModelFile(
      path: file.path,
      fromCache: false,
      bytes: bytes.length,
    );
  }

  /// Marks a file as used. `setLastModified` may fail on a read-only or
  /// locked filesystem; that must never fail a successful load, so this
  /// swallows the error (the consequence is only eviction order).
  Future<void> _touch(File file) async {
    try {
      await file.setLastModified(DateTime.now());
    } catch (_) {/* best effort — see doc comment */}
  }

  Future<String> _sha256OfFile(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  Future<int> _sizeOf(File file) async {
    try {
      return await file.length();
    } catch (_) {
      return 0;
    }
  }

  Future<bool> _deleteQuietly(File file) async {
    try {
      await file.delete();
      return true;
    } catch (_) {
      // A file we cannot delete is not an error to the caller: eviction is
      // best-effort and the next pass will try again.
      return false;
    }
  }
}

/// `<app support>/shoe_models`, created lazily by [ShoeModelService].
Future<Directory> _defaultCacheDirectory() async {
  final base = await getApplicationSupportDirectory();
  return Directory(
    '${base.path}${Platform.pathSeparator}${ShoeModelService.cacheFolderName}',
  );
}
