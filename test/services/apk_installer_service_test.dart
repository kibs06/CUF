import 'package:app/services/apk_installer_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two decisions that stand between a download and Android's package
/// installer, tested on their own because both of them, when wrong, produce the
/// same opaque dialog the user cannot act on: "App not installed."
///
/// History (2026-09-28): a truncated stream was promoted to the final APK name
/// and then reused by every later Install tap, so one dropped connection became
/// a permanent failure on that device.
void main() {
  group('isDownloadComplete', () {
    test('accepts a stream that delivered every byte the server promised', () {
      expect(isDownloadComplete(227569046, 227569046), isTrue);
      expect(isDownloadComplete(1, 1), isTrue);
    });

    test('refuses a short stream — the truncation this guards against', () {
      expect(isDownloadComplete(0, 227569046), isFalse);
      expect(isDownloadComplete(227569045, 227569046), isFalse);
    });

    test('refuses a stream longer than promised', () {
      // A resumed download appended to a stale partial can overshoot; that file
      // is as uninstallable as a short one.
      expect(isDownloadComplete(227569047, 227569046), isFalse);
    });

    test('allows an unknown length through — it cannot be checked', () {
      // Chunked responses carry no Content-Length; refusing them would break
      // hosts that stream the manifest's APK without one.
      expect(isDownloadComplete(12345678, 0), isTrue);
      expect(isDownloadComplete(12345678, -1), isTrue);
    });
  });

  group('isUsableApkFile', () {
    test('rejects a file too small to be an APK', () {
      expect(isUsableApkFile(0), isFalse);
      expect(isUsableApkFile(1024), isFalse);
      expect(
        isUsableApkFile(ApkInstallerService.minPlausibleApkBytes - 1),
        isFalse,
      );
    });

    test('accepts a file at the threshold or above', () {
      expect(isUsableApkFile(ApkInstallerService.minPlausibleApkBytes), isTrue);
      // The real APK is ~220 MB (ARCore + ML Kit + Filament).
      expect(isUsableApkFile(227569046), isTrue);
    });
  });

  group('DownloadIncompleteException', () {
    test('reports how far the download got, for the resume prompt', () {
      const e = DownloadIncompleteException(4194304, 227569046);
      expect(e.receivedBytes, 4194304);
      expect(e.expectedBytes, 227569046);
      expect(e.toString(), contains('4194304'));
      expect(e.toString(), contains('227569046'));
    });
  });
}
