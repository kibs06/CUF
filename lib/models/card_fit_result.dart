/// The handoff from a single-foot card capture to the live AR try-on.
///
/// [FootCaptureScreen] in `singleFootInstant` mode computes this through the
/// same validator-gated path as the sizing flow (`CvReferenceDetector` →
/// `coachForDetection` → hold dwell → burst → `measureCardCapture`) and pops
/// it as the route result. The AR screen applies it: auto-select the size,
/// seed the controller's live reading, and let the native tracker keep
/// drawing the shoe from there.
///
/// A result is only ever built from a [CardMeasurementSuccess] — refusals
/// (`referenceInvalid`, `outlineInvalid`, …) re-coach in the capture screen
/// and never become a result, so there is no failure case here to handle.
library;

import '../utils/card_measurement_pipeline.dart';
import '../utils/size_key.dart';

/// Which foot the instant capture measured (label only — sizing uses the
/// single reading either way).
/// Mirrors the capture screen's `'left'` / `'right'` side strings.
class CardFitResult {
  /// Post-sock-compensation length in mm — the number sizing and the live
  /// reading are seeded from.
  final double compensatedLengthMm;

  /// Raw rectified width in mm (display only; the tracker is length-only).
  final double widthMm;

  /// Recommended EU size label from the pipeline (e.g. `'42'`).
  final String sizeEu;

  /// Burst provenance, stored for the same confidence fields the results
  /// screens persist.
  final double scaleMedian;
  final double scaleIqrMmPerPx;
  final int burstFrames;

  /// `'high'` | `'medium'` | `'low'`, from the burst IQR spread.
  final String confidenceLevel;

  /// `'left'` | `'right'`.
  final String footSide;

  const CardFitResult({
    required this.compensatedLengthMm,
    required this.widthMm,
    required this.sizeEu,
    required this.scaleMedian,
    required this.scaleIqrMmPerPx,
    required this.burstFrames,
    required this.confidenceLevel,
    required this.footSide,
  });

  /// The only construction path: a successful pipeline outcome.
  ///
  /// [burstConfidenceLevel] is the burst's level (`'high'` | `'medium'` |
  /// `'low'`) — the same string the pipeline was graded with — not the
  /// recommendation's display sentence (`'High confidence'`, ...).
  factory CardFitResult.fromSuccess(
    CardMeasurementSuccess success, {
    required String footSide,
    required String burstConfidenceLevel,
  }) =>
      CardFitResult(
        compensatedLengthMm: success.compensatedLengthMm,
        widthMm: success.widthMm,
        sizeEu: success.recommendation.eu,
        scaleMedian: success.scaleMedian,
        scaleIqrMmPerPx: success.scaleIqrMmPerPx,
        burstFrames: success.burstFrames,
        confidenceLevel: burstConfidenceLevel,
        footSide: footSide,
      );

  /// The snackbar sentence for an applied result: exact, nearest in stock,
  /// or an honest out-of-stock — the three outcomes the try-on screen must
  /// tell apart, in one tested place instead of a widget.
  static String appliedMessage({
    required String recommendedEu,
    required String? fitted,
  }) {
    if (fitted == null) {
      return 'Card fit measured EU $recommendedEu — not in stock for this shoe';
    }
    if (sizeKey(fitted) == sizeKey(recommendedEu)) {
      return 'Card fit applied: ${formatSize(fitted)}';
    }
    return 'Card fit measured EU $recommendedEu — '
        'nearest in stock is ${formatSize(fitted)}';
  }

  /// Live-reading quality (0.0–1.0) derived from the burst confidence label.
  ///
  /// A steady burst earns a reading the verdict card can grade; a shaky one
  /// still seeds the size but stays a nudge until the tracker confirms it.
  double get liveQuality => switch (confidenceLevel) {
        'high' => 0.9,
        'medium' => 0.7,
        _ => 0.4,
      };
}

/// Pick the catalog size to wear for a calibrated EU size.
///
/// Exact in-stock match wins. Otherwise the nearest in-stock size within half
/// a size (the app's "closest available" tolerance, [kNearSizeToleranceEu])
/// — never a silent substitution across the chart. Null when nothing in
/// stock is close enough, so the caller keeps the current selection and says
/// so instead of jumping sizes.
String? pickStockSizeForFit({
  required Map<String, dynamic> sizes,
  required String recommendedEu,
}) {
  final want = sizeNumberInEu(recommendedEu);
  if (want == null) return null;
  String? bestKey;
  var bestGap = double.infinity;
  sizes.forEach((key, qty) {
    if ((qty as int) <= 0) return;
    final candidate = sizeNumberInEu(key);
    if (candidate == null) return;
    final gap = (candidate - want).abs();
    if (gap < bestGap) {
      bestGap = gap;
      bestKey = key;
    }
  });
  if (bestKey == null) return null;
  if (bestGap > kNearSizeToleranceEu) return null;
  return bestKey;
}
