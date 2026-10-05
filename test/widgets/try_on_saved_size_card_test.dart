import 'package:app/models/foot_measurement.dart';
import 'package:app/providers/auth_provider.dart';
import 'package:app/providers/foot_measurement_provider.dart';
import 'package:app/screens/customer/foot_instructions_screen.dart';
import 'package:app/utils/try_on_fit.dart';
import 'package:app/widgets/foot_size_v2/glass_card.dart';
import 'package:app/widgets/try_on/try_on_saved_size_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

/// **V4.7's card.** The comparison rules live in `try_on_saved_size_test.dart`;
/// this file is about what a customer actually sees and touches — that a
/// suggestion without a saved scan to back it draws *nothing*, that the
/// sentence and both millimetres appear when the two measurements disagree,
/// that the lock gates it, that "Rescan" opens the scan flow, and that the one
/// saved-scan read happens once per mount and only for a customer the profile
/// says has scanned.
///
/// The last test repeats the scan's own lesson: the card is laid out at 320 px
/// with 1.6× text, because a card over a camera has no scroll view to rescue
/// it.
class _MockAuthProvider extends Mock
    with ChangeNotifier
    implements AuthProvider {}

class _MockFootMeasurementProvider extends Mock
    with ChangeNotifier
    implements FootMeasurementProvider {}

/// A scanned customer's foot: 264 mm on the sizing (right) foot — the number
/// the engine itself grades with, no compensation applied.
FootMeasurement scannedFoot({double lengthMm = 264}) => FootMeasurement(
      userId: 'user-1',
      sizingFootSide: 'right',
      footLengthRightMm: lengthMm,
      paperSizeUsed: 'ar',
      scanDate: DateTime(2026, 9, 27),
    );

void main() {
  Widget wrap(
    TryOnSavedSizeCard card, {
    Map<String, dynamic>? profile = const {
      'foot_size_ph': 42,
      'foot_profile_source': 'ar_scan',
    },
    FootMeasurement? measurement,
    VoidCallback? onLoad,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final auth = _MockAuthProvider();
    when(() => auth.profile).thenReturn(profile);
    when(() => auth.currentUser).thenReturn(const {'id': 'user-1'});

    final foot = _MockFootMeasurementProvider();
    when(() => foot.latestMeasurement).thenReturn(measurement);
    when(() => foot.loadLatest(any())).thenAnswer((_) async {
      onLoad?.call();
    });

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<FootMeasurementProvider>.value(value: foot),
      ],
      child: MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: MediaQuery(
            data: MediaQueryData(textScaler: textScaler),
            child: Center(
              child: SizedBox(width: 320, child: card),
            ),
          ),
        ),
      ),
    );
  }

  TryOnSavedSizeCard card({double? liveMm = 273, bool locked = true}) =>
      TryOnSavedSizeCard(
        live: TryOnLiveFoot(lengthMm: liveMm, quality: 0.9, locked: locked),
      );

  testWidgets('no saved scan draws nothing — even from a stale reading',
      (tester) async {
    await tester.pumpWidget(wrap(card()));
    await tester.pump();

    expect(find.byType(GlassCard), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('a difference inside the band draws nothing', (tester) async {
    await tester.pumpWidget(
      wrap(card(liveMm: 271.9), measurement: scannedFoot()),
    );

    expect(find.byType(GlassCard), findsNothing);
  });

  testWidgets('a stale profile draws the sentence, both millimetres and the '
      'action', (tester) async {
    await tester.pumpWidget(
      wrap(card(liveMm: 273.4), measurement: scannedFoot(lengthMm: 264)),
    );

    expect(find.byKey(const ValueKey('try-on-saved-size')), findsOneWidget);
    expect(
      find.text('Your saved size may be stale — rescan?'),
      findsOneWidget,
    );
    expect(
      find.text(
        'The foot in view measures 273 mm; your saved scan measured 264 mm.',
      ),
      findsOneWidget,
    );
    expect(
      find.text("Your size won't change unless you rescan."),
      findsOneWidget,
    );
    expect(find.text('Rescan'), findsOneWidget);
  });

  testWidgets('an unlocked tracker draws nothing, however stale the profile',
      (tester) async {
    await tester.pumpWidget(
      wrap(card(locked: false), measurement: scannedFoot()),
    );

    expect(find.byType(GlassCard), findsNothing);
  });

  testWidgets('the action opens the scan flow', (tester) async {
    await tester.pumpWidget(
      wrap(card(), measurement: scannedFoot(lengthMm: 264)),
    );

    await tester.tap(find.byKey(const ValueKey('try-on-saved-size-rescan')));
    await tester.pumpAndSettle();

    expect(find.byType(FootInstructionsScreen), findsOneWidget);
  });

  testWidgets('one read per mount — and only when the profile says scanned',
      (tester) async {
    var loads = 0;
    await tester.pumpWidget(
      wrap(card(), profile: null, onLoad: () => loads++),
    );
    await tester.pump();

    // No profile: nothing may be asked of the database at all.
    expect(loads, 0);

    loads = 0;
    await tester.pumpWidget(
      wrap(card(), measurement: null, profile: const {
        'foot_size_ph': 42,
        'foot_profile_source': 'ar_scan',
      }, onLoad: () => loads++),
    );
    await tester.pump();
    await tester.pump();

    expect(loads, 1, reason: 'a scanned customer gets exactly one read');
  });

  testWidgets('every visible state fits at 320 px and 1.6× text',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        card(),
        measurement: scannedFoot(lengthMm: 264),
        textScaler: const TextScaler.linear(1.6),
      ),
    );

    expect(find.byKey(const ValueKey('try-on-saved-size')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
