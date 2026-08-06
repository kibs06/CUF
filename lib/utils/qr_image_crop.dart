/// QR auto-detection + auto-crop for seller GCash QR uploads.
///
/// When a seller uploads a screenshot of their GCash "My QR" screen, the QR
/// code is usually embedded inside a larger branded image (blue header, account
/// details below). This utility detects the QR's bounding box and crops to it
/// (with a quiet-zone margin) so the stored/displayed image is just the code.
///
/// Detection reuses the **existing** `mobile_scanner` dependency — no new
/// detection library. `mobile_scanner` exposes
/// `MobileScannerPlatform.instance.analyzeImage(path)` for STATIC images (its
/// Android/iOS implementation runs ML Kit / Vision over a file, no camera
/// needed) and each `Barcode` carries `corners` (4 pixel-space points), which
/// gives us the exact module bounds for a precise crop.
///
/// Cropping uses `dart:ui` (decode → `Canvas.drawImageRect` → PNG encode) so
/// no image-processing package is required either.
///
/// Failure handling is explicit and safe: if no QR is found, the corners are
/// unusable, or anything throws, we return the ORIGINAL image unchanged with a
/// user-facing message. A bad crop is never silently produced.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:mobile_scanner/mobile_scanner.dart';

/// Outcome of the detect-and-crop pass on a picked image.
class QrAutoCropResult {
  /// Path of the cropped PNG, or `null` when detection failed/`[detected]` is false.
  final String? croppedPath;

  /// Whether a usable QR bounding box was found and cropped.
  final bool detected;

  /// The crop rectangle in original-image pixel coordinates (null if not detected).
  final ui.Rect? cropRect;

  /// Short, non-alarming explanation for the seller (used when not detected).
  final String? message;

  const QrAutoCropResult({
    this.croppedPath,
    required this.detected,
    this.cropRect,
    this.message,
  });
}

class QrImageAutoCrop {
  /// Quiet-zone margin around the detected QR, as a fraction of QR width.
  /// Scanners need a little breathing room around the code.
  static const double quietZoneRatio = 0.10;

  /// Max output dimension (px) for the cropped image — small QRs are never
  /// upscaled (that just makes them blurry), and large screenshots are capped
  /// so the uploaded file stays reasonable.
  static const int maxOutputDimension = 1024;

  /// Detect the largest QR in [sourcePath] and crop to it (+ margin).
  ///
  /// Returns the cropped PNG path when detection succeeds; otherwise falls
  /// back to the original by returning `detected: false` (never throws).
  ///
  /// Coordinate-space assumption: ML Kit's `corners` (returned by
  /// `analyzeImage`) and dart:ui's decoded pixels must share the same upright,
  /// un-rotated space. This holds for screenshots (no EXIF) and for
  /// `image_picker` picks made with `maxWidth`/`maxHeight`/`imageQuality` set,
  /// because image_picker re-encodes and bakes orientation into the pixels.
  /// Do not drop those pick parameters, or camera-photo crops could be offset.
  static Future<QrAutoCropResult> detectAndCrop(String sourcePath) async {
    final file = File(sourcePath);
    if (!file.existsSync()) {
      return const QrAutoCropResult(
        detected: false,
        message: 'The picked image could not be read — using the full image instead.',
      );
    }

    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final imgW = image.width;
      final imgH = image.height;

      try {
        // ── Detect QR(s) in the static image — largest wins ──
        // `analyzeImage` is a plain platform-channel call (no camera init).
        // Unsupported platforms (web, iOS Simulator) throw/return null → caught
        // below and handled by the original-image fallback.
        final BarcodeCapture? capture;
        try {
          capture = await MobileScannerPlatform.instance.analyzeImage(
            sourcePath,
            formats: const [BarcodeFormat.qrCode],
          );
        } catch (e) {
          debugPrint('[QrAutoCrop] analyzeImage unsupported/errored: $e');
          return const QrAutoCropResult(
            detected: false,
            message: 'QR detection is not supported on this device — using the '
                'full image instead.',
          );
        }

        final barcodes = capture?.barcodes ?? const <Barcode>[];
        Barcode? best;
        var bestArea = 0.0;
        for (final barcode in barcodes) {
          if (barcode.corners.length != 4) continue;
          final rect = cornersToRect(barcode.corners);
          if (rect == null) continue;
          final area = rect.width * rect.height;
          if (area > bestArea) {
            bestArea = area;
            best = barcode;
          }
        }

        if (barcodes.length > 1) {
          debugPrint(
            '[QrAutoCrop] ${barcodes.length} QR patterns detected — '
            'picked the largest by area',
          );
        }

        if (best == null || bestArea <= 0) {
          debugPrint('[QrAutoCrop] No QR detected in $sourcePath');
          return const QrAutoCropResult(
            detected: false,
            message: 'We couldn\'t detect a QR code in this image — using the '
                'full image instead. Make sure the QR is clearly visible and '
                'not blurry, or crop it yourself before uploading.',
          );
        }

        // ── Crop rect = QR bounds + quiet-zone margin, clamped to image ──
        final rawRect = cornersToRect(best.corners)!;
        final margin = rawRect.width * quietZoneRatio;
        final cropRect = rawRect
            .inflate(margin)
            .intersect(ui.Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble()));
        if (cropRect.width < 4 || cropRect.height < 4) {
          return const QrAutoCropResult(
            detected: false,
            message: 'The QR code was too small to crop cleanly — using the '
                'full image instead.',
          );
        }

        // ── Crop + downscale (never upscale) + PNG encode ──
        final outW = cropRect.width.round();
        final outH = cropRect.height.round();
        final scale = fitScale(outW, outH, maxOutputDimension);
        final dstW = (outW * scale).round().clamp(1, maxOutputDimension);
        final dstH = (outH * scale).round().clamp(1, maxOutputDimension);

        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawImageRect(
          image,
          cropRect,
          ui.Rect.fromLTWH(0, 0, dstW.toDouble(), dstH.toDouble()),
          ui.Paint()..filterQuality = ui.FilterQuality.high,
        );
        final picture = recorder.endRecording();
        final cropped = await picture.toImage(dstW, dstH);
        final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
        cropped.dispose();
        picture.dispose();
        if (data == null) {
          return const QrAutoCropResult(
            detected: false,
            message: 'We couldn\'t process this image — using the full image instead.',
          );
        }

        final outFile = File(
          '${Directory.systemTemp.path}/qr_crop_'
          '${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await outFile.writeAsBytes(data.buffer.asUint8List());

        debugPrint(
          '[QrAutoCrop] Cropped QR ${rawRect.width.round()}x'
          '${rawRect.height.round()} → ${dstW}x$dstH',
        );
        return QrAutoCropResult(
          croppedPath: outFile.path,
          detected: true,
          cropRect: cropRect,
        );
      } finally {
        image.dispose();
        codec.dispose();
      }
    } catch (e) {
      debugPrint('[QrAutoCrop] Error: $e');
      return const QrAutoCropResult(
        detected: false,
        message: 'We couldn\'t process this image — using the full image instead.',
      );
    }
  }

  /// Bounding box of 4 corner points (pixel space), or null if degenerate.
  static ui.Rect? cornersToRect(List<ui.Offset> corners) {
    if (corners.length != 4) return null;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final c in corners) {
      if (c.dx < minX) minX = c.dx;
      if (c.dy < minY) minY = c.dy;
      if (c.dx > maxX) maxX = c.dx;
      if (c.dy > maxY) maxY = c.dy;
    }
    if (!minX.isFinite || maxX <= minX || maxY <= minY) return null;
    return ui.Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Uniform scale to fit [w]x[h] within [maxDim] — returns 1.0 when already
  /// small enough (never upscales).
  static double fitScale(int w, int h, int maxDim) {
    final largest = w > h ? w : h;
    if (largest <= maxDim) return 1.0;
    return maxDim / largest;
  }
}
