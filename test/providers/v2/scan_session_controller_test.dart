import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

import 'package:app/providers/v2/scan_phase.dart';
import 'package:app/providers/v2/scan_session_controller.dart';
import 'package:app/services/ar_core_channel.dart';
import 'package:app/utils/ar_foot_measurement_pipeline.dart'
    show
        idealSampleCount,
        maxScanDuration,
        minSamplesForEarlyStop,
        noSampleGiveUpAttempts,
        sampleIntervalMs;
import 'package:app/utils/foot_detector.dart';
import 'package:app/utils/foot_measurement_utils.dart' show kSockLengthOffsetMm;

// ═══════════════════════════════════════════════════════════════════
// FAKES — same harness approach as auto_scan_controller_test.dart.
// ═══════════════════════════════════════════════════════════════════

class FakeArCore implements ArCoreChannel {
  final Completer<ArSessionStartResult> startCompleter = Completer();
  final StreamController<ArSessionEvent> eventSink =
      StreamController<ArSessionEvent>.broadcast();

  ArCameraFrame? nextFrame;

  /// Mean luma the fake reports (0–255). Bright by default so existing tests
  /// never see a dark view.
  double? meanLuma = 120;

  /// Last torch state the controller asked for.
  bool? torchRequest;

  /// Camera tilt from straight down the fake reports (degrees). Null = unknown,
  /// which the controller treats as level.
  double? tiltReply;

  @override
  Future<double?> getMeanLuma() async => meanLuma;

  @override
  Future<void> setTorch(bool enabled) async {
    torchRequest = enabled;
  }

  /// Staged sample batches, popped one per non-probe hitTestBatch call so
  /// they stay in lockstep with [FakeDetector.script] (both advance once per
  /// sampling tick).
  final List<List<ArWorldPoint?>> sampleHitScript = [];
  List<ArWorldPoint?>? _lastSampleHits;

  /// Staged hits for the 5-point guide-box area probes.
  List<ArWorldPoint?> probeHits = const [];
  bool sessionActive = false;

  /// Geometry of the simulated device. Applied to 5-point area probes the
  /// same way the native center-crop hitTest behaves: a probe whose
  /// normalized point lands outside the visible band maps to off-screen
  /// viewport pixels and can never hit a plane polygon → null.
  /// (This is what the original fake missed, hiding the off-screen
  /// side-step box bug.) Sample batches bypass the filter: their points are
  /// detector outputs, not guide-box geometry.
  double uprightFrameAspect = 3 / 4;
  double viewAspect = 9 / 19.5;

  Rect get _visibleBand {
    if (uprightFrameAspect > viewAspect) {
      final half = (viewAspect / uprightFrameAspect) / 2;
      return Rect.fromLTRB(0.5 - half, 0, 0.5 + half, 1);
    }
    final half = (uprightFrameAspect / viewAspect) / 2;
    return Rect.fromLTRB(0, 0.5 - half, 1, 0.5 + half);
  }

  bool _inBand(Offset p) {
    final b = _visibleBand;
    return p.dx >= b.left - 1e-9 &&
        p.dx <= b.right + 1e-9 &&
        p.dy >= b.top - 1e-9 &&
        p.dy <= b.bottom + 1e-9;
  }

  @override
  bool get isSessionActive => sessionActive;

  @override
  Stream<ArSessionEvent> get events => eventSink.stream;

  @override
  Future<ArSessionStartResult> startSession() {
    sessionActive = true;
    return startCompleter.future;
  }

  /// Availability reported to the controller's callers (the setup screen's
  /// pre-flight probe lives outside this controller, but the interface must
  /// still be satisfied).
  ArCoreAvailability availability = const ArCoreAvailability(
    rawValue: 'SUPPORTED_INSTALLED',
    support: ArCoreSupport.ready,
  );

  /// Terminal outcome of a [retrySession] call. Unset → reuse the start
  /// completer so tests that never retry behave exactly as before.
  Future<ArSessionStartResult>? retryReply;
  int retryCalls = 0;

  @override
  Future<ArCoreAvailability> checkAvailability() async => availability;

  @override
  Future<ArSessionStartResult> retrySession() {
    retryCalls++;
    sessionActive = true;
    return retryReply ?? startCompleter.future;
  }

  @override
  Future<void> stopSession() async {
    sessionActive = false;
  }

  @override
  Future<List<ArWorldPoint?>> hitTestBatch({
    required List<Offset> screenPoints,
    bool preferDepth = false,
  }) async {
    if (screenPoints.length == 5 && probeHits.length == 5) {
      return [
        for (var i = 0; i < screenPoints.length; i++)
          _inBand(screenPoints[i]) ? probeHits[i] : null,
      ];
    }
    if (sampleHitScript.isNotEmpty) {
      _lastSampleHits = sampleHitScript.removeAt(0);
    }
    return _lastSampleHits ?? List.filled(screenPoints.length, null);
  }

  @override
  Future<ArCameraFrame?> acquireCameraFrame() async => nextFrame;

  @override
  Future<ArWorldPoint?> hitTest({required double x, required double y, bool preferDepth = false}) async =>
      null;

  @override
  Future<ArTrackingState> getTrackingState() async => ArTrackingState.paused;

  @override
  Future<double?> getCameraTiltDegrees() async => tiltReply;

  @override
  Future<ArPlane?> getFloorPlane() async => null;

  @override
  Future<double?> getFloorDistance() async => null;

  @override
  void dispose() {}
}

class FakeDetector implements FootDetector {
  final List<FootDetectionResult> script = [];
  int calls = 0;

  @override
  Future<FootDetectionResult> detect({
    required Uint8List nv21Bytes,
    required int width,
    required int height,
    required int rotationDegrees,
    String? preferSide,
    Rect? guideRect,
  }) async {
    calls++;
    if (script.isEmpty) return const FootDetectionResult.negative();
    final i = calls - 1 < script.length ? calls - 1 : script.length - 1;
    return script[i];
  }

  @override
  void dispose() {}
}

ArWorldPoint wp(double x, double y) =>
    ArWorldPoint(x: x, y: y, z: 0, distanceFromCamera: 0.3);

/// Detection WITH a real width pair. Heel↔toe = 240mm, width = 60mm.
FootDetectionResult detectedWithWidth({String side = 'left'}) =>
    FootDetectionResult(
      footDetected: true,
      confidence: 0.9,
      footSide: side,
      qualityScore: 0.9,
      shapeScore: 1.0,
      containmentScore: 1.0,
      heelPoint: const FootPoint(x: 0.40, y: 0.45, likelihood: 0.95),
      toePoint: const FootPoint(x: 0.60, y: 0.45, likelihood: 0.95),
      widthPoints: const [
        FootPoint(x: 0.48, y: 0.35, likelihood: 0.9),
        FootPoint(x: 0.54, y: 0.35, likelihood: 0.9),
      ],
    );

/// Detection WITHOUT width points — controller records a proportional
/// estimate tagged widthMeasured:false (E7).
FootDetectionResult detectedNoWidth({String side = 'left'}) =>
    FootDetectionResult(
      footDetected: true,
      confidence: 0.9,
      footSide: side,
      qualityScore: 0.9,
      shapeScore: 1.0,
      containmentScore: 1.0,
      heelPoint: const FootPoint(x: 0.40, y: 0.45, likelihood: 0.95),
      toePoint: const FootPoint(x: 0.60, y: 0.45, likelihood: 0.95),
    );

/// Shape-valid but weak detection — must never be recorded as a sample.
FootDetectionResult detectedLowConfidence({String side = 'left'}) =>
    FootDetectionResult(
      footDetected: true,
      confidence: 0.3,
      footSide: side,
      qualityScore: 0.35,
      heelPoint: const FootPoint(x: 0.40, y: 0.45, likelihood: 0.4),
      toePoint: const FootPoint(x: 0.60, y: 0.45, likelihood: 0.4),
    );

/// A full-size NV21 frame with sharp vertical edges, so it passes the blur
/// gate the way a focused camera frame would.
const int _frameW = 640;
const int _frameH = 480;
Uint8List _sharpLuma() {
  final bytes = Uint8List(_frameW * _frameH * 3 ~/ 2);
  for (var i = 0; i < _frameW * _frameH; i++) {
    // Period-4 stripes: the sampler reads every 2nd pixel, so a period-2
    // pattern would alias to a flat plane.
    bytes[i] = (i % _frameW) % 4 < 2 ? 0 : 255;
  }
  return bytes;
}

ArCameraFrame frame() => ArCameraFrame(
      nv21Bytes: _sharpLuma(),
      width: _frameW,
      height: _frameH,
      rotationDegrees: 90,
    );

/// The same frame, smoothed to a flat luma plane: what a blurry lens delivers.
ArCameraFrame blurredFrame() => ArCameraFrame(
      nv21Bytes: Uint8List.fromList(
        List.filled(_frameW * _frameH * 3 ~/ 2, 128),
      ),
      width: _frameW,
      height: _frameH,
      rotationDegrees: 90,
    );

void main() {
  late FakeArCore ar;
  late FakeDetector detector;
  late ScanSessionController ctrl;
  final List<ScanSessionEvent> caughtEvents = [];

  /// Build controller + complete session start + drive to 'ready'.
  void harness(
    FakeAsync async, {
    String condition = 'bare',
    String footMode = 'both',
  }) {
    ar = FakeArCore();
    detector = FakeDetector();
    ctrl = ScanSessionController(
      arCore: ar,
      detectorFactory: () => detector,
      footCondition: condition,
      footMode: footMode,
    );
    caughtEvents.clear();
    ctrl.events.listen(caughtEvents.add);

    ar.probeHits = List.filled(5, wp(0.5, 0));
    ctrl.initialize();
    ar.startCompleter.complete(const ArSessionStartResult(started: true));
    async.flushMicrotasks();

    ar.eventSink
        .add(const ArSessionEvent(type: 'tracking', data: {'state': 'tracking'}));
    ar.eventSink.add(const ArSessionEvent(type: 'plane', data: {}));
    async.elapse(const Duration(milliseconds: 50));

    assert(ctrl.trackingState == ArTrackingState.tracking);
    assert(ctrl.areaTracked);
    assert(ctrl.phase == ScanPhase.ready);
  }

  /// Stage one happy-path sample tick (with measured width).
  void stageGoodTick({bool withWidth = true, String side = 'left'}) {
    ar.nextFrame = frame();
    // Heel↔toe 240mm; width pair present → 60mm, else proportional est.
    ar.sampleHitScript.add(
      withWidth
          ? [wp(0.30, 0), wp(0.06, 0), wp(0.13, 0), wp(0.19, 0)]
          : [wp(0.30, 0), wp(0.06, 0)],
    );
    detector.script.add(
        withWidth ? detectedWithWidth(side: side) : detectedNoWidth(side: side));
  }

  /// Run one capture pass to completion, plus the 900ms success beat.
  /// Caller must have staged ticks already.
  ///
  /// The pass is sample-driven, so it is stepped a tick at a time and stops
  /// exactly when it has its samples. Elapsing a fixed block instead would leave
  /// idle poll time after the state machine advances, and the 500ms area poll
  /// would re-lock the floor before the caller could assert on it.
  void runPass(FakeAsync async) {
    ctrl.startCapture();
    expect(ctrl.phase, ScanPhase.capturing);
    var ticks = 0;
    while (ctrl.phase == ScanPhase.capturing && ticks < 300) {
      async.elapse(const Duration(milliseconds: sampleIntervalMs));
      ticks++;
    }
    expect(ctrl.phase, ScanPhase.stepComplete,
        reason: 'the staged detections must carry the pass to completion');
    // Success-beat timer before the state machine advances.
    async.elapse(const Duration(milliseconds: 900));
  }

  /// Re-verify the guide-box area deterministically (production relies on
  /// the 500ms poll; see auto_scan_controller_test.dart's relockArea).
  void relockArea(FakeAsync async) {
    ar.probeHits = List.filled(5, wp(0.5, 0));
    ctrl.refreshAreaTracking();
    async.flushMicrotasks();
    assert(ctrl.areaTracked);
  }

  group('ScanSessionController — phone tilt gate', () {
    test('a phone tilted past the limit is not ready and is told to level it',
        () {
      fakeAsync((async) {
        harness(async);
        ar.tiltReply = 45;
        relockArea(async);
        expect(ctrl.phase, ScanPhase.positioning);
        expect(ctrl.coachHint?.reason, CoachReason.tiltPhone);
      });
    });

    test('levelling the phone again returns the scan to ready', () {
      fakeAsync((async) {
        harness(async);
        ar.tiltReply = 45;
        relockArea(async);
        ar.tiltReply = 5;
        relockArea(async);
        expect(ctrl.phase, ScanPhase.ready);
      });
    });

    test('a tilted phone cannot start a capture pass', () {
      fakeAsync((async) {
        harness(async);
        ar.tiltReply = 45;
        relockArea(async);
        ctrl.startCapture();
        expect(ctrl.phase, ScanPhase.positioning);
        expect(ctrl.coachHint?.reason, CoachReason.tiltPhone);
      });
    });

    test('an unknown tilt never blocks the scan', () {
      fakeAsync((async) {
        harness(async);
        ar.tiltReply = 45;
        relockArea(async);
        ar.tiltReply = null;
        relockArea(async);
        expect(ctrl.phase, ScanPhase.ready);
      });
    });
  });

  group('ScanSessionController — session init', () {
    test('failed start surfaces typed startFailed state with reason', () {
      fakeAsync((async) {
        ar = FakeArCore();
        detector = FakeDetector();
        ctrl =
            ScanSessionController(arCore: ar, detectorFactory: () => detector);
        ctrl.initialize();
        ar.startCompleter.complete(const ArSessionStartResult(
            started: false, reason: 'needs_install'));
        async.flushMicrotasks();

        expect(ctrl.phase, ScanPhase.startFailed);
        expect(ctrl.startFailureReason, 'needs_install');
      });
    });

    test('permission denied reports the typed needsPermission phase', () {
      fakeAsync((async) {
        ar = FakeArCore();
        detector = FakeDetector();
        ctrl =
            ScanSessionController(arCore: ar, detectorFactory: () => detector);
        ctrl.reportPermissionDenied();
        expect(ctrl.phase, ScanPhase.needsPermission);
        ctrl.dispose();
      });
    });

    test('initializes in `starting` — the phase that mounts the AR platform '
        'view (regression: camera never opened on a cold first scan)', () {
      fakeAsync((async) {
        ar = FakeArCore();
        detector = FakeDetector();
        ctrl =
            ScanSessionController(arCore: ar, detectorFactory: () => detector);

        // The screen gates the ar_foot_scan platform view on the phase; the
        // native session is created BY that view, so any gated starting phase
        // parks the startSession reply until its 15 s timeout.
        expect(ctrl.phase, ScanPhase.starting);

        ctrl.initialize();
        expect(ctrl.phase, ScanPhase.starting,
            reason: 'setup keeps warming-up state while the start is in flight');

        ar.startCompleter.complete(const ArSessionStartResult(started: true));
        async.flushMicrotasks();
        expect(ctrl.phase, ScanPhase.positioning);
        ctrl.dispose();
      });
    });

    test(
        'retryStart asks for a FRESH native session (not the replayed failure) '
        'and recovers into positioning', () {
      fakeAsync((async) {
        ar = FakeArCore();
        detector = FakeDetector();
        ctrl =
            ScanSessionController(arCore: ar, detectorFactory: () => detector);

        ctrl.initialize();
        ar.startCompleter.complete(const ArSessionStartResult(
          started: false,
          reason: 'needs_install',
          message: 'ARCore is being installed from Google Play.',
        ));
        async.flushMicrotasks();
        expect(ctrl.phase, ScanPhase.startFailed);
        expect(ctrl.startFailureReason, 'needs_install');

        // The customer installed ARCore from Play and tapped Retry.
        ar.retryReply = Future.value(const ArSessionStartResult(started: true));
        ctrl.retryStart();
        expect(ctrl.phase, ScanPhase.starting,
            reason: 'retry re-enters the warming-up phase while it runs');

        async.flushMicrotasks();
        expect(ar.retryCalls, 1,
            reason: 'retry must call retrySession — startSession would replay '
                'the cached native failure forever');
        expect(ctrl.phase, ScanPhase.positioning);
        expect(ctrl.startFailureReason, isNull,
            reason: 'the failure sheet must clear once a retry succeeds');
        ctrl.dispose();
      });
    });

    test('successful start lands in positioning → ready via area tracking',
        () {
      fakeAsync((async) {
        harness(async);
        expect(ctrl.phase, ScanPhase.ready);
        expect(
          ctrl.coachHint?.reason,
          CoachReason.positionFoot,
          reason: 'ready phase coaches the user to position their foot',
        );
        ctrl.dispose();
      });
    });
  });

  group('ScanSessionController — full successful scan', () {
    test('advances L·T → R·T and emits compensated payload', () {
      fakeAsync((async) {
        harness(async);

        // Plenty of good ticks for both top passes (script repeats last).
        for (int i = 0; i < 40; i++) {
          stageGoodTick(withWidth: true, side: i % 2 == 0 ? 'left' : 'right');
        }
        stageGoodTick(); // sticky tail

        // Pass 1: LEFT TOP → the left foot is measured and frozen at once.
        runPass(async);
        expect(ctrl.currentStep, CaptureStep.rightTop);
        expect(ctrl.phase, ScanPhase.ready);
        expect(caughtEvents.whereType<StepCompletedEvent>().single.step,
            CaptureStep.leftTop);
        final footDone = caughtEvents.whereType<FootCompletedEvent>().single;
        expect(footDone.footSide, 'left');
        expect(footDone.lengthMm, greaterThan(0));

        // Pass 2: RIGHT TOP → complete.
        relockArea(async);
        runPass(async);
        expect(ctrl.phase, ScanPhase.complete);

        final completed = caughtEvents.whereType<ScanCompleteEvent>().single;
        final p = completed.payload;
        expect(p.euSize, isNotNull);
        expect(p.usSize, isNotNull);
        expect(p.ukSize, isNotNull);
        expect(p.sizingFootSide, isIn(['left', 'right']));
        expect(p.widthCategory, isIn(['narrow', 'standard', 'wide']));
        expect(p.leftLengthMm, greaterThan(0));
        expect(p.rightLengthMm, greaterThan(0));

        // Confidence breakdown ships with the payload for the results UI.
        expect(p.confidenceFactors, isNotEmpty);
        // Both feet measured + plenty of samples → all factors positive.
        expect(p.confidenceFactors.every((f) => f.positive), isTrue);

        // Bare feet: compensated == raw (identity compensation).
        expect(p.leftLengthMm, p.leftRawLengthMm);
        ctrl.dispose();
      });
    });

    test('E7: proportional width estimates are excluded from width stats',
        () {
      fakeAsync((async) {
        harness(async);

        // Front pass: first 12 ticks carry REAL width pairs (~60mm), the
        // rest (and everything after) fall back to no-width detections
        // whose 0.38×len estimate would be ~91mm.
        for (int i = 0; i < 12; i++) {
          stageGoodTick(withWidth: true);
        }
        stageGoodTick(withWidth: false); // sticky: estimates from here on

        runPass(async); // LEFT TOP — mixes 10 measured + ~8 estimated rows
        // Left foot combined NOW with frozen statistics.
        final footDone = caughtEvents.whereType<FootCompletedEvent>().single;

        // The width median must come from the measured cluster (~60mm):
        // had estimates (~91mm) leaked into the stats, combining 10 real +
        // many estimated rows would pull the median well above 70mm.
        expect(footDone.lengthMm, greaterThan(0));

        // Drive the whole session home to inspect the width value.
        for (int i = 0; i < 40; i++) {
          stageGoodTick(withWidth: true, side: 'right');
        }
        stageGoodTick();
        relockArea(async);
        runPass(async); // RIGHT TOP

        final p = caughtEvents.whereType<ScanCompleteEvent>().single.payload;
        // Left foot was the mixed-measured one; its width must reflect the
        // MEASURED cluster only.
        expect(p.leftWidthMm!, lessThan(75),
            reason: 'width median must exclude 0.38×len estimates');
        expect(p.leftWidthMm!, greaterThan(50));
        ctrl.dispose();
      });
    });

    test('E8: socks scans expose compensated values as the display values',
        () {
      fakeAsync((async) {
        harness(async, condition: 'socks');

        for (int i = 0; i < 40; i++) {
          stageGoodTick(side: i % 2 == 0 ? 'left' : 'right');
        }
        stageGoodTick();

        runPass(async); // LEFT TOP
        relockArea(async);
        runPass(async); // RIGHT TOP

        final p = caughtEvents.whereType<ScanCompleteEvent>().single.payload;
        expect(p.leftLengthMm!, closeTo(p.leftRawLengthMm! - kSockLengthOffsetMm, 0.01));
        // And sizing consumed exactly what will be displayed.
        expect(p.euSize, isNotNull);
        ctrl.dispose();
      });
    });
  });

  group('ScanSessionController — precision gates (v2-only tuning)', () {
    test('good detections become samples; passSampleCount tracks them', () {
      fakeAsync((async) {
        harness(async);

        for (int i = 0; i < 30; i++) {
          stageGoodTick(withWidth: true);
        }
        stageGoodTick();

        ctrl.startCapture();
        async.elapse(const Duration(seconds: 1)); // ≈5 sampling ticks
        expect(ctrl.passSampleCount, greaterThanOrEqualTo(1),
            reason: 'clean ticks must be recorded and visible to the UI');

        ctrl.cancelCapture();
        ctrl.dispose();
      });
    });

    test('low-confidence detections never become samples', () {
      fakeAsync((async) {
        harness(async);

        for (int i = 0; i < 30; i++) {
          ar.nextFrame = frame();
          ar.sampleHitScript
              .add([wp(0.30, 0), wp(0.06, 0), wp(0.13, 0), wp(0.19, 0)]);
          detector.script.add(detectedLowConfidence());
        }
        stageGoodTick();

        ctrl.startCapture();
        async.elapse(const Duration(seconds: 3));
        expect(ctrl.passSampleCount, 0,
            reason: 'confidence 0.3 is below the v2 recording bar (0.5)');

        ctrl.cancelCapture();
        ctrl.dispose();
      });
    });

    test('implausible measured widths are rejected as bad hitTest pairs', () {
      fakeAsync((async) {
        harness(async);

        // Width pair = 150mm against a 240mm length → ratio 0.625 > 0.60.
        for (int i = 0; i < 30; i++) {
          ar.nextFrame = frame();
          ar.sampleHitScript.add(
              [wp(0.30, 0), wp(0.06, 0), wp(0.20, 0), wp(0.05, 0)]);
          detector.script.add(detectedWithWidth());
        }
        stageGoodTick();

        ctrl.startCapture();
        async.elapse(const Duration(seconds: 3));
        expect(ctrl.passSampleCount, 0,
            reason: 'width/length ratio outside 0.20–0.60 is a bad pair, '
                'not anatomy');

        ctrl.cancelCapture();
        ctrl.dispose();
      });
    });

    test('a frame whose mask shape is poor never becomes a sample', () {
      fakeAsync((async) {
        harness(async);

        for (int i = 0; i < 30; i++) {
          ar.nextFrame = frame();
          ar.sampleHitScript
              .add([wp(0.30, 0), wp(0.06, 0), wp(0.13, 0), wp(0.19, 0)]);
          detector.script.add(const FootDetectionResult(
            footDetected: true,
            confidence: 0.9,
            footSide: 'left',
            qualityScore: 0.9,
            shapeScore: 0.2,
            containmentScore: 1.0,
            heelPoint: FootPoint(x: 0.40, y: 0.45, likelihood: 0.95),
            toePoint: FootPoint(x: 0.60, y: 0.45, likelihood: 0.95),
          ));
        }
        stageGoodTick();

        ctrl.startCapture();
        async.elapse(const Duration(seconds: 3));
        expect(ctrl.passSampleCount, 0,
            reason: 'shape 0.2 is below the v2 bar (0.5): the mask caught '
                'something other than the foot');

        ctrl.cancelCapture();
        ctrl.dispose();
      });
    });

    test('a heel/toe swap against the kept axis is never a sample', () {
      fakeAsync((async) {
        harness(async);

        // Same foot, heel and toe swapped: the axis turns by about 180°.
        // The temporal gate drops the first two frames as not-confirmed, so the
        // first three are normal: the third is the first kept frame and sets the
        // axis. The swapped frames after it are a run shorter than the re-seed
        // length, and the window below ends before that run could re-seed.
        const flipped = FootDetectionResult(
          footDetected: true,
          confidence: 0.9,
          footSide: 'left',
          qualityScore: 0.9,
          shapeScore: 1.0,
          containmentScore: 1.0,
          heelPoint: FootPoint(x: 0.60, y: 0.45, likelihood: 0.95),
          toePoint: FootPoint(x: 0.40, y: 0.45, likelihood: 0.95),
        );
        for (int i = 0; i < 30; i++) {
          ar.nextFrame = frame();
          ar.sampleHitScript
              .add([wp(0.30, 0), wp(0.06, 0), wp(0.13, 0), wp(0.19, 0)]);
          detector.script.add(i < 3 ? detectedWithWidth() : flipped);
        }
        stageGoodTick();

        ctrl.startCapture();
        async.elapse(const Duration(seconds: 1)); // ~5 ticks, before a re-seed
        expect(ctrl.passSampleCount, 1,
            reason: 'only the first frame sets the kept axis; the swapped '
                'frames point against it and must not be recorded');

        ctrl.cancelCapture();
        ctrl.dispose();
      });
    });

    test('a run of swapped frames re-seeds the axis instead of locking the pass',
        () {
      fakeAsync((async) {
        harness(async);

        // The first kept frame is an outlier: every later frame reads the foot
        // the other way round. Without a re-seed, the outlier axis locks out the
        // rest of the pass.
        const flipped = FootDetectionResult(
          footDetected: true,
          confidence: 0.9,
          footSide: 'left',
          qualityScore: 0.9,
          shapeScore: 1.0,
          containmentScore: 1.0,
          heelPoint: FootPoint(x: 0.60, y: 0.45, likelihood: 0.95),
          toePoint: FootPoint(x: 0.40, y: 0.45, likelihood: 0.95),
        );
        for (int i = 0; i < 30; i++) {
          ar.nextFrame = frame();
          ar.sampleHitScript
              .add([wp(0.30, 0), wp(0.06, 0), wp(0.13, 0), wp(0.19, 0)]);
          detector.script.add(i < 3 ? detectedWithWidth() : flipped);
        }
        stageGoodTick();

        ctrl.startCapture();
        // Track the largest count seen: the pass ends (and clears its buffer)
        // once the kept samples agree, so the final count is not the signal.
        var maxCount = 0;
        for (int t = 0; t < 15; t++) {
          async.elapse(const Duration(milliseconds: 200));
          if (ctrl.passSampleCount > maxCount) maxCount = ctrl.passSampleCount;
        }
        expect(maxCount, greaterThan(1),
            reason: 'after three swapped frames the next frame must re-seed '
                'the axis, so later correct frames are kept');

        ctrl.cancelCapture();
        ctrl.dispose();
      });
    });

    test('a foot too small in frame asks the customer to move closer', () {
      fakeAsync((async) {
        harness(async);

        // Heel↔toe span 0.20 in normalized space: below the too-far line (0.30).
        for (int i = 0; i < 30; i++) {
          ar.nextFrame = frame();
          ar.sampleHitScript
              .add([wp(0.30, 0), wp(0.06, 0), wp(0.13, 0), wp(0.19, 0)]);
          detector.script.add(detectedWithWidth());
        }
        stageGoodTick();

        ctrl.startCapture();
        async.elapse(const Duration(seconds: 1));
        expect(ctrl.coachHint?.reason, CoachReason.moveCloser);

        ctrl.cancelCapture();
        ctrl.dispose();
      });
    });

    test('a foot filling the frame asks the customer to move back', () {
      fakeAsync((async) {
        harness(async);

        // Heel↔toe span 0.96 in normalized space: above the too-close line (0.92).
        const huge = FootDetectionResult(
          footDetected: true,
          confidence: 0.9,
          footSide: 'left',
          qualityScore: 0.9,
          shapeScore: 1.0,
          containmentScore: 1.0,
          heelPoint: FootPoint(x: 0.02, y: 0.50, likelihood: 0.95),
          toePoint: FootPoint(x: 0.98, y: 0.50, likelihood: 0.95),
        );
        for (int i = 0; i < 30; i++) {
          ar.nextFrame = frame();
          ar.sampleHitScript
              .add([wp(0.30, 0), wp(0.06, 0), wp(0.13, 0), wp(0.19, 0)]);
          detector.script.add(huge);
        }
        stageGoodTick();

        ctrl.startCapture();
        async.elapse(const Duration(seconds: 1));
        expect(ctrl.coachHint?.reason, CoachReason.moveFarther);

        ctrl.cancelCapture();
        ctrl.dispose();
      });
    });

    test('the pass ends on collected samples, not on a fixed window', () {
      fakeAsync((async) {
        harness(async);

        for (int i = 0; i < 40; i++) {
          stageGoodTick(withWidth: false);
        }
        stageGoodTick();

        ctrl.startCapture();
        expect(ctrl.phase, ScanPhase.capturing);

        // Step a tick at a time so the pass stops where it really stops.
        var ticks = 0;
        while (ctrl.phase == ScanPhase.capturing && ticks < 300) {
          async.elapse(const Duration(milliseconds: sampleIntervalMs));
          ticks++;
        }

        expect(ctrl.phase, ScanPhase.stepComplete);
        expect(ticks * sampleIntervalMs < maxScanDuration.inMilliseconds, isTrue,
            reason: 'it stopped on evidence, not on the safety cap');
        expect(ctrl.passSampleCount,
            greaterThanOrEqualTo(minSamplesForEarlyStop));
        ctrl.dispose();
      });
    });

    test('readings that already agree end the pass before the full target', () {
      fakeAsync((async) {
        harness(async);

        // Every staged frame reports the same heel↔toe length, so the IQR is 0
        // and the agreement clause applies well before [idealSampleCount].
        for (int i = 0; i < 40; i++) {
          stageGoodTick(withWidth: false);
        }
        stageGoodTick();

        ctrl.startCapture();
        var ticks = 0;
        while (ctrl.phase == ScanPhase.capturing && ticks < 300) {
          async.elapse(const Duration(milliseconds: sampleIntervalMs));
          ticks++;
        }

        expect(ctrl.passSampleCount, lessThan(idealSampleCount),
            reason: 'tight agreement stands in for the full sample target');
        expect(ctrl.passSampleCount,
            greaterThanOrEqualTo(minSamplesForEarlyStop));
        ctrl.dispose();
      });
    });

    test('a pass that records no sample gives up in seconds, not in a minute',
        () {
      fakeAsync((async) {
        harness(async);

        ar.nextFrame = null; // nothing detectable at all
        ctrl.startCapture();

        async.elapse(Duration(
            milliseconds: sampleIntervalMs * (noSampleGiveUpAttempts - 2)));
        expect(ctrl.phase, ScanPhase.capturing,
            reason: 'an attempt or two short of the budget is not a failure');

        // The give-up, not the cap: a pass that never records anything must not
        // keep the customer standing there for a minute to reach the same dead
        // end the old five-second window reached.
        async.elapse(const Duration(seconds: 20));
        expect(ctrl.phase, ScanPhase.ready);
        expect(ctrl.coachHint?.reason, CoachReason.havingTrouble);
        ctrl.dispose();
      });
    });

    test('a detected foot whose points never land on the floor gives up too',
        () {
      fakeAsync((async) {
        harness(async);

        // The detector is happy every tick, but hitTestBatch finds no floor
        // plane — the wet/glossy-surface case. Detections accumulate; samples
        // never do. A give-up keyed on DETECTIONS would miss this entirely and
        // run the full cap.
        ar.nextFrame = frame();
        ar.sampleHitScript.add(const []);
        detector.script.add(detectedWithWidth());

        ctrl.startCapture();

        async.elapse(Duration(
            milliseconds: sampleIntervalMs * (noSampleGiveUpAttempts - 2)));
        expect(ctrl.phase, ScanPhase.capturing);
        expect(ctrl.passSampleCount, 0,
            reason: 'a detection without a floor hit is not a sample');

        async.elapse(const Duration(seconds: 20));
        expect(ctrl.phase, isNot(ScanPhase.capturing),
            reason: 'the bounce back to the start must not wait out the cap');
        ctrl.dispose();
      });
    });
  });

  group('ScanSessionController — visible-band geometry (off-screen box fix)', () {
    test('top guide rect stays on screen in the visible crop band', () {
      fakeAsync((async) {
        harness(async);

        // Front rect (x 0.30–0.70) fits the band on any phone — unclamped.
        final front = ctrl.effectiveGuideRect;
        expect(front, ctrl.currentGuideRect);

        // The one top-down guide (x 0.30–0.70) sits inside the visible band on
        // the simulated tall phone, so it is never clamped.
        final band = ar._visibleBand;
        final eff = ctrl.effectiveGuideRect;
        expect(eff, ctrl.currentGuideRect);
        expect(eff.left >= band.left && eff.right <= band.right, isTrue);
        expect(eff.top >= band.top && eff.bottom <= band.bottom, isTrue);
        ctrl.dispose();
      });
    });

    test('area re-locks for the right-foot step (regression: off-screen probes)',
        () {
      fakeAsync((async) {
        harness(async);

        // Pass 1 (LEFT TOP) completes; the state machine resets area tracking
        // for the new box position.
        for (int i = 0; i < 25; i++) {
          stageGoodTick();
        }
        stageGoodTick();
        runPass(async);
        expect(ctrl.currentStep, CaptureStep.rightTop);
        expect(ctrl.areaTracked, isFalse);

        // Before the fix, the guide's corner probes could sit outside the
        // visible band — so every probe but the center missed the
        // plane and the lock stalled forever (box gone, capture blocked).
        // Now the probes use the clamped rect and the 500 ms poll re-locks.
        ar.probeHits = List.filled(5, wp(0.5, 0));
        async.elapse(const Duration(milliseconds: 600));
        expect(ctrl.areaTracked, isTrue,
            reason: 'side-step area lock must recover via clamped probes');
        expect(ctrl.phase, ScanPhase.ready);
        ctrl.dispose();
      });
    });
  });

  group('ScanSessionController — floor stability', () {
    test('a settling floor does not lock the area until two polls agree', () {
      fakeAsync((async) {
        harness(async);
        expect(ctrl.areaTracked, isTrue, reason: 'settled floor from harness');

        // Corner probes now read a floor 5 cm higher: the plane is still moving.
        ar.probeHits = [
          wp(0.5, 0),
          wp(0.1, 0.05),
          wp(0.9, 0.05),
          wp(0.1, 0.05),
          wp(0.9, 0.05),
        ];
        ctrl.refreshAreaTracking();
        async.flushMicrotasks();
        expect(ctrl.areaTracked, isFalse,
            reason: 'a drifting floor must drop the lock');

        // The floor settles at the new height: two agreeing polls re-lock it.
        ar.probeHits = [
          wp(0.5, 0.05),
          wp(0.1, 0.05),
          wp(0.9, 0.05),
          wp(0.1, 0.05),
          wp(0.9, 0.05),
        ];
        ctrl.refreshAreaTracking();
        async.flushMicrotasks();
        expect(ctrl.areaTracked, isTrue,
            reason: 'the settled floor is the new reference');
        ctrl.dispose();
      });
    });
  });

  group('ScanSessionController — follow box', () {
    test('the guide box follows the detected foot and returns to fixed when lost',
        () {
      fakeAsync((async) {
        harness(async);
        final fixed = ctrl.effectiveGuideRect;

        for (int i = 0; i < 3; i++) {
          stageGoodTick();
        }
        ctrl.startCapture();
        async.elapse(Duration(milliseconds: sampleIntervalMs * 3));

        // The fixture's heel/toe/width give a box around (0.32..0.68, 0.27..0.53).
        final drawn = ctrl.drawnGuideRect;
        expect(drawn, isNot(fixed), reason: 'the box moved to the foot');
        expect(drawn.left, closeTo(0.32, 0.001));
        expect(drawn.right, closeTo(0.68, 0.001));
        expect(drawn.top, closeTo(0.27, 0.001));
        expect(drawn.bottom, closeTo(0.53, 0.001));

        // No foot in frame any more: the box falls back to the fixed guide.
        ar.nextFrame = null;
        async.elapse(Duration(milliseconds: sampleIntervalMs * 2));
        expect(ctrl.drawnGuideRect, fixed,
            reason: 'a lost foot restores the fixed guide');
        ctrl.cancelCapture();
        ctrl.dispose();
      });
    });
  });

  group('ScanSessionController — night aid', () {
    test('a dark view that cannot find the floor says the light is the problem', () {
      fakeAsync((async) {
        harness(async);
        ar.eventSink.add(
          const ArSessionEvent(type: 'tracking', data: {'state': 'limited'}),
        );
        ar.probeHits = const [];
        ar.meanLuma = 20;
        async.elapse(const Duration(milliseconds: 600));

        expect(ctrl.tooDark, isTrue);
        expect(ctrl.phase, ScanPhase.positioning);
        expect(ctrl.coachHint?.reason, CoachReason.tooDark);
        expect(ctrl.coachHint?.tone, CoachTone.warning);
        ctrl.dispose();
      });
    });

    test('a dark view with the floor in sight keeps the normal ready state', () {
      fakeAsync((async) {
        harness(async);
        ar.meanLuma = 20;
        async.elapse(const Duration(milliseconds: 600));

        expect(ctrl.tooDark, isTrue);
        expect(ctrl.phase, ScanPhase.ready,
            reason: 'a floor that is found is not blocked by the light');
        ctrl.dispose();
      });
    });

    test('setTorch records the state and tells the channel', () {
      fakeAsync((async) {
        harness(async);
        ctrl.setTorch(true);
        expect(ctrl.torchOn, isTrue);
        expect(ar.torchRequest, isTrue);

        ctrl.setTorch(false);
        expect(ctrl.torchOn, isFalse);
        expect(ar.torchRequest, isFalse);
        ctrl.dispose();
      });
    });
  });

  group('ScanSessionController — blur gate', () {
    test('a blurry frame never becomes a sample and asks to hold steady', () {
      fakeAsync((async) {
        harness(async);
        ar.nextFrame = blurredFrame();
        ctrl.startCapture();
        async.elapse(Duration(milliseconds: sampleIntervalMs * 3));

        expect(ctrl.passSampleCount, 0,
            reason: 'blurred frames must not feed the measurement');
        expect(ctrl.coachHint?.reason, CoachReason.holdSteady);
        expect(ctrl.coachHint?.tone, CoachTone.warning);
        ctrl.cancelCapture();
        ctrl.dispose();
      });
    });
  });

  group('ScanSessionController — one-foot scans', () {
    for (final mode in ['left', 'right']) {
      test('$mode-only scan measures just that foot and completes', () {
        fakeAsync((async) {
          harness(async, footMode: mode);
          expect(ctrl.planSteps, hasLength(1));
          expect(
            ctrl.currentStep,
            mode == 'left' ? CaptureStep.leftTop : CaptureStep.rightTop,
          );

          for (int i = 0; i < 25; i++) {
            stageGoodTick(side: mode);
          }
          stageGoodTick(side: mode);
          runPass(async);

          expect(ctrl.phase, ScanPhase.complete);
          final done = caughtEvents.whereType<FootCompletedEvent>().single;
          expect(done.footSide, mode);
          final p = caughtEvents.whereType<ScanCompleteEvent>().single.payload;
          expect(p.sizingFootSide, mode);
          expect(p.euSize, isNotNull);
          if (mode == 'left') {
            expect(p.leftLengthMm, greaterThan(0));
            expect(p.rightLengthMm, isNull);
          } else {
            expect(p.rightLengthMm, greaterThan(0));
            expect(p.leftLengthMm, isNull);
          }
          // Scanning one foot by choice is not a missing-foot warning.
          expect(
            p.confidenceFactors.any((f) => f.title.startsWith('Only your')),
            isFalse,
          );
          ctrl.dispose();
        });
      });
    }
  });

  group('ScanSessionController — failure paths', () {
    test('zero-detection pass fails explicitly, discards buffer, stays ready',
        () {
      fakeAsync((async) {
        harness(async);

        ar.nextFrame = null; // nothing detectable all pass
        ctrl.startCapture();
        async.elapse(maxScanDuration);
        async.elapse(const Duration(milliseconds: 900));

        expect(ctrl.phase, ScanPhase.ready,
            reason: 'v2 returns to ready with a warning hint instead of '
                'a dead-end error state');
        expect(ctrl.coachHint?.reason, CoachReason.havingTrouble);
        expect(ctrl.coachHint?.tone, CoachTone.warning);
        expect(caughtEvents, isEmpty);
        expect(ctrl.currentStep, CaptureStep.leftTop);
        ctrl.dispose();
      });
    });

    test(
        'a pass that pooled disagreeing samples says so, not "check the '
        'lighting"', () {
      fakeAsync((async) {
        harness(async);

        ar.nextFrame = frame();
        ctrl.startCapture();
        // Alternate a 240mm foot with a 320mm one. The pass collects more than
        // enough samples (so this is not a "foot never seen" failure), but they
        // scatter far past the agreement threshold, so the combine produces a
        // reading the rescan gate refuses.
        for (int i = 0; i < 30; i++) {
          final long = i.isEven;
          ar.sampleHitScript.add(long
              ? [wp(0.34, 0), wp(0.02, 0), wp(0.16, 0), wp(0.24, 0)]
              : [wp(0.30, 0), wp(0.06, 0), wp(0.13, 0), wp(0.19, 0)]);
          detector.script.add(detectedWithWidth());
        }
        async.elapse(maxScanDuration);
        async.elapse(const Duration(milliseconds: 900));

        expect(ctrl.phase, ScanPhase.ready,
            reason: 'the reading is refused, not shown as a size');
        expect(
          ctrl.coachHint?.reason,
          CoachReason.readingsDisagreed,
          reason: 'the foot was measured fine and the numbers disagreed — '
              'blaming lighting and floor texture would send the customer to '
              'fix something that was never wrong',
        );
        expect(ctrl.coachHint?.tone, CoachTone.warning);
        // The pass itself completed (so the step event fires), but no foot was
        // completed and no size left the controller: the reading was refused.
        expect(caughtEvents.whereType<StepCompletedEvent>(), hasLength(1));
        expect(caughtEvents.whereType<FootCompletedEvent>(), isEmpty,
            reason: 'a refused reading must never complete the foot');
        expect(caughtEvents.whereType<ScanCompleteEvent>(), isEmpty);
        expect(ctrl.currentStep, CaptureStep.leftTop);
        ctrl.dispose();
      });
    });

    test('E13: a failed pass contributes nothing to the retry', () {
      fakeAsync((async) {
        harness(async);

        // Pass A (LEFT TOP): succeeds with good samples.
        for (int i = 0; i < 25; i++) {
          stageGoodTick();
        }
        stageGoodTick();
        runPass(async);
        expect(ctrl.currentStep, CaptureStep.rightTop);
        expect(caughtEvents.whereType<FootCompletedEvent>().single.footSide,
            'left');

        // Pass B (RIGHT TOP): fails completely — no frames at all.
        ar.nextFrame = null;
        detector.script.clear();
        ar.sampleHitScript.clear();
        relockArea(async);
        ctrl.startCapture();
        async.elapse(maxScanDuration);
        async.elapse(const Duration(milliseconds: 900));
        expect(ctrl.phase, ScanPhase.ready);
        expect(caughtEvents.whereType<FootCompletedEvent>(), hasLength(1),
            reason: 'failed right pass must not finalize the right foot');

        // Pass C: retry the right top step with good data — succeeds cleanly.
        for (int i = 0; i < 25; i++) {
          stageGoodTick();
        }
        stageGoodTick();
        relockArea(async);
        runPass(async);

        // Exactly one completion per foot, from the clean retry only.
        final done = caughtEvents.whereType<FootCompletedEvent>().toList();
        expect(done, hasLength(2));
        expect(done.last.footSide, 'right');
        expect(done.last.lengthMm, greaterThan(0));
        expect(ctrl.phase, ScanPhase.complete);
        ctrl.dispose();
      });
    });

    test('floor search exposes probe hits and steadiness for the guide', () {
      fakeAsync((async) {
        harness(async);
        // The harness locks the floor with all five probes hitting and steady.
        expect(ctrl.floorProbeHits, 5);
        expect(ctrl.floorSteady, isTrue);
        ctrl.dispose();
      });
    });

    test('§8 stall coaching fires mid-pass without destroying the pass', () {
      fakeAsync((async) {
        harness(async);

        ar.nextFrame = null;
        ctrl.startCapture();
        expect(ctrl.coachHint?.reason, CoachReason.holdStill);

        async.elapse(Duration(milliseconds: sampleIntervalMs * 11));
        expect(ctrl.coachHint?.reason, CoachReason.havingTrouble);
        expect(ctrl.coachHint?.tone, CoachTone.warning);
        expect(ctrl.phase, ScanPhase.capturing,
            reason: 'stall coaching is non-destructive');

        async.elapse(maxScanDuration);
        expect(ctrl.phase, ScanPhase.ready);
        ctrl.dispose();
      });
    });

    test('cancelCapture discards the running pass (E13)', () {
      fakeAsync((async) {
        harness(async);

        for (int i = 0; i < 25; i++) {
          stageGoodTick();
        }
        stageGoodTick();
        ctrl.startCapture();
        async.elapse(const Duration(seconds: 1)); // mid-pass

        ctrl.cancelCapture();
        expect(ctrl.phase, isNot(ScanPhase.capturing));

        // Samples collected pre-cancel must never reach results.
        for (int i = 0; i < 25; i++) {
          stageGoodTick();
        }
        stageGoodTick();
        relockArea(async);
        runPass(async); // LEFT TOP again — the clean retry completes the foot

        final done = caughtEvents.whereType<FootCompletedEvent>();
        expect(done, hasLength(1));
        ctrl.dispose();
      });
    });
  });
}
