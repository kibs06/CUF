/// Typed state machine for the Foot Size 2.0 auto-scan session.
///
/// V2 replaces v1's stringly-typed `guidanceState` (`'initializing'`,
/// `'searching'`, `'ready'`, …) and pre-formatted English guidance strings
/// with a closed set of enums plus structured [CoachHint]s. The screen owns
/// all copy; the controller only says WHAT happened, never how to phrase it.
library;

// ═══════════════════════════════════════════════════════════════════
// CAPTURE STEPS
// ═══════════════════════════════════════════════════════════════════

/// The guided captures of one session, in order.
///
/// Each foot is captured once from the top (the phone held straight above it).
/// The top view gives both measurements: the outline's long axis is the length
/// and its widest span is the width. The side/profile capture was dropped
/// because holding the phone beside the foot was too hard to do reliably.
/// Left foot completes fully before the right foot starts — feet can differ in
/// size, and finishing one foot's statistics immediately protects them from
/// later-pass failures.
enum CaptureStep { leftTop, rightTop }

extension CaptureStepX on CaptureStep {
  /// Which foot this capture belongs to ('left' | 'right').
  String get footSide => this == CaptureStep.leftTop ? 'left' : 'right';

  /// Every v2 capture is top-down ('front'); the guide and coaching key off it.
  String get captureAngle => 'front';

  /// Zero-based position in the session order.
  int get index => CaptureStep.values.indexOf(this);

  CaptureStep? get next {
    final i = index + 1;
    return i < CaptureStep.values.length ? CaptureStep.values[i] : null;
  }
}

/// The capture steps for a session's feet, in order.
///
/// `'left'` or `'right'` measures one foot — the default for most customers,
/// whose feet match. `'both'` measures each foot, for customers whose feet
/// differ in size or shape.
List<CaptureStep> stepsForFootMode(String footMode) {
  switch (footMode) {
    case 'left':
      return const [CaptureStep.leftTop];
    case 'right':
      return const [CaptureStep.rightTop];
    default:
      return const [CaptureStep.leftTop, CaptureStep.rightTop];
  }
}

// ═══════════════════════════════════════════════════════════════════
// SESSION PHASES
// ═══════════════════════════════════════════════════════════════════

/// High-level phase of the v2 scan session. Exactly one phase is active at
/// any moment; the screen renders each phase as a distinct visual state.
enum ScanPhase {
  /// Camera permission not yet granted. The screen shows the permission
  /// pre-flight UI; [ScanSessionController.requestPermission] resumes flow.
  needsPermission,

  /// ARCore session starting (availability check, install, plane search).
  /// Rendered as an indeterminate "warming up" state.
  starting,

  /// Session failed to start. [ScanSessionController.startFailure] carries
  /// the structured reason (from `ArSessionStartResult`).
  startFailed,

  /// Camera live, floor not yet confirmed — user is repositioning the phone.
  positioning,

  /// Floor confirmed, current step's guide box on screen, waiting for the
  /// user to frame their foot inside the guide.
  ready,

  /// Actively sampling the current step ([ScanSessionController.currentStep]
  /// + [ScanSessionController.captureProgress] drive the ring/stepper UI).
  capturing,

  /// Current step just completed; brief celebratory beat before the next
  /// step begins (or results when it was the last step).
  stepComplete,

  /// All four captures done; combining samples into final measurements.
  processing,

  /// Results computed — payload available at
  /// [ScanSessionController.resultsPayload]. Screen navigates onward.
  complete,
}

// ═══════════════════════════════════════════════════════════════════
// COACHING HINTS
// ═══════════════════════════════════════════════════════════════════

/// Why the coach card is showing what it's showing.
///
/// Structured reason → the screen maps it to copy/icon/tone. This keeps the
/// controller testable (assert reasons, not sentences) and copy editable in
/// exactly one place.
enum CoachReason {
  /// No floor plane yet — move the phone slowly over the floor.
  findFloor,

  /// Tracking degraded — move slower / improve lighting.
  moveSlowly,

  /// The camera frames are too blurry to measure — hold steady, wipe the lens.
  holdSteady,

  /// Floor ready — position your foot inside the guide frame.
  positionFoot,

  /// Foot detected and locked — hold still while we measure.
  holdStill,

  /// Detection struggling for several attempts (stall coaching). Amber tone;
  /// screen offers the tips sheet instead of v1's dead-end fallback button.
  havingTrouble,

  /// A step just finished successfully — celebratory tone.
  stepDone,

  /// One foot fully measured — shows its combined length.
  footDone,
}

/// Severity/tone bucket the screen uses to restyle the glass card.
enum CoachTone { neutral, active, success, warning }

/// One coaching message: a structured reason plus optional data.
class CoachHint {
  final CoachReason reason;
  final CoachTone tone;

  /// For [CoachReason.footDone]: combined length of the finished foot (mm).
  final double? footLengthMm;

  const CoachHint({
    required this.reason,
    required this.tone,
    this.footLengthMm,
  });

  @override
  bool operator ==(Object other) =>
      other is CoachHint &&
      other.reason == reason &&
      other.tone == tone &&
      other.footLengthMm == footLengthMm;

  @override
  int get hashCode => Object.hash(reason, tone, footLengthMm);
}
