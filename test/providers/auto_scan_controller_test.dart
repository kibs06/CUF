import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

import 'package:app/providers/auto_scan_controller.dart';
import 'package:app/services/ar_core_channel.dart';
import 'package:app/utils/ar_foot_measurement_pipeline.dart' show scanDuration, sampleIntervalMs;
import 'package:app/utils/foot_detector.dart';

// ═══════════════════════════════════════════════════════════════
// FAKES — the controller is pure Dart now, so no widget tree is needed.
// ═══════════════════════════════════════════════════════════════

/// Scriptable [ArCoreChannel] fake: startSession resolves via a Completer the
/// test controls; hitTestBatch returns whatever point list was staged.
class FakeArCore implements ArCoreChannel {
  final Completer<ArSessionStartResult> startCompleter = Completer();
  final StreamController<ArSessionEvent> eventSink =
      StreamController<ArSessionEvent>.broadcast();

  ArCameraFrame? nextFrame;

  /// Staged hits for sampling batches (heel/toe/width — 4 points).
  List<ArWorldPoint?> nextHits = const [];

  /// Staged hits for the controller's 5-point guide-box area probes.
  /// Kept separate from [nextHits] so re-locking the area never disturbs
  /// the sample geometry mid-pass.
  List<ArWorldPoint?> probeHits = const [];
  bool sessionActive = false;

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
    if (screenPoints.length == 5 && probeHits.length == 5) return probeHits;
    if (nextHits.length == screenPoints.length) return nextHits;
    return List.filled(screenPoints.length, null);
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

/// Scriptable [FootDetector] fake: pops one staged result per detect() call,
/// repeating the last one when the queue runs dry.
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

ArWorldPoint wp(double x, double y) => ArWorldPoint(x: x, y: y, z: 0, distanceFromCamera: 0.3);

FootDetectionResult validDetection({
  double qualityScore = 0.9,
  double confidence = 0.9,
}) {
  return FootDetectionResult(
    footDetected: true,
    confidence: confidence,
    footSide: 'left',
    qualityScore: qualityScore,
    heelPoint: const FootPoint(x: 0.40, y: 0.45, likelihood: 0.95),
    toePoint: const FootPoint(x: 0.60, y: 0.45, likelihood: 0.95),
    // Width pair present so raycast math uses real width points (not 0.38×).
    widthPoints: const [
      FootPoint(x: 0.48, y: 0.35, likelihood: 0.9),
      FootPoint(x: 0.52, y: 0.35, likelihood: 0.9),
    ],
  );
}

ArCameraFrame frame() => ArCameraFrame(
      nv21Bytes: Uint8List.fromList(List.filled(64, 1)),
      width: 640,
      height: 480,
      rotationDegrees: 90,
    );

void main() {
  // ── shared harness ──
  late FakeArCore ar;
  late FakeDetector detector;
  late AutoScanController ctrl;
  final List<AutoScanEvent> caughtEvents = [];

  /// Build controller + complete a successful session start + drive it to
  /// the 'ready' state (tracking event, plane event, area probe all-hit).
  void harness(FakeAsync async, {String condition = 'bare'}) {
    ar = FakeArCore();
    detector = FakeDetector();
    ctrl = AutoScanController(
      arCore: ar,
      detectorFactory: () => detector,
      footCondition: condition,
    );
    caughtEvents.clear();
    ctrl.events.listen(caughtEvents.add);

    ar.nextHits = List.filled(5, wp(0.5, 0)); // area probes all hit
    ar.probeHits = List.filled(5, wp(0.5, 0));
    ctrl.initialize();
    ar.startCompleter.complete(const ArSessionStartResult(started: true));
    async.flushMicrotasks();

    // tracking + plane events → refreshAreaTracking (async hitTestBatch)
    ar.eventSink.add(const ArSessionEvent(type: 'tracking', data: {'state': 'tracking'}));
    ar.eventSink.add(const ArSessionEvent(type: 'plane', data: {}));
    async.elapse(const Duration(milliseconds: 50));

    assert(ctrl.trackingState == ArTrackingState.tracking);
    assert(ctrl.areaTracked);
    assert(ctrl.guidanceState == 'ready');
  }

  /// Stage one full sample tick's worth of happy-path data.
  void stageGoodTick() {
    ar.nextFrame = frame();
    // Heel↔toe 240mm apart, width pair 90mm apart — plausible foot dims
    // that clear the sanity bounds (≤500/≤200mm).
    ar.nextHits = [wp(0.30, 0), wp(0.06, 0), wp(0.13, 0), wp(0.22, 0)];
    detector.script.add(validDetection());
  }

  /// After every pass `_endScan` clears [_areaTracked] §2 (the new guide-box
  /// position must be re-verified). Production relies on the 500 ms area
  /// poll; tests re-lock deterministically before starting the next pass.
  void relockArea(FakeAsync async) {
    ar.probeHits = List.filled(5, wp(0.5, 0));
    ctrl.refreshAreaTracking();
    async.flushMicrotasks();
    assert(ctrl.areaTracked);
  }

  group('AutoScanController — session init', () {
    test('failed start surfaces reason-coded error state', () {
      fakeAsync((async) {
        ar = FakeArCore();
        detector = FakeDetector();
        ctrl = AutoScanController(arCore: ar, detectorFactory: () => detector);
        ctrl.initialize();
        ar.startCompleter.complete(const ArSessionStartResult(
          started: false, reason: 'needs_install'));
        async.flushMicrotasks();

        expect(ctrl.guidanceState, 'error');
        expect(ctrl.guidanceText, contains('installing ARCore'));
      });
    });

    test('camera permission denied reports the exact legacy error text', () {
      fakeAsync((async) {
        ar = FakeArCore();
        detector = FakeDetector();
        ctrl = AutoScanController(arCore: ar, detectorFactory: () => detector);
        ctrl.reportCameraPermissionDenied();
        expect(ctrl.guidanceState, 'error');
        expect(ctrl.guidanceText,
            'Camera permission is required for AR scanning');
      });
    });
  });

  group('AutoScanController — full successful scan (both angles, both feet)', () {
    test('advances front→side→right-foot and emits completed payload', () {
      fakeAsync((async) {
        harness(async);

        // Every tick of every pass is a confirmed, sane sample:
        // ~20 ticks/pass × 4 passes. Script repeats last entry when dry.
        for (int i = 0; i < 90; i++) {
          stageGoodTick();
        }

        ar.nextFrame = frame();
        ar.nextHits = [wp(0.30, 0), wp(0.06, 0), wp(0.13, 0), wp(0.22, 0)];
        detector.script.add(validDetection()); // sticky from here on

        // Pass 1: left FRONT (4s). First 2 ticks confirm the temporal gate
        // (confirmAfter=3), sampling starts on tick 3.
        ctrl.startScan();
        expect(ctrl.scanActive, isTrue);
        expect(ctrl.captureStep, 'front');
        expect(ctrl.currentFoot, 0);
        async.elapse(scanDuration);

        expect(ctrl.scanActive, isFalse);
        expect(ctrl.currentSampleCount, greaterThan(0));
        expect(ctrl.leftSampleCount, greaterThan(0));
        // §2.5 advance to side, waiting for user to start next step
        expect(ctrl.captureStep, 'side');
        expect(ctrl.stepPending, isTrue);
        expect(ctrl.guidanceState, 'ready');

        // Pass 2: left SIDE → finalize left foot → auto-advance to right.
        relockArea(async);
        ctrl.startScan();
        async.elapse(scanDuration);

        expect(ctrl.currentFoot, 1);
        expect(ctrl.captureStep, 'front');
        expect(ctrl.stepPending, isTrue);
        final leftDone = caughtEvents.whereType<LeftFootDoneEvent>().toList();
        expect(leftDone, hasLength(1));
        expect(leftDone.first.lengthMm, greaterThan(0));

        // Pass 3: right FRONT.
        relockArea(async);
        ctrl.startScan();
        async.elapse(scanDuration);
        expect(ctrl.captureStep, 'side');
        expect(caughtEvents.whereType<LeftFootDoneEvent>(), hasLength(1));

        // Pass 4: right SIDE → both done → ScanCompletedEvent.
        relockArea(async);
        ctrl.startScan();
        async.elapse(scanDuration);

        final completed = caughtEvents.whereType<ScanCompletedEvent>().toList();
        expect(completed, hasLength(1));
        final p = completed.first.payload;
        expect(p.footSide, 'both');
        expect(p.measurementSource, 'ar_auto_scan');
        expect(p.paperSize, 'ar');
        expect(p.footCondition, 'bare');
        expect(p.footLengthMm, greaterThan(0));
        expect(p.footLengthRightMm, greaterThan(0));
        expect(p.sizingFootSide, isIn(['left', 'right']));
        expect(p.euSize, isNotNull);
        expect(p.usSize, isNotNull);
        expect(p.ukSize, isNotNull);
      });
    });
  });

  group('AutoScanController — failure paths', () {
    test('zero detections in a pass fails explicitly with error UI state',
        () {
      fakeAsync((async) {
        harness(async);

        // No-frame ticks: acquireCameraFrame returns null every time.
        ar.nextFrame = null;
        ctrl.startScan();
        async.elapse(scanDuration);

        expect(ctrl.scanActive, isFalse);
        expect(ctrl.noFootFailure, isTrue);
        expect(ctrl.guidanceState, 'error');
        expect(ctrl.validDetectionsThisPass, 0);
        expect(caughtEvents, isEmpty); // no completion / snackbar events
        expect(ctrl.leftSampleCount, 0);
      });
    });

    test('§8 stall prompt fires mid-pass after 10 attempts with zero '
        'detections, while staying in scanning state (E2 fix)', () {
      fakeAsync((async) {
        harness(async);

        ar.nextFrame = null; // nothing ever detectable
        ctrl.startScan();
        expect(ctrl.stallPromptShown, isFalse);

        // 10 attempts × 200ms ≈ 2s — inside the 4s pass window.
        async.elapse(Duration(milliseconds: sampleIntervalMs * 11));
        expect(ctrl.stallPromptShown, isTrue,
            reason: 'stall coaching must be reachable before the pass ends');
        expect(ctrl.guidanceState, 'scanning',
            reason: 'prompt is non-destructive: pass keeps running');
        expect(ctrl.guidanceText, contains('Guided Tap'));

        // Pass still ends normally at 4s with the explicit failure.
        async.elapse(scanDuration);
        expect(ctrl.noFootFailure, isTrue);
        expect(ctrl.guidanceState, 'error');
      });
    });

    test('side-combine failure emits SideCombineFailedEvent and stays on '
        'the screen ready to retry', () {
      fakeAsync((async) {
        harness(async);

        // Front pass: detections CONFIRM but every ray misses the floor →
        // the pass "succeeds" into the side advance with ZERO samples
        // recorded (confirmations ≠ samples — E4 interplay).
        for (int i = 0; i < 25; i++) {
          ar.nextFrame = frame();
          ar.nextHits = const [];
          detector.script.add(validDetection());
        }
        ar.nextFrame = frame();
        ar.nextHits = const [];
        detector.script.add(validDetection());
        ctrl.startScan();
        async.elapse(scanDuration);
        expect(ctrl.captureStep, 'side');
        expect(ctrl.leftSampleCount, 0);
        expect(ctrl.noFootFailure, isFalse);

        // Side pass: confirmations again with all rays missing →
        // validDetectionsThisPass > 0 skips the zero-detection branch,
        // combineGuidedSamples([]) returns null → SideCombineFailedEvent.
        relockArea(async);
        for (int i = 0; i < 25; i++) {
          ar.nextFrame = frame();
          ar.nextHits = const [];
          detector.script.add(validDetection());
        }
        ar.nextFrame = frame();
        ar.nextHits = const [];
        detector.script.add(validDetection());
        ctrl.startScan();
        async.elapse(scanDuration);

        expect(caughtEvents.whereType<SideCombineFailedEvent>(), hasLength(1));
        expect(ctrl.guidanceState, 'ready');
        expect(ctrl.guidanceText, 'Measurement failed — please try again');

        // Retry restarts the SAME ('side') capture step once tracking+area
        // allow it.
        relockArea(async);
        ctrl.retryScan();
        expect(ctrl.scanActive, isTrue);
        expect(ctrl.captureStep, 'side',
            reason: 'retry re-runs the failed capture step');
      });
    });
  });

  group('AutoScanController — retry semantics (E13 documented as-is)', () {
    test('KNOWN ISSUE E13: samples from earlier passes are NOT cleared by '
        'retry — they bleed into subsequent passes/combination (behavior '
        'preserved intentionally; fix deferred to a later phase)', () {
      fakeAsync((async) {
        harness(async);

        // Pass 1 (left front): record some samples successfully.
        for (int i = 0; i < 25; i++) {
          stageGoodTick();
        }
        ar.nextFrame = frame();
        ar.nextHits = [wp(0.30, 0), wp(0.06, 0), wp(0.13, 0), wp(0.22, 0)];
        detector.script.add(validDetection());
        ctrl.startScan();
        async.elapse(scanDuration);
        final samplesAfterPass1 = ctrl.leftSampleCount;
        expect(samplesAfterPass1, greaterThan(0));
        expect(ctrl.captureStep, 'side');

        // Pass 2 (left side): total detection failure → explicit error.
        relockArea(async);
        ar.nextFrame = null;
        ctrl.startScan();
        async.elapse(scanDuration);
        expect(ctrl.noFootFailure, isTrue);

        // Retry: current code restarts the side pass WITHOUT clearing
        // anything — the front-pass samples persist (this part is intended
        // design: per-foot combination needs both angles), and any new side
        // samples APPEND to the same list across retries.
        relockArea(async);
        ctrl.retryScan();
        for (int i = 0; i < 25; i++) {
          stageGoodTick();
        }
        ar.nextFrame = frame();
        ar.nextHits = [wp(0.30, 0), wp(0.06, 0), wp(0.13, 0), wp(0.22, 0)];
        detector.script.add(validDetection());
        async.elapse(scanDuration);

        expect(ctrl.leftSampleCount, greaterThan(samplesAfterPass1),
            reason: 'current behavior: retried-pass samples append to the '
                'same per-foot list rather than replacing the failed pass\'s '
                'contribution — pinned here so a later-phase E13 fix must '
                'change this deliberately, not silently');
      });
    });
  });

  group('AutoScanController — sanity & gating details preserved', () {
    test('confirmed detections whose rays miss the floor record NO sample '
        'but DO count as valid detections (E4 interplay)', () {
      fakeAsync((async) {
        harness(async);

        // Confirmed detections, but hitTestBatch misses everything.
        for (int i = 0; i < 25; i++) {
          ar.nextFrame = frame();
          ar.nextHits = const [];
          detector.script.add(validDetection());
        }
        ar.nextFrame = frame();
        ar.nextHits = const [];
        detector.script.add(validDetection());

        ctrl.startScan();
        async.elapse(scanDuration);

        // validDetectionsThisPass counts confirmations regardless of raycast…
        expect(ctrl.validDetectionsThisPass, greaterThan(0));
        // …so the pass "succeeds" into the side-advance branch with 0 new
        // samples recorded (sanity/raycast rejects).
        expect(ctrl.captureStep, 'side');
        expect(ctrl.leftSampleCount, 0,
            reason: 'raycast-miss frames must never append samples');
      });
    });

    test('startScan refuses to run without tracking or area lock', () {
      fakeAsync((async) {
        ar = FakeArCore();
        detector = FakeDetector();
        ctrl = AutoScanController(arCore: ar, detectorFactory: () => detector);
        ctrl.initialize();
        ar.startCompleter.complete(const ArSessionStartResult(started: true));
        async.flushMicrotasks();

        // Not tracking yet (no events delivered): silent no-op guard.
        ctrl.startScan();
        expect(ctrl.scanActive, isFalse);
        expect(ctrl.guidanceState, isNot('scanning'));

        // Tracking but area not verified → coaching text, no scan.
        ar.eventSink.add(const ArSessionEvent(type: 'tracking', data: {'state': 'tracking'}));
        async.elapse(const Duration(milliseconds: 10));
        ctrl.startScan();
        expect(ctrl.scanActive, isFalse);
        expect(ctrl.guidanceState, 'searching');
        expect(ctrl.stepPending, isFalse);
      });
    });
  });
}
