/// Android custom foot detector (YOLO11n-pose → ONNX) behind [FootDetector].
///
/// - [OnnxFootDetector]: thin MethodChannel client for the Android-only
///   native plugin (`OnnxFootDetectorPlugin.kt`, channel
///   `com.solevision/onnx_foot_detector`). Off Android (iOS, tests without a
///   mock) it answers "no foot" rather than throwing, so iOS keeps building
///   and running on ML Kit with zero changes.
/// - [OnnxFirstFootDetector]: the controller default — tries ONNX first and
///   falls back to ML Kit segmentation only when the native call *fails*
///   (missing plugin, load error, mid-stream exception), mirroring the
///   portal worker (`footTracker.worker.js`: ONNX preferred, Pose fallback
///   on mid-stream failure — never on an empty frame).
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import 'foot_detector.dart';
import 'mlkit_segmentation_foot_detector.dart';

/// Channel twin of `ONNX_FOOT_DETECTOR_CHANNEL` in `OnnxFootDetectorPlugin.kt`.
const MethodChannel kOnnxFootDetectorChannel =
    MethodChannel('com.solevision/onnx_foot_detector');

/// [FootDetector] backed by the Android native YOLO11n-pose ONNX session.
class OnnxFootDetector implements FootDetector {
  final MethodChannel _channel;

  OnnxFootDetector({MethodChannel? channel})
      : _channel = channel ?? kOnnxFootDetectorChannel;

  @override
  Future<FootDetectionResult> detect({
    required Uint8List nv21Bytes,
    required int width,
    required int height,
    required int rotationDegrees,
    String? preferSide,
    Rect? guideRect,
  }) async {
    // iOS / desktop / tests without a mock: no native plugin exists.
    if (!Platform.isAndroid) {
      return const FootDetectionResult.negative(detectorBackend: 'onnx');
    }
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'detectFoot',
        <String, dynamic>{
          'nv21': nv21Bytes,
          'width': width,
          'height': height,
          'rotationDegrees': rotationDegrees,
        },
      );
      if (res == null || res['found'] != true) {
        return const FootDetectionResult.negative(detectorBackend: 'onnx');
      }
      double conf(String key) {
        final v = res[key];
        if (v is num) return v.toDouble().clamp(0.0, 1.0);
        return 0.0;
      }

      FootPoint? point(String key) {
        final m = res[key];
        if (m is Map) {
          final x = (m['x'] as num?)?.toDouble();
          final y = (m['y'] as num?)?.toDouble();
          final s = (m['score'] as num?)?.toDouble() ?? 0.0;
          if (x != null && y != null) {
            return FootPoint(x: x, y: y, likelihood: s.clamp(0.0, 1.0));
          }
        }
        return null;
      }

      final heel = point('heel');
      final toe = point('toe');
      if (heel == null || toe == null) {
        return const FootDetectionResult.negative(detectorBackend: 'onnx');
      }
      final score = conf('score');
      // Box (center-based UV from the native decode) → normalized rect for
      // the test overlay. Missing box is tolerated (older native build).
      Rect? box;
      final bm = res['box'];
      if (bm is Map) {
        final bx = (bm['x'] as num?)?.toDouble();
        final by = (bm['y'] as num?)?.toDouble();
        final bw = (bm['w'] as num?)?.toDouble();
        final bh = (bm['h'] as num?)?.toDouble();
        if (bx != null && by != null && bw != null && bh != null) {
          box = Rect.fromCenter(
            center: Offset(bx, by),
            width: bw,
            height: bh,
          );
        }
      }
      // Pose-style result (no mask on this path — the native side owns no
      // segmentation): heel/toe required, quality mirrors the portal's box
      // confidence, side is the model's constant `left`.
      return FootDetectionResult(
        footDetected: true,
        confidence: score,
        footSide: (res['side'] as String?) ?? 'left',
        heelPoint: heel,
        toePoint: toe,
        boundingBox: box,
        detectorBackend: 'onnx',
        qualityScore: score,
        segmentationScore: score,
        shapeScore: 1.0,
        containmentScore: 1.0,
      );
    } catch (e) {
      debugPrint('[OnnxDiag] detect failed, caller falls back: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    try {
      _channel.invokeMethod('close');
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}

/// Controller default: ONNX first (Android), ML Kit segmentation on failure.
///
/// An ONNX *negative* (valid call, no foot) is returned as-is — a second
/// inference pass would double per-frame cost and let two backends disagree
/// about the same frame. Only an *error* (missing plugin on iOS/tests, load
/// failure, mid-stream exception) falls through to ML Kit, exactly like the
/// portal's ONNX→Pose fallback.
class OnnxFirstFootDetector implements FootDetector {
  final FootDetector _onnx;
  final FootDetector Function() _mlkitFactory;
  FootDetector? _mlkit;

  OnnxFirstFootDetector({
    FootDetector? onnx,
    FootDetector Function()? mlkitFactory,
  })  : _onnx = onnx ?? OnnxFootDetector(),
        _mlkitFactory = mlkitFactory ?? MlKitSegmentationFootDetector.new;

  @override
  Future<FootDetectionResult> detect({
    required Uint8List nv21Bytes,
    required int width,
    required int height,
    required int rotationDegrees,
    String? preferSide,
    Rect? guideRect,
  }) async {
    try {
      final r = await _onnx.detect(
        nv21Bytes: nv21Bytes,
        width: width,
        height: height,
        rotationDegrees: rotationDegrees,
        preferSide: preferSide,
        guideRect: guideRect,
      );
      // Off Android the ONNX detector answers negative without ever calling
      // native code — fall through to ML Kit there, but keep a genuine
      // Android negative as the answer.
      if (!Platform.isAndroid) {
        return _fallback(nv21Bytes, width, height, rotationDegrees,
            preferSide, guideRect);
      }
      return r;
    } catch (_) {
      return _fallback(
          nv21Bytes, width, height, rotationDegrees, preferSide, guideRect);
    }
  }

  Future<FootDetectionResult> _fallback(
    Uint8List nv21Bytes,
    int width,
    int height,
    int rotationDegrees,
    String? preferSide,
    Rect? guideRect,
  ) async {
    _mlkit ??= _mlkitFactory();
    final r = await _mlkit!.detect(
      nv21Bytes: nv21Bytes,
      width: width,
      height: height,
      rotationDegrees: rotationDegrees,
      preferSide: preferSide,
      guideRect: guideRect,
    );
    // Pre-backend results (and the pose path) predate the label — stamp the
    // fallback origin so the test overlay always names the running backend.
    if (r.detectorBackend == null) {
      return r.copyWith(detectorBackend: 'mlkit-seg');
    }
    return r;
  }

  @override
  void dispose() {
    try {
      _onnx.dispose();
    } catch (_) {}
    try {
      _mlkit?.dispose();
    } catch (_) {}
  }
}
