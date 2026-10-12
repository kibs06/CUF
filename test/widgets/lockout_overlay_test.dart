import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/widgets/lockout_overlay.dart';

const String _place = 'Manila, National Capital Region, Philippines';
const String _coordinates = '14.6042° N, 120.9822° E';
const String _network = 'Globe Telecom Inc. (AS132199)';
const String _device = 'Globe Telecom TCL (Android 14)';
const String _ip = '112.198.115.20';

/// The sentence that keeps "we know where they are" from being the reading:
/// the card states what the data actually is, next to the data.
const String _cityLevelCaveat =
    'Location comes from the IP address, so it is city-level — '
    'not a street address.';

Widget _harness({
  String? location,
  String? coordinates,
  String? network,
  String? device = _device,
  String? ipAddress = _ip,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => LockoutOverlay.show(
              context,
              email: 'owner@cufmai.test',
              remainingMinutes: 30,
              device: device,
              ipAddress: ipAddress,
              location: location,
              coordinates: coordinates,
              network: network,
            ),
            child: const Text('Trigger'),
          ),
        ),
      ),
    ),
  );
}

/// Tap the trigger and settle the 300ms entrance transition.
Future<void> _showOverlay(WidgetTester tester, Widget harness) async {
  await tester.pumpWidget(harness);
  await tester.tap(find.text('Trigger'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

/// The card runs a one-second countdown, so `pumpAndSettle` would never
/// return, and on a short card the tertiary button can sit below the fold.
/// Tearing the tree down disposes the card — and cancels that timer with it.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets('shows where the attempts came from', (tester) async {
    await _showOverlay(
      tester,
      _harness(location: _place, coordinates: _coordinates, network: _network),
    );

    expect(find.text(_place), findsOneWidget);
    // The coordinate pair and the network share one line under the place.
    expect(find.text('$_coordinates · $_network'), findsOneWidget);
    // And the card says what that is, rather than letting a city read as an
    // address.
    expect(find.text(_cityLevelCaveat), findsOneWidget);

    await _close(tester);
  });

  testWidgets('keeps the device and the address next to the location',
      (tester) async {
    await _showOverlay(
      tester,
      _harness(location: _place, coordinates: _coordinates, network: _network),
    );

    expect(find.text(_device), findsOneWidget);
    expect(find.text(_ip), findsOneWidget);
    // The action the owner needs, unchanged by any of the above.
    expect(find.text('Reset password'), findsOneWidget);
    expect(find.text("This wasn't me"), findsOneWidget);

    await _close(tester);
  });

  testWidgets('a location without coordinates or a network still names it',
      (tester) async {
    await _showOverlay(tester, _harness(location: _place));

    expect(find.text(_place), findsOneWidget);
    expect(find.text(_coordinates), findsNothing);
    expect(find.text(_network), findsNothing);
    expect(find.text(_cityLevelCaveat), findsOneWidget);

    await _close(tester);
  });

  testWidgets('coordinates without a place name are still shown, and labelled',
      (tester) async {
    await _showOverlay(tester, _harness(coordinates: _coordinates));

    expect(find.text(_coordinates), findsOneWidget);
    expect(find.text(_cityLevelCaveat), findsOneWidget);

    await _close(tester);
  });

  testWidgets('no location means no location row and no caveat',
      (tester) async {
    await _showOverlay(tester, _harness());

    expect(find.text(_cityLevelCaveat), findsNothing);
    expect(find.text(_place), findsNothing);
    expect(find.text(_coordinates), findsNothing);
    // The evidence this overlay has always carried is still there.
    expect(find.text(_device), findsOneWidget);
    expect(find.text(_ip), findsOneWidget);

    await _close(tester);
  });

  testWidgets('no details at all still renders the actions', (tester) async {
    await _showOverlay(
      tester,
      _harness(device: null, ipAddress: null),
    );

    expect(find.text('Account temporarily locked'), findsOneWidget);
    expect(find.text('Reset password'), findsOneWidget);
    expect(find.text(_cityLevelCaveat), findsNothing);

    await _close(tester);
  });
}
