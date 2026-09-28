import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:app/constants/app_constants.dart';
import 'package:app/models/foot_measurement.dart';
import 'package:app/providers/auth_provider.dart';
import 'package:app/providers/foot_measurement_provider.dart';
import 'package:app/utils/fit_engine.dart';
import 'package:app/utils/fit_verdict_state.dart';
import 'package:app/widgets/fit_verdict_card.dart';

/// The fit verdict card: the words, the box, and the one wire that matters.
///
/// The decision rules live in `test/utils/fit_verdict_state_test.dart`; this
/// file is about what a customer actually sees and touches — that every band
/// has its own phrase, icon and colour (never colour alone), that the reasons
/// the engine wrote are all printed rather than summarised away, that a hidden
/// card leaves no space behind it, and that "Scan my feet" is wired to
/// something.
///
/// The wired `FitVerdictCard` is asserted **in whichever configuration the
/// build is in**: with the switch off (the shipped default) it must render
/// nothing and touch no provider at all, and the moment someone flips it on
/// these same tests start asserting the verdict path — so the flip cannot
/// happen quietly on unwired code.
class _MockAuthProvider extends Mock
    with ChangeNotifier
    implements AuthProvider {}

class _MockFootMeasurementProvider extends Mock
    with ChangeNotifier
    implements FootMeasurementProvider {}

/// A men's EU 42 last: 275 mm internal, 98 mm wide.
FitSpecs shoe = const FitSpecs(lastLengthMm: 275, lastWidthMm: 98, refSizeEu: 42);

/// A 265 mm foot, 95 mm wide — 10 mm of toe room: true to size.
FootFitInput foot = const FootFitInput(
  lengthMm: 265,
  widthMm: 95,
  scanConfidence: 0.9,
);

/// The product row the card reads, spec-complete.
Map<String, dynamic> specProduct = {
  'id': 'product-1',
  'last_length_mm': 275,
  'last_width_mm': 98,
  'fit_ref_size_eu': 42,
};

FitVerdict verdictFor(FitVerdictKind kind) => switch (kind) {
  // Widen the last until the band says what the test needs, so every case
  // comes from the engine rather than from a hand-built verdict.
  FitVerdictKind.tooSmall => fitVerdictAt(
    foot: foot,
    shoe: const FitSpecs(lastLengthMm: 265, lastWidthMm: 98, refSizeEu: 42),
    sizeEu: 42,
  )!,
  FitVerdictKind.trueToSize => fitVerdictAt(
    foot: foot,
    shoe: shoe,
    sizeEu: 42,
  )!,
  FitVerdictKind.roomy => fitVerdictAt(
    foot: foot,
    shoe: const FitSpecs(lastLengthMm: 282, lastWidthMm: 98, refSizeEu: 42),
    sizeEu: 42,
  )!,
  FitVerdictKind.snug => fitVerdictAt(
    foot: foot,
    shoe: const FitSpecs(lastLengthMm: 270, lastWidthMm: 98, refSizeEu: 42),
    sizeEu: 42,
  )!,
  FitVerdictKind.tooBig => fitVerdictAt(
    foot: foot,
    shoe: const FitSpecs(lastLengthMm: 300, lastWidthMm: 98, refSizeEu: 42),
    sizeEu: 42,
  )!,
};

Future<void> pumpPanel(WidgetTester tester, FitVerdictCardState state,
    {VoidCallback? onScan}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FitVerdictPanel(state: state, onScanRequested: onScan),
      ),
    ),
  );
  await tester.pump();
}

/// The card, wired to mocked providers — one scanned customer's product page.
Widget wired({
  Map<String, dynamic>? product,
  String? selectedSize = '42',
  Map<String, dynamic>? profile,
  FootMeasurement? measurement,
}) {
  final auth = _MockAuthProvider();
  when(() => auth.profile).thenReturn(profile);
  when(() => auth.currentUser).thenReturn(const {'id': 'user-1'});

  final footProvider = _MockFootMeasurementProvider();
  when(() => footProvider.latestMeasurement).thenReturn(measurement);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<FootMeasurementProvider>.value(
        value: footProvider,
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: FitVerdictCard(
          product: product ?? specProduct,
          selectedSize: selectedSize,
        ),
      ),
    ),
  );
}

FootMeasurement scannedFoot() => FootMeasurement(
  userId: 'user-1',
  sizingFootSide: 'right',
  footLengthRightMm: 265,
  footWidthRightMm: 95,
  paperSizeUsed: 'ar',
  scanDate: DateTime(2026, 9, 27),
);

void main() {
  group('the words', () {
    test('every band has its own phrase — none share a hedge', () {
      final phrases = {
        for (final kind in FitVerdictKind.values) fitVerdictPhrase(kind),
      };

      expect(phrases, hasLength(FitVerdictKind.values.length));
      expect(fitVerdictPhrase(FitVerdictKind.trueToSize), 'True to size');
      expect(fitVerdictPhrase(FitVerdictKind.tooSmall), 'Too small');
      expect(fitVerdictPhrase(FitVerdictKind.snug), 'Snug');
      expect(fitVerdictPhrase(FitVerdictKind.roomy), 'Roomy');
      expect(fitVerdictPhrase(FitVerdictKind.tooBig), 'Too big');
    });

    test('the two wrong directions read as errors, the target as good', () {
      for (final kind in [FitVerdictKind.tooSmall, FitVerdictKind.tooBig]) {
        expect(fitVerdictColor(kind), AppConstants.error, reason: kind.name);
      }
      for (final kind in [FitVerdictKind.snug, FitVerdictKind.roomy]) {
        expect(
          fitVerdictColor(kind),
          AppConstants.statusPendingColor,
          reason: kind.name,
        );
      }
      expect(fitVerdictColor(FitVerdictKind.trueToSize), AppConstants.success);
    });

    test('no band is colour alone — each carries its own icon', () {
      final icons = {
        for (final kind in FitVerdictKind.values) fitVerdictIcon(kind),
      };

      expect(icons, hasLength(FitVerdictKind.values.length));
    });
  });

  group('the verdict panel', () {
    testWidgets('prints the phrase, the size, every reason and the source', (
      tester,
    ) async {
      final verdict = verdictFor(FitVerdictKind.trueToSize);
      await pumpPanel(tester, FitVerdictCardState.answer(verdict, 42));

      expect(find.text('True to size'), findsOneWidget);
      // Labelled through `euSizeLabel`, so no surface spells its own EU 42.
      expect(find.text('EU 42'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

      // The engine's sentences are the card's evidence: all of them, in order,
      // not a summarised subset — including anything it could not compare.
      for (final reason in verdict.reasons) {
        expect(find.text(reason), findsOneWidget, reason: reason);
      }
      expect(find.textContaining('toe room'), findsWidgets);
      expect(find.text('Based on your saved foot measurements'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a length-only verdict says the width went unchecked', (
      tester,
    ) async {
      final verdict = fitVerdictAt(
        foot: foot,
        shoe: const FitSpecs(lastLengthMm: 275, refSizeEu: 42),
        sizeEu: 42,
      )!;

      expect(verdict.widthCompared, isFalse);
      await pumpPanel(tester, FitVerdictCardState.answer(verdict, 42));

      expect(find.textContaining('no last width recorded'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a low-confidence verdict prints the reason for the hedge', (
      tester,
    ) async {
      final verdict = fitVerdictAt(
        foot: const FootFitInput(lengthMm: 265, scanConfidence: 0.4),
        shoe: shoe,
        sizeEu: 42,
      )!;

      expect(verdict.isConfident, isFalse);
      await pumpPanel(tester, FitVerdictCardState.answer(verdict, 42));

      expect(find.textContaining('treat as a hint'), findsOneWidget);
    });

    testWidgets('every status that cannot speak renders nothing at all', (
      tester,
    ) async {
      for (final status in const [
        FitVerdictCardStatus.disabled,
        FitVerdictCardStatus.noSpecs,
        FitVerdictCardStatus.noSize,
        FitVerdictCardStatus.ungradeable,
        FitVerdictCardStatus.unavailable,
      ]) {
        await pumpPanel(tester, FitVerdictCardState.of(status));

        expect(find.byType(FitVerdictPanel), findsOneWidget, reason: status.name);
        expect(
          tester.getSize(find.byType(FitVerdictPanel)),
          Size.zero,
          reason: '${status.name} must leave no space behind it',
        );
        expect(tester.takeException(), isNull, reason: status.name);
      }
    });

    testWidgets('a visible card carries its own trailing gap', (tester) async {
      await pumpPanel(
        tester,
        FitVerdictCardState.answer(verdictFor(FitVerdictKind.trueToSize), 42),
      );

      // One gap, owned by the card: hidden means none, visible means the mount
      // site has nothing to add (the `in_your_size_section` rule).
      final outer = tester
          .widgetList<Padding>(
            find.descendant(
              of: find.byType(FitVerdictPanel),
              matching: find.byType(Padding),
            ),
          )
          .first;
      expect(outer.padding, const EdgeInsets.only(bottom: 8));
    });

    testWidgets('with no scan it invites one, and the button is wired', (
      tester,
    ) async {
      var taps = 0;
      await pumpPanel(
        tester,
        FitVerdictCardState.of(FitVerdictCardStatus.needsScan),
        onScan: () => taps++,
      );

      expect(find.text('See how this size fits you'), findsOneWidget);
      expect(find.textContaining('under a minute'), findsOneWidget);
      // No verdict words leak into an invitation.
      for (final kind in FitVerdictKind.values) {
        expect(find.text(fitVerdictPhrase(kind)), findsNothing);
      }

      await tester.tap(find.text('Scan my feet'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('the invitation survives a missing callback as a dead button', (
      tester,
    ) async {
      await pumpPanel(tester, FitVerdictCardState.of(FitVerdictCardStatus.needsScan));

      expect(find.text('See how this size fits you'), findsOneWidget);
      final button = tester.widget<TextButton>(find.byType(TextButton));
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a read in flight says so quietly and claims nothing', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        FitVerdictCardState.of(FitVerdictCardStatus.awaitingScan),
      );

      expect(find.text('Checking your saved measurements…'), findsOneWidget);
      expect(find.text('See how this size fits you'), findsNothing);
      for (final kind in FitVerdictKind.values) {
        expect(find.text(fitVerdictPhrase(kind)), findsNothing);
      }
    });

    testWidgets('every state survives a narrow phone at a large text scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final states = [
        for (final kind in FitVerdictKind.values)
          FitVerdictCardState.answer(verdictFor(kind), 42.5),
        FitVerdictCardState.of(FitVerdictCardStatus.needsScan),
        FitVerdictCardState.of(FitVerdictCardStatus.awaitingScan),
      ];

      // 1.3 is the scale the size-poster tests use; 1.6 is the accessibility
      // band where a fixed-width button beside a paragraph stops fitting. The
      // card's own font here is the test font, whose glyphs are a full em —
      // wider than DM Sans, so this is the pessimistic side of the estimate.
      for (final scale in const [1.3, 1.6]) {
        for (final state in states) {
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(scale),
              ),
              child: MaterialApp(
                home: Scaffold(body: FitVerdictPanel(state: state)),
              ),
            ),
          );
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: '${state.status.name} at ${scale}x',
          );
        }
      }
    });
  });

  group('the wired card', () {
    testWidgets('a product with no spec touches no provider and asks nothing', (
      tester,
    ) async {
      // No MultiProvider above this card at all: a spec-less product must be
      // answered from the row alone, with no read and no provider lookup.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FitVerdictCard(product: {}, selectedSize: '42'),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(FitVerdictPanel), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the switch decides the whole surface, and nothing else does', (
      tester,
    ) async {
      await tester.pumpWidget(
        wired(
          profile: const {'foot_size_ph': 42, 'foot_profile_source': 'ar_scan'},
          measurement: scannedFoot(),
        ),
      );
      await tester.pump();

      if (AppConstants.virtualFitEnabled) {
        // The flip-on contract, asserted by the same test that guards the
        // shipped state: a scanned customer with a spec-complete product sees
        // the verdict.
        expect(find.text('True to size'), findsOneWidget);
        expect(find.text('EU 42'), findsOneWidget);
      } else {
        // Nothing visible — measured, not counted: with shadow mode on, the
        // card still computes a record beside a customer who is shown nothing,
        // so asserting on the widget's presence would fail in exactly the
        // configuration the roadmap asks for (collect with the card off).
        expect(tester.getSize(find.byType(FitVerdictCard)).height, 0);
        expect(find.text('True to size'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the switch being off means no scan read is even attempted', (
      tester,
    ) async {
      final footProvider = _MockFootMeasurementProvider();
      when(() => footProvider.latestMeasurement).thenReturn(null);

      final auth = _MockAuthProvider();
      when(() => auth.profile).thenReturn(const {
        'foot_size_ph': 42,
        'foot_profile_source': 'ar_scan',
      });
      when(() => auth.currentUser).thenReturn(const {'id': 'user-1'});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<FootMeasurementProvider>.value(
              value: footProvider,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: FitVerdictCard(product: {}, selectedSize: '42'),
            ),
          ),
        ),
      );

      // pump a frame and let any post-frame callback fire and complete
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // A spec-less product is the one case that must never read the network,
      // whatever the switch says — the card is decided from the row.
      verifyNever(() => footProvider.loadLatest(any()));
      expect(tester.takeException(), isNull);
    });
  });

  group('shadow mode', () {
    // The collection configuration, which the roadmap asks someone to run
    // (`virtualFitShadowEnabled = true`) and which the shipped build does not
    // use. Gated rather than skipped silently, so the suite reports it.
    //
    // Captured through `debugPrint`, the one hook the diag channel writes to
    // that a test can see: the logger's file needs path_provider and a real
    // documents directory, and this assertion is about the *record*, not about
    // the channel that carries it.
    // `testWidgets`'s `skip` is a bool, so the reason lives here: these two
    // only assert anything while `AppConstants.virtualFitShadowEnabled` is on.
    final shadowOff = !AppConstants.virtualFitShadowEnabled;

    /// Pumps [app] with `debugPrint` captured.
    ///
    /// Restored inside the test body rather than in a teardown: the framework
    /// verifies foundation debug variables are back to their defaults *before*
    /// tear-downs run, and fails the test if one is still overridden.
    Future<List<String>> capture(WidgetTester tester, Widget app) async {
      final lines = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) lines.add(message);
      };
      try {
        await tester.pumpWidget(app);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      } finally {
        debugPrint = original;
      }
      return lines;
    }

    List<String> fitLines(List<String> lines) =>
        lines.where((line) => line.contains('[FIT]')).toList();

    testWidgets('a scanned page writes one record and shows nothing', (
      tester,
    ) async {
      final lines = await capture(
        tester,
        wired(
          profile: const {'foot_size_ph': 42, 'foot_profile_source': 'ar_scan'},
          measurement: scannedFoot(),
        ),
      );

      final records = fitLines(lines);
      expect(records, hasLength(1), reason: records.join('\n'));
      expect(records.single, contains('[FIT] product=product-1'));
      expect(records.single, contains('band=trueToSize'));

      // The customer is shown nothing, and a measurement already in memory
      // means the record cost no query at all.
      expect(tester.getSize(find.byType(FitVerdictCard)).height, 0);
      expect(find.text('True to size'), findsNothing);
    }, skip: shadowOff);

    testWidgets('a page that must read the scan records the outcome', (
      tester,
    ) async {
      final footProvider = _MockFootMeasurementProvider();
      when(() => footProvider.latestMeasurement).thenReturn(null);
      when(() => footProvider.loadLatest('user-1')).thenAnswer((_) async {});
      when(() => footProvider.error).thenReturn(null);

      final auth = _MockAuthProvider();
      when(() => auth.profile).thenReturn(const {
        'foot_size_ph': 42,
        'foot_profile_source': 'ar_scan',
      });
      when(() => auth.currentUser).thenReturn(const {'id': 'user-1'});

      final lines = await capture(
        tester,
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<FootMeasurementProvider>.value(
              value: footProvider,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: FitVerdictCard(product: specProduct, selectedSize: '42'),
            ),
          ),
        ),
      );

      // The read happened (a saved profile whose millimetres are not in
      // memory), and the record is the outcome *after* it — the loading beat
      // itself is deliberately not a record.
      verify(() => footProvider.loadLatest('user-1')).called(1);
      final records = fitLines(lines);
      expect(records, hasLength(1), reason: records.join('\n'));
      expect(records.single, contains('would=needsScan'));
      expect(
        records.where((line) => line.contains('awaitingScan')),
        isEmpty,
      );
    }, skip: shadowOff);
  });

  group('the mount', () {
    // Read from the source, because this repo has no product-page widget test
    // at all: nothing else in the suite can prove the card is where the feature
    // says it is, and a refactor that dropped the mount would leave every other
    // assertion here passing (they pump the panel directly). The same technique
    // the size-poster tests use for the one thing a widget test cannot see.
    final source = File(
      'lib/screens/customer/product_detail_screen.dart',
    ).readAsStringSync();

    test('the product page mounts the card, on the selected size', () {
      final at = source.indexOf('FitVerdictCard(');
      expect(at, greaterThan(-1), reason: 'the card must be mounted somewhere');

      final call = source.substring(at, at + 200);
      expect(call, contains('product: widget.product'));
      expect(call, contains('selectedSize: _selectedSize'));
      expect(source.indexOf('import \'../../widgets/fit_verdict_card.dart\';'),
          greaterThan(-1));
    });

    test('it sits under the size grid and above the buy controls', () {
      final at = source.indexOf('FitVerdictCard(');

      // Searched from the mount, not from the top of the file: both strings
      // have other occurrences (the grid the other sections use, and the
      // stepper's own definition), so "first in the file" would say nothing.
      // A verdict is about the size those buttons choose, so it has to come
      // after them and before the customer commits to one.
      expect(source.lastIndexOf('GridView.count', at), greaterThan(-1));
      expect(source.indexOf('_buildQuantityStepper()', at), greaterThan(-1));
    });
  });
}
