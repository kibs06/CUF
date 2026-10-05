import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:app/providers/try_on/try_on_mode.dart';
import 'package:app/providers/try_on/try_on_phase.dart';
import 'package:app/providers/try_on/try_on_session_controller.dart';
import 'package:app/services/ar_core_channel.dart' show ArCameraFrame;
import 'package:app/services/ar_try_on_channel.dart';
import 'package:app/services/shoe_model_service.dart';
import 'package:app/utils/foot_detector.dart';
import 'package:app/utils/shoe_model_resolver.dart';
import 'package:app/utils/try_on_coach.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';

/// V4.1's detection loop, driven without a camera, a device or the ML runtime —
/// frames are faked, the detector is faked, and `fakeAsync` owns the clock.
///
/// What is being pinned, in the order the groups appear:
///
///   1. **The loop is a permission, not a consequence.** With the flag off, or
///      with a session that degraded, no frame is requested and no detector is
///      even constructed (F19's rule extended to V4's half).
///   2. **The cadence is §2.11's 5 Hz** — one observation per 200 ms tick, and
///      the temporal gate's first three ticks are the price of calling anything
///      a foot.
///   3. **Failure is bounded.** Five consecutive failures stop the loop with a
///      logged reason instead of an exception per tick, which is what a build
///      without V4.2's native frame source would otherwise do forever.
///   4. **Lock state belongs to native.** Dart mirrors the event into phases and
///      getters and never re-derives it.
void main() {
  group('the loop is off unless the build asks and the session is real', () {
    test('flag off: no frame requested, no detector constructed', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final detector = _FakeDetector();
        final controller = _controller(
          channel: channel,
          detector: detector,
          footTrack: false,
        );
        _startRealSession(controller, async);
        expect(controller.mode, TryOnMode.real,
            reason: 'V3 still works — the loop is what is off');

        async.elapse(const Duration(seconds: 2));

        expect(channel.frameRequests, 0);
        expect(detector.detectCalls, 0);
        expect(controller.footTrackingActive, isFalse);
        controller.dispose();
      });
    });

    test('a session that degrades to simulated never starts the loop', () {
      fakeAsync((async) {
        final channel = _FakeChannel()..startSucceeds = false;
        final detector = _FakeDetector();
        final controller = _controller(channel: channel, detector: detector);
        _startRealSession(controller, async);
        expect(controller.mode, TryOnMode.simulated);

        async.elapse(const Duration(seconds: 2));

        expect(channel.frameRequests, 0);
        expect(detector.detectCalls, 0);
        controller.dispose();
      });
    });
  });

  group('the cadence', () {
    test('one pose per 200 ms tick after the gate confirms (≥5 Hz)', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final detector = _FakeDetector()..result = _positive();
        final controller = _controller(channel: channel, detector: detector);
        _startRealSession(controller, async);
        expect(controller.footTrackingActive, isTrue);

        // 5 ticks in the first second; the gate needs three consecutive
        // positives before the first pose, so 3 are published.
        async.elapse(const Duration(seconds: 1));
        expect(channel.poses, hasLength(3));

        // Steady state is one per tick: 5 more in the next second.
        async.elapse(const Duration(seconds: 1));
        expect(channel.poses, hasLength(8));
        expect(detector.detectCalls, 10);
        expect(controller.footPoseCount, 8);
        controller.dispose();
      });
    });

    test('an isolated positive frame is not a foot', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final detector = _FakeDetector(); // negative by default
        final controller = _controller(channel: channel, detector: detector);
        _startRealSession(controller, async);

        // One lucky frame, then nothing: the positive streak resets, so no
        // pose is ever published.
        detector.result = _positive();
        async.elapse(const Duration(milliseconds: 200));
        detector.result = const FootDetectionResult.negative();
        async.elapse(const Duration(seconds: 1));

        expect(channel.poses, isEmpty);
        controller.dispose();
      });
    });

    test('a confirmed detection missing heel or toe publishes nothing', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final detector = _FakeDetector()
          ..result = const FootDetectionResult(
            footDetected: true,
            confidence: 0.9,
            qualityScore: 0.9,
            heelPoint: FootPoint(x: 0.1, y: 0.9, likelihood: 0.9),
          );
        final controller = _controller(channel: channel, detector: detector);
        _startRealSession(controller, async);

        async.elapse(const Duration(seconds: 1));

        expect(channel.poses, isEmpty,
            reason: 'a frame that cannot describe an axis is dropped, not '
                'repaired with a guess');
        controller.dispose();
      });
    });

    test('a frame-less tick is skipped, and is not a failure', () {
      fakeAsync((async) {
        final channel = _FakeChannel()
          ..nextFrame = ArCameraFrame(
            nv21Bytes: Uint8List(0),
            width: 0,
            height: 0,
            rotationDegrees: 0,
          );
        final detector = _FakeDetector()..result = _positive();
        final controller = _controller(channel: channel, detector: detector);
        _startRealSession(controller, async);

        async.elapse(const Duration(seconds: 1));

        expect(detector.detectCalls, 0);
        expect(controller.footTrackingActive, isTrue,
            reason: 'no frame yet is normal, and must not count toward the '
                'failure limit');
        expect(channel.poses, isEmpty);
        controller.dispose();
      });
    });
  });

  group("V4.4: the mask rides the accepted pose", () {
    test('every published pose carries its mask, byte-identical', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final result = _positive();
        final detector = _FakeDetector()..result = result;
        final controller = _controller(channel: channel, detector: detector);
        _startRealSession(controller, async);

        async.elapse(const Duration(seconds: 1));

        expect(channel.poses, hasLength(3));
        expect(channel.masks, hasLength(3),
            reason: 'a published pose is the frame the mask belongs to');
        expect(channel.masks.first.bytes, same(result.mask),
            reason: 'the mask crosses exactly as the detector built it — no '
                'copy, no resample, no second convention');
        expect(channel.masks.first.confidence, 0.85,
            reason: "the sample's quality, not the raw segmentation score");
        controller.dispose();
      });
    });

    test('a maskless detection publishes the pose and no mask', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final detector = _FakeDetector()..result = _positive(withMask: false);
        final controller = _controller(channel: channel, detector: detector);
        _startRealSession(controller, async);

        async.elapse(const Duration(seconds: 1));

        expect(channel.poses, hasLength(3),
            reason: 'a null mask is not an error — V4.0/V4.1 detectors have '
                'none, and the pose loop must still work');
        expect(channel.masks, isEmpty);
        controller.dispose();
      });
    });

    test('a mask send that fails costs the occlusion, not the loop', () {
      fakeAsync((async) {
        final channel = _FakeChannel()
          ..maskError = MissingPluginException('no setFootMask handler');
        final detector = _FakeDetector()..result = _positive();
        final controller = _controller(channel: channel, detector: detector);
        _startRealSession(controller, async);

        async.elapse(const Duration(seconds: 1));
        expect(channel.poses, hasLength(3), reason: 'the pose still crossed');
        expect(channel.masks, isEmpty, reason: 'and the mask did not');

        // Well past kFootTrackFailureLimit ticks: an auxiliary failure must not
        // be counted by the loop's failure stop.
        async.elapse(const Duration(seconds: 3));
        expect(controller.footTrackingActive, isTrue,
            reason: 'a mask fault is not a tracking fault');
        expect(channel.poses.length, greaterThan(3),
            reason: 'the loop kept publishing through the mask failures');
        controller.dispose();
      });
    });
  });

  group("V4.5: the coach cue rides the loop's own state", () {
    test('the switch off leaves the card silent, even live', () {
      fakeAsync((async) {
        final controller = _controller(
          channel: _FakeChannel(),
          detector: _FakeDetector()..result = _positive(),
          footTrack: false,
        );
        _startRealSession(controller, async);
        expect(controller.mode, TryOnMode.real);

        async.elapse(const Duration(seconds: 2));

        expect(controller.coachCue.value, isNull,
            reason: 'a build that never asked for foot tracking draws no card '
                '— not even a wrong one');
        controller.dispose();
      });
    });

    test('a live session points at the foot, then talks about the scene', () {
      fakeAsync((async) {
        // Negative detector: nothing is seen, which is every session's first
        // seconds and the only state that reaches pointAtFoot.
        final controller =
            _controller(channel: _FakeChannel(), detector: _FakeDetector());
        _startRealSession(controller, async);

        async.elapse(const Duration(milliseconds: 400));
        expect(controller.coachCue.value, TryOnCoachCue.pointAtFoot);

        async.elapse(const Duration(seconds: 3));
        expect(controller.coachCue.value, TryOnCoachCue.improveScene,
            reason: 'after kFootSceneHintAfter the honest hint is the floor '
                'and the light');
        controller.dispose();
      });
    });

    test('a confirmed foot asks for stillness', () {
      fakeAsync((async) {
        final controller = _controller(
          channel: _FakeChannel(),
          detector: _FakeDetector()..result = _positive(),
        );
        _startRealSession(controller, async);

        // Three consecutive positives confirm the gate (~600 ms).
        async.elapse(const Duration(seconds: 1));

        expect(controller.coachCue.value, TryOnCoachCue.holdStill,
            reason: "the frame's own heel→toe span is sane, so the cue is "
                'stillness rather than framing');
        controller.dispose();
      });
    });

    test('framing outranks stillness in the cue', () {
      fakeAsync((async) {
        final controller = _controller(
          channel: _FakeChannel(),
          detector: _FakeDetector()
            ..result = const FootDetectionResult(
              footDetected: true,
              confidence: 0.85,
              qualityScore: 0.85,
              heelPoint: FootPoint(x: 0.30, y: 0.80, likelihood: 0.9),
              toePoint: FootPoint(x: 0.32, y: 0.55, likelihood: 0.9),
            ),
        );
        _startRealSession(controller, async);

        async.elapse(const Duration(seconds: 1));

        expect(controller.coachCue.value, TryOnCoachCue.moveCloser);
        controller.dispose();
      });
    });

    test('a lock and a loss drive the card', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final controller =
            _controller(channel: channel, detector: _FakeDetector()..result = _positive());
        _startRealSession(controller, async);

        channel.emit(const TryOnFootLockEvent(
          locked: true,
          quality: 0.82,
          side: 'right',
        ));
        async.flushMicrotasks();
        expect(controller.coachCue.value, TryOnCoachCue.locked);

        channel.emit(const TryOnFootLockEvent(locked: false, quality: 0.4));
        async.flushMicrotasks();
        expect(controller.coachCue.value, TryOnCoachCue.regain);
        controller.dispose();
      });
    });

    test('15 s without a lock offers manual placement, and accepting it says tap',
        () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final controller =
            _controller(channel: channel, detector: _FakeDetector());
        _startRealSession(controller, async);

        async.elapse(const Duration(seconds: 16));
        expect(controller.coachCue.value, TryOnCoachCue.manual);

        controller.dismissManualOffer();
        expect(controller.coachCue.value, TryOnCoachCue.placeByTap);

        // A lock clears the acceptance and resets the clock, so a later loss
        // can offer again rather than staying permanently dismissed.
        channel.emit(const TryOnFootLockEvent(locked: true, quality: 0.9));
        async.flushMicrotasks();
        expect(controller.coachCue.value, TryOnCoachCue.locked);

        channel.emit(const TryOnFootLockEvent(locked: false, quality: 0.3));
        async.flushMicrotasks();
        expect(controller.coachCue.value, TryOnCoachCue.regain);

        async.elapse(const Duration(seconds: 16));
        expect(controller.coachCue.value, TryOnCoachCue.manual,
            reason: 'the offer is re-made after a fresh loss');
        controller.dispose();
      });
    });

    test('a loop stopped by failures offers manual placement', () {
      fakeAsync((async) {
        final channel = _FakeChannel()
          ..frameError = MissingPluginException('no native frame source yet');
        final controller =
            _controller(channel: channel, detector: _FakeDetector());
        _startRealSession(controller, async);

        async.elapse(const Duration(seconds: 2));
        expect(controller.footTrackingActive, isFalse);

        expect(controller.coachCue.value, TryOnCoachCue.manual,
            reason: 'a loop that gave up must hand the customer a way to '
                'finish, not silence');
        controller.dispose();
      });
    });
  });

  group("V4.6: the live reading behind the fit verdict", () {
    test('a footMeasure publishes the length and quality', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final controller =
            _controller(channel: channel, detector: _FakeDetector());
        _startRealSession(controller, async);

        channel.emit(const TryOnFootMeasureEvent(lengthMm: 264.0, quality: 0.88));
        async.flushMicrotasks();

        final live = controller.liveFoot.value;
        expect(live.lengthMm, 264.0);
        expect(live.quality, 0.88);
        expect(live.locked, isFalse,
            reason: 'the measurement does not imply a lock — that is the '
                "tracker's edge to send");
        controller.dispose();
      });
    });

    test('the lock half rides its own edge and keeps the reading', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final controller =
            _controller(channel: channel, detector: _FakeDetector()..result = _positive());
        _startRealSession(controller, async);

        channel.emit(const TryOnFootMeasureEvent(lengthMm: 264.0, quality: 0.8));
        channel.emit(const TryOnFootLockEvent(locked: true, quality: 0.8));
        async.flushMicrotasks();
        expect(controller.liveFoot.value.locked, isTrue);
        expect(controller.liveFoot.value.lengthMm, 264.0);

        channel.emit(const TryOnFootLockEvent(locked: false, quality: 0.4));
        async.flushMicrotasks();
        expect(controller.liveFoot.value.locked, isFalse);
        expect(
          controller.liveFoot.value.lengthMm,
          264.0,
          reason: 'an unlock is not a reason to forget the last measurement',
        );
        controller.dispose();
      });
    });

    test('a broken length is refused rather than published', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final controller =
            _controller(channel: channel, detector: _FakeDetector());
        _startRealSession(controller, async);

        channel.emit(const TryOnFootMeasureEvent(lengthMm: 0, quality: 0.9));
        channel.emit(
            const TryOnFootMeasureEvent(lengthMm: double.nan, quality: 0.9));
        channel.emit(const TryOnFootMeasureEvent(lengthMm: -20, quality: 0.9));
        async.flushMicrotasks();

        expect(controller.liveFoot.value.lengthMm, isNull,
            reason: 'the card must never grade a number the tracker would '
                'have rejected');
        controller.dispose();
      });
    });

    test('quality is clamped, and a broken one degrades to zero', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final controller =
            _controller(channel: channel, detector: _FakeDetector());
        _startRealSession(controller, async);

        channel.emit(const TryOnFootMeasureEvent(lengthMm: 260, quality: 1.7));
        async.flushMicrotasks();
        expect(controller.liveFoot.value.quality, 1.0);

        channel.emit(
            const TryOnFootMeasureEvent(lengthMm: 260, quality: double.nan));
        async.flushMicrotasks();
        expect(controller.liveFoot.value.quality, 0.0,
            reason: 'a confidence that is not a number is not a good one');
        controller.dispose();
      });
    });

    test('a stopped loop clears the reading', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final controller =
            _controller(channel: channel, detector: _FakeDetector());
        _startRealSession(controller, async);

        channel.emit(const TryOnFootMeasureEvent(lengthMm: 260, quality: 0.9));
        async.flushMicrotasks();
        expect(controller.liveFoot.value.lengthMm, 260);

        channel.frameError = MissingPluginException('frame source died');
        async.elapse(const Duration(seconds: 2));

        expect(controller.footTrackingActive, isFalse);
        expect(controller.liveFoot.value.lengthMm, isNull,
            reason: 'a verdict must not keep grading a session that ended');
        controller.dispose();
      });
    });

    test('a measurement outside a real session is ignored', () {
      fakeAsync((async) {
        final channel = _FakeChannel()..startSucceeds = false;
        final controller =
            _controller(channel: channel, detector: _FakeDetector());
        _startRealSession(controller, async);
        expect(controller.mode, TryOnMode.simulated);

        channel.emit(const TryOnFootMeasureEvent(lengthMm: 260, quality: 0.9));
        async.flushMicrotasks();

        expect(controller.liveFoot.value.lengthMm, isNull);
        controller.dispose();
      });
    });
  });

  group('failure handling', () {
    test('five consecutive failures stop the loop instead of spamming', () {
      fakeAsync((async) {
        final channel = _FakeChannel()
          ..frameError =
              MissingPluginException('no native frame source yet');
        final detector = _FakeDetector();
        final controller = _controller(channel: channel, detector: detector);
        _startRealSession(controller, async);

        async.elapse(const Duration(seconds: 2));

        expect(channel.frameRequests, kFootTrackFailureLimit);
        expect(controller.footTrackingActive, isFalse);
        expect(detector.detectCalls, 0);
        controller.dispose();
      });
    });

    test('a mid-session renderer error takes the loop with it', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final detector = _FakeDetector()..result = _positive();
        final controller = _controller(channel: channel, detector: detector);
        _startRealSession(controller, async);
        async.elapse(const Duration(milliseconds: 400));
        expect(controller.footTrackingActive, isTrue);

        channel.emit(const TryOnErrorEvent(reason: 'renderer_init_failed'));
        async.flushMicrotasks();

        expect(controller.footTrackingActive, isFalse,
            reason: 'frames bought for a renderer that died are exactly the '
                'cost the flag exists to avoid');
        expect(controller.mode, TryOnMode.simulated);
        controller.dispose();
      });
    });
  });

  group('footLock', () {
    test('locked and lost move the phase and announce once each', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final controller =
            _controller(channel: channel, detector: _FakeDetector());
        _startRealSession(controller, async);
        expect(controller.phase, TryOnPhase.searching);

        final events = <TryOnSessionEvent>[];
        controller.events.listen(events.add);

        channel.emit(const TryOnFootLockEvent(
          locked: true,
          quality: 0.82,
          side: 'right',
        ));
        async.flushMicrotasks();

        expect(controller.phase, TryOnPhase.locked);
        expect(controller.footLocked, isTrue);
        expect(controller.footQuality, 0.82);
        expect(controller.footSide, 'right');

        channel.emit(const TryOnFootLockEvent(locked: false, quality: 0.4));
        async.flushMicrotasks();

        expect(controller.phase, TryOnPhase.lost);
        expect(controller.footLocked, isFalse);
        expect(controller.footSide, isNull);

        async.flushMicrotasks();
        expect(events.whereType<TryOnFootLockChangedEvent>(), hasLength(2));
        controller.dispose();
      });
    });

    test('a lost lock before any lock leaves the phase searching', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final controller =
            _controller(channel: channel, detector: _FakeDetector());
        _startRealSession(controller, async);

        channel.emit(const TryOnFootLockEvent(locked: false, quality: 0.2));
        async.flushMicrotasks();

        expect(controller.phase, TryOnPhase.searching,
            reason: '"lost" is a transition out of a lock, not the state of '
                'never having had one');
        controller.dispose();
      });
    });

    test('a footLock that arrives after a fallback does not move the phase',
        () {
      fakeAsync((async) {
        final channel = _FakeChannel()..startSucceeds = false;
        final controller =
            _controller(channel: channel, detector: _FakeDetector());
        _startRealSession(controller, async);
        expect(controller.mode, TryOnMode.simulated);

        channel.emit(const TryOnFootLockEvent(locked: true, quality: 0.9));
        async.flushMicrotasks();

        expect(controller.phase, TryOnPhase.arFailed);
        expect(controller.footLocked, isFalse);
        controller.dispose();
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // V4.8 — the app's lifecycle is a pause, not a stop
  // ═══════════════════════════════════════════════════════════════════════

  group('V4.8: the app lifecycle pauses the loop without ending the session',
      () {
    test('backgrounding stops the ticks and resuming restarts them', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final detector = _FakeDetector()..result = _positive();
        final controller = _controller(channel: channel, detector: detector);
        _startRealSession(controller, async);
        async.elapse(const Duration(seconds: 1));
        final posesWhileLive = channel.poses.length;
        final framesWhileLive = channel.frameRequests;
        expect(posesWhileLive, greaterThan(0));

        controller.setAppForeground(foreground: false);
        expect(controller.footTrackingActive, isFalse);

        async.elapse(const Duration(seconds: 2));
        expect(channel.frameRequests, framesWhileLive,
            reason: 'a backgrounded app buys no frames and runs no detector');
        expect(channel.poses, hasLength(posesWhileLive));

        controller.setAppForeground(foreground: true);
        expect(controller.footTrackingActive, isTrue);
        async.elapse(const Duration(seconds: 1));
        expect(channel.poses.length, greaterThan(posesWhileLive),
            reason: 'the resume restores the loop, not just the flag');
        controller.dispose();
      });
    });

    test('a pause leaves the live reading alone — the session is not over',
        () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final controller =
            _controller(channel: channel, detector: _FakeDetector());
        _startRealSession(controller, async);
        channel.emit(const TryOnFootMeasureEvent(lengthMm: 262, quality: 0.8));
        async.flushMicrotasks();

        controller.setAppForeground(foreground: false);
        async.elapse(const Duration(milliseconds: 200));

        expect(controller.liveFoot.value.lengthMm, 262,
            reason: 'a backgrounded screen keeps its number; only a *stopped* '
                'loop clears it');

        controller.setAppForeground(foreground: true);
        expect(controller.liveFoot.value.lengthMm, 262);
        controller.dispose();
      });
    });

    test('a pause with no live loop is inert', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final detector = _FakeDetector()..result = _positive();
        final controller = _controller(
          channel: channel,
          detector: detector,
          footTrack: false,
        );
        _startRealSession(controller, async);

        // Both directions are no-ops when the build never asked for tracking,
        // and a resume must not conjure a loop the flag forbids.
        controller.setAppForeground(foreground: false);
        controller.setAppForeground(foreground: true);
        async.elapse(const Duration(seconds: 1));

        expect(channel.frameRequests, 0);
        expect(controller.footTrackingActive, isFalse);
        controller.dispose();
      });
    });

    test('a resume after a failure stop does not restart the loop', () {
      fakeAsync((async) {
        final channel = _FakeChannel()
          ..frameError = MissingPluginException('no frame source');
        final controller =
            _controller(channel: channel, detector: _FakeDetector());
        _startRealSession(controller, async);
        async.elapse(const Duration(seconds: 2));
        expect(controller.footTrackingActive, isFalse,
            reason: 'the failure stop is the loop\'s own decision');

        controller.setAppForeground(foreground: false);
        controller.setAppForeground(foreground: true);
        async.elapse(const Duration(seconds: 1));

        expect(controller.footTrackingActive, isFalse,
            reason: 'a resume is not an amnesty: five failures still mean '
                'stopped');
        controller.dispose();
      });
    });

    test('a resume after the session degraded does not restart the loop', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final controller =
            _controller(channel: channel, detector: _FakeDetector());
        _startRealSession(controller, async);
        controller.setAppForeground(foreground: false);

        // The renderer died while backgrounded — the loop stays stopped and the
        // session leaves real mode regardless of the pause.
        channel.emit(const TryOnErrorEvent(reason: 'renderer_init_failed'));
        async.flushMicrotasks();
        expect(controller.mode, TryOnMode.simulated);

        controller.setAppForeground(foreground: true);
        async.elapse(const Duration(seconds: 1));

        expect(controller.footTrackingActive, isFalse,
            reason: 'a fallback screen must not spend frames');
        controller.dispose();
      });
    });

    test('after dispose the lifecycle calls are inert', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final detector = _FakeDetector()..result = _positive();
        final controller = _controller(channel: channel, detector: detector);
        _startRealSession(controller, async);
        async.elapse(const Duration(milliseconds: 400));
        final framesBefore = channel.frameRequests;

        controller.dispose();
        controller.setAppForeground(foreground: false);
        controller.setAppForeground(foreground: true);
        async.elapse(const Duration(seconds: 1));

        expect(channel.frameRequests, framesBefore,
            reason: 'a disposed controller has no loop to resume');
      });
    });
  });

  group('V4.9: the readout seam', () {
    test('a diagnostics build asks for the heartbeat before the session',
        () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final controller = _controller(
          channel: channel,
          detector: _FakeDetector(),
          diagnostics: true,
        );
        _startRealSession(controller, async);

        expect(channel.diagnosticsEnabled, isTrue);
        expect(
          channel.calls.indexOf('setDiagnostics'),
          lessThan(channel.calls.indexOf('startSession')),
          reason: 'the readout is on before the session exists, so a session '
              'that then fails still leaves its state readable',
        );
        controller.dispose();
      });
    });

    test('a build without the switch makes no readout call at all', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final controller =
            _controller(channel: channel, detector: _FakeDetector());
        _startRealSession(controller, async);

        expect(channel.calls, isNot(contains('setDiagnostics')),
            reason: 'the V3 switch rule extended: a build that did not ask '
                'for the readout never makes the call');
        controller.dispose();
      });
    });

    test('a status event becomes the heartbeat line, and an empty one is '
        'ignored', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final controller =
            _controller(channel: channel, detector: _FakeDetector());
        expect(controller.nativeStatusLine.value, isNull);
        // The subscription is `startAr`'s (the same one every other event test
        // rides), so the line is emitted into a live session, not into the
        // broadcast stream's empty room.
        _startRealSession(controller, async);

        channel.emit(const TryOnStatusEvent(
            line: 'loop=on iter=61 foot=locked len=264mm'));
        async.flushMicrotasks();
        expect(controller.nativeStatusLine.value,
            'loop=on iter=61 foot=locked len=264mm');

        channel.emit(const TryOnStatusEvent(
            line: 'loop=on iter=62 foot=search len=-'));
        async.flushMicrotasks();
        expect(controller.nativeStatusLine.value, contains('iter=62'));

        // An empty line is a malformed payload's residue, not a heartbeat:
        // the last words stay.
        channel.emit(const TryOnStatusEvent(line: ''));
        async.flushMicrotasks();
        expect(controller.nativeStatusLine.value, contains('iter=62'));
        controller.dispose();
      });
    });

    test('a failed readout request does not cost the session', () {
      fakeAsync((async) {
        final channel = _FakeChannel()
          ..diagnosticsError = MissingPluginException('no native readout');
        final controller = _controller(
          channel: channel,
          detector: _FakeDetector(),
          diagnostics: true,
        );
        _startRealSession(controller, async);

        expect(controller.phase, TryOnPhase.searching,
            reason: 'a readout is evidence, not a precondition');
        controller.dispose();
      });
    });
  });

  group('teardown', () {
    test('dispose stops the loop and disposes the detector', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final detector = _FakeDetector()..result = _positive();
        final controller = _controller(channel: channel, detector: detector);
        _startRealSession(controller, async);
        async.elapse(const Duration(milliseconds: 400));
        final posesBefore = channel.poses.length;

        controller.dispose();
        async.elapse(const Duration(seconds: 2));

        expect(channel.poses, hasLength(posesBefore));
        expect(detector.disposed, isTrue,
            reason: 'the controller owns the loop, so it owns the detector '
                'even when one was injected');
        expect(controller.footTrackingActive, isFalse);
      });
    });

    test('twenty open/close cycles release every loop resource', () {
      fakeAsync((async) {
        for (var cycle = 0; cycle < 20; cycle++) {
          final channel = _FakeChannel();
          final detector = _FakeDetector()..result = _positive();
          final controller = _controller(channel: channel, detector: detector);
          _startRealSession(controller, async);
          // A full second: the temporal gate's first three ticks are the price
          // of calling anything a foot, so 400 ms would close before cycle 0
          // ever published.
          async.elapse(const Duration(seconds: 1));
          expect(channel.poses, isNotEmpty,
              reason: 'cycle $cycle must have ticked before it closes');

          controller.dispose();
          async.flushMicrotasks();

          expect(detector.disposed, isTrue,
              reason: 'cycle $cycle leaked its detector');
          expect(async.pendingTimers, isEmpty,
              reason: 'cycle $cycle left a timer armed');

          final posesAtDispose = channel.poses.length;
          final framesAtDispose = channel.frameRequests;
          async.elapse(const Duration(seconds: 2));
          expect(channel.poses, hasLength(posesAtDispose),
              reason: 'cycle $cycle kept publishing after dispose');
          expect(channel.frameRequests, framesAtDispose,
              reason: 'cycle $cycle kept asking for frames after dispose');
        }

        // Twenty sessions in, the timer ledger is the leak detector: a
        // `Timer.periodic` no `dispose` cancelled would still be sitting here.
        expect(async.pendingTimers, isEmpty,
            reason: 'twenty closed sessions must leave zero armed timers');
      });
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════

TryOnSessionController _controller({
  required _FakeChannel channel,
  required _FakeDetector detector,
  bool footTrack = true,
  bool diagnostics = false,
}) =>
    TryOnSessionController(
      productId: 'product-1',
      enabled: true,
      footTrackEnabled: footTrack,
      diagnostics: diagnostics,
      channel: channel,
      models: _FakeModels(),
      footDetector: detector,
    );

/// Drives the controller to a live session without a single real await.
void _startRealSession(TryOnSessionController controller, FakeAsync async) {
  unawaited(controller.prepareModel());
  async.flushMicrotasks();
  unawaited(controller.startAr(arViewReady: true));
  async.flushMicrotasks();
}

FootDetectionResult _positive({bool withMask = true}) => FootDetectionResult(
      footDetected: true,
      confidence: 0.85,
      qualityScore: 0.85,
      footSide: 'right',
      heelPoint: const FootPoint(x: 0.30, y: 0.80, likelihood: 0.9),
      toePoint: const FootPoint(x: 0.35, y: 0.20, likelihood: 0.9),
      mask: withMask ? _mask() : null,
    );

/// A stand-in for `downsampleFootMask`'s output: 32×32, one value. Its identity
/// is what the loop tests assert on, so it is built fresh per call.
Uint8List _mask() => Uint8List.fromList(List<int>.filled(32 * 32, 200));

/// The channel, faked: records what the loop asked for and lets a test choose
/// the frame, the failure and the session's answer.
class _FakeChannel extends ArTryOnChannel {
  final List<String> calls = <String>[];
  final List<FootPoseFrame> poses = <FootPoseFrame>[];

  int frameRequests = 0;
  ArCameraFrame? nextFrame = ArCameraFrame(
    nv21Bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
    width: 640,
    height: 480,
    rotationDegrees: 0,
  );
  Object? frameError;
  bool startSucceeds = true;

  final StreamController<ArTryOnEvent> _events =
      StreamController<ArTryOnEvent>.broadcast();

  void emit(ArTryOnEvent event) => _events.add(event);

  @override
  Stream<ArTryOnEvent> get events => _events.stream;

  @override
  void attach() {}

  @override
  Future<void> detach() async {}

  @override
  Future<TryOnStartResult> startSession() async {
    calls.add('startSession');
    return TryOnStartResult(started: startSucceeds);
  }

  bool? diagnosticsEnabled;
  Object? diagnosticsError;

  @override
  Future<void> setDiagnostics(bool enabled) async {
    calls.add('setDiagnostics');
    final failure = diagnosticsError;
    if (failure != null) throw failure;
    diagnosticsEnabled = enabled;
  }

  @override
  Future<void> setModel(TryOnModelSpec spec) async => calls.add('setModel');

  @override
  Future<ArCameraFrame?> acquireCameraFrame() async {
    frameRequests++;
    final failure = frameError;
    if (failure != null) throw failure;
    return nextFrame;
  }

  @override
  Future<void> setFootPose(FootPoseFrame frame) async {
    calls.add('setFootPose');
    poses.add(frame);
  }

  final List<({Uint8List bytes, double confidence})> masks =
      <({Uint8List bytes, double confidence})>[];
  Object? maskError;

  @override
  Future<void> setFootMask({
    required Uint8List bytes32x32,
    required double confidence,
  }) async {
    calls.add('setFootMask');
    final failure = maskError;
    if (failure != null) throw failure;
    masks.add((bytes: bytes32x32, confidence: confidence));
  }
}

/// The detector, faked: one answer for every frame, and a dispose that is
/// observable.
class _FakeDetector implements FootDetector {
  FootDetectionResult result = const FootDetectionResult.negative();
  int detectCalls = 0;
  bool disposed = false;

  @override
  Future<FootDetectionResult> detect({
    required Uint8List nv21Bytes,
    required int width,
    required int height,
    required int rotationDegrees,
    String? preferSide,
    Rect? guideRect,
  }) async {
    detectCalls++;
    return result;
  }

  @override
  void dispose() => disposed = true;
}

/// The model read seam in memory — no database, no download, no file I/O, so
/// the whole session can run inside `fakeAsync`.
class _FakeModels extends ShoeModelService {
  @override
  Future<ShoeModelSpec?> resolveForProduct(
    String productId, {
    String? variantId,
    bool anyVariant = false,
  }) async =>
      const ShoeModelSpec(
        id: 1,
        storagePath: 'store-1/product-1/model.glb',
        sha256: 'sha',
        version: 1,
        shoeSide: 'right',
        authoredLengthMm: 270,
      );

  @override
  Future<ShoeModelFile> ensureLocal(
    ShoeModelSpec spec, {
    bool force = false,
  }) async =>
      const ShoeModelFile(
        path: 'C:/fake/model.glb',
        fromCache: true,
        bytes: 32,
      );
}
