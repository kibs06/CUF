/// Foot detection & segmentation layer for AR foot scanning.
///
/// This is the missing "does the camera actually see a foot?" layer that sits
/// between the AR camera pipeline and the measurement pipeline:
///
///   ARCore frame (NV21)  →  FootDetector  →  FootDetectionResult
///                                             (points + confidence)
///                                                   ↓
///                                     ARCore hitTest (raycast → 3D world)
///                                                   ↓
///                                     MeasurementSample (§5.3 pipeline)
///
/// Architecture notes (§8 of FOOT_DETECTION_SEGMENTATION_PROMPT):
/// - Detection/segmentation code is intentionally kept separate from the AR
///   raycast/geometry code (which lives in ar_core_channel.dart). Each layer
///   is independently testable.
/// - [FootDetector] is an interface so a segmentation-based detector can be
///   swapped in later without touching the scan screen. The current ML Kit
///   Pose implementation (mlkit_pose_foot_detector.dart) provides heel/toe
///   points; a future segmentation detector can also supply the widest-point
///   pair.
/// - The confidence threshold ([minFootDetectionConfidence]) is a named,
///   tunable constant — frames below it are gated out of the sample set.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

// ═══════════════════════════════════════════════════════════════════
// CONFIDENCE THRESHOLDS (§3.3 of the prompt)
// ═══════════════════════════════════════════════════════════════════

/// Minimum foot-detection confidence (0.0–1.0) below which a frame is
/// treated as "no foot detected" rather than accepting a low-confidence guess.
///
/// This mirrors the tunable-confidence-threshold approach used for the
/// measurement pipeline (`minSegmentationConfidence` in
/// ar_foot_measurement_pipeline.dart) and should be tuned after real-device
/// testing. A frame below this threshold contributes NOTHING to the sample
/// set — it is skipped, not recorded as a guess.
const double minFootDetectionConfidence = 0.5;

/// Minimum number of foreground (above-threshold) mask pixels required for a
/// frame to count as a foot detection. Smaller blobs are treated as noise.
const int minFootMaskPixels = 200;

/// Minimum FRACTION of the mask that must be foreground for a frame to count
/// as a foot detection. Resolution-independent noise floor: in the close-up
/// scan framing the foot fills a substantial fraction of the frame, so a blob
/// below this fraction is treated as background misclassification rather than
/// a foot. Guards against tiny noise blobs that would otherwise pass the
/// absolute [minFootMaskPixels] floor at low mask resolutions.
const double minFootMaskForegroundFraction = 0.01; // 1% of mask pixels

/// Maximum FRACTION of the mask that may be foreground for a frame to count
/// as a foot detection (§1.1). `google_mlkit_selfie_segmentation` is a
/// general foreground/background segmenter with no foot concept — a wall, an
/// object filling the camera, or a carpet edge can produce a whole-frame
/// foreground blob. In the guided capture framing the foot is the largest
/// object but still occupies well under half the frame, so a blob covering
/// most of the mask is rejected as "not a foot" even at high confidence.
const double maxFootMaskForegroundFraction = 0.60; // 60% of mask pixels

/// Minimum elongation (length ÷ width of the mask's oriented bounding box)
/// for a frame to count as a foot (§1.1). A foot silhouette is clearly
/// elongated (roughly 2.5–4.5×); a round or squarish blob (a hand, a balled-
/// up cloth, a shadow) fails this geometric check even if the segmenter
/// scored it high. Tunable after real-capture measurements.
const double minFootAspectRatio = 1.8;

/// Maximum elongation. A thread-thin strip (fold in clothing, edge of a rug,
/// cable) is not foot-shaped. Tunable after real-capture measurements.
const double maxFootAspectRatio = 6.0;

/// Reference overlap threshold for the guide-box containment SUB-SCORE
/// (§1.2 of the overhaul brief). This is no longer a hard gate — it's the
/// point at which containment transitions from "substantial" toward
/// "partial" in the weighted scoring. A blob sitting outside the guide box
/// scores ~0 on containment and is rejected by the combined score threshold.
const double minGuideOverlapFraction = 0.5;

// ═══════════════════════════════════════════════════════════════════
// SAMPLE-QUALITY SCORING (§1 of EFFICIENCY_ACCURACY_OVERHAUL_PROMPT)
// ═══════════════════════════════════════════════════════════════════
// Weighted confidence scoring replaces the strict AND-chain of binary gates:
// each check contributes a normalized 0.0–1.0 sub-score, and ONE combined
// score decides acceptance. Weights are tunable constants — revisit after
// real ground-truth accuracy testing (brief §5).

/// Weight of segmentation confidence in the combined quality score.
const double kQualityWeightSegmentation = 0.25;

/// Weight of the shape/elongation sub-score.
const double kQualityWeightShape = 0.35;

/// Weight of the guide-box containment sub-score (position correctness —
/// high weight because where heel/toe/width points land matters most).
const double kQualityWeightContainment = 0.40;

/// Reserved weight for a future sharpness/blur sub-score. No blur metric is
/// computed in the pipeline yet, so this stays 0 (neutral) — the combined
/// score is normalized over the weights actually applied, so enabling it
/// later doesn't require rebalancing the others.
const double kQualityWeightSharpness = 0.0;

/// Combined sample-quality score at/above which a frame is accepted as a
/// foot detection (`footDetected`) and eligible to record a sample.
const double kSampleAcceptScore = 0.7;

/// Shape-score plateau: elongations within [low, high] score 1.0; outside the
/// plateau the score decays linearly to 0 at the acceptability edges.
/// Calibrated so a typical real foot (≈2.5–4×) sits on the plateau.
const double kFootShapeIdealLow = 2.5;
const double kFootShapeIdealHigh = 4.9;

// ═══════════════════════════════════════════════════════════════════
// GUIDE BOXES (§2.3 — on-screen bounding-box capture)
// ═══════════════════════════════════════════════════════════════════
// Normalized (0–1) rectangles in the upright frame space. The scan screen
// draws the current step's box on the preview AND passes it to
// [evaluateFootMask] so the mask must substantially overlap it. These are
// UX-calibration values: if device testing shows the coached hold-distance
// is unrealistic, adjust the box size/position rather than the measurement
// math (§3 of the brief).

/// Guide box for the FRONT / top-down capture (primary measurement: width).
/// A centered, slightly-tall box — the foot fills it when the phone is held
/// ~30cm above pointing straight down.
const Rect kFrontCaptureGuideRect = Rect.fromLTRB(0.30, 0.15, 0.70, 0.70);

/// Guide box for the SIDE / profile capture (primary measurement: length).
/// A wider, shorter box — the foot's profile fills it when the phone is held
/// to the side.
const Rect kSideCaptureGuideRect = Rect.fromLTRB(0.15, 0.35, 0.85, 0.65);

// ═══════════════════════════════════════════════════════════════════
// DATA CLASSES
// ═══════════════════════════════════════════════════════════════════

/// A single 2D point with an associated confidence likelihood.
///
/// Coordinates are **normalized** (0.0–1.0 relative to the upright image),
/// matching the coordinate convention that ARCore hitTest expects.
class FootPoint {
  final double x;
  final double y;
  final double likelihood;

  const FootPoint({
    required this.x,
    required this.y,
    required this.likelihood,
  });

  /// Normalized (x, y) as a UI [Offset].
  Offset get asOffset => Offset(x, y);
}

/// Result of running foot detection on a single camera frame.
class FootDetectionResult {
  /// Whether a foot was confidently detected in this frame.
  final bool footDetected;

  /// Detection confidence (0.0–1.0).
  ///
  /// For the pose-based detector this is the minimum likelihood of the
  /// heel/toe landmark pair. For a future segmentation detector it would be
  /// the segmentation mask confidence.
  final double confidence;

  /// Which foot was detected: 'left', 'right', or null if uncertain.
  final String? footSide;

  /// For negative results under strict side gating: which foot WAS actually
  /// detected but rejected because it wasn't the requested side.
  ///
  /// This exists so device testing can diagnose whether the model mislabels
  /// the foot side in close-up framing (the §2.1 caveat) — a scan that
  /// repeatedly fails with `rejectedFootSide: 'right'` while scanning left
  /// points at a labeling problem, not a "no foot" problem.
  final String? rejectedFootSide;

  /// Heel point in normalized image coordinates (rear-most extent).
  final FootPoint? heelPoint;

  /// Toe point in normalized image coordinates (forward-most extent).
  final FootPoint? toePoint;

  /// Widest-point pair (normalized coordinates).
  ///
  /// The pose-based detector cannot reliably produce these (it has no
  /// width landmarks); they are filled by a segmentation-based detector.
  /// When null, the caller falls back to a proportional width estimate.
  final List<FootPoint>? widthPoints;

  /// Combined sample-quality score (0.0–1.0) from the weighted sub-scores
  /// below (§1 of EFFICIENCY_ACCURACY_OVERHAUL_PROMPT). A frame is accepted
  /// as a foot detection when this ≥ [kSampleAcceptScore] — replacing the
  /// strict AND-chain of binary gates with a single tunable threshold.
  final double qualityScore;

  /// Normalized segmentation-confidence sub-score (0.0–1.0).
  final double segmentationScore;

  /// Normalized shape/elongation sub-score (0.0–1.0).
  final double shapeScore;

  /// Normalized guide-box containment sub-score (0.0–1.0).
  final double containmentScore;

  /// Normalized sharpness sub-score (0.0–1.0). Neutral (1.0) — no blur
  /// metric is computed in the pipeline yet (see kQualityWeightSharpness).
  final double sharpnessScore;

  const FootDetectionResult({
    required this.footDetected,
    required this.confidence,
    this.footSide,
    this.rejectedFootSide,
    this.heelPoint,
    this.toePoint,
    this.widthPoints,
    this.qualityScore = 0.0,
    this.segmentationScore = 0.0,
    this.shapeScore = 0.0,
    this.containmentScore = 0.0,
    this.sharpnessScore = 1.0,
  });

  /// A "no foot detected" result for this frame.
  ///
  /// [rejectedFootSide] optionally records which side was detected but
  /// rejected by strict side gating (see [FootDetectionResult.rejectedFootSide]).
  const FootDetectionResult.negative({
    double confidence = 0.0,
    String? rejectedFootSide,
  })  : this(
          footDetected: false,
          confidence: confidence,
          rejectedFootSide: rejectedFootSide,
          footSide: null,
          heelPoint: null,
          toePoint: null,
          widthPoints: null,
        );
}

// ═══════════════════════════════════════════════════════════════════
// SMART-ASSIST PROPOSAL (§6 of MANUAL_MEASUREMENT_PIVOT_PROMPT)
// ═══════════════════════════════════════════════════════════════════
// The paused automatic detection is reused as an optional "smart assist"
// layer over the fully manual flow: while the user is waiting to place the
// first point of a pair, a background sample runs this detector and proposes
// the two initial point positions. The user can accept them — and drag-adjust
// with the exact same manual UI — or ignore them and tap manually.
// Pure and deterministic: maps a detection result to the normalized point
// pair the CURRENT capture step needs, or null when the result can't supply
// the required landmarks.

/// Return the normalized (upright-frame) point pair to PROPOSE for a capture
/// step from a smart-assist detection, or `null` when the detection can't
/// supply the required landmarks for that step:
///
/// - **FRONT / top-down** (`isFront: true`): the two widest-point landmarks
///   (W/W) — width is what this angle is best suited to measure.
/// - **SIDE / profile** (`isFront: false`): heel + tip of the longest toe
///   (H/T) — length is what this angle is best suited to measure.
///
/// Callers map the returned normalized points into view pixels via
/// `mapNormalizedToView` and raycast them to world space (hitTest).
({FootPoint a, FootPoint b})? proposePointPair(
  FootDetectionResult detection, {
  required bool isFront,
}) {
  if (!detection.footDetected) return null;

  if (isFront) {
    final width = detection.widthPoints;
    if (width == null || width.length < 2) return null;
    return (a: width[0], b: width[1]);
  }

  final heel = detection.heelPoint;
  final toe = detection.toePoint;
  if (heel == null || toe == null) return null;
  return (a: heel, b: toe);
}

// ═══════════════════════════════════════════════════════════════════
// DETECTOR INTERFACE (§8 — clean separation from AR geometry)
// ═══════════════════════════════════════════════════════════════════

/// Interface for the on-device foot detector.
///
/// Implementations:
/// - [MlKitPoseFootDetector] (mlkit_pose_foot_detector.dart) — ML Kit Pose
///   landmarks (heel + foot_index) → gating + heel/toe points.
/// - Future: a segmentation-based detector producing a mask → outline,
///   heel/toe/widest points (Option B fallback per the implementation brief).
abstract class FootDetector {
  /// Run detection on a single camera frame.
  ///
  /// [nv21Bytes] is an NV21-encoded image (Y plane + interleaved VU).
  /// [width]/[height] are the sensor-orientation dimensions.
  /// [rotationDegrees] is the rotation to make the image upright (0/90/180/270).
  ///
  /// Returns a [FootDetectionResult] — never throws; callers should treat
  /// a result with `footDetected == false` as "no foot in this frame".
  ///
  /// [preferSide] ('left' or 'right') strictly gates the frame: if the
  /// preferred foot's landmarks aren't present above the confidence threshold,
  /// the frame is treated as "no foot" rather than falling back to the
  /// opposite foot (so a left-foot scan never silently accepts right-foot
  /// samples — §4 "don't measure garbage").
  ///
  /// [guideRect] (normalized upright-frame coords, optional) is the on-screen
  /// guide box for the current capture angle. When provided, the detector
  /// requires the mask to substantially overlap it (position sanity — §1.1).
  Future<FootDetectionResult> detect({
    required Uint8List nv21Bytes,
    required int width,
    required int height,
    required int rotationDegrees,
    String? preferSide,
    Rect? guideRect,
  });

  /// Release any native/model resources.
  void dispose();
}

// ═══════════════════════════════════════════════════════════════════
// TEMPORAL CONSISTENCY (§1.2 of the fix brief)
// ═══════════════════════════════════════════════════════════════════

/// Rolling temporal-consistency gate for foot detection.
///
/// A single frame briefly misclassifying a non-foot object should not be
/// enough to mark "foot detected". This gate requires [confirmAfter]
/// CONSECUTIVE shape-validated positive frames before reporting [confirmed],
/// and requires [clearAfter] consecutive negatives before dropping back to
/// unconfirmed — which also prevents UI flicker (§1.2).
///
/// Pure and deterministic: feed it one frame's boolean each sample interval
/// via [update], and gate the scan's sample recording / UI on [confirmed].
class TemporalFootGate {
  /// Consecutive positive frames required to flip to confirmed.
  final int confirmAfter;

  /// Consecutive negative frames required to flip back to unconfirmed.
  final int clearAfter;

  int _positiveStreak = 0;
  int _negativeStreak = 0;
  bool _confirmed = false;

  TemporalFootGate({
    this.confirmAfter = 3,
    this.clearAfter = 3,
  });

  /// Feed one frame's shape-validated detection result and return the new
  /// confirmation state.
  bool update(bool detected) {
    if (detected) {
      _positiveStreak++;
      _negativeStreak = 0;
      if (_positiveStreak >= confirmAfter) _confirmed = true;
    } else {
      _negativeStreak++;
      _positiveStreak = 0;
      if (_negativeStreak >= clearAfter) _confirmed = false;
    }
    return _confirmed;
  }

  /// Whether the gate is currently confirmed (enough consecutive positives).
  bool get confirmed => _confirmed;

  /// Current consecutive positive streak (for diagnostics).
  int get positiveStreak => _positiveStreak;

  /// Reset for a new scan pass.
  void reset() {
    _positiveStreak = 0;
    _negativeStreak = 0;
    _confirmed = false;
  }
}

// ═══════════════════════════════════════════════════════════════════
// PURE EVALUATION LOGIC (unit-testable without the ML runtime)
// ═══════════════════════════════════════════════════════════════════

/// Raw landmark inputs extracted from a pose model — deliberately decoupled
/// from the ML Kit `PoseLandmark` class so this logic is pure Dart and can be
/// unit-tested without the platform runtime.
class LandmarkInput {
  /// Normalized x (0.0–1.0) in the upright image.
  final double x;

  /// Normalized y (0.0–1.0) in the upright image.
  final double y;

  /// Likelihood (0.0–1.0) from the model.
  final double likelihood;

  const LandmarkInput({
    required this.x,
    required this.y,
    required this.likelihood,
  });

  bool get isAboveThreshold => likelihood >= minFootDetectionConfidence;
}

/// Evaluate foot detection from a set of raw heel/toe landmarks.
///
/// This is the pure, deterministic core shared by any detector implementation
/// (ML Kit today, segmentation later). It:
/// 1. Determines whether a left or right foot is present above the confidence
///    threshold (heel + foot-index landmarks both required).
/// 2. Chooses which foot to report. If [preferSide] is given, **strict gating**
///    applies: the frame is a foot only when the preferred side is detected;
///    the opposite side is never substituted. Without a preference, the
///    higher-confidence side wins.
/// 3. Computes an overall confidence (min of the landmark pair likelihoods).
///
/// All coordinates are expected to be already normalized to the upright image.
FootDetectionResult evaluateFootLandmarks({
  LandmarkInput? leftHeel,
  LandmarkInput? leftToe,
  LandmarkInput? rightHeel,
  LandmarkInput? rightToe,
  String? preferSide,
}) {
  // ── Evaluate each side ──
  FootDetectionResult? leftResult;
  if (leftHeel != null &&
      leftToe != null &&
      leftHeel.isAboveThreshold &&
      leftToe.isAboveThreshold) {
    final conf = leftHeel.likelihood < leftToe.likelihood
        ? leftHeel.likelihood
        : leftToe.likelihood;
    leftResult = FootDetectionResult(
      footDetected: true,
      confidence: conf,
      // Pose path is legacy-only (segmentation is the runtime detector), but
      // keep the quality fields internally consistent: the landmark
      // likelihood is the only sub-score available, so it doubles as both the
      // segmentation score and the combined quality score.
      qualityScore: conf,
      segmentationScore: conf,
      footSide: 'left',
      heelPoint: FootPoint(
        x: leftHeel.x,
        y: leftHeel.y,
        likelihood: leftHeel.likelihood,
      ),
      toePoint: FootPoint(
        x: leftToe.x,
        y: leftToe.y,
        likelihood: leftToe.likelihood,
      ),
    );
  }

  FootDetectionResult? rightResult;
  if (rightHeel != null &&
      rightToe != null &&
      rightHeel.isAboveThreshold &&
      rightToe.isAboveThreshold) {
    final conf = rightHeel.likelihood < rightToe.likelihood
        ? rightHeel.likelihood
        : rightToe.likelihood;
    rightResult = FootDetectionResult(
      footDetected: true,
      confidence: conf,
      qualityScore: conf,
      segmentationScore: conf,
      footSide: 'right',
      heelPoint: FootPoint(
        x: rightHeel.x,
        y: rightHeel.y,
        likelihood: rightHeel.likelihood,
      ),
      toePoint: FootPoint(
        x: rightToe.x,
        y: rightToe.y,
        likelihood: rightToe.likelihood,
      ),
    );
  }

  // ── Strict side gating (§4): never substitute the opposite foot ──
  // If the user is scanning their left foot and this frame only shows the
  // right foot, the frame must contribute NOTHING — not a right-foot sample
  // appended to the left-foot sample set. The rejected side is preserved for
  // device-testing diagnostics (§7: log what was actually seen).
  if (preferSide == 'left') {
    if (leftResult != null) return leftResult;
    return FootDetectionResult.negative(rejectedFootSide: rightResult?.footSide);
  }
  if (preferSide == 'right') {
    if (rightResult != null) return rightResult;
    return FootDetectionResult.negative(rejectedFootSide: leftResult?.footSide);
  }

  if (leftResult == null && rightResult == null) {
    return const FootDetectionResult.negative();
  }

  // ── No preference: pick the higher-confidence side ──
  if (leftResult == null) return rightResult!;
  if (rightResult == null) return leftResult;

  return leftResult.confidence >= rightResult.confidence
      ? leftResult
      : rightResult;
}

// ═══════════════════════════════════════════════════════════════════
// MASK → POINTS EXTRACTION (segmentation fallback, §2.2 of the brief)
//
// Unlike pose detection (which hands us heel/toe as named landmarks), a
// segmentation mask requires computing those points geometrically:
//  1. Threshold the per-pixel confidences into a foreground blob
//  2. Find the blob's principal axis (PCA) — the foot's long axis, which is
//     NOT assumed to be vertical in the frame
//  3. Heel = blob extent at one end of that axis, toe = the other end
//  4. Widest pair = maximum perpendicular extent along that axis
// ═══════════════════════════════════════════════════════════════════

/// Internal: a foreground mask pixel with normalized coordinates.
class _MaskPixel {
  final double nx;
  final double ny;
  final double confidence;

  const _MaskPixel({
    required this.nx,
    required this.ny,
    required this.confidence,
  });
}

/// Elongation (length ÷ width) sub-score for the shape check (§1.2).
///
/// Returns 1.0 for ratios near the ideal foot range ([kFootShapeIdealLow],
/// [kFootShapeIdealHigh]), decaying linearly to 0 at the acceptability edges
/// ([minFootAspectRatio], [maxFootAspectRatio]) and 0 outside. Replaces the
/// hard in/out aspect gate: a round blob (≈1.0) or thread-thin strip (≫6.0)
/// scores 0 and drives the combined sample-quality score below threshold,
/// while a real foot scores near 1.0.
double footShapeScore(double aspectRatio) {
  if (aspectRatio <= minFootAspectRatio ||
      aspectRatio >= maxFootAspectRatio) {
    return 0.0;
  }
  if (aspectRatio <= kFootShapeIdealLow) {
    return (aspectRatio - minFootAspectRatio) /
        (kFootShapeIdealLow - minFootAspectRatio);
  }
  if (aspectRatio >= kFootShapeIdealHigh) {
    return (maxFootAspectRatio - aspectRatio) /
        (maxFootAspectRatio - kFootShapeIdealHigh);
  }
  return 1.0;
}

/// Combine normalized sub-scores into the single sample-quality score (§1.3).
///
/// Weighted sum of segmentation confidence, shape and guide-box containment
/// (weights are the tunable `kQualityWeight*` constants). The sharpness slot
/// is reserved (weight 0 today) — it defaults to neutral 1.0 and contributes
/// nothing until a blur metric is added. Normalized by the total applied
/// weight so enabling sharpness later doesn't require rebalancing.
double combineQualityScore({
  required double segmentationScore,
  required double shapeScore,
  required double containmentScore,
  double sharpnessScore = 1.0,
}) {
  final totalWeight = kQualityWeightSegmentation +
      kQualityWeightShape +
      kQualityWeightContainment +
      kQualityWeightSharpness;
  if (totalWeight <= 0) return 0.0;
  final score = (kQualityWeightSegmentation * segmentationScore +
          kQualityWeightShape * shapeScore +
          kQualityWeightContainment * containmentScore +
          kQualityWeightSharpness * sharpnessScore) /
      totalWeight;
  return score.clamp(0.0, 1.0);
}

/// Evaluate foot detection from a segmentation mask.
///
/// [confidences] is the per-pixel foreground probability in row-major order
/// (length ≥ width×height), in the upright (post-rotation) image space.
/// [width]/[height] are the mask dimensions.
///
/// Returns a [FootDetectionResult] with heel/toe/widest points computed via
/// PCA on the thresholded foreground blob. Returns a negative result when the
/// blob is too small to be a foot.
///
/// §1.1 false-positive rejection + §1 weighted scoring
/// (EFFICIENCY_ACCURACY_OVERHAUL_PROMPT) — because
/// `google_mlkit_selfie_segmentation` is a general person/foreground
/// segmenter (no foot concept), a high mask confidence alone is NOT proof of
/// a foot. This function:
///   - only the LARGEST connected foreground component drives geometry —
///     disconnected patches (a hand, leg skin at the frame edge, a shadow)
///     never contribute to the heel/toe/width points (§1.1 extraction fix)
///   - hard-rejects structurally unusable masks (noise blobs below the pixel
///     floor, whole-frame foreground like a wall, degenerate PCA with no
///     extractable points, and a post-clip remnant too small to extract from)
///   - converts the remaining checks (segmentation confidence, shape/aspect,
///     guide-box containment) into normalized SUB-SCORES and combines them
///     into [qualityScore] with a weighted sum (§1.3). `footDetected` is
///     true when the combined score ≥ [kSampleAcceptScore] (§1.4) — a
///     partial credit model instead of the strict all-or-nothing chain.
///   - when [guideRect] is provided, mask pixels outside the box are clipped
///     before point extraction so an out-of-box extreme can never become a
///     point (§1.2 of the extraction-fix brief), and overlap contributes a
///     containment sub-score rather than a hard gate
///
/// Note on [preferSide]: a general person-segmentation mask cannot determine
/// which foot (left/right) is present, so this function does NOT apply strict
/// side gating — it reports any sufficiently large foreground blob as the
/// foot. The caller's framing (the requested foot fills the view) is assumed.
FootDetectionResult evaluateFootMask({
  required List<double> confidences,
  required int width,
  required int height,
  double threshold = minFootDetectionConfidence,
  String? preferSide,
  Rect? guideRect,
  int? frameWidth,
  int? frameHeight,

  /// TEMP-DEBUG: invoked once per frame at each terminal point of this
  /// function with the stage-by-stage trace (e.g. `mask=OK → component=OK →
  /// shape=REJECT ...`). Lets on-device logcat show which gate rejects a
  /// candidate sample while the UI still shows "Foot detected" (§1 of
  /// ZERO_SAMPLES_DIAGNOSTIC_PROMPT). Remove after diagnosis.
  void Function(String trace)? onStageLog,
}) {
  // ── TEMP-DEBUG stage trace buffer (§1 of ZERO_SAMPLES_DIAGNOSTIC_PROMPT) ──
  final trace = <String>[];
  void emit() => onStageLog?.call(trace.join(' → '));

  if (width <= 0 || height <= 0 || confidences.length < width * height) {
    trace.add('input=REJECT (bad dims ${width}x$height / ${confidences.length})');
    emit();
    return const FootDetectionResult.negative();
  }

  // When the upright frame dimensions are known, geometry (PCA + elongation)
  // is computed in PIXEL space. The raw mask is square (e.g. 256×256) but the
  // upright frame is portrait (e.g. 480×640): a pixel-space elongation of
  // L/W appears in normalized space as L/W × (H/W_frame), which distorts the
  // shape check (§1.1) by the frame aspect ratio. Scaling by the true frame
  // dims makes the elongation check frame-independent.
  // Dart's flow analysis promotes frameWidth/frameHeight to non-null after the
  // `!= null` checks within the same `&&` chain (and in the ternary true
  // branch), so no `!` operators are needed below.
  final usePixelSpace =
      (frameWidth != null && frameHeight != null && frameWidth > 0 && frameHeight > 0);
  double xOf(_MaskPixel p) => usePixelSpace ? p.nx * frameWidth : p.nx;
  double yOf(_MaskPixel p) => usePixelSpace ? p.ny * frameHeight : p.ny;

  // ── 1. Threshold the mask into a foreground blob ──
  // A selfie-segmentation mask frequently contains disconnected foreground
  // regions (a hand, leg/ankle skin at the frame edge, a shadow patch). Only
  // the foot region must drive the geometry, so run connected-component
  // labeling (8-connectivity flood-fill — trivial at typical mask sizes) and
  // keep ONLY the largest component (§1.1 of the extraction-fix brief).
  // Without this, a disconnected patch can pull the PCA extremes (and thus
  // the heel/toe/width points) far outside the foot.
  // A visited bitmap (0/1) is all the flood-fill needs — the component label
  // itself is never read back. Cheaper than a full int label grid.
  final visited = Uint8List(width * height);
  final components = <List<_MaskPixel>>[];

  for (int y = 0; y < height; y++) {
    final rowOffset = y * width;
    for (int x = 0; x < width; x++) {
      final idx = rowOffset + x;
      if (confidences[idx] < threshold) continue; // Background
      if (visited[idx] != 0) continue; // Already labeled

      // BFS flood-fill this new component (8-connectivity).
      final component = <_MaskPixel>[];
      final queue = <int>[idx];
      visited[idx] = 1;
      while (queue.isNotEmpty) {
        final cur = queue.removeLast();
        final py = cur ~/ width;
        final px = cur - py * width;
        component.add(_MaskPixel(
          nx: px / width,
          ny: py / height,
          confidence: confidences[cur],
        ));
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final npx = px + dx;
            final npy = py + dy;
            if (npx < 0 || npy < 0 || npx >= width || npy >= height) continue;
            final nidx = npy * width + npx;
            if (visited[nidx] != 0) continue;
            if (confidences[nidx] < threshold) continue;
            visited[nidx] = 1;
            queue.add(nidx);
          }
        }
      }
      components.add(component);
    }
  }

  if (components.isEmpty) {
    trace.add('mask=REJECT (no foreground above threshold)');
    emit();
    return const FootDetectionResult.negative();
  }

  // Keep only the largest connected foreground component — the foot. All
  // downstream validation and point extraction run on this set.
  var foreground = components[0];
  for (final component in components) {
    if (component.length > foreground.length) foreground = component;
  }
  trace.add('mask=OK components=${components.length}');
  trace.add('component=OK largest=${foreground.length}px');

  // ── 1.1 Area validation: reject too-small (noise) and too-large
  // (whole-frame foreground) masks — applied to the largest component ──
  final maskArea = width * height;
  final foregroundFraction =
      maskArea > 0 ? foreground.length / maskArea : 0.0;
  if (foreground.length < minFootMaskPixels ||
      foregroundFraction < minFootMaskForegroundFraction ||
      foregroundFraction > maxFootMaskForegroundFraction) {
    trace.add('area=REJECT (px=${foreground.length} ');
    trace.add('frac=${foregroundFraction.toStringAsFixed(3)}, ');
    trace.add('minPx=$minFootMaskPixels minFrac=$minFootMaskForegroundFraction ');
    trace.add('maxFrac=$maxFootMaskForegroundFraction)');
    emit();
    return const FootDetectionResult.negative();
  }
  trace.add('area=OK (px=${foreground.length} ');
  trace.add('frac=${foregroundFraction.toStringAsFixed(3)})');

  // ── 1.1 Position scoring (§1.2 of the overhaul brief): guide-box overlap
  // is now a SUB-SCORE, not a hard gate. Fully-contained masks score 1.0,
  // partial overlap gets partial credit, and a mask sitting outside the box
  // scores ~0 (driving the combined score below the accept threshold).
  // `minGuideOverlapFraction` remains as the reference point where
  // containment transitions from substantial → partial.
  double containmentScore = 1.0; // No guide box → neutral (no constraint)
  if (guideRect != null) {
    var insideGuide = 0;
    for (final p in foreground) {
      if (guideRect.contains(Offset(p.nx, p.ny))) insideGuide++;
    }
    final overlapFraction =
        foreground.isEmpty ? 0.0 : insideGuide / foreground.length;
    containmentScore = overlapFraction;
    trace.add('containment=score ${overlapFraction.toStringAsFixed(2)}');

    // ── §1.2 Guide-box clipping safeguard (unchanged — geometry safety) ──
    // Independently of connectivity, mask pixels OUTSIDE the guide box must
    // never become a heel/toe/width point. Clip before PCA/extraction so an
    // out-of-box extreme (e.g. leg connected to the shoe at the ankle) can't
    // be selected. The overlap check above guarantees ≥ half the component
    // survives, so this is a light trim, not a destruction.
    final preClip = foreground.length;
    foreground = foreground
        .where((p) => guideRect.contains(Offset(p.nx, p.ny)))
        .toList();
    // Re-apply the area floor to the clipped set for consistency with the
    // earlier area validation (a heavily-trimmed remnant isn't trustworthy).
    if (foreground.length < minFootMaskPixels) {
      trace.add('clip=REJECT ($preClip→${foreground.length}px, floor=$minFootMaskPixels)');
      emit();
      return const FootDetectionResult.negative();
    }
    trace.add('clip=OK ($preClip→${foreground.length}px)');
  }

  double confidenceSum = 0;
  for (final p in foreground) {
    confidenceSum += p.confidence;
  }
  final overallConfidence = (confidenceSum / foreground.length).clamp(0.0, 1.0);

  // ── 2. PCA: find the blob's principal (long) axis ──
  // Uses pixel-space coordinates when available so the elongation check is
  // frame-independent; falls back to normalized space otherwise.
  double cx = 0, cy = 0;
  for (final p in foreground) {
    cx += xOf(p);
    cy += yOf(p);
  }
  cx /= foreground.length;
  cy /= foreground.length;

  double xx = 0, xy = 0, yy = 0;
  for (final p in foreground) {
    final dx = xOf(p) - cx;
    final dy = yOf(p) - cy;
    xx += dx * dx;
    xy += dx * dy;
    yy += dy * dy;
  }

  // Principal axis angle from the covariance matrix (largest eigenvector).
  final angle = 0.5 * math.atan2(2 * xy, xx - yy);
  final cosA = math.cos(angle);
  final sinA = math.sin(angle);

  // ── 3. Project onto principal & perpendicular axes ──
  double minProj = double.infinity;
  double maxProj = double.negativeInfinity;
  double minPerp = double.infinity;
  double maxPerp = double.negativeInfinity;
  _MaskPixel? minProjPixel;
  _MaskPixel? maxProjPixel;
  _MaskPixel? minPerpPixel;
  _MaskPixel? maxPerpPixel;

  for (final p in foreground) {
    final dx = xOf(p) - cx;
    final dy = yOf(p) - cy;
    final proj = dx * cosA + dy * sinA;
    final perp = -dx * sinA + dy * cosA;

    if (proj < minProj) {
      minProj = proj;
      minProjPixel = p;
    }
    if (proj > maxProj) {
      maxProj = proj;
      maxProjPixel = p;
    }
    if (perp < minPerp) {
      minPerp = perp;
      minPerpPixel = p;
    }
    if (perp > maxPerp) {
      maxPerp = perp;
      maxPerpPixel = p;
    }
  }

  if (minProjPixel == null ||
      maxProjPixel == null ||
      minPerpPixel == null ||
      maxPerpPixel == null) {
    trace.add('shape=REJECT (degenerate — no extreme pixels)');
    emit();
    return const FootDetectionResult.negative();
  }

  final extent = maxProj - minProj;
  final perpExtent = maxPerp - minPerp;
  if (extent <= 0.02 || perpExtent <= 0.01) {
    trace.add('shape=REJECT (degenerate extent=${extent.toStringAsFixed(3)} ');
    trace.add('perp=${perpExtent.toStringAsFixed(3)})');
    emit();
    return const FootDetectionResult.negative(); // Degenerate blob
  }

  // ── 1.1 Shape scoring (§1.2 of the overhaul brief): elongation is now a
  // SUB-SCORE (1.0 on the ideal plateau, decaying to 0 at the acceptability
  // edges, 0 well outside) rather than a hard in/out gate. A round blob or
  // thread-thin strip drives the combined score below threshold; a real foot
  // sits near 1.0. Computed in pixel space (frame-independent) when frame
  // dims are known.
  final aspectRatio = extent / perpExtent;
  final shapeScore = footShapeScore(aspectRatio);
  trace.add('shape=score ${shapeScore.toStringAsFixed(2)} (aspect=${aspectRatio.toStringAsFixed(2)})');

  // ── 4. Assign heel vs toe ──
  // Heuristic: the heel end is the one with the larger mean perpendicular
  // extent near its extreme (the heel/ankle region is broader than the toe
  // tip). Exact labeling does not affect length measurement (distance is
  // symmetric), but this keeps heel/toe meaningful for display/debugging.
  final perpNearMin = _meanPerpNearExtreme(
    foreground, cx, cy, cosA, sinA, minProj, maxProj, xOf: xOf, yOf: yOf, nearMin: true,
  );
  final perpNearMax = _meanPerpNearExtreme(
    foreground, cx, cy, cosA, sinA, minProj, maxProj, xOf: xOf, yOf: yOf, nearMin: false,
  );

  final heelPixel = perpNearMin >= perpNearMax ? minProjPixel : maxProjPixel;
  final toePixel = heelPixel == minProjPixel ? maxProjPixel : minProjPixel;

  final heelPoint = FootPoint(
    x: heelPixel.nx,
    y: heelPixel.ny,
    likelihood: heelPixel.confidence,
  );
  final toePoint = FootPoint(
    x: toePixel.nx,
    y: toePixel.ny,
    likelihood: toePixel.confidence,
  );

  // Widest pair = max perpendicular extent (the ball of the foot).
  final widthPoints = [
    FootPoint(x: minPerpPixel.nx, y: minPerpPixel.ny, likelihood: minPerpPixel.confidence),
    FootPoint(x: maxPerpPixel.nx, y: maxPerpPixel.ny, likelihood: maxPerpPixel.confidence),
  ];

  // ── §1.3 Combine sub-scores into the sample-quality score ──
  // Weighted sum (segmentation + shape + containment). Sharpness is neutral
  // (1.0, weight 0) until a blur metric exists. This replaces the strict
  // AND-chain: acceptance is now `qualityScore >= kSampleAcceptScore`.
  final qualityScore = combineQualityScore(
    segmentationScore: overallConfidence,
    shapeScore: shapeScore,
    containmentScore: containmentScore,
  );
  final accepted = qualityScore >= kSampleAcceptScore;

  trace.add('points=OK conf=${overallConfidence.toStringAsFixed(2)} ');
  trace.add('H=(${heelPoint.x.toStringAsFixed(2)},${heelPoint.y.toStringAsFixed(2)}) ');
  trace.add('T=(${toePoint.x.toStringAsFixed(2)},${toePoint.y.toStringAsFixed(2)})');
  trace.add('quality=${accepted ? 'OK' : 'REJECT'} '
      '${qualityScore.toStringAsFixed(2)} '
      '(seg=${overallConfidence.toStringAsFixed(2)}, '
      'shape=${shapeScore.toStringAsFixed(2)}, '
      'cont=${containmentScore.toStringAsFixed(2)})');
  emit();

  return FootDetectionResult(
    // §1.4: `footDetected` now means the combined score cleared the
    // threshold. Points are still returned for below-threshold frames so the
    // debug overlay / diagnostics can show why a frame was rejected.
    footDetected: accepted,
    confidence: overallConfidence,
    footSide: preferSide, // Assumed from framing; a mask can't verify side
    heelPoint: heelPoint,
    toePoint: toePoint,
    widthPoints: widthPoints,
    qualityScore: qualityScore,
    segmentationScore: overallConfidence,
    shapeScore: shapeScore,
    containmentScore: containmentScore,
  );
}

/// Mean absolute perpendicular extent of foreground pixels near one extreme
/// end of the principal axis. Used for the heel/toe heuristic.
///
/// [xOf]/[yOf] map a mask pixel to the working (pixel or normalized) space
/// the PCA was computed in, keeping the heuristic consistent with the
/// elongation check.
double _meanPerpNearExtreme(
  List<_MaskPixel> foreground,
  double cx,
  double cy,
  double cosA,
  double sinA,
  double minProj,
  double maxProj, {
  required bool nearMin,
  required double Function(_MaskPixel) xOf,
  required double Function(_MaskPixel) yOf,
}) {
  final extent = maxProj - minProj;
  if (extent <= 0) return 0;

  // Consider the extreme 20% of the axis.
  final boundary = nearMin ? minProj + 0.2 * extent : maxProj - 0.2 * extent;

  double sum = 0;
  int count = 0;
  for (final p in foreground) {
    final dx = xOf(p) - cx;
    final dy = yOf(p) - cy;
    final proj = dx * cosA + dy * sinA;
    final inExtreme = nearMin ? proj <= boundary : proj >= boundary;
    if (inExtreme) {
      sum += (-dx * sinA + dy * cosA).abs();
      count++;
    }
  }
  return count == 0 ? 0 : sum / count;
}
