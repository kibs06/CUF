import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/providers/auth_provider.dart';
import 'package:app/providers/theme_provider.dart';
import 'package:app/providers/update_provider.dart';
import 'package:app/screens/shared/settings_screen.dart';
import 'package:app/services/theme_service.dart';

/// The Appearance section of Settings — the only place a user chooses between
/// System / Light / Dark, so the row has to reach both the provider and disk.
///
/// `AuthProvider`/`UpdateProvider` are mocked rather than constructed: the
/// real `AuthProvider` restores a Supabase session in its constructor, and
/// this suite runs without a Supabase instance.
class _MockAuthProvider extends Mock with ChangeNotifier implements AuthProvider {}

class _MockUpdateProvider extends Mock
    with ChangeNotifier
    implements UpdateProvider {}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ThemeProvider> pumpSettings(
    WidgetTester tester, {
    ThemeMode initial = ThemeMode.system,
  }) async {
    final update = _MockUpdateProvider();
    when(() => update.installedVersion).thenReturn(null);
    when(() => update.hasUnviewedUpdate).thenReturn(false);

    final provider = ThemeProvider(initialMode: initial);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: _MockAuthProvider()),
          ChangeNotifierProvider<UpdateProvider>.value(value: update),
          ChangeNotifierProvider<ThemeProvider>.value(value: provider),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    return provider;
  }

  testWidgets('the row exists and spells out what System currently means',
      (tester) async {
    await pumpSettings(tester);

    expect(find.text('Appearance'), findsOneWidget); // section header
    expect(find.text('Theme'), findsOneWidget);
    // Explicit, not a bare "System": the test platform brightness is light.
    expect(find.text('System · Light (device)'), findsOneWidget);
  });

  testWidgets('the row reports a pinned mode without the device suffix',
      (tester) async {
    await pumpSettings(tester, initial: ThemeMode.dark);

    expect(find.text('Dark'), findsOneWidget);
    expect(find.textContaining('device'), findsNothing);
  });

  testWidgets('picking Dark applies it, persists it and updates the row',
      (tester) async {
    final provider = await pumpSettings(tester);

    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();

    // All three choices are offered — an on/off switch would silently stop
    // following the device, which is what most people want.
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(provider.mode, ThemeMode.dark);
    expect(find.text('Dark'), findsOneWidget); // the row's new subtitle
    expect(await ThemeService.instance.load(), ThemeMode.dark);
  });

  testWidgets('a saved choice is what the row shows after a relaunch',
      (tester) async {
    await ThemeService.instance.save(ThemeMode.light);

    // What main() does before runApp.
    final restored = await ThemeService.instance.load();
    final provider = await pumpSettings(tester, initial: restored);

    expect(provider.mode, ThemeMode.light);
    expect(find.text('Light'), findsOneWidget);
  });
}
