import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// In-app APK self-updater: streams the new APK to app storage with live
/// progress + resume support, then hands the finished file to Android's
/// system package installer (one tap — the browser download flow stays
/// available as a fallback in the What's New screen).
///
/// Android contract:
///  • The APK must be signed with the same key as the installed build: Android
///    refuses a differently-signed replacement (its "App not installed."
///    dialog) and reports nothing back to the caller. Releases are signed with
///    `android/app/cufmai-release.jks` — see docs/RELEASE_SIGNING.md.
///  • `REQUEST_INSTALL_PACKAGES` is declared in the manifest.
///  • The FIRST install attempt bounces the user to the one-time
///    "Allow CUFMAI to install apps" toggle; OpenFilex returns
///    [open_filex] result and the user taps Download again to continue.
///  • Every later update goes straight to the system Install dialog.
class ApkInstallerService extends ChangeNotifier {
  ApkInstallerService._();

  static final ApkInstallerService instance = ApkInstallerService._();

  final Dio _dio = Dio();

  /// Highest state this service can surface to the UI. [progress] is 0..1
  /// while downloading; [message] carries a human-readable status.
  ApkDownloadState? _state;
  ApkDownloadState? get state => _state;

  /// Cancel handle for the in-flight download (drives the Cancel button).
  CancelToken? _cancelToken;

  bool _busy = false;
  bool get isBusy => _busy;

  void _emit(ApkDownloadState state) {
    _state = state;
    notifyListeners();
  }

  /// Smallest file this service will believe is one of its own APKs. The real
  /// thing is ~220 MB (ARCore + ML Kit + Filament); anything a few KB under the
  /// final name was promoted while still truncated, and handing that to the
  /// installer ends in Android's generic "App not installed." with no way back —
  /// the file would be reused by every later Install tap.
  static const int minPlausibleApkBytes = 5 * 1024 * 1024;

  /// Path of the APK previously downloaded for [version], or null.
  /// Used to resume/tap-Install without re-downloading. A file too small to be
  /// a real APK is deleted, so the download starts over instead of being
  /// retried as-is forever.
  Future<String?> _existingApkPath(String version) async {
    try {
      final dir = await _apkDir();
      final f = File('${dir.path}/cufmai-$version.apk');
      if (!f.existsSync()) return null;
      if (isUsableApkFile(f.lengthSync())) return f.path;
      f.deleteSync();
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _apkDir() async {
    final base = await getExternalStorageDirectory(); // app-private, no permission
    final dir = Directory('${base!.path}/updates');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Streams [url] to app-private storage, reporting progress via [onProgress]
  /// (0..1). Resumes an existing partial file via HTTP Range when the server
  /// supports it; falls back to a clean restart when it doesn't.
  ///
  /// Returns the local APK path once the download completes.
  Future<String> downloadApk(
    String url,
    String version, {
    void Function(double progress, int receivedMb, int totalMb)? onProgress,
  }) async {
    if (_busy) throw Exception('DOWNLOAD_ALREADY_RUNNING');
    _busy = true;
    _cancelToken = CancelToken();

    void report(int received, int total) {
      if (total <= 0) return;
      onProgress?.call(
        received / total,
        received ~/ (1024 * 1024),
        total ~/ (1024 * 1024),
      );
    }

    try {
      final dir = await _apkDir();
      final savePath = '${dir.path}/cufmai-$version.apk';
      final partial = File('$savePath.part');
      var existing = partial.existsSync() ? partial.lengthSync() : 0;

      _emit(ApkDownloadState.downloading(0, message: 'Starting…'));

      // Resume support: ask the server for the remaining bytes.
      final headers = <String, dynamic>{};
      if (existing > 0) headers['Range'] = 'bytes=$existing-';

      Response<ResponseBody> resp;
      try {
        resp = await _dio.get<ResponseBody>(
          url,
          options: Options(
            responseType: ResponseType.stream,
            headers: headers,
            // A Range request answers 206; accept that plus 200 (server
            // ignored Range → full body → restart from zero).
            validateStatus: (s) => s != null && (s == 200 || s == 206),
          ),
          cancelToken: _cancelToken,
        );
      } on DioException catch (e) {
        if (e.type == DioExceptionType.badResponse) {
          // Some CDNs reject Range — retry once without it.
          existing = 0;
          resp = await _dio.get<ResponseBody>(
            url,
            options: Options(
              responseType: ResponseType.stream,
              validateStatus: (s) => s != null && s == 200,
            ),
            cancelToken: _cancelToken,
          );
        } else {
          rethrow;
        }
      }

      // 200 = full body (Range ignored) → discard the partial.
      final resumed = resp.statusCode == 206 && existing > 0;
      if (!resumed && partial.existsSync()) {
        partial.deleteSync();
        existing = 0;
      }

      final total = resumed
          ? existing + (int.tryParse(resp.headers.value('content-length') ?? '') ?? 0)
          : (int.tryParse(resp.headers.value('content-length') ?? '') ?? 0);

      final sink = partial.openSync(mode: FileMode.append);
      var received = resumed ? existing : 0;

      try {
        await for (final chunk in resp.data!.stream) {
          sink.writeFromSync(chunk);
          received += chunk.length;
          report(received, total);
        }
      } finally {
        await sink.close();
      }

      // A dropped connection can end the stream without raising, so "the loop
      // finished" is not "the file is complete". Promoting a short file to the
      // final name would make it the reusable APK for this version — and it can
      // only ever fail to install. Keep the .part (so the next tap resumes it)
      // unless the byte count matches what the server promised.
      final written = partial.lengthSync();
      if (!isDownloadComplete(written, total)) {
        _emit(ApkDownloadState.error(
          'Download stopped early at $written of $total bytes.',
        ));
        throw DownloadIncompleteException(written, total);
      }

      // Complete → promote to the final name.
      final finalFile = File(savePath);
      if (finalFile.existsSync()) finalFile.deleteSync();
      partial.renameSync(savePath);

      _emit(ApkDownloadState.done(savePath));
      return savePath;
    } on DownloadIncompleteException {
      // State was already emitted with the byte counts; the .part file stays
      // on disk for the resume.
      rethrow;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        _emit(ApkDownloadState.idle(message: 'Download cancelled'));
        throw Exception('DOWNLOAD_CANCELLED');
      }
      _emit(ApkDownloadState.error('Download failed — check your connection.'));
      rethrow;
    } catch (e) {
      _emit(ApkDownloadState.error('Download failed — check your connection.'));
      rethrow;
    } finally {
      _busy = false;
      _cancelToken = null;
    }
  }

  /// Cancel the in-flight download (partial file stays on disk for resume).
  void cancelDownload() {
    _cancelToken?.cancel();
  }

  /// Opens the downloaded APK with Android's system package installer.
  /// Returns a user-facing message; empty string when the installer opened
  /// cleanly.
  Future<String> installApk(String path) async {
    try {
      final result = await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
      switch (result.type) {
        case ResultType.done:
          return '';
        case ResultType.noAppToOpen:
          return 'No installer available on this device.';
        // The standard first-time case: the OS wants the one-time
        // "allow installs" toggle first.
        case ResultType.permissionDenied:
          return 'Allow CUFMAI to install apps in the next screen, then tap Download again.';
        default:
          return 'Could not start the installer (${result.message}).';
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ApkInstaller] install failed: $e');
      return 'Could not start the installer.';
    }
  }

  /// Downloads (or reuses the already-completed APK) then triggers the
  /// installer. Called both for the initial download AND the Install tap
  /// after completion — the second call short-circuits on the existing
  /// file instead of re-downloading.
  Future<void> downloadAndInstall(
    String url,
    String version, {
    void Function(double progress, int receivedMb, int totalMb)? onProgress,
  }) async {
    final existing = await _existingApkPath(version);
    final path = existing ??
        await downloadApk(url, version, onProgress: onProgress);
    await installApk(path);
  }

  /// Deletes leftover partial + completed APKs (called on successful update
  /// boot, or when disk space matters).
  Future<void> clearDownloads() async {
    try {
      final dir = await _apkDir();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// Whether a finished byte stream may be promoted to the reusable APK name.
///
/// A dropped connection can end the stream without raising, so "the loop
/// finished" is not "the file is complete": this is the check that keeps a
/// truncated APK from taking the final name and failing every future install.
/// An unknown expected length (`<= 0`, e.g. a chunked response) cannot be
/// checked and is allowed through — the HTTP layer's own timeouts are the only
/// guard there.
@visibleForTesting
bool isDownloadComplete(int writtenBytes, int expectedBytes) =>
    expectedBytes <= 0 || writtenBytes == expectedBytes;

/// Whether a file sitting under the final APK name is big enough to be one.
/// Used when reusing a previous download: an implausibly small file is deleted
/// so the download starts over instead of being retried forever.
@visibleForTesting
bool isUsableApkFile(int bytes) =>
    bytes >= ApkInstallerService.minPlausibleApkBytes;

/// Thrown when the byte stream ended before Content-Length bytes arrived — a
/// dropped connection, a closing proxy, or a killed download that never
/// raised. The partial file is kept, so tapping Download again resumes it.
class DownloadIncompleteException implements Exception {
  const DownloadIncompleteException(this.receivedBytes, this.expectedBytes);

  final int receivedBytes;
  final int expectedBytes;

  @override
  String toString() =>
      'DownloadIncompleteException($receivedBytes/$expectedBytes bytes)';
}

/// Immutable status snapshot for the UI.
class ApkDownloadState {
  const ApkDownloadState._({
    required this.phase,
    this.progress = 0,
    this.receivedMb = 0,
    this.totalMb = 0,
    this.message,
    this.filePath,
  });

  final ApkDownloadPhase phase;
  final double progress;
  final int receivedMb;
  final int totalMb;
  final String? message;
  final String? filePath;

  factory ApkDownloadState.idle({String? message}) =>
      ApkDownloadState._(phase: ApkDownloadPhase.idle, message: message);

  factory ApkDownloadState.downloading(double progress,
      {int receivedMb = 0, int totalMb = 0, String? message}) {
    // Clamp — dio occasionally reports >1 on resumable streams.
    final p = progress.clamp(0.0, 1.0);
    return ApkDownloadState._(
      phase: ApkDownloadPhase.downloading,
      progress: p,
      receivedMb: receivedMb,
      totalMb: totalMb,
      message: message,
    );
  }

  factory ApkDownloadState.done(String filePath) =>
      ApkDownloadState._(phase: ApkDownloadPhase.done, filePath: filePath, progress: 1);

  factory ApkDownloadState.error(String message) =>
      ApkDownloadState._(phase: ApkDownloadPhase.error, message: message);
}

enum ApkDownloadPhase { idle, downloading, done, error }
