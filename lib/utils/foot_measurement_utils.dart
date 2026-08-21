/// Measurement utilities for the AR Foot Sizing feature.
///
/// Contains pure functions for:
/// - Paper corner detection confidence
/// - Pixels-to-millimeters conversion using known paper dimensions
/// - Foot outline segmentation (pixel bounding box → mm)
/// - EU/US/UK shoe size chart mapping
/// - Sock-thickness compensation
/// - Width-to-fit category
/// - Plausibility guards (soft-warn / hard-reject tiers)
/// - Safety margin application
///
/// All functions are deterministic and independently testable.
library;

import 'dart:math' as math;
import 'dart:ui';

// ═══════════════════════════════════════════════════════════════════
// PAPER DIMENSIONS (known real-world sizes)
// ═══════════════════════════════════════════════════════════════════

/// Paper dimensions in millimeters.
/// Used as the scale reference for pixel→mm conversion.
class PaperDimensions {
  final String name;
  final double widthMm;
  final double heightMm;

  const PaperDimensions({
    required this.name,
    required this.widthMm,
    required this.heightMm,
  });

  /// A4 paper: 210 × 297 mm
  static const a4 = PaperDimensions(
    name: 'A4',
    widthMm: 210.0,
    heightMm: 297.0,
  );

  /// US Letter: 215.9 × 279.4 mm
  static const letter = PaperDimensions(
    name: 'US Letter',
    widthMm: 215.9,
    heightMm: 279.4,
  );

  /// Get the correct dimensions for a paper size key.
  static PaperDimensions fromKey(String key) {
    return key == 'letter' ? letter : a4;
  }
}

// ═══════════════════════════════════════════════════════════════════
// PIXELS → MILLIMETERS CONVERSION
// ═══════════════════════════════════════════════════════════════════

/// Compute a pixels-to-millimeters scale factor from paper corner positions.
///
/// [paperCorners] should contain 4 corners detected in the image (in pixels).
/// [paper] is the known real-world paper dimensions.
///
/// Returns the average mm-per-pixel ratio, or `null` if corners are invalid.
///
/// Algorithm: compute the ratio of the known paper diagonal (mm) to the
/// detected diagonal (pixels). Average the two diagonals for robustness.
double? computeScaleFactor({
  required List<Offset> paperCorners,
  required PaperDimensions paper,
}) {
  if (paperCorners.length < 4) return null;

  // Known paper diagonal in mm
  final knownDiagonalMm = _hypot(paper.widthMm, paper.heightMm);

  // Sort corners: top-left, top-right, bottom-right, bottom-left
  // by angle from centroid
  final sorted = _sortCornersClockwise(paperCorners);

  // Detected diagonals in pixels (top-left↔bottom-right, top-right↔bottom-left)
  final diag1Px = _distance(sorted[0], sorted[2]);
  final diag2Px = _distance(sorted[1], sorted[3]);

  if (diag1Px < 10 || diag2Px < 10) return null; // Too small to be valid

  // Average mm-per-pixel from both diagonals
  final scale1 = knownDiagonalMm / diag1Px;
  final scale2 = knownDiagonalMm / diag2Px;

  return (scale1 + scale2) / 2;
}

/// Convert a pixel length to millimeters using the scale factor.
double pixelsToMm(double pixels, double scaleFactor) {
  return pixels * scaleFactor;
}

// ═══════════════════════════════════════════════════════════════════
// FOOT OUTLINE → MEASUREMENTS
// ═══════════════════════════════════════════════════════════════════

/// Result of foot measurement computation.
class FootMeasurementResult {
  final double lengthMm;
  final double widthMm;

  const FootMeasurementResult({
    required this.lengthMm,
    required this.widthMm,
  });
}

/// Compute foot length and width in mm from a foot outline bounding box.
///
/// [footOutline] is a list of pixel coordinates representing the foot boundary.
/// [scaleFactor] converts pixels to mm (from [computeScaleFactor]).
///
/// Foot length = longest dimension along the paper's long axis (heel to toe).
/// Foot width = widest dimension perpendicular to length.
///
/// Returns `null` if the outline is degenerate.
FootMeasurementResult? computeFootMeasurements({
  required List<Offset> footOutline,
  required double scaleFactor,
}) {
  if (footOutline.length < 10) return null; // Need reasonable point count

  // Compute the oriented bounding box using the foot's principal axis
  // via PCA (principal component analysis) on the outline points.
  final centroid = _centroid(footOutline);

  // Compute covariance matrix
  double xx = 0, xy = 0, yy = 0;
  for (final p in footOutline) {
    final dx = p.dx - centroid.dx;
    final dy = p.dy - centroid.dy;
    xx += dx * dx;
    xy += dx * dy;
    yy += dy * dy;
  }
  final n = footOutline.length.toDouble();
  xx /= n;
  xy /= n;
  yy /= n;

  // Principal axis angle (largest eigenvalue direction)
  final angle = 0.5 * math.atan2(2 * xy, xx - yy);

  // Project all points onto the principal axis and perpendicular axis
  final cosA = math.cos(angle);
  final sinA = math.sin(angle);

  double minProj = double.infinity, maxProj = double.negativeInfinity;
  double minPerp = double.infinity, maxPerp = double.negativeInfinity;

  for (final p in footOutline) {
    final dx = p.dx - centroid.dx;
    final dy = p.dy - centroid.dy;
    final proj = dx * cosA + dy * sinA;      // Along principal axis
    final perp = -dx * sinA + dy * cosA;     // Perpendicular

    if (proj < minProj) minProj = proj;
    if (proj > maxProj) maxProj = proj;
    if (perp < minPerp) minPerp = perp;
    if (perp > maxPerp) maxPerp = perp;
  }

  // Length = extent along principal axis, width = extent perpendicular
  final lengthPx = maxProj - minProj;
  final widthPx = maxPerp - minPerp;

  if (lengthPx < 10 || widthPx < 5) return null; // Too small

  // Apply a small correction: the foot is typically ~85-90% of the
  // bounding box along the principal axis due to arch curvature.
  // We use 0.92 as a conservative correction factor.
  const archCorrection = 0.92;

  return FootMeasurementResult(
    lengthMm: pixelsToMm(lengthPx * archCorrection, scaleFactor),
    widthMm: pixelsToMm(widthPx, scaleFactor),
  );
}

// ═══════════════════════════════════════════════════════════════════
// SHOE SIZE CHART (EU / Mondopoint)
// ═══════════════════════════════════════════════════════════════════

/// EU shoe size lookup table.
///
/// Based on ISO 9407 / Mondopoint: 1 EU size = 6.67mm (2/3 cm).
/// The standard manufacturing allowance is ~10-15mm added to foot length.
///
/// This table maps foot length ranges (in mm) to EU sizes.
/// Each entry: (minFootLengthMm, maxFootLengthMm, euSize).
///
/// Source: Standard EU sizing chart used by major footwear manufacturers.
const List<(double, double, String)> euSizeChart = [
  // Children's sizes (for reference)
  (133.0, 140.0, '22'),
  (140.0, 146.0, '23'),
  (146.0, 153.0, '24'),
  (153.0, 160.0, '25'),
  (160.0, 166.0, '26'),
  (166.0, 173.0, '27'),
  (173.0, 180.0, '28'),
  (180.0, 186.0, '29'),
  (186.0, 193.0, '30'),
  (193.0, 200.0, '31'),
  (200.0, 206.0, '32'),
  (206.0, 213.0, '33'),
  (213.0, 220.0, '34'),
  (220.0, 226.0, '35'),
  // Women's sizes
  (226.0, 233.0, '36'),
  (233.0, 240.0, '37'),
  (240.0, 246.0, '38'),
  (246.0, 253.0, '39'),
  (253.0, 260.0, '40'),
  // Men's sizes
  (260.0, 266.0, '41'),
  (266.0, 273.0, '42'),
  (273.0, 280.0, '43'),
  (280.0, 286.0, '44'),
  (286.0, 293.0, '45'),
  (293.0, 300.0, '46'),
  (300.0, 306.0, '47'),
  (306.0, 313.0, '48'),
];

/// Safety margin added to the measured foot length before size lookup.
///
/// Rationale: shoes need ~5-10mm of room beyond the foot for comfort.
/// We add 8mm as a conservative allowance that works across most
/// shoe types (loafers, oxfords, boots).
///
/// This value can be tuned based on feedback.
const double comfortAllowanceMm = 8.0;

/// Map a foot length in mm to an EU shoe size.
///
/// Applies [comfortAllowanceMm] to the measured length before lookup.
/// Returns the EU size as a string (e.g., '42'), or null if out of range.
String? footLengthMmToEuSize(double footLengthMm) {
  // Add comfort allowance so the shoe has room
  final adjustedLength = footLengthMm + comfortAllowanceMm;

  for (final (minMm, maxMm, euSize) in euSizeChart) {
    if (adjustedLength >= minMm && adjustedLength < maxMm) {
      return euSize;
    }
  }

  // If above the chart, return the largest size
  if (adjustedLength >= euSizeChart.last.$2) {
    return euSizeChart.last.$3;
  }

  // If below the chart, return the smallest size
  if (adjustedLength < euSizeChart.first.$1) {
    return euSizeChart.first.$3;
  }

  return null;
}

/// Convert an EU size string to a US size with category-specific offset.
///
/// Offsets sourced from standard conversion charts:
/// - Men: EU - 33
/// - Women: EU - 31.5 (women's US runs ~1.5 sizes higher for same EU)
/// - Kids: EU - 33 (same as men's for kids' sizes)
///
/// TODO(human-review): Verify these offset values against an authoritative
/// conversion chart. The women's offset is approximate and may need per-range tuning.
String? euToUs(String euSize, {String category = 'men'}) {
  final eu = double.tryParse(euSize);
  if (eu == null) return null;
  double offset;
  switch (category) {
    case 'women':
      offset = 31.5;
      break;
    case 'kids':
      offset = 33.0;
      break;
    case 'men':
    default:
      offset = 33.0;
      break;
  }
  final us = (eu - offset).round();
  return '$us';
}

/// Convert an EU size string to a UK size.
///
/// Standard approximation: UK ≈ EU - 33.5 (slightly offset from US).
String? euToUk(String euSize) {
  final eu = double.tryParse(euSize);
  if (eu == null) return null;
  final uk = (eu - 33.5).round();
  return '$uk';
}

// ═══════════════════════════════════════════════════════════════════
// SIZE RECOMMENDATION REASONING
// ═══════════════════════════════════════════════════════════════════

/// Minimum distance (mm) from a size boundary to consider the measurement
/// "near" a boundary rather than clearly within a size range.
const double kBoundaryProximityMm = 2.0;

/// Generate a human-readable reason for the EU size recommendation.
///
/// [compensatedLengthMm] is the post-sock-compensation foot length used
/// for the EU lookup. [euSize] is the recommended EU size string.
/// [measurementSource] is 'ar_guided_tap', 'ar_auto_scan', or 'paper'.
/// [confidenceLevel] is 'high', 'medium', or 'low' (nullable for manual).
///
/// Returns an honest reasoning string based on what the data actually supports.
String generateSizeRecommendationReason({
  required double compensatedLengthMm,
  required String euSize,
  required String measurementSource,
  String? confidenceLevel,
}) {
  final eu = double.tryParse(euSize);
  if (eu == null) return 'Based on your measurement, we recommend EU $euSize.';

  // Find the size boundary this EU size sits on, and the next size down.
  // EU sizes are 1 unit apart; the threshold for this size is
  // (eu - comfort_allowance_offset) mapped back to mm.
  // We use the size chart: each EU size spans ~6.67mm (2/3 cm).
  // The lower bound for this EU size is when (length + 8mm) enters this size's range.
  final sizeLowerBoundMm = eu * (20.0 / 3.0) - comfortAllowanceMm;
  final prevSizeLowerBoundMm = (eu - 1) * (20.0 / 3.0) - comfortAllowanceMm;

  // Distance from the lower boundary of the current size
  final distanceFromLowerBound = compensatedLengthMm - sizeLowerBoundMm;
  // Distance from the upper boundary of the previous size
  final distanceFromPrevUpper = compensatedLengthMm - prevSizeLowerBoundMm;

  final cmStr = (compensatedLengthMm / 10).toStringAsFixed(1);

  // Near a boundary?
  final nearPrevBoundary = distanceFromPrevUpper.abs() < kBoundaryProximityMm;

  // Auto-scan with high confidence: prefer confidence-based phrasing
  if (measurementSource == 'ar_auto_scan' && confidenceLevel == 'high') {
    if (nearPrevBoundary && eu > 35) {
      return 'You\'re close to the line between EU ${(eu - 1).round()} and EU $euSize '
          '($cmStr cm) — based on a steady scan with high confidence, we recommend EU $euSize, '
          'but if you prefer a snugger fit, EU ${(eu - 1).round()} may also work.';
    }
    return 'Based on a steady scan with high measurement confidence, we recommend EU $euSize '
        '($cmStr cm).';
  }

  // Near a size boundary: mention the adjacent size
  if (nearPrevBoundary && eu > 35) {
    return 'You\'re close to the line between EU ${(eu - 1).round()} and EU $euSize '
        '($cmStr cm) — if you prefer a snugger fit, EU ${(eu - 1).round()} may also work.';
  }

  // Clear fit, no boundary proximity
  final pastBoundary = distanceFromLowerBound > 0
      ? distanceFromLowerBound.toStringAsFixed(1)
      : '0.0';
  if (distanceFromLowerBound > 1.0) {
    return 'Your foot measures $cmStr cm — that\'s ${pastBoundary}mm past the EU $euSize '
        'threshold, so we\'ve rounded up for room to move.';
  }

  return 'Based on your measurement ($cmStr cm), we recommend EU $euSize.';
}

// ═══════════════════════════════════════════════════════════════════
// SOCK-THICKNESS COMPENSATION (§4)
// ═══════════════════════════════════════════════════════════════════

/// Sock thickness offset for length measurement (mm).
/// When the user scans with socks, the measured length includes the sock
/// material. Subtract this to approximate bare-foot length for sizing.
const double kSockLengthOffsetMm = 3.0;

/// Sock thickness offset for width measurement (mm).
/// Socks add less width than length (foot compresses laterally in socks).
const double kSockWidthOffsetMm = 2.0;

/// Apply sock-thickness compensation to a raw measurement.
///
/// [rawMm] is the measured value in millimeters.
/// [isLength] distinguishes length (larger offset) from width (smaller offset).
/// [isSocks] is true when `foot_condition == 'socks'`.
///
/// Returns the compensated measurement (raw minus sock offset if applicable).
double applySockCompensation(double rawMm, {required bool isLength, required bool isSocks}) {
  if (!isSocks) return rawMm;
  return rawMm - (isLength ? kSockLengthOffsetMm : kSockWidthOffsetMm);
}

// ═══════════════════════════════════════════════════════════════════
// WIDTH → FIT CATEGORY (§6)
// ═══════════════════════════════════════════════════════════════════

/// Width-to-length ratio thresholds for fit category.
/// Ratios below 0.36 indicate a narrow foot; above 0.42 indicate a wide foot.
///
/// TODO(human-review): These thresholds are starting points. If the project
/// has existing sizing chart data or reference tables for width categories,
/// use those instead and adjust.
const double kNarrowWidthRatioThreshold = 0.36;
const double kWideWidthRatioThreshold = 0.42;

/// Classify a foot width measurement into a fit category.
///
/// Uses a width-to-length ratio rather than a flat width threshold,
/// so the category scales sensibly across foot sizes.
///
/// [widthMm] and [lengthMm] should be the COMPENSATED (post-sock) values
/// from the sizing foot.
///
/// Returns 'narrow', 'standard', or 'wide'.
String widthMmToFitCategory(double widthMm, double lengthMm) {
  if (lengthMm <= 0) return 'standard'; // Guard against division by zero
  final ratio = widthMm / lengthMm;
  if (ratio < kNarrowWidthRatioThreshold) return 'narrow';
  if (ratio > kWideWidthRatioThreshold) return 'wide';
  return 'standard';
}

// ═══════════════════════════════════════════════════════════════════
// PLAUSIBILITY GUARDS (§7 — soft-warn / hard-reject tiers)
// ═══════════════════════════════════════════════════════════════════

/// Hard-reject bounds (cm). Measurements outside these are discarded.
const double kHardRejectMinLengthCm = 12;
const double kHardRejectMaxLengthCm = 34;
const double kHardRejectMinWidthCm = 4.5;
const double kHardRejectMaxWidthCm = 15;

/// Soft-warn bounds (cm). Measurements outside these but within hard-reject
/// trigger a "does this look right?" confirmation step.
const double kSoftWarnMinLengthCm = 15;
const double kSoftWarnMaxLengthCm = 30;
const double kSoftWarnMinWidthCm = 6;
const double kSoftWarnMaxWidthCm = 13.5;

/// Result of a plausibility check on a measurement.
enum PlausibilityResult {
  /// Measurement is within normal bounds — accept silently.
  ok,

  /// Measurement is edge-case but plausible — show confirmation step.
  softWarn,

  /// Measurement is implausible — reject and prompt retry.
  hardReject,
}

/// Check a measurement (length or width) against the two-tier plausibility
/// bounds.
///
/// [valueCm] is the measurement in centimeters.
/// [isLength] distinguishes length from width bounds.
///
/// Returns [PlausibilityResult.ok], [PlausibilityResult.softWarn], or
/// [PlausibilityResult.hardReject].
PlausibilityResult checkPlausibility(double valueCm, {required bool isLength}) {
  final minHard = isLength ? kHardRejectMinLengthCm : kHardRejectMinWidthCm;
  final maxHard = isLength ? kHardRejectMaxLengthCm : kHardRejectMaxWidthCm;
  final minSoft = isLength ? kSoftWarnMinLengthCm : kSoftWarnMinWidthCm;
  final maxSoft = isLength ? kSoftWarnMaxLengthCm : kSoftWarnMaxWidthCm;

  if (valueCm < minHard || valueCm > maxHard) {
    return PlausibilityResult.hardReject;
  }
  if (valueCm < minSoft || valueCm > maxSoft) {
    return PlausibilityResult.softWarn;
  }
  return PlausibilityResult.ok;
}

// ═══════════════════════════════════════════════════════════════════
// CONFIDENCE & QUALITY SIGNALS
// ═══════════════════════════════════════════════════════════════════

/// Compute a confidence score for paper detection (0.0–1.0).
///
/// Based on how closely the 4 detected corners form a rectangle.
/// Perfect rectangle = 1.0, distorted = lower.
double computePaperConfidence(List<Offset> corners) {
  if (corners.length < 4) return 0.0;

  final sorted = _sortCornersClockwise(corners);

  // Check that opposite sides are roughly parallel
  // and adjacent sides are roughly perpendicular
  final sides = <double>[];
  for (int i = 0; i < 4; i++) {
    sides.add(_distance(sorted[i], sorted[(i + 1) % 4]));
  }

  // Parallel sides should be similar lengths
  final ratio1 = sides[0] / sides[2]; // top / bottom
  final ratio2 = sides[1] / sides[3]; // right / left

  // Ideal ratios are 1.0; deviation reduces confidence
  final parallelScore = 1.0 - ((ratio1 - 1.0).abs() + (ratio2 - 1.0).abs()) / 2;
  final sizeScore = sides.every((s) => s > 50) ? 1.0 : sides[0] / 50;

  return (parallelScore * 0.7 + sizeScore * 0.3).clamp(0.0, 1.0);
}

/// Estimate lighting quality from image brightness histogram (0.0–1.0).
///
/// [averageBrightness] is the mean pixel intensity (0–255).
/// Returns a quality score: 1.0 for well-lit, lower for too dark or too bright.
double computeLightingQuality(double averageBrightness) {
  // Optimal range: 80–180 (out of 255)
  if (averageBrightness >= 80 && averageBrightness <= 180) {
    return 1.0;
  } else if (averageBrightness < 80) {
    return (averageBrightness / 80).clamp(0.2, 1.0);
  } else {
    return ((255 - averageBrightness) / 75).clamp(0.2, 1.0);
  }
}

// ═══════════════════════════════════════════════════════════════════
// OVERLAY COORDINATE MAPPING (§3 of EFFICIENCY_ACCURACY_OVERHAUL_PROMPT)
// ═══════════════════════════════════════════════════════════════════
// THE single shared transformation for mapping a normalized (0–1) detection
// / guide-box coordinate from the full upright camera frame onto the
// center-cropped AR preview. Every overlay painter (debug detection overlay,
// guide box) MUST go through this function so the two can never drift out of
// sync — the native ARCore hitTest on Android mirrors this exact math
// (see ArFootSizingView.hitTest in the Kotlin plugin).

/// Map a normalized (0–1) point from the FULL upright camera frame onto the
/// center-cropped preview using the same scale-and-crop math a `BoxFit.cover`
/// render applies:
///   scale = max(viewW/frameW, viewH/frameH)
///   then crop the overflowing axis and offset by the crop margin.
///
/// This mirrors how the native ARCore preview draws the camera texture, so
/// anything drawn through this helper should sit on the actual camera pixels.
/// Shared by the debug detection overlay and the guided-capture guide box so
/// the two stay in exact agreement.
Offset mapNormalizedToView(
  Offset normalized,
  Size viewSize, {
  required int frameWidth,
  required int frameHeight,
}) {
  final fw = frameWidth.toDouble();
  final fh = frameHeight.toDouble();
  if (fw <= 0 || fh <= 0) {
    return Offset(normalized.dx * viewSize.width, normalized.dy * viewSize.height);
  }

  final frameAspect = fw / fh;
  final viewAspect = viewSize.width / viewSize.height;

  double scale;
  double offsetX = 0;
  double offsetY = 0;
  if (frameAspect > viewAspect) {
    // Frame wider than view → crop left/right.
    scale = viewSize.height / fh;
    final drawnW = viewSize.width / scale;
    offsetX = (fw - drawnW) / 2;
  } else {
    // Frame taller than view → crop top/bottom.
    scale = viewSize.width / fw;
    final drawnH = viewSize.height / scale;
    offsetY = (fh - drawnH) / 2;
  }

  return Offset(
    (normalized.dx * fw - offsetX) * scale,
    (normalized.dy * fh - offsetY) * scale,
  );
}

/// INVERSE of [mapNormalizedToView]: map a point in the on-screen preview
/// (view pixels) back into normalized (0–1) upright-frame coordinates.
///
/// This is what the manual tap-to-measure flow needs: the user taps the
/// preview, the tap arrives as view pixels, and the native ARCore hitTest
/// expects normalized upright-frame coordinates (it applies the same
/// center-crop math internally — see ArFootSizingView.hitTest).
///
/// Exact inverse of [mapNormalizedToView] for the same frame/view geometry
/// (round-trips to within floating-point precision). Falls back to a direct
/// pixel→normalized scaling when the frame dimensions are unknown.
Offset mapViewToNormalized(
  Offset viewPoint,
  Size viewSize, {
  required int frameWidth,
  required int frameHeight,
}) {
  final vw = viewSize.width;
  final vh = viewSize.height;
  final fw = frameWidth.toDouble();
  final fh = frameHeight.toDouble();
  if (vw <= 0 || vh <= 0) return Offset.zero;
  if (fw <= 0 || fh <= 0) {
    return Offset(
      (viewPoint.dx / vw).clamp(0.0, 1.0),
      (viewPoint.dy / vh).clamp(0.0, 1.0),
    );
  }

  final frameAspect = fw / fh;
  final viewAspect = vw / vh;

  double scale;
  double offsetX = 0;
  double offsetY = 0;
  if (frameAspect > viewAspect) {
    // Frame wider than view → the view crops left/right.
    scale = vh / fh;
    offsetX = (fw - vw / scale) / 2;
  } else {
    // Frame taller than view → the view crops top/bottom.
    scale = vw / fw;
    offsetY = (fh - vh / scale) / 2;
  }

  return Offset(
    ((viewPoint.dx / scale + offsetX) / fw).clamp(0.0, 1.0),
    ((viewPoint.dy / scale + offsetY) / fh).clamp(0.0, 1.0),
  );
}

// ═══════════════════════════════════════════════════════════════════
// GEOMETRY HELPERS (private)
// ═══════════════════════════════════════════════════════════════════

double _hypot(double a, double b) => math.sqrt(a * a + b * b);

double _distance(Offset a, Offset b) {
  return math.sqrt((a.dx - b.dx) * (a.dx - b.dx) + (a.dy - b.dy) * (a.dy - b.dy));
}

Offset _centroid(List<Offset> points) {
  double cx = 0, cy = 0;
  for (final p in points) {
    cx += p.dx;
    cy += p.dy;
  }
  final n = points.length.toDouble();
  return Offset(cx / n, cy / n);
}

/// Sort 4 corners clockwise from top-left.
List<Offset> _sortCornersClockwise(List<Offset> corners) {
  if (corners.length != 4) return corners;

  // Find centroid
  final cx = corners.map((c) => c.dx).reduce((a, b) => a + b) / 4;
  final cy = corners.map((c) => c.dy).reduce((a, b) => a + b) / 4;
  final centroid = Offset(cx, cy);

  // Sort by angle from centroid
  final sorted = List<Offset>.from(corners);
  sorted.sort((a, b) {
    final angleA = math.atan2(a.dy - centroid.dy, a.dx - centroid.dx);
    final angleB = math.atan2(b.dy - centroid.dy, b.dx - centroid.dx);
    return angleA.compareTo(angleB);
  });

  // Rotate so the top-left corner is first
  // (smallest x + y sum)
  int topLeftIdx = 0;
  double minSum = double.infinity;
  for (int i = 0; i < 4; i++) {
    final sum = sorted[i].dx + sorted[i].dy;
    if (sum < minSum) {
      minSum = sum;
      topLeftIdx = i;
    }
  }

  final result = <Offset>[];
  for (int i = 0; i < 4; i++) {
    result.add(sorted[(topLeftIdx + i) % 4]);
  }
  return result;
}
