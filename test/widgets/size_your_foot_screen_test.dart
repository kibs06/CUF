import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:app/providers/auth_provider.dart';
import 'package:app/screens/customer/size_your_foot_screen.dart';

/// `Size Your Foot` is ONE settings entry with two swipable panels: the AR
/// scan (Foot Size 2.0 — the landing panel) and manual entry. The tests pin
/// the landing panel, the indicator that names which panel is showing, and
/// that both the indicator and the swipe switch panels.
///
/// The scan panel asks for camera permission as it mounts, so the
/// permission_handler channel is mocked rather than left to throw
/// MissingPluginException.
class _MockAuthProvider extends Mock with ChangeNotifier implements AuthProvider {}

const _permissionsChannel = MethodChannel('flutter.baseflow.com/permissions/methods');

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permissionsChannel, (call) async {
      if (call.method == 'checkPermissionStatus' ||
          call.method == 'requestPermissions') {
        return 1; // PermissionStatus.granted
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permissionsChannel, null);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _MockAuthProvider(),
        child: const MaterialApp(home: SizeYourFootScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// fling (not drag): a slow half-width drag has no velocity and snaps back
  /// to the page it started on.
  Future<void> swipe(WidgetTester tester, double dx) async {
    await tester.fling(find.byType(PageView), Offset(dx, 0), 1000);
    await tester.pumpAndSettle();
  }

  testWidgets('lands on the scan panel and names both panels above it',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Size Your Foot'), findsOneWidget);
    // The indicator above the panels.
    expect(find.text('Scan with camera'), findsOneWidget);
    expect(find.text('Enter size manually'), findsOneWidget);

    // Landing panel is the scan (Foot Size 2.0 setup), not the manual picker.
    // Its section label is rendered uppercased by the v2 setup screen.
    expect(find.text('WHAT TO EXPECT'), findsOneWidget);
    expect(find.text('Save my size'), findsNothing);
  });

  testWidgets('tapping the indicator switches to the manual panel',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Enter size manually'));
    await tester.pumpAndSettle();

    expect(find.text('Save my size'), findsOneWidget);
    expect(find.text('Enter your size'), findsOneWidget);
    // The shopping scale the customer picks here (the scan panel is gone, so
    // these chips can only belong to the manual panel).
    expect(find.text('SHOPPING SIZE'), findsOneWidget);
    expect(find.text("Women's"), findsOneWidget);
    expect(find.text('WHAT TO EXPECT'), findsNothing);
    expect(find.text('Start scanning'), findsNothing);
  });

  testWidgets('swiping also switches panels, both ways', (tester) async {
    await pumpScreen(tester);

    await swipe(tester, -400);
    expect(find.text('Save my size'), findsOneWidget);

    await swipe(tester, 400);
    expect(find.text('WHAT TO EXPECT'), findsOneWidget);
    expect(find.text('Save my size'), findsNothing);
  });

  testWidgets('tapping the active panel again is a no-op', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Scan with camera'));
    await tester.pumpAndSettle();

    expect(find.text('WHAT TO EXPECT'), findsOneWidget);
  });
}
