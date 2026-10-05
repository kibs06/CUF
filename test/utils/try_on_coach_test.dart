import 'package:app/providers/try_on/try_on_phase.dart';
import 'package:app/utils/foot_detector.dart';
import 'package:app/utils/try_on_coach.dart';
import 'package:flutter_test/flutter_test.dart';

/// **V4.5's rules, as a table.** What the coach card says is a pure function of
/// state the session already has — the phase machine, the tracker's lock, the
/// last detection's own points, and a counted clock — so every sentence a
/// customer can be shown is pinned here, with no camera and no device.
///
/// Three things are being protected:
///
///   1. **The silence.** A build with the switch off, or a session that is not
///      live, must produce `null` — an empty card, not a wrong one.
///   2. **The priority order.** A lock beats a pending manual offer; the offer
///      beats "bring your foot back"; framing beats "hold still". Every one of
///      those pairs is a judgement call, so each is its own test.
///   3. **The counted clock.** 15 s is 75 ticks of the loop's own cadence, and
///      the boundary is inclusive — the offer has to arrive on time in a test
///      as well as on a device.
void main() {
  FootDetectionResult detectionAt(Offset heel, Offset toe) => FootDetectionResult(
        footDetected: true,
        confidence: 0.9,
        qualityScore: 0.9,
        heelPoint: FootPoint(x: heel.dx, y: heel.dy, likelihood: 0.9),
        toePoint: FootPoint(x: toe.dx, y: toe.dy, likelihood: 0.9),
      );

  /// A detection whose heel→toe span is exactly [span] (horizontal and
  /// zero-based, so `toe.x - heel.x` and the square root are both exact for
  /// every value this file uses — a non-zero base like `0.2 + span - 0.2`
  /// rounds `0.92` up to `0.9200000000000002` and would fail a boundary the
  /// rule gets right).
  FootDetectionResult spanDetection(double span) =>
      detectionAt(const Offset(0, 0.5), Offset(span, 0.5));

  group('framing', () {
    test('no usable heel/toe pair is unknown, not a guess', () {
      expect(
        footFramingFromDetection(const FootDetectionResult.negative()),
        TryOnFootFraming.unknown,
      );
      expect(
        footFramingFromDetection(const FootDetectionResult(
          footDetected: true,
          confidence: 0.9,
          heelPoint: FootPoint(x: 0.3, y: 0.8, likelihood: 0.9),
        )),
        TryOnFootFraming.unknown,
        reason: 'a heel with no toe describes no extent',
      );
    });

    test('degenerate and non-finite extents are unknown', () {
      expect(
        footFramingFromDetection(
          detectionAt(const Offset(0.4, 0.4), const Offset(0.4, 0.4)),
        ),
        TryOnFootFraming.unknown,
      );
      expect(
        footFramingFromDetection(
          detectionAt(const Offset(double.nan, 0.4), const Offset(0.6, 0.4)),
        ),
        TryOnFootFraming.unknown,
      );
    });

    test('the thresholds are inclusive at both ends', () {
      expect(footFramingFromDetection(spanDetection(0.10)), TryOnFootFraming.tooFar);
      expect(
        footFramingFromDetection(spanDetection(kFootFramingTooFar)),
        TryOnFootFraming.ok,
        reason: 'exactly at the threshold is frameable, not far',
      );
      expect(footFramingFromDetection(spanDetection(0.6)), TryOnFootFraming.ok);
      expect(
        footFramingFromDetection(spanDetection(kFootFramingTooClose)),
        TryOnFootFraming.ok,
      );
      expect(
        footFramingFromDetection(spanDetection(0.97)),
        TryOnFootFraming.tooClose,
      );
    });
  });

  group('silence', () {
    TryOnCoachCue? cue({
      bool trackingEnabled = true,
      bool trackingActive = true,
      TryOnPhase phase = TryOnPhase.searching,
      bool locked = false,
      bool footSeen = false,
      Duration searchingFor = Duration.zero,
      TryOnFootFraming framing = TryOnFootFraming.unknown,
      bool manualOfferDismissed = false,
    }) =>
        coachCueFor(
          trackingEnabled: trackingEnabled,
          trackingActive: trackingActive,
          phase: phase,
          locked: locked,
          footSeen: footSeen,
          searchingFor: searchingFor,
          framing: framing,
          manualOfferDismissed: manualOfferDismissed,
        );

    test('the switch off is always null', () {
      expect(cue(trackingEnabled: false), isNull);
      expect(
        cue(trackingEnabled: false, locked: true, footSeen: true),
        isNull,
        reason: 'even a lock must not draw a card in a build that never asked '
            'for foot tracking',
      );
    });

    test('phases that are not a live AR session are null', () {
      for (final phase in <TryOnPhase>[
        TryOnPhase.idle,
        TryOnPhase.loadingModel,
        TryOnPhase.modelReady,
        TryOnPhase.arStarting,
        TryOnPhase.arFailed,
        TryOnPhase.error,
      ]) {
        expect(cue(phase: phase), isNull, reason: '${phase.name} draws no card');
      }
      for (final phase in <TryOnPhase>[
        TryOnPhase.searching,
        TryOnPhase.locked,
        TryOnPhase.lost,
      ]) {
        expect(cue(phase: phase), isNotNull, reason: '${phase.name} is live');
      }
    });
  });

  group('lock and loss', () {
    TryOnCoachCue? cue({
      bool trackingActive = true,
      TryOnPhase phase = TryOnPhase.searching,
      bool locked = false,
      bool footSeen = false,
      Duration searchingFor = Duration.zero,
      TryOnFootFraming framing = TryOnFootFraming.unknown,
      bool manualOfferDismissed = false,
    }) =>
        coachCueFor(
          trackingEnabled: true,
          trackingActive: trackingActive,
          phase: phase,
          locked: locked,
          footSeen: footSeen,
          searchingFor: searchingFor,
          framing: framing,
          manualOfferDismissed: manualOfferDismissed,
        );

    test('a lock outranks a pending offer, a dismissal and a loss', () {
      expect(
        cue(
          locked: true,
          phase: TryOnPhase.locked,
          searchingFor: const Duration(seconds: 40),
          manualOfferDismissed: true,
        ),
        TryOnCoachCue.locked,
      );
    });

    test('a loss walks the customer back', () {
      expect(
        cue(locked: false, phase: TryOnPhase.lost, searchingFor: const Duration(seconds: 2)),
        TryOnCoachCue.regain,
      );
    });

    test('a loss that does not come back becomes the offer', () {
      expect(
        cue(phase: TryOnPhase.lost, searchingFor: kFootManualOfferAfter),
        TryOnCoachCue.manual,
        reason: '"step back into view" repeated for 15 s is how a customer '
            'ends up stuck',
      );
      expect(
        cue(
          phase: TryOnPhase.lost,
          searchingFor: kFootManualOfferAfter,
          manualOfferDismissed: true,
        ),
        TryOnCoachCue.placeByTap,
      );
    });
  });

  group('the manual offer', () {
    TryOnCoachCue? cue({
      bool trackingActive = true,
      Duration searchingFor = Duration.zero,
      bool manualOfferDismissed = false,
      bool footSeen = false,
    }) =>
        coachCueFor(
          trackingEnabled: true,
          trackingActive: trackingActive,
          phase: TryOnPhase.searching,
          locked: false,
          footSeen: footSeen,
          searchingFor: searchingFor,
          framing: TryOnFootFraming.ok,
          manualOfferDismissed: manualOfferDismissed,
        );

    test('a stopped loop offers it immediately', () {
      expect(
        cue(trackingActive: false),
        TryOnCoachCue.manual,
        reason: 'after kFootTrackFailureLimit failures the honest answer is '
            '"do it yourself", not another tracking hint',
      );
      expect(
        cue(trackingActive: false, manualOfferDismissed: true),
        TryOnCoachCue.placeByTap,
      );
    });

    test('15 s without a lock is the boundary, and it is inclusive', () {
      expect(
        cue(searchingFor: kFootManualOfferAfter - const Duration(milliseconds: 200)),
        isNot(TryOnCoachCue.manual),
      );
      expect(cue(searchingFor: kFootManualOfferAfter), TryOnCoachCue.manual);
    });

    test('the offer outranks framing advice', () {
      expect(
        cue(searchingFor: kFootManualOfferAfter, footSeen: true),
        TryOnCoachCue.manual,
      );
    });
  });

  group('the search cues', () {
    TryOnCoachCue? cue({
      bool footSeen = false,
      Duration searchingFor = Duration.zero,
      TryOnFootFraming framing = TryOnFootFraming.unknown,
    }) =>
        coachCueFor(
          trackingEnabled: true,
          trackingActive: true,
          phase: TryOnPhase.searching,
          locked: false,
          footSeen: footSeen,
          searchingFor: searchingFor,
          framing: framing,
          manualOfferDismissed: false,
        );

    test('nothing seen: point at the foot, then talk about the scene', () {
      expect(cue(), TryOnCoachCue.pointAtFoot);
      expect(
        cue(searchingFor: kFootSceneHintAfter - const Duration(milliseconds: 200)),
        TryOnCoachCue.pointAtFoot,
      );
      expect(
        cue(searchingFor: kFootSceneHintAfter),
        TryOnCoachCue.improveScene,
        reason: '§2.12 groups "no floor plane" and "poor light" into one line, '
            'because the app cannot tell them apart',
      );
    });

    test('a seen foot asks for stillness, whatever the framing opinion', () {
      expect(cue(footSeen: true, framing: TryOnFootFraming.ok), TryOnCoachCue.holdStill);
      expect(
        cue(footSeen: true, framing: TryOnFootFraming.unknown),
        TryOnCoachCue.holdStill,
      );
    });

    test('framing outranks stillness', () {
      expect(
        cue(
          footSeen: true,
          framing: TryOnFootFraming.tooFar,
          searchingFor: const Duration(seconds: 5),
        ),
        TryOnCoachCue.moveCloser,
        reason: 'a customer holding perfectly still a metre from the phone is '
            'still not going to lock',
      );
      expect(
        cue(footSeen: true, framing: TryOnFootFraming.tooClose),
        TryOnCoachCue.moveBack,
      );
    });

    test('a foot that has never been seen does not get framing advice', () {
      expect(
        cue(searchingFor: const Duration(seconds: 6), framing: TryOnFootFraming.tooFar),
        TryOnCoachCue.improveScene,
      );
    });
  });
}
