/// Pure conversion from a detected foot to the pose frame the renderer
/// consumes (`docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md` V4.1, design
/// `VIRTUAL_FITTING_ARCHITECTURE.md` §2.8/§2.9).
///
/// **Why this is a pure function and not a method on the controller.** The
/// numbers that cross to native are the same numbers the scan's measurement
/// pipeline trusts, and this mapping is where a coordinate convention can be
/// flipped without anything throwing: normalized UV in, normalized UV out, no
/// ARCore, no ML runtime, no channel. Table-driven tests pin every branch.
///
/// **What the renderer does with it, and what it does not.** The points are raw
/// observations in *upright-image normalized* coordinates — the space ARCore's
/// `hitTest` takes, the same space `FootPoint` uses. All smoothing, the world
/// basis and the lock hysteresis live in the native `FootPoseTracker` (V4.2);
/// Dart publishes observations at ≥5 Hz and must not pre-filter them into
/// something the native side cannot undo. The one judgement made here is
/// *which* detections become frames at all — see [footPoseFromDetection].
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../services/ar_try_on_channel.dart';
import 'foot_detector.dart';

/// **E7's width estimate**: a foot silhouette is roughly `length × 0.38`.
///
/// Used only when the detector cannot supply a widest-point pair (the pose
/// detector has no width landmarks; the segmentation detector usually does).
/// Named rather than inlined because two other call sites carry the same
/// ratio, and a third silent copy is how three estimates start to disagree.
const double kProportionalFootWidthRatio = 0.38;

/// Builds the pose frame for one accepted detection, or null when the frame
/// cannot describe a foot's axis.
///
/// Requirements, in order:
///
///   1. `detection.footDetected` — the detector's combined score already
///      cleared `kSampleAcceptScore`, so a low-quality frame never becomes a
///      pose. This is the same gate the scan uses to record a sample, not a
///      second threshold invented for rendering.
///   2. heel and toe both present. They define the forward axis; a frame
///      missing either end cannot be repaired by guessing, and a guessed axis
///      rotates a shoe on a customer's screen.
///
/// Width points are optional by design — [FootDetectionResult.widthPoints]
/// documents them as segmentation-only — and the fallback is the documented
/// proportional pair: two points straddling the heel–toe midpoint,
/// perpendicular to the foot's axis, half of `length × 0.38` either side.
///
/// [FootPoseFrame.confidence] is `qualityScore`, the combined score: it is the
/// one number that already blends segmentation, shape and containment, and it
/// is the number the native lock hysteresis compares against §2.9's 0.7/0.45.
FootPoseFrame? footPoseFromDetection(FootDetectionResult detection) {
  if (!detection.footDetected) return null;

  final heel = detection.heelPoint;
  final toe = detection.toePoint;
  if (heel == null || toe == null) return null;

  final List<Offset> width;
  final widthPoints = detection.widthPoints;
  if (widthPoints != null && widthPoints.length >= 2) {
    // The widest pair as the detector emitted it. First/last rather than
    // sorted by confidence: the pair is an ordered observation (left/right of
    // the mask), and reordering it would rotate the shoe's lateral axis.
    width = <Offset>[
      widthPoints.first.asOffset,
      widthPoints.last.asOffset,
    ];
  } else {
    width = proportionalWidthPoints(heel.asOffset, toe.asOffset);
  }

  return FootPoseFrame(
    heelUv: heel.asOffset,
    toeUv: toe.asOffset,
    widthUv: width,
    confidence: detection.qualityScore,
    footSide: detection.footSide,
  );
}

/// The perpendicular width pair for a heel–toe axis, or empty when the axis has
/// no length.
///
/// Exposed rather than private because the fallback is a *rule* — tests drive it
/// directly with axes that are horizontal, vertical and degenerate, which is
/// three cases a detector fake would only reach by accident.
List<Offset> proportionalWidthPoints(Offset heel, Offset toe) {
  final dx = toe.dx - heel.dx;
  final dy = toe.dy - heel.dy;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length <= 0) return const <Offset>[];

  final half = length * kProportionalFootWidthRatio / 2;
  // Perpendicular unit vector × half-width. Screen coordinates: y grows down,
  // but the pair is symmetric about the axis, so the sign convention cannot
  // change the shape — only which point is first, and both are sent.
  final px = -dy / length * half;
  final py = dx / length * half;
  final midX = (heel.dx + toe.dx) / 2;
  final midY = (heel.dy + toe.dy) / 2;
  return <Offset>[
    Offset(midX - px, midY - py),
    Offset(midX + px, midY + py),
  ];
}
