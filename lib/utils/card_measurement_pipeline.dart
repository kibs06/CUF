/// Card measurement pipeline: the single validator-gated mm path from a
/// card-referenced capture to a displayable size recommendation.
///
/// This is the function production calls once the detector (corners) and
/// segmentation (outline) are both real. Until then it is exercised by
/// hostile tests through this exact entry point — no parallel logic in
/// the screens. Every refusal returns a typed failure so the UI re-coaches
/// instead of sizing garbage:
///
/// 1. outline present and non-degenerate, else [CardMeasurementFailure.outlineInvalid]
/// 2. reference quad passes [diagnoseReferenceQuad], else `referenceInvalid`
/// 3. rectified homography measurement succeeds, else `referenceInvalid`
///    (singular plane) or `outlineInvalid` (degenerate outline)
/// 4. raw mm inside hard-reject plausibility bounds, else `implausibleMeasurement`
/// 5. sock compensation → [recommendCardSizes], else `sizingOutOfRange`
library;

import 'dart:ui';

import 'foot_measurement_utils.dart';

/// Why a card capture produced no measurement.
enum CardMeasurementFailure {
  /// Reference quad failed validation (tilted / lifted / too small / wrong
  /// object / missing). The UI re-coaches the exact fix from the issues.
  referenceInvalid,

  /// No usable foot outline (missing, too few points, degenerate).
  outlineInvalid,

  /// Rectified mm outside hard-reject plausibility bounds.
  implausibleMeasurement,

  /// Plausible mm that maps to no size (outside the chart entirely).
  sizingOutOfRange,
}

/// A successful card measurement, ready for display and saving.
class CardMeasurementSuccess {
  /// Raw rectified length/width in mm (pre-compensation).
  final double lengthMm;
  final double widthMm;

  /// Post-sock-compensation values used for sizing.
  final double compensatedLengthMm;
  final double compensatedWidthMm;

  /// EU/US/UK + range + confidence label (no fake precision).
  final CardSizeRecommendation recommendation;

  /// Burst provenance for the stored confidence fields.
  final double scaleMedian;
  final double scaleIqrMmPerPx;
  final int burstFrames;

  const CardMeasurementSuccess({
    required this.lengthMm,
    required this.widthMm,
    required this.compensatedLengthMm,
    required this.compensatedWidthMm,
    required this.recommendation,
    required this.scaleMedian,
    required this.scaleIqrMmPerPx,
    required this.burstFrames,
  });
}

/// Outcome of [measureCardCapture]: either [success] or [failure] + the
/// validator [issues] that explain a `referenceInvalid` refusal.
class CardMeasurementOutcome {
  final CardMeasurementSuccess? success;
  final CardMeasurementFailure? failure;
  final Set<ReferenceQuadIssue> issues;

  const CardMeasurementOutcome._({this.success, this.failure, this.issues = const {}});

  factory CardMeasurementOutcome.ok(CardMeasurementSuccess s) =>
      CardMeasurementOutcome._(success: s);

  factory CardMeasurementOutcome.fail(
    CardMeasurementFailure f, [
    Set<ReferenceQuadIssue> issues = const {},
  ]) =>
      CardMeasurementOutcome._(failure: f, issues: issues);

  bool get isOk => success != null;
}

CardMeasurementOutcome measureCardCapture({
  required List<Offset> refCorners,
  required List<Offset> footOutline,
  required PaperDimensions paper,
  required bool isSocks,
  required String measurementSource,
  required String confidenceLevel,
  required String shoeCategory,
  required double scaleMedian,
  required double scaleIqrMmPerPx,
  required int burstFrames,
}) {
  if (footOutline.length < 10) {
    return CardMeasurementOutcome.fail(CardMeasurementFailure.outlineInvalid);
  }
  final issues = diagnoseReferenceQuad(refCorners, paper);
  if (issues.isNotEmpty) {
    return CardMeasurementOutcome.fail(
      CardMeasurementFailure.referenceInvalid,
      issues,
    );
  }
  final measured = measureFootRectified(
    footOutline: footOutline,
    refCorners: refCorners,
    paper: paper,
  );
  if (measured == null) {
    // Quad passed the gate but the plane is singular (vanishingly rare):
    // blame the reference, never the foot.
    return CardMeasurementOutcome.fail(
      CardMeasurementFailure.referenceInvalid,
      issues,
    );
  }
  if (checkPlausibility(measured.lengthMm / 10, isLength: true) ==
          PlausibilityResult.hardReject ||
      checkPlausibility(measured.widthMm / 10, isLength: false) ==
          PlausibilityResult.hardReject) {
    return CardMeasurementOutcome.fail(
      CardMeasurementFailure.implausibleMeasurement,
    );
  }
  final compLen = applySockCompensation(
    measured.lengthMm,
    isLength: true,
    isSocks: isSocks,
  );
  final compWid = applySockCompensation(
    measured.widthMm,
    isLength: false,
    isSocks: isSocks,
  );
  // NOTE: currently unreachable — plausible mm always lands on the chart
  // (it clamps at both ends) — but recommendCardSizes' contract includes
  // null, and unwrapping it with `!` would turn a future refusal into a
  // crash. The branch stays as contract handling, not speculation.
  final recommendation = recommendCardSizes(
    compensatedLengthMm: compLen,
    measurementSource: measurementSource,
    confidenceLevel: confidenceLevel,
    shoeCategory: shoeCategory,
  );
  if (recommendation == null) {
    return CardMeasurementOutcome.fail(CardMeasurementFailure.sizingOutOfRange);
  }
  return CardMeasurementOutcome.ok(
    CardMeasurementSuccess(
      lengthMm: measured.lengthMm,
      widthMm: measured.widthMm,
      compensatedLengthMm: compLen,
      compensatedWidthMm: compWid,
      recommendation: recommendation,
      scaleMedian: scaleMedian,
      scaleIqrMmPerPx: scaleIqrMmPerPx,
      burstFrames: burstFrames,
    ),
  );
}
