/// ReferenceDetector seam: the capture screen's only source of reference
/// corners.
///
/// [CvReferenceDetector] runs the real classical-CV quad finder over a
/// luminance plane (camera Y plane: one byte per pixel). Its output goes
/// through the same [coachForDetection] → [diagnoseReferenceQuad] authority
/// as everything else, so a bad detection re-coaches instead of measuring.
/// [SimulatedReferenceDetector] preserves the old synthesized behavior for
/// devices where the image stream is unavailable — it is a fallback, not
/// the path, and the UI never knows which implementation is behind the seam.
library;

import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import 'card_quad_detector.dart';
import 'foot_measurement_utils.dart';

/// Corner source for the capture loop. Implementations never throw:
/// no detection means an empty list (keep coaching as `searching`).
abstract class ReferenceDetector {
  /// Corners in full-frame pixels for a [frameW]×[frameH] frame.
  List<Offset> detect({
    required Uint8List luminance,
    required int frameW,
    required int frameH,
  });
}

/// Real detector: downscale → [detectReferenceQuad] → scale back up.
///
/// Detection runs on a ≤[maxSide]px frame (speed), but corners are
/// returned in full-frame pixels so downstream scale math stays exact.
class CvReferenceDetector implements ReferenceDetector {
  final int maxSide;

  const CvReferenceDetector({this.maxSide = 320});

  @override
  List<Offset> detect({
    required Uint8List luminance,
    required int frameW,
    required int frameH,
  }) {
    try {
      if (luminance.length < frameW * frameH || frameW < 32 || frameH < 32) {
        return const [];
      }
      final longSide = frameW > frameH ? frameW : frameH;
      if (longSide <= maxSide) {
        return _detectFull(
          luminance.sublist(0, frameW * frameH),
          frameW,
          frameH,
          1.0,
        );
      }
      final k = longSide / maxSide;
      final dw = (frameW / k).round();
      final dh = (frameH / k).round();
      if (dw < 32 || dh < 32) return const [];
      final small = Uint8List(dw * dh);
      final src = luminance;
      for (var y = 0; y < dh; y++) {
        final sy = (y * k).floor().clamp(0, frameH - 1);
        for (var x = 0; x < dw; x++) {
          final sx = (x * k).floor().clamp(0, frameW - 1);
          small[y * dw + x] = src[sy * frameW + sx];
        }
      }
      return _detectFull(small, dw, dh, k);
    } catch (_) {
      return const [];
    }
  }

  List<Offset> _detectFull(
    Uint8List plane,
    int w,
    int h,
    double scaleUp,
  ) {
    final quad = detectReferenceQuad(plane, w, h);
    if (quad == null) return const [];
    return [
      for (final c in quad.corners)
        Offset(c.x * scaleUp, c.y * scaleUp),
    ];
  }
}

/// Result of decoding one burst still and running the quad finder on it.
class StillDetection {
  /// Corners in the still's full-resolution pixels ([] when none).
  final List<Offset> corners;
  final int frameW;
  final int frameH;
  const StillDetection(this.corners, this.frameW, this.frameH);
}

/// Decode burst-still JPEG bytes and detect the reference quad.
///
/// Top-level so the capture screen can run it in an isolate via `compute`:
/// full-res JPEG decode plus detection stays off the UI thread while the
/// burst progress ring animates. Never throws — failure is empty corners.
StillDetection decodeAndDetectStill(Map<String, Object> args) {
  try {
    final bytes = args['bytes'] as Uint8List;
    final maxSide = args['maxSide'] as int? ?? 320;
    final decoded = img.decodeJpg(bytes) ?? img.decodePng(bytes);
    if (decoded == null) return const StillDetection([], 0, 0);
    final frameW = decoded.width, frameH = decoded.height;
    img.Image small = decoded;
    var scaleUp = 1.0;
    final longSide = frameW > frameH ? frameW : frameH;
    if (longSide > maxSide) {
      final k = longSide / maxSide;
      small = img.copyResize(decoded,
          width: (frameW / k).round(), height: (frameH / k).round());
      scaleUp = k;
    }
    final gray = img.grayscale(small);
    final plane = Uint8List(gray.width * gray.height);
    for (var y = 0; y < gray.height; y++) {
      for (var x = 0; x < gray.width; x++) {
        plane[y * gray.width + x] =
            gray.getPixel(x, y).luminance.toInt().clamp(0, 255);
      }
    }
    final quad = detectReferenceQuad(plane, gray.width, gray.height);
    if (quad == null) return StillDetection(const [], frameW, frameH);
    return StillDetection(
      [
        for (final c in quad.corners)
          Offset(c.x * scaleUp, c.y * scaleUp),
      ],
      frameW,
      frameH,
    );
  } catch (_) {
    return const StillDetection([], 0, 0);
  }
}

/// Fallback detector: the previous synthesized behavior (framing ticks,
/// then a stable reference-proportioned quad with jitter, every 7th tick
/// keystoned so the tilted re-coach path keeps exercising).
class SimulatedReferenceDetector implements ReferenceDetector {
  int _tick = 0;
  final PaperDimensions reference;

  SimulatedReferenceDetector({required this.reference});

  void reset() => _tick = 0;

  @override
  List<Offset> detect({
    required Uint8List luminance,
    required int frameW,
    required int frameH,
  }) {
    _tick++;
    if (_tick < 6) return const [];
    final long = frameW * 0.3;
    final short = long / reference.aspectRatio;
    final cx = frameW / 2, cy = frameH / 2;
    final jx = ((_tick % 3) - 1) * 2.0;
    final jy = ((_tick % 5) - 2) * 2.0;
    if (_tick % 7 == 0) {
      return [
        Offset(cx - 40 + jx, cy - 50 + jy),
        Offset(cx + 40 + jx, cy - 50 + jy),
        Offset(cx + 80, cy + 50),
        Offset(cx - 80, cy + 50),
      ];
    }
    return [
      Offset(cx - long / 2 + jx, cy - short / 2 + jy),
      Offset(cx + long / 2 + jx, cy - short / 2 + jy),
      Offset(cx + long / 2 + jx, cy + short / 2 + jy),
      Offset(cx - long / 2 + jx, cy + short / 2 + jy),
    ];
  }
}
