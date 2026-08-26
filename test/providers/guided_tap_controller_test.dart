import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

import 'package:app/providers/guided_tap_controller.dart';
import 'package:app/services/ar_core_channel.dart';
import 'package:app/utils/foot_detector.dart';

// ═══════════════════════════════════════════════════════════════
// FAKES — the controller is pure Dart now, so no widget tree is needed.
// ═══════════════════════════════════════════════════════════════

/// Scriptable [ArCoreChannel] fake for the manual flow's per-tap raycasts.
class FakeArCore implements ArCoreChannel {
  final Completer<ArSessionStartResult> startCompleter = Completer();
  final StreamController<ArSessionEvent> eventSink =
      StreamController<ArSessionEvent>.broadcast();

  ArCameraFrame? nextFrame;

  /// Scripted single hitTest results (burst sampling / drag / live-center).
  /// Repeats the last entry when dry; null entries are raycast misses.
  List<ArWorldPoint?> hitScript = [];

  /// Staged hits for hitTestBatch (suggestion acceptance).
  List<ArWorldPoint?> batchHits = const [];

  /// When non-null, each hitTest awaits this before resolving — used to hold
  /// a tap's burst mid-flight and prove overlapping taps are dropped.
  Completer<void>? gate;

  bool sessionActive = false;
  ArTrackingState trackingReply = ArTrackingState.tracking;

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
  Future<ArWorldPoint?> hitTest({required double x, required double y}) async {
    if (gate != null && !gate!.isCompleted) await gate!.future;
    if (hitScript.isEmpty) return null;
    return hitScript.last;
  }

  @override
  Future<List<ArWorldPoint?>> hitTestBatch({
    required List<Offset> screenPoints,
  }) async {
    if (batchHits.length == screenPoints.length) return batchHits;
    return List.filled(screenPoints.length, null);
  }

  @override
  Future<ArCameraFrame?> acquireCameraFrame() async => nextFrame;

  @override
  Future<ArTrackingState> getTrackingState() async => trackingReply;

  @override
  Future<ArPlane?> getFloorPlane() async => null;

  @override
  Future<double?> getFloorDistance() async => null;

  @override
  void dispose() {}
}

/// Scriptable detector fake for the smart-assist proposal sampler. The
/// manual flow itself never runs detection — only §6 suggestions do.
class FakeAssistDetector implements FootDetector {
  FootDetectionResult next = const FootDetectionResult.negative();

  @override
  Future<FootDetectionResult> detect({
    required Uint8List nv21Bytes,
    required int width,
    required int height,
    required int rotationDegrees,
    String? preferSide,
    Rect? guideRect,
  }) async =>
      next;

  @override
  void dispose() {}
}

ArWorldPoint wp(double x, double y) =>
    ArWorldPoint(x: x, y: y, z: 0, distanceFromCamera: 0.3);

/// Width pair 90mm apart (9cm — inside hard bounds), used for front passes.
ArWorldPoint widthInner() => wp(0.30, 0);
ArWorldPoint widthOuter() => wp(0.21, 0);

/// Heel↔toe 240mm apart (24cm — inside hard bounds), used for side passes.
ArWorldPoint heel() => wp(0.40, 0);
ArWorldPoint toeFar() => wp(0.16, 0);

ArCameraFrame frame() => ArCameraFrame(
      nv21Bytes: Uint8List.fromList(List.filled(64, 1)),
      width: 480,
      height: 640,
      rotationDegrees: 90,
    );

const testViewSize = Size(400, 800);

/// One tap's burst = 5 hitTests × 40ms gaps ≈ 160ms; elapsing 300ms pumps
/// every internal await (microtasks ride along between timers).
const tapWindowMs = 300;

void main() {
  late FakeArCore ar;
  late FakeAssistDetector assist;
  late GuidedTapController ctrl;
  final List<GuidedTapEvent> caughtEvents = [];

  /// Build controller + complete a successful session start + drive it to
  /// 'ready' via a tracking event. Frame geometry staged so coordinate
  /// mapping has real dimensions (480×640 upright).
  void harness(FakeAsync async) {
    ar = FakeArCore();
    assist = FakeAssistDetector();
    ctrl = GuidedTapController(
      arCore: ar,
      detectorFactory: () => assist,
    );
    caughtEvents.clear();
    ctrl.events.listen(caughtEvents.add);

    ar.nextFrame = frame();
    ctrl.initialize();
    ar.startCompleter.complete(const ArSessionStartResult(started: true));
    async.flushMicrotasks();

    ar.eventSink.add(
        const ArSessionEvent(type: 'tracking', data: {'state': 'tracking'}));
    async.flushMicrotasks();

    assert(ctrl.trackingState == ArTrackingState.tracking);
    assert(ctrl.guidanceState == 'ready');
    assert(ctrl.frameWidth > 0, 'frame geometry must be cached after init');
  }

  /// Place one full pair via two taps with the given scripted world points.
  void placePair(FakeAsync async, ArWorldPoint a, ArWorldPoint b) {
    ar.hitScript = [a];
    ctrl.handleTapAt(const Offset(100, 400), testViewSize);
    async.elapse(const Duration(milliseconds: tapWindowMs));
    ar.hitScript = [b];
    ctrl.handleTapAt(const Offset(200, 400), testViewSize);
    async.elapse(const Duration(milliseconds: tapWindowMs));
  }

  group('GuidedTapController — session init', () {
    test('failed start surfaces reason-coded error state', () {
      fakeAsync((async) {
        ar = FakeArCore();
        assist = FakeAssistDetector();
        ctrl = GuidedTapController(arCore: ar, detectorFactory: () => assist);
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
        assist = FakeAssistDetector();
        ctrl = GuidedTapController(arCore: ar, detectorFactory: () => assist);
        ctrl.reportCameraPermissionDenied();
        expect(ctrl.guidanceState, 'error');
        expect(ctrl.guidanceText,
            'Camera permission is required for AR measuring');
      });
    });
  });

  group('GuidedTapController — full successful flow', () {
    test('advances front→side→right-foot and emits completed payload '
        '(both angles, both feet)', () {
      fakeAsync((async) {
        harness(async);

        // ── Left FRONT: width pair 90mm apart ──
        placePair(async, widthInner(), widthOuter());
        expect(ctrl.pairPhase, 2);
        expect(ctrl.currentFoot, 0);
        expect(ctrl.captureStep, 'front');
        expect(ctrl.liveDistanceMm, closeTo(90.0, 0.5));

        ctrl.confirmPair();
        expect(ctrl.captureStep, 'side');
        expect(ctrl.pairPhase, 0);
        expect(ctrl.guidanceText, 'Width done! Now the SIDE of your left foot');

        // ── Left SIDE: heel↔toe 240mm apart ──
        placePair(async, heel(), toeFar());
        expect(ctrl.liveDistanceMm, closeTo(240.0, 0.5));
        ctrl.confirmPair();
        expect(ctrl.currentFoot, 1);
        expect(ctrl.captureStep, 'front');
        expect(ctrl.guidanceText, 'Left foot done! Now your right foot');

        // ── Right FRONT ──
        placePair(async, widthInner(), widthOuter());
        ctrl.confirmPair();
        expect(ctrl.captureStep, 'side');

        // ── Right SIDE → completed event ──
        placePair(async, heel(), toeFar());
        ctrl.confirmPair();
        // Broadcast-stream delivery rides a microtask; pump it before
        // asserting on the captured events.
        async.flushMicrotasks();

        final done =
            caughtEvents.whereType<MeasurementCompletedEvent>().toList();
        expect(done, hasLength(1));
        final p = done.first.payload;
        expect(p.footSide, 'both');
        expect(p.measurementSource, 'ar_guided_tap');
        expect(p.manualMode, isTrue);
        expect(p.paperSize, 'ar');
        expect(p.paperConfidence, 1.0);
        expect(p.lightingQuality, 0.9);
        expect(p.footLengthMm, closeTo(240.0, 0.5));
        expect(p.footWidthMm, closeTo(90.0, 0.5));
        expect(p.footLengthRightMm, closeTo(240.0, 0.5));
        expect(p.sizingFootSide, isIn(['left', 'right']));
        expect(p.euSize, isNotNull);
        expect(p.usSize, isNotNull);
        expect(p.ukSize, isNotNull);
        expect(p.sizeRecommendationReason, isNotNull);
      });
    });
  });

  group('GuidedTapController — tap rejection & guards', () {
    test('tap while not tracking shows coaching feedback and places nothing',
        () {
      fakeAsync((async) {
        harness(async);
        ar.trackingReply = ArTrackingState.limited;

        ar.hitScript = [widthInner()];
        ctrl.handleTapAt(const Offset(100, 400), testViewSize);
        async.flushMicrotasks();

        expect(ctrl.pointA, isNull);
        expect(ctrl.pairPhase, 0);
        expect(ctrl.tapFeedback, 'Move phone slowly — tracking is limited');

        // Feedback auto-clears after 2s.
        async.elapse(const Duration(seconds: 2));
        expect(ctrl.tapFeedback, isNull);
      });
    });

    test('tap whose entire burst misses the floor shows the §3.3 message',
        () {
      fakeAsync((async) {
        harness(async);
        ar.hitScript = [null]; // every ray misses

        ctrl.handleTapAt(const Offset(100, 400), testViewSize);
        async.elapse(const Duration(milliseconds: tapWindowMs));

        expect(ctrl.pointA, isNull);
        expect(ctrl.pairPhase, 0);
        expect(ctrl.tapFeedback,
            "Can't measure there — tap on the tracked floor near your foot");
      });
    });

    test('rapid double-tap during an in-flight placement is dropped '
        '(placement-in-progress guard)', () {
      fakeAsync((async) {
        harness(async);
        ar.gate = Completer<void>(); // first tap's burst hangs
        ar.hitScript = [widthInner()];

        ctrl.handleTapAt(const Offset(100, 400), testViewSize);
        ctrl.handleTapAt(const Offset(300, 400), testViewSize); // must be dropped
        async.flushMicrotasks();

        // Release the gated burst and let its remaining delay timers run.
        ar.gate!.complete();
        async.elapse(const Duration(milliseconds: tapWindowMs));

        expect(ctrl.pointA, isNotNull);
        expect(ctrl.pointB, isNull,
            reason: 'second tap must be ignored while the first is in flight');
        expect(ctrl.pairPhase, 1);
      });
    });

    test('confirming an implausible pair hard-rejects with feedback and '
        'stores nothing (current behavior: no soft-warn dialog exists)', () {
      fakeAsync((async) {
        harness(async);

        // Pair only 20mm apart — far below kHardRejectMinWidthCm (4.5cm).
        placePair(async, wp(0.10, 0), wp(0.12, 0));
        expect(ctrl.pairPhase, 2);

        ctrl.confirmPair();
        expect(ctrl.tapFeedback, 'That looks off — place the two points again');
        expect(ctrl.captureStep, 'front',
            reason: 'flow must NOT advance on a rejected pair');
        expect(ctrl.currentFoot, 0);
        expect(caughtEvents, isEmpty);
      });
    });
  });

  group('GuidedTapController — trash & drag', () {
    test('trash resets to phase 0 and re-derives guidance', () {
      fakeAsync((async) {
        harness(async);
        placePair(async, widthInner(), widthOuter());
        expect(ctrl.pairPhase, 2);

        ctrl.trashPair();
        expect(ctrl.pointA, isNull);
        expect(ctrl.pointB, isNull);
        expect(ctrl.pairPhase, 0);
        expect(ctrl.liveDistanceMm, isNull);
        expect(ctrl.dragIndex, isNull);
        // Guidance re-derived from tracking (ready → first-point prompt).
        expect(ctrl.guidanceState, 'ready');
        expect(ctrl.guidanceText, contains('widest point'));
      });
    });

    test('drag updates the dragged point and the live distance from its '
        'raycast world position', () {
      fakeAsync((async) {
        harness(async);
        placePair(async, widthInner(), widthOuter());
        expect(ctrl.liveDistanceMm, closeTo(90.0, 0.5));

        // Grab point A (placed at Offset(100,400)), then drag it somewhere
        // whose ray lands 120mm away from B's world point.
        ctrl.onPanStart(const Offset(100, 400));
        expect(ctrl.dragIndex, 0);

        ar.hitScript = [wp(0.33, 0)]; // |0.33 - 0.21| = 120mm from B
        ctrl.onPanUpdate(const Offset(150, 420), testViewSize);
        async.flushMicrotasks();

        expect(ctrl.pointA!.screen, const Offset(150, 420));
        expect(ctrl.liveDistanceMm, closeTo(120.0, 0.5));

        ctrl.onPanEnd();
        expect(ctrl.dragIndex, isNull);
      });
    });
  });

  group('GuidedTapController — smart-assist (§6)', () {
    test('disabled sampler never proposes even when ticks fire', () {
      fakeAsync((async) {
        ar = FakeArCore();
        assist = FakeAssistDetector();
        ctrl = GuidedTapController(
          arCore: ar,
          detectorFactory: () => assist,
          smartAssistEnabled: false,
        );
        ar.nextFrame = frame();
        ctrl.updateViewSize(testViewSize);
        ctrl.initialize();
        ar.startCompleter.complete(const ArSessionStartResult(started: true));
        async.flushMicrotasks();
        ar.eventSink.add(
            const ArSessionEvent(type: 'tracking', data: {'state': 'tracking'}));
        async.flushMicrotasks();

        assist.next = _validDetection();
        async.elapse(const Duration(milliseconds: 1300)); // 2 sampler ticks

        expect(ctrl.suggestion, isNull);
      });
    });

    test('enabled sampler proposes an in-bounds pair; accepting raycasts and '
        'locks both points in one step', () {
      fakeAsync((async) {
        harness(async);
        ctrl.updateViewSize(testViewSize);

        assist.next = _validDetection();
        async.elapse(const Duration(milliseconds: 700)); // one sampler tick

        final sugg = ctrl.suggestion;
        expect(sugg, isNotNull,
            reason: 'detection maps inside the view → suggestion appears');
        expect(sugg!.confidence, greaterThanOrEqualTo(0.7));

        // Acceptance raycasts BOTH proposed points onto the floor 90mm apart
        // — clears the width plausibility band.
        ar.batchHits = [widthInner(), widthOuter()];
        ctrl.acceptSuggestion();
        async.flushMicrotasks();

        expect(ctrl.pairPhase, 2);
        expect(ctrl.pointA, isNotNull);
        expect(ctrl.pointB, isNotNull);
        expect(ctrl.suggestion, isNull);
        expect(ctrl.liveDistanceMm, closeTo(90.0, 0.5));
        expect(ctrl.guidanceText, 'Drag the points to adjust, then confirm');
      });
    });

    test('accepting a suggestion whose rays miss shows feedback, clears the '
        'proposal, and stays in phase 0 (per-point validation)', () {
      fakeAsync((async) {
        harness(async);
        ctrl.updateViewSize(testViewSize);

        assist.next = _validDetection();
        async.elapse(const Duration(milliseconds: 700));
        expect(ctrl.suggestion, isNotNull);

        ar.batchHits = const []; // batch dispatch falls back to all-null
        ctrl.acceptSuggestion();
        async.flushMicrotasks();

        expect(ctrl.pairPhase, 0);
        expect(ctrl.pointA, isNull);
        expect(ctrl.suggestion, isNull);
        expect(ctrl.tapFeedback,
            "Suggested points didn't hit the floor — place them manually");
      });
    });
  });
}

FootDetectionResult _validDetection({double qualityScore = 0.9}) {
  return FootDetectionResult(
    footDetected: true,
    confidence: 0.9,
    footSide: 'left',
    qualityScore: qualityScore,
    heelPoint: const FootPoint(x: 0.40, y: 0.45, likelihood: 0.95),
    toePoint: const FootPoint(x: 0.60, y: 0.45, likelihood: 0.95),
    widthPoints: const [
      FootPoint(x: 0.48, y: 0.35, likelihood: 0.9),
      FootPoint(x: 0.52, y: 0.35, likelihood: 0.9),
    ],
  );
}
