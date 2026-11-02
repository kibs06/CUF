/// Background-isolate wrapper for the mask math (MISSION v2 Phase 1.1).
///
/// `MlKitSegmentationFootDetector.detect` does two things:
///  1. `processImage` — ML Kit platform-channel call, MUST stay on the main
///     isolate (background isolates have no platform channels without a
///     `RootIsolateToken`, and ML Kit's segmenter is bound to the main one).
///  2. `evaluateFootMask` — pure Dart over ~65K confidences (connected
///     components + PCA). CPU-heavy, no platform needs, safe to move.
///
/// This file moves only (2) via `Isolate.run` with primitives-only params.
/// `Rect` is serialized to `[l,t,r,b]` because `dart:ui` objects are not
/// guaranteed sendable. Any isolate failure falls back to the synchronous
/// call so detection never breaks because the isolate did.
library;

import 'dart:isolate';
import 'dart:ui' show Rect;

import 'foot_detector.dart';

/// Params that cross the isolate boundary — primitives only.
class FootMaskIsolateParams {
  FootMaskIsolateParams({
    required this.confidences,
    required this.width,
    required this.height,
    required this.threshold,
    this.preferSide,
    this.guideLtrb,
    this.frameWidth,
    this.frameHeight,
  });

  final List<double> confidences;
  final int width;
  final int height;
  final double threshold;
  final String? preferSide;
  final List<double>? guideLtrb;
  final int? frameWidth;
  final int? frameHeight;
}

FootDetectionResult _evaluateInIsolate(FootMaskIsolateParams p) {
  Rect? guide;
  final ltrb = p.guideLtrb;
  if (ltrb != null && ltrb.length == 4) {
    guide = Rect.fromLTRB(ltrb[0], ltrb[1], ltrb[2], ltrb[3]);
  }
  return evaluateFootMask(
    confidences: p.confidences,
    width: p.width,
    height: p.height,
    threshold: p.threshold,
    preferSide: p.preferSide,
    guideRect: guide,
    frameWidth: p.frameWidth,
    frameHeight: p.frameHeight,
  );
}

/// Runs [evaluateFootMask] off the main isolate.
///
/// Falls back to the synchronous call on any error so a broken isolate
/// costs one frame of jank, never the loop.
Future<FootDetectionResult> evaluateFootMaskOffMain({
  required List<double> confidences,
  required int width,
  required int height,
  double threshold = minFootDetectionConfidence,
  String? preferSide,
  Rect? guideRect,
  int? frameWidth,
  int? frameHeight,
}) async {
  final params = FootMaskIsolateParams(
    confidences: confidences,
    width: width,
    height: height,
    threshold: threshold,
    preferSide: preferSide,
    guideLtrb: guideRect == null
        ? null
        : <double>[
            guideRect.left,
            guideRect.top,
            guideRect.right,
            guideRect.bottom,
          ],
    frameWidth: frameWidth,
    frameHeight: frameHeight,
  );
  try {
    return await Isolate.run(() => _evaluateInIsolate(params));
  } catch (_) {
    return evaluateFootMask(
      confidences: confidences,
      width: width,
      height: height,
      threshold: threshold,
      preferSide: preferSide,
      guideRect: guideRect,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
    );
  }
}
