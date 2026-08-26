import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

import 'package:app/providers/v2/scan_phase.dart';
import 'package:app/providers/v2/scan_session_controller.dart';
import 'package:app/services/ar_core_channel.dart';
import 'package:app/utils/ar_foot_measurement_pipeline.dart'
    show sampleIntervalMs;
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

  @override
  Future<void> stopSession() async {
    sessionActive = false;
  }

  @override
  Future<List<ArWorldPoint?>> hitTestBatch({
    required List<Offset> screenPoints,
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
  Future<ArWorldPoint?> hitTest({required double x, required double y}) async =>
      null;

  @override
  Future<ArTrackingState> getTrackingState() async => ArTrackingState.paused;

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

ArCameraFrame frame() => ArCameraFrame(
      nv21Bytes: Uint8List.fromList(List.filled(64, 1)),
      width: 640,
      height: 480,
      rotationDegrees: 90,
    );

void main() {
  late FakeArCore ar;
  late FakeDetector detector;
  late ScanSessionController ctrl;
  final List<ScanSessionEvent> caughtEvents = [];

  /// Build controller + complete session start + drive to 'ready'.
  void harness(FakeAsync async, {String condition = 'bare'}) {
    ar = FakeArCore();
    detector = FakeDetector();
    ctrl = ScanSessionController(
      arCore: ar,
      detectorFactory: () => detector,
      footCondition: condition,
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

  /// Run one capture pass to completion (v2: 5s) plus the 900ms success beat.
  /// Caller must have staged ticks already.
  void runPass(FakeAsync async) {
    ctrl.startCapture();
    expect(ctrl.phase, ScanPhase.capturing);
    async.elapse(ScanSessionController.kV2ScanDuration);
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
    test('advances L·T → L·S → R·T → R·S and emits compensated payload', () {
      fakeAsync((async) {
        harness(async);

        // Plenty of good ticks for all four passes (script repeats last).
        for (int i = 0; i < 40; i++) {
          stageGoodTick(withWidth: true, side: i % 2 == 0 ? 'left' : 'right');
        }
        stageGoodTick(); // sticky tail

        // Pass 1: LEFT TOP.
        runPass(async);
        expect(ctrl.currentStep, CaptureStep.leftSide);
        expect(ctrl.phase, ScanPhase.ready);
        expect(caughtEvents.whereType<StepCompletedEvent>().single.step,
            CaptureStep.leftTop);

        // Pass 2: LEFT SIDE → left foot frozen immediately.
        relockArea(async);
        runPass(async);
        expect(ctrl.currentStep, CaptureStep.rightTop);
        final footDone = caughtEvents.whereType<FootCompletedEvent>().single;
        expect(footDone.footSide, 'left');
        expect(footDone.lengthMm, greaterThan(0));

        // Pass 3: RIGHT TOP.
        relockArea(async);
        runPass(async);
        expect(ctrl.currentStep, CaptureStep.rightSide);

        // Pass 4: RIGHT SIDE → complete.
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

        relockArea(async);
        runPass(async); // LEFT SIDE — all estimated rows
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
        relockArea(async);
        runPass(async); // RIGHT SIDE

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
        runPass(async); // LEFT SIDE
        relockArea(async);
        runPass(async); // RIGHT TOP
        relockArea(async);
        runPass(async); // RIGHT SIDE

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

    test('v2 capture window is 5 seconds (longer than v1)', () {
      fakeAsync((async) {
        harness(async);

        for (int i = 0; i < 40; i++) {
          stageGoodTick(withWidth: false);
        }
        stageGoodTick();

        ctrl.startCapture();
        async.elapse(const Duration(seconds: 4));
        expect(ctrl.phase, ScanPhase.capturing,
            reason: 'v2 deliberately samples one second longer than v1');
        async.elapse(const Duration(seconds: 1));
        expect(ctrl.phase, ScanPhase.stepComplete);
        ctrl.dispose();
      });
    });
  });

  group('ScanSessionController — visible-band geometry (off-screen box fix)', () {
    test('side guide rect clamps into the visible crop band', () {
      fakeAsync((async) {
        harness(async);

        // Front rect (x 0.30–0.70) fits the band on any phone — unclamped.
        final front = ctrl.effectiveGuideRect;
        expect(front, ctrl.currentGuideRect);

        // Drive to the side step.
        for (int i = 0; i < 25; i++) {
          stageGoodTick();
        }
        stageGoodTick();
        runPass(async);
        expect(ctrl.currentStep, CaptureStep.leftSide);

        // Side rect (x 0.15–0.85) must clamp to the visible band
        // [0.5 ∓ (va/fa)/2] ≈ [0.192, 0.808] on the simulated tall phone.
        // Y is untouched — horizontal center-crop only.
        final band = ar._visibleBand;
        final eff = ctrl.effectiveGuideRect;
        expect(eff.left, closeTo(band.left, 0.001));
        expect(eff.right, closeTo(band.right, 0.001));
        expect(eff.top, closeTo(0.35, 0.001));
        expect(eff.bottom, closeTo(0.65, 0.001));
        // Fully inside the band (corners sit exactly ON the edges — the
        // clamp is inclusive; Rect.contains is half-open so don't use it).
        expect(eff.left >= band.left && eff.right <= band.right, isTrue);
        expect(eff.top >= band.top && eff.bottom <= band.bottom, isTrue);
        ctrl.dispose();
      });
    });

    test('area re-locks for the side step (regression: off-screen probes)',
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
        expect(ctrl.currentStep, CaptureStep.leftSide);
        expect(ctrl.areaTracked, isFalse);

        // Before the fix, the side rect's corner probes sat at x 0.15/0.85 —
        // outside the visible band — so every probe but the center missed the
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

  group('ScanSessionController — failure paths', () {
    test('zero-detection pass fails explicitly, discards buffer, stays ready',
        () {
      fakeAsync((async) {
        harness(async);

        ar.nextFrame = null; // nothing detectable all pass
        ctrl.startCapture();
        async.elapse(ScanSessionController.kV2ScanDuration);
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

    test('E13: a failed pass contributes nothing to the retry', () {
      fakeAsync((async) {
        harness(async);

        // Pass A (LEFT TOP): succeeds with good samples.
        for (int i = 0; i < 25; i++) {
          stageGoodTick();
        }
        stageGoodTick();
        runPass(async);
        expect(ctrl.currentStep, CaptureStep.leftSide);

        // Pass B (LEFT SIDE): fails completely — no frames at all.
        ar.nextFrame = null;
        detector.script.clear();
        ar.sampleHitScript.clear();
        relockArea(async);
        ctrl.startCapture();
        async.elapse(ScanSessionController.kV2ScanDuration);
        async.elapse(const Duration(milliseconds: 900));
        expect(ctrl.phase, ScanPhase.ready);
        expect(caughtEvents.whereType<FootCompletedEvent>(), isEmpty,
            reason: 'failed side pass must not finalize the foot');

        // Pass C: retry the same step with good data — succeeds cleanly.
        for (int i = 0; i < 25; i++) {
          stageGoodTick();
        }
        stageGoodTick();
        relockArea(async);
        runPass(async);

        // Exactly ONE completion event, from the clean retry only.
        final done = caughtEvents.whereType<FootCompletedEvent>().toList();
        expect(done, hasLength(1));
        expect(done.single.footSide, 'left');
        expect(done.single.lengthMm, greaterThan(0));
        expect(ctrl.currentStep, CaptureStep.rightTop);
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

        async.elapse(ScanSessionController.kV2ScanDuration);
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
        runPass(async); // LEFT TOP again
        relockArea(async);
        for (int i = 0; i < 25; i++) {
          stageGoodTick();
        }
        stageGoodTick();
        runPass(async); // LEFT SIDE

        final done = caughtEvents.whereType<FootCompletedEvent>();
        expect(done, hasLength(1));
        ctrl.dispose();
      });
    });
  });
}
