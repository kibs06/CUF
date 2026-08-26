/// Statistical measurement pipeline for multi-sample AR foot scanning.
///
/// Core of the accuracy mechanism: collects multiple measurement samples
/// during a guided scan, filters outliers, and combines them via median
/// for a robust final measurement. Confidence is derived from the spread
/// of filtered samples (tight spread = high confidence).
///
/// Architecture per §5 of the implementation prompt:
/// 1. Collect samples during the scan (every 150–250ms)
/// 2. Discard low-quality samples (poor tracking, low segmentation confidence)
/// 3. Filter statistical outliers (IQR method)
/// 4. Take median of filtered samples
/// 5. Compute confidence from IQR spread
library;


// ═══════════════════════════════════════════════════════════════════
// SAMPLE DATA
// ═══════════════════════════════════════════════════════════════════

/// A single measurement sample from one frame during the AR scan.
class MeasurementSample {
  /// Foot length in mm (heel-to-toe distance in real-world space).
  final double lengthMm;

  /// Foot width in mm (widest point perpendicular to length).
  final double widthMm;

  /// ARCore tracking quality for this frame (0.0–1.0).
  /// Below [minTrackingQuality] the sample is discarded.
  final double trackingQuality;

  /// ML segmentation confidence for this frame (0.0–1.0).
  /// Below [minSegmentationConfidence] the sample is discarded.
  final double segmentationConfidence;

  /// Timestamp of the sample (for sequencing/ordering).
  final DateTime timestamp;

  /// Which guided capture produced this sample: 'front' (top-down, primary
  /// for width) or 'side' (profile, primary for length). 'both' is the
  /// legacy value for tests that don't track capture angle.
  final String captureAngle;

  /// Whether [widthMm] was actually measured from detected width points.
  ///
  /// E7 fix: when the detector supplies no width points, callers may record a
  /// proportional estimate (`length * ~0.38`) for the live readout — but that
  /// fabricated number must not pollute the width median, which would skew the
  /// narrow/standard/wide fit category for non-average feet. Estimates are
  /// tagged `widthMeasured: false` and excluded from width statistics.
  /// Defaults to `true` so existing call sites keep their behavior.
  final bool widthMeasured;

  const MeasurementSample({
    required this.lengthMm,
    required this.widthMm,
    required this.trackingQuality,
    required this.segmentationConfidence,
    required this.timestamp,
    this.captureAngle = 'both',
    this.widthMeasured = true,
  });

  @override
  String toString() =>
      'Sample(${lengthMm.toStringAsFixed(1)}mm × ${widthMm.toStringAsFixed(1)}mm, '
      'angle=$captureAngle, measuredW=$widthMeasured, '
      'track=${trackingQuality.toStringAsFixed(2)}, '
      'seg=${segmentationConfidence.toStringAsFixed(2)})';
}

// ═══════════════════════════════════════════════════════════════════
// QUALITY THRESHOLDS
// ═══════════════════════════════════════════════════════════════════

/// Minimum ARCore tracking quality to accept a sample.
/// ARCore reports TrackingState as TRACKING(1.0), PAUSED(0.0), LIMITED(0.5).
/// We reject samples below this threshold to avoid noisy measurements.
const double minTrackingQuality = 0.7;

/// Minimum ML segmentation confidence to accept a sample.
/// Below this, the foot outline detection is unreliable.
const double minSegmentationConfidence = 0.5;

/// Minimum number of valid samples required for a confident measurement.
/// If fewer than this remain after filtering, we flag low confidence.
const int minValidSamples = 5;

/// Ideal number of samples for robust statistics.
/// The scan should run long enough to collect at least this many.
const int idealSampleCount = 15;

// ═══════════════════════════════════════════════════════════════════
// OUTLIER FILTERING (IQR METHOD)
// ═══════════════════════════════════════════════════════════════════

/// Filter outliers from a list of numeric values using the IQR method.
///
/// Values outside [Q1 - k*IQR, Q3 + k*IQR] are considered outliers.
/// [k] defaults to 1.5 (standard) — use 2.0 for more lenient filtering
/// if the scan environment is challenging.
///
/// Returns only the inlier values, preserving the original order.
List<double> filterOutliersIqr(List<double> values, {double k = 1.5}) {
  if (values.length < 4) return values; // Too few to filter meaningfully

  final sorted = List<double>.from(values)..sort();

  // Q1 = 25th percentile, Q3 = 75th percentile
  final q1 = _percentile(sorted, 0.25);
  final q3 = _percentile(sorted, 0.75);
  final iqr = q3 - q1;

  if (iqr < 0.001) {
    // All values are essentially the same — no outliers to filter
    return values;
  }

  final lowerBound = q1 - k * iqr;
  final upperBound = q3 + k * iqr;

  return values.where((v) => v >= lowerBound && v <= upperBound).toList();
}

/// Compute the p-th percentile of a **sorted** list.
double _percentile(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0;
  if (sorted.length == 1) return sorted[0];

  final index = p * (sorted.length - 1);
  final lower = index.floor();
  final upper = index.ceil();

  if (lower == upper) return sorted[lower];

  // Linear interpolation between the two nearest values
  final fraction = index - lower;
  return sorted[lower] + fraction * (sorted[upper] - sorted[lower]);
}

// ═══════════════════════════════════════════════════════════════════
// STATISTICAL COMBINATION
// ═══════════════════════════════════════════════════════════════════

/// Result of the statistical measurement pipeline.
class MeasurementResult {
  /// Final foot length in mm (median of filtered samples).
  final double lengthMm;

  /// Final foot width in mm (median of filtered samples).
  final double widthMm;

  /// Spread of length samples (IQR in mm) — used for confidence scoring.
  final double lengthIqrMm;

  /// Spread of width samples (IQR in mm) — used for confidence scoring.
  final double widthIqrMm;

  /// Confidence level: 'high', 'medium', or 'low'.
  final String confidence;

  /// Numeric confidence score (0.0–1.0) for storage and fine-grained use.
  final double confidenceScore;

  /// Number of raw samples collected.
  final int rawSampleCount;

  /// Number of samples after quality filtering.
  final int filteredSampleCount;

  /// Number of samples after outlier removal.
  final int finalSampleCount;

  const MeasurementResult({
    required this.lengthMm,
    required this.widthMm,
    required this.lengthIqrMm,
    required this.widthIqrMm,
    required this.confidence,
    required this.confidenceScore,
    required this.rawSampleCount,
    required this.filteredSampleCount,
    required this.finalSampleCount,
  });

  @override
  String toString() =>
      'Result(${lengthMm.toStringAsFixed(1)}mm × ${widthMm.toStringAsFixed(1)}mm, '
      'conf=$confidence (${confidenceScore.toStringAsFixed(2)}), '
      'samples=$finalSampleCount/$filteredSampleCount/$rawSampleCount)';
}

/// Combine multiple measurement samples into a single robust measurement.
///
/// Pipeline (§5.3 of the implementation prompt):
/// 1. Filter out low-quality samples (poor tracking or segmentation)
/// 2. Extract length and width arrays
/// 3. Filter outliers via IQR method
/// 4. Compute median of filtered values
/// 5. Compute confidence from IQR spread and sample count
///
/// Returns `null` if fewer than [minValidSamples] survive filtering.
MeasurementResult? combineSamples(List<MeasurementSample> samples) {
  if (samples.isEmpty) return null;

  final rawCount = samples.length;

  // Step 1: Filter by quality thresholds
  final qualitySamples = samples.where((s) =>
      s.trackingQuality >= minTrackingQuality &&
      s.segmentationConfidence >= minSegmentationConfidence).toList();

  if (qualitySamples.length < minValidSamples) return null;

  // Step 2: Extract length and width arrays
  final lengths = qualitySamples.map((s) => s.lengthMm).toList();
  final widths = qualitySamples.map((s) => s.widthMm).toList();

  // Step 3: Filter outliers
  final filteredLengths = filterOutliersIqr(lengths);
  final filteredWidths = filterOutliersIqr(widths);

  // Ensure we still have enough samples after outlier removal
  if (filteredLengths.length < minValidSamples ||
      filteredWidths.length < minValidSamples) {
    return null;
  }

  // Step 4: Compute median (robust to remaining outliers)
  final lengthMedian = _median(filteredLengths);
  final widthMedian = _median(filteredWidths);

  // Step 5: Compute IQR spread for confidence
  final lengthIqr = _iqr(filteredLengths);
  final widthIqr = _iqr(filteredWidths);

  // Step 6: Compute confidence score
  final confidenceScore = _computeConfidence(
    lengthIqr: lengthIqr,
    widthIqr: widthIqr,
    sampleCount: filteredLengths.length,
    medianLength: lengthMedian,
  );

  final confidence = _confidenceLabel(confidenceScore);

  return MeasurementResult(
    lengthMm: lengthMedian,
    widthMm: widthMedian,
    lengthIqrMm: lengthIqr,
    widthIqrMm: widthIqr,
    confidence: confidence,
    confidenceScore: confidenceScore,
    rawSampleCount: rawCount,
    filteredSampleCount: qualitySamples.length,
    finalSampleCount: filteredLengths.length,
  );
}

/// Combine guided-capture samples into a single robust measurement, using
/// the two-angle structure (§2.4 of the guided capture brief):
///
/// - **Front/top-down capture** (`captureAngle == 'front'`) is primarily for
///   **width** — a top-down view sees the foot's full lateral extent without
///   leg/ankle foreshortening.
/// - **Side/profile capture** (`captureAngle == 'side'`) is primarily for
///   **length** — a straight-on profile avoids toe-overlap/perspective
///   foreshortening that a top-down view can introduce.
///
/// Each angle's samples still carry BOTH dimensions (both are computed from
/// the same mask via hitTest), but the final measurement trusts the angle
/// best suited to each dimension. Samples with the legacy
/// `captureAngle == 'both'` count for either dimension.
///
/// Falls back to all samples for a dimension when an angle produced too few
/// samples to filter statistically.
///
/// Returns `null` if fewer than [minValidSamples] survive filtering.
MeasurementResult? combineGuidedSamples(List<MeasurementSample> samples) {
  if (samples.isEmpty) return null;

  final rawCount = samples.length;

  // Step 1: Filter by quality thresholds
  final qualitySamples = samples.where((s) =>
      s.trackingQuality >= minTrackingQuality &&
      s.segmentationConfidence >= minSegmentationConfidence).toList();

  if (qualitySamples.length < minValidSamples) return null;

  // Step 2: Split by capture angle. 'both' is the legacy value that counts
  // for either angle.
  final sideSamples = qualitySamples
      .where((s) => s.captureAngle == 'side' || s.captureAngle == 'both')
      .toList();
  final frontSamples = qualitySamples
      .where((s) => s.captureAngle == 'front' || s.captureAngle == 'both')
      .toList();

  // Length comes primarily from the side/profile capture; width primarily
  // from the front/top-down capture.
  final lengthSource = sideSamples.length >= minValidSamples
      ? sideSamples
      : qualitySamples;
  final widthSource = frontSamples.length >= minValidSamples
      ? frontSamples
      : qualitySamples;

  // E7 fix: width statistics use only samples whose width was actually
  // measured from detected width points. Proportional estimates (tagged
  // `widthMeasured: false`) are excluded so an average-foot ratio can't skew
  // the median — and therefore the narrow/standard/wide fit category. Fall
  // back to the full width source when too few measured widths exist, so a
  // scan that never detected width points still produces a (low-confidence)
  // result instead of failing outright.
  final measuredWidthSource = widthSource
      .where((s) => s.widthMeasured)
      .toList();
  final effectiveWidthSource =
      measuredWidthSource.length >= minValidSamples
          ? measuredWidthSource
          : widthSource;

  // Step 3: Extract per-dimension arrays
  final lengths = lengthSource.map((s) => s.lengthMm).toList();
  final widths = effectiveWidthSource.map((s) => s.widthMm).toList();

  // Step 4: Filter outliers
  final filteredLengths = filterOutliersIqr(lengths);
  final filteredWidths = filterOutliersIqr(widths);

  if (filteredLengths.length < minValidSamples ||
      filteredWidths.length < minValidSamples) {
    return null;
  }

  // Step 5: Compute medians
  final lengthMedian = _median(filteredLengths);
  final widthMedian = _median(filteredWidths);

  // Step 6: Compute IQR spread for confidence
  final lengthIqr = _iqr(filteredLengths);
  final widthIqr = _iqr(filteredWidths);

  // Step 7: Confidence
  final confidenceScore = _computeConfidence(
    lengthIqr: lengthIqr,
    widthIqr: widthIqr,
    sampleCount: filteredLengths.length,
    medianLength: lengthMedian,
  );

  final confidence = _confidenceLabel(confidenceScore);

  return MeasurementResult(
    lengthMm: lengthMedian,
    widthMm: widthMedian,
    lengthIqrMm: lengthIqr,
    widthIqrMm: widthIqr,
    confidence: confidence,
    confidenceScore: confidenceScore,
    rawSampleCount: rawCount,
    filteredSampleCount: qualitySamples.length,
    finalSampleCount: filteredLengths.length,
  );
}

/// Compute the median of a list of doubles.
double _median(List<double> values) {
  if (values.isEmpty) return 0;
  if (values.length == 1) return values[0];

  final sorted = List<double>.from(values)..sort();
  final mid = sorted.length ~/ 2;

  if (sorted.length.isOdd) {
    return sorted[mid];
  } else {
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }
}

/// Compute the IQR (Interquartile Range) of a list of doubles.
double _iqr(List<double> values) {
  if (values.length < 4) return 0;

  final sorted = List<double>.from(values)..sort();
  final q1 = _percentile(sorted, 0.25);
  final q3 = _percentile(sorted, 0.75);
  return q3 - q1;
}

// ═══════════════════════════════════════════════════════════════════
// CONFIDENCE SCORING
// ═══════════════════════════════════════════════════════════════════

/// Compute a confidence score (0.0–1.0) from measurement characteristics.
///
/// Factors:
/// - **IQR spread**: Tighter spread → higher confidence. For a 270mm foot,
///   an IQR of 2mm is excellent; 10mm is concerning.
/// - **Sample count**: More samples → more reliable statistics.
/// - **IQR relative to length**: Normalized spread metric.
///
/// The thresholds below are tunable (§11: "start with reasonable defaults,
/// flag as tunable once real ground-truth data comes in").
double _computeConfidence({
  required double lengthIqr,
  required double widthIqr,
  required int sampleCount,
  required double medianLength,
}) {
  // Factor 1: IQR spread (0.0–1.0, higher = tighter = better)
  // IQR < 2mm = excellent, IQR > 12mm = poor
  final lengthSpreadScore = 1.0 - (lengthIqr / 12.0).clamp(0.0, 1.0);
  final widthSpreadScore = 1.0 - (widthIqr / 12.0).clamp(0.0, 1.0);
  final spreadScore = (lengthSpreadScore * 0.6 + widthSpreadScore * 0.4);

  // Factor 2: Sample count (0.0–1.0)
  // < 5 = 0.3, 5–10 = 0.6–0.8, > 15 = 1.0
  double sampleScore;
  if (sampleCount >= idealSampleCount) {
    sampleScore = 1.0;
  } else if (sampleCount >= minValidSamples) {
    sampleScore = 0.3 + 0.7 * (sampleCount - minValidSamples) /
        (idealSampleCount - minValidSamples);
  } else {
    sampleScore = 0.3;
  }

  // Factor 3: Relative spread (IQR as % of foot length)
  // < 0.5% = excellent, > 5% = poor
  final relativeSpread = medianLength > 0 ? lengthIqr / medianLength : 0.1;
  final relativeScore = 1.0 - (relativeSpread / 0.05).clamp(0.0, 1.0);

  // Weighted combination
  final confidence = (spreadScore * 0.50 + sampleScore * 0.25 + relativeScore * 0.25)
      .clamp(0.0, 1.0);

  return confidence;
}

/// Convert a numeric confidence score (0.0–1.0) to a human-readable label.
///
/// Thresholds:
/// - ≥ 0.75 → 'high'
/// - ≥ 0.45 → 'medium'
/// - < 0.45 → 'low'
String _confidenceLabel(double score) {
  if (score >= 0.75) return 'high';
  if (score >= 0.45) return 'medium';
  return 'low';
}

// ═══════════════════════════════════════════════════════════════════
// TRACKING QUALITY ASSESSMENT
// ═══════════════════════════════════════════════════════════════════

/// Assess whether the current AR session state is suitable for measurement.
///
/// Returns a [TrackingAssessment] with a readiness flag and coaching message.
class TrackingAssessment {
  final bool ready;
  final String message;
  final String state; // 'initializing', 'searching', 'tracking', 'limited', 'lost'

  const TrackingAssessment({
    required this.ready,
    required this.message,
    required this.state,
  });
}

/// Assess ARCore tracking state for scan readiness.
///
/// [trackingState] maps from ARCore's TrackingState:
/// - 1.0 = TRACKING (good)
/// - 0.5 = LIMITED (need coaching)
/// - 0.0 = PAUSED (need reinitialization)
///
/// [planeDetected] indicates whether a horizontal floor plane has been found.
/// [sessionDuration] is how long the session has been active.
///
/// [areaTracked] — when provided (non-null) — is the LOCALIZED plane signal
/// (§2 of EFFICIENCY_ACCURACY_OVERHAUL_PROMPT): it reflects whether a tracked
/// plane covers the guide-box region specifically. When set, it takes
/// precedence over [planeDetected], so capture becomes ready as soon as the
/// small floor area under the guide box is mapped — no whole-room mapping
/// required. When null, falls back to [planeDetected] (legacy behavior).
TrackingAssessment assessTracking({
  required double trackingState,
  required bool planeDetected,
  required Duration sessionDuration,
  bool? areaTracked,
}) {
  if (trackingState <= 0.0) {
    return const TrackingAssessment(
      ready: false,
      message: 'AR tracking lost — move your phone slowly to reinitialize',
      state: 'lost',
    );
  }

  if (trackingState < 0.7) {
    return const TrackingAssessment(
      ready: false,
      message: 'Tracking is limited — move your phone slowly side to side',
      state: 'limited',
    );
  }

  // §2 localized readiness: the guide-box region must be on a tracked plane.
  final boxAreaTracked = areaTracked ?? planeDetected;
  if (!boxAreaTracked) {
    if (sessionDuration.inSeconds < 5) {
      return const TrackingAssessment(
        ready: false,
        message: 'Searching for the floor under the guide box...',
        state: 'searching',
      );
    }
    return const TrackingAssessment(
      ready: false,
      message: 'Point the guide box at the floor — move your phone slowly so the area is tracked',
      state: 'searching',
    );
  }

  return const TrackingAssessment(
    ready: true,
    message: 'Guide-box area tracked — begin scan',
    state: 'tracking',
  );
}

// ═══════════════════════════════════════════════════════════════════
// SCAN PROGRESS
// ═══════════════════════════════════════════════════════════════════

/// Duration of the guided scan arc in seconds.
/// During this window, samples are collected at [sampleIntervalMs].
const Duration scanDuration = Duration(seconds: 4);

/// Interval between samples in milliseconds.
/// 200ms = 5 samples/second, ~20 samples over a 4-second scan.
const int sampleIntervalMs = 200;

/// Compute scan progress (0.0–1.0) based on elapsed time since scan started.
double scanProgress(DateTime scanStartTime) {
  final elapsed = DateTime.now().difference(scanStartTime);
  return (elapsed.inMilliseconds / scanDuration.inMilliseconds).clamp(0.0, 1.0);
}

/// Whether the scan window has completed.
bool scanComplete(DateTime scanStartTime) {
  return scanProgress(scanStartTime) >= 1.0;
}
