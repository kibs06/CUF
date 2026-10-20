/// Guided card-capture coaching: pure decision logic for the card+foot
/// capture flow.
///
/// Maps a reference detector's corner output to the exact coaching state
/// the capture screen shows, and summarizes an auto-capture burst of scale
/// samples (median + IQR) for the confidence the results screen stores.
///
/// All functions are deterministic and independently testable — no camera,
/// no widgets. The screen owns the detector (still simulated until the CV
/// pipeline lands) and the timers; this file owns *what each detection
/// means* so tilted/lifted cards always re-coach instead of measuring.
library;

import 'dart:ui';

import 'ar_foot_measurement_pipeline.dart' show filterOutliersIqr;
import 'foot_measurement_utils.dart';

// ═══════════════════════════════════════════════════════════════════
// BURST CAPTURE CONSTANTS
// ═══════════════════════════════════════════════════════════════════

/// Frames per auto-capture burst (mission spec: 5–8). Six gives the IQR
/// pipeline enough samples to drop one outlier and still hold five.
const int cardBurstFrameCount = 6;

/// Hold-still dwell before the burst fires (ms). The detector must report
/// `ready` continuously through this window; any regress resets it.
const int cardHoldStillMs = 1000;

/// Minimum scale samples needed to summarize a burst. Below this the burst
/// is discarded and the user re-captures (never a single-frame number).
const int cardBurstMinSamples = 4;

// ═══════════════════════════════════════════════════════════════════
// COACH STATES
// ═══════════════════════════════════════════════════════════════════

/// What the capture screen shows for the current detector output.
enum CardCoachStatus {
  /// No usable quad yet — keep framing foot + reference.
  searching,

  /// Quad too small — phone too far. Never measure, ask to move closer.
  tooSmall,

  /// Keystoned / side-mismatched quad — card lifted or phone tilted.
  /// Never measure, ask to lay flat / hold perpendicular.
  tilted,

  /// Aspect far from the reference — wrong object or severe tilt.
  wrongObject,

  /// Good quad, hold-still dwell in progress (0.0–1.0).
  holding,

  /// Dwell complete — burst may fire.
  ready,
}

/// One coaching decision: what to show and whether to measure.
class CardCoachState {
  final CardCoachStatus status;

  /// Exact line the guidance bar shows.
  final String message;

  /// Detection confidence 0.0–1.0 for the progress UI. Null when there is
  /// nothing to score (searching).
  final double? confidence;

  const CardCoachState({
    required this.status,
    required this.message,
    this.confidence,
  });

  /// True only when the hold-still dwell may run / burst may fire.
  bool get isMeasurable =>
      status == CardCoachStatus.holding || status == CardCoachStatus.ready;
}

/// Reference-agnostic copy: works for card, A4, and Letter via [paper].
/// [footLabel] is 'left'/'right' for the per-foot guidance line.
CardCoachState coachForDetection({
  required List<Offset> corners,
  required PaperDimensions paper,
  required String footLabel,
  double holdProgress = 0.0,
}) {
  final refName = paper.isCard ? 'card' : 'paper';
  if (corners.isEmpty) {
    return CardCoachState(
      status: CardCoachStatus.searching,
      message: paper.isCard
          ? 'Place your $footLabel foot beside the card, both flat on the floor'
          : 'Place your $footLabel foot on the ${paper.name} paper',
    );
  }
  final issues = diagnoseReferenceQuad(corners, paper);
  if (issues.contains(ReferenceQuadIssue.tooSmall)) {
    return CardCoachState(
      status: CardCoachStatus.tooSmall,
      message: 'Move closer — the $refName is too small to measure from',
      confidence: computePaperConfidence(corners),
    );
  }
  if (issues.contains(ReferenceQuadIssue.keystoned) ||
      issues.contains(ReferenceQuadIssue.sideMismatch)) {
    return CardCoachState(
      status: CardCoachStatus.tilted,
      message: paper.isCard
          ? 'Lay the card flat and hold the phone straight above it'
          : 'Hold the phone straight above the paper — no angle',
      confidence: computePaperConfidence(corners),
    );
  }
  if (issues.isNotEmpty) {
    return CardCoachState(
      status: CardCoachStatus.wrongObject,
      message: paper.isCard
          ? 'That doesn\'t look like a card — frame the whole card next to your foot'
          : 'Frame the whole ${paper.name} sheet next to your foot',
      confidence: computePaperConfidence(corners),
    );
  }
  final confidence = computePaperConfidence(corners);
  if (holdProgress >= 1.0) {
    return CardCoachState(
      status: CardCoachStatus.ready,
      message: 'Capturing your $footLabel foot… hold still',
      confidence: confidence,
    );
  }
  if (holdProgress > 0.0) {
    return CardCoachState(
      status: CardCoachStatus.holding,
      message: 'Hold still… keeping the $refName in frame',
      confidence: confidence,
    );
  }
  return CardCoachState(
    status: CardCoachStatus.holding,
    message: 'Good — hold still to capture your $footLabel foot',
    confidence: confidence,
  );
}

// ═══════════════════════════════════════════════════════════════════
// BURST SUMMARY (median + IQR over per-frame scale samples)
// ═══════════════════════════════════════════════════════════════════

/// Median + spread of one burst's mm-per-pixel scale samples.
///
/// Outliers are IQR-filtered first (a hand shake mid-burst must not move
/// the number). Returns null when fewer than [cardBurstMinSamples] valid
/// samples exist — the caller re-captures instead of sizing.
class BurstScaleSummary {
  /// Median mm/px — the scale the measurement uses.
  final double medianScale;

  /// IQR of kept samples in mm/px — stored as the burst confidence spread.
  final double iqrScale;

  /// Raw samples collected.
  final int rawCount;

  /// Samples kept after IQR filtering.
  final int keptCount;

  const BurstScaleSummary({
    required this.medianScale,
    required this.iqrScale,
    required this.rawCount,
    required this.keptCount,
  });
}

BurstScaleSummary? summarizeScaleSamples(List<double> scales) {
  final valid = scales.where((s) => s.isFinite && s > 0).toList();
  if (valid.length < cardBurstMinSamples) return null;
  final kept = filterOutliersIqr(valid);
  if (kept.length < cardBurstMinSamples) return null;
  kept.sort();
  final median = kept.length.isOdd
      ? kept[kept.length ~/ 2]
      : (kept[kept.length ~/ 2 - 1] + kept[kept.length ~/ 2]) / 2;
  final q1 = _pct(kept, 0.25);
  final q3 = _pct(kept, 0.75);
  return BurstScaleSummary(
    medianScale: median,
    iqrScale: (q3 - q1).clamp(0.0, double.infinity),
    rawCount: valid.length,
    keptCount: kept.length,
  );
}

/// Map a burst's scale spread to the confidence level the sizing path uses.
///
/// Relative spread (IQR ÷ median) under 1% is a rock-steady burst (high);
/// under 3% is normal hand shake (medium); anything wider is low — the
/// results screen shows a range and a confirm-fit note instead of a
/// single pretending-exact size. Non-finite or non-positive medians
/// conservatively return 'low'.
String burstConfidenceLevel({
  required double scaleMedian,
  required double scaleIqr,
}) {
  if (!scaleMedian.isFinite || !scaleIqr.isFinite || !(scaleMedian > 0)) {
    return 'low';
  }
  final rel = (scaleIqr / scaleMedian).clamp(0.0, double.infinity);
  if (rel < 0.01) return 'high';
  if (rel < 0.03) return 'medium';
  return 'low';
}

double _pct(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0;
  if (sorted.length == 1) return sorted[0];
  final index = p * (sorted.length - 1);
  final lower = index.floor();
  final upper = index.ceil();
  if (lower == upper) return sorted[lower];
  final fraction = index - lower;
  return sorted[lower] + fraction * (sorted[upper] - sorted[lower]);
}
