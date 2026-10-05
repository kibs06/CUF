import 'package:app/utils/try_on_coach.dart';
import 'package:app/widgets/foot_size_v2/glass_card.dart';
import 'package:app/widgets/try_on/try_on_coach_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// **V4.5's card.** The rules decide the cue (`try_on_coach_test.dart`); this
/// file decides that the card renders the cue's own sentence, its tone, and its
/// one interaction — and that a null cue draws *nothing at all*, which is the
/// state every build with the foot-tracking switch off lives in.
///
/// The last group is the one the scan's own coach tests taught: every cue is
/// laid out at 320 px with 1.6× text. A card over a camera has no scroll view to
/// rescue it, so an overflow is a customer-visible bug rather than a warning.
void main() {
  Widget wrap(Widget child, {TextScaler textScaler = TextScaler.noScaling}) =>
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: MediaQuery(
            data: MediaQueryData(textScaler: textScaler),
            child: Center(
              child: SizedBox(width: 320, child: child),
            ),
          ),
        ),
      );

  GlassTone toneOf(WidgetTester tester) =>
      tester.widget<GlassCard>(find.byType(GlassCard)).tone;

  testWidgets('a null cue draws nothing', (tester) async {
    await tester.pumpWidget(wrap(const TryOnCoachCard(cue: null)));

    expect(find.byType(GlassCard), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('each cue says its own line', (tester) async {
    const expected = <TryOnCoachCue, String>{
      TryOnCoachCue.pointAtFoot: 'Point the camera at your foot',
      TryOnCoachCue.improveScene: 'Keep the floor in view',
      TryOnCoachCue.moveCloser: 'Move the phone closer',
      TryOnCoachCue.moveBack: 'Move the phone back',
      TryOnCoachCue.holdStill: 'Hold still',
      TryOnCoachCue.locked: 'Locked on',
      TryOnCoachCue.regain: 'Bring your foot back into view',
      TryOnCoachCue.manual: 'Place the shoe yourself',
      TryOnCoachCue.placeByTap: 'Tap the floor to place the shoe',
    };

    for (final entry in expected.entries) {
      await tester.pumpWidget(wrap(TryOnCoachCard(cue: entry.key)));
      expect(
        find.text(entry.value),
        findsOneWidget,
        reason: '${entry.key.name} has its own sentence',
      );
    }
  });

  testWidgets('the tone follows the beat', (tester) async {
    await tester.pumpWidget(wrap(const TryOnCoachCard(cue: TryOnCoachCue.locked)));
    expect(toneOf(tester), GlassTone.success);

    await tester.pumpWidget(wrap(const TryOnCoachCard(cue: TryOnCoachCue.regain)));
    expect(toneOf(tester), GlassTone.warning);

    await tester.pumpWidget(wrap(const TryOnCoachCard(cue: TryOnCoachCue.manual)));
    expect(toneOf(tester), GlassTone.active);

    await tester.pumpWidget(
      wrap(const TryOnCoachCard(cue: TryOnCoachCue.pointAtFoot)),
    );
    expect(toneOf(tester), GlassTone.neutral);
  });

  testWidgets('the offer has a button, and accepting it reports', (tester) async {
    var accepted = 0;
    await tester.pumpWidget(
      wrap(TryOnCoachCard(cue: TryOnCoachCue.manual, onPlaceManually: () => accepted++)),
    );

    expect(find.text('Place it myself'), findsOneWidget);
    await tester.tap(find.text('Place it myself'));
    await tester.pump();

    expect(accepted, 1);
  });

  testWidgets('tap-by-tap has no button — the offer was already accepted',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        TryOnCoachCard(
          cue: TryOnCoachCue.placeByTap,
          onPlaceManually: () {},
        ),
      ),
    );

    expect(find.text('Tap the floor to place the shoe'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('a manual cue without a callback still renders, without a button',
      (tester) async {
    // The card is a pure function of the cue; a screen that forgot the callback
    // must still show the sentence rather than a dead control.
    await tester.pumpWidget(wrap(const TryOnCoachCard(cue: TryOnCoachCue.manual)));

    expect(find.text('Place the shoe yourself'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('every cue fits a 320 px screen at 1.6× text', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final cue in TryOnCoachCue.values) {
      await tester.pumpWidget(
        wrap(
          TryOnCoachCard(cue: cue, onPlaceManually: () {}),
          textScaler: const TextScaler.linear(1.6),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '${cue.name} must fit');
    }
  });
}
