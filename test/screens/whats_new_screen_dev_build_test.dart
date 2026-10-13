import 'dart:convert';

import 'package:app/providers/update_provider.dart';
import 'package:app/screens/shared/whats_new_screen.dart';
import 'package:app/services/update_checker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockHttpClient extends Mock implements http.Client {}

/// What's New is where someone goes to update by hand, so it is the surface that
/// has to *explain* a development build rather than offer a ~220 MB download
/// Android will refuse to install — the running copy carries the machine-local
/// debug key, and the installer reports the refusal as a bare "App not
/// installed."
///
/// `flutter test` compiles in debug mode, so this file is that build.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockHttpClient mockClient;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com/version.json'));
  });

  setUp(() {
    mockClient = MockHttpClient();
    SharedPreferences.setMockInitialValues({});
  });

  /// A provider that has already seen a newer release, so the banner renders.
  Future<UpdateProvider> providerWithUpdateAvailable() async {
    final provider = UpdateProvider(
      service: UpdateCheckerService(
        client: mockClient,
        installedVersionReader: () async => '1.0.53',
      ),
    );
    when(() => mockClient.get(any())).thenAnswer(
      (_) async => http.Response(
        jsonEncode({
          'latest_version': '1.0.54',
          'apk_url': 'https://example.com/app-release-1.0.54.apk',
          'released_at': '2026-10-13',
          'notes': ['A newer build is out'],
        }),
        200,
      ),
    );
    await provider.checkForUpdate();
    return provider;
  }

  testWidgets('the banner explains instead of offering the download',
      (tester) async {
    final provider = await providerWithUpdateAvailable();
    // Guard the guard: if no update were available the banner would not be on
    // screen and the assertions below would pass for the wrong reason.
    expect(provider.latestUpdate, isNotNull);

    await tester.pumpWidget(
      ChangeNotifierProvider<UpdateProvider>.value(
        value: provider,
        child: const MaterialApp(home: WhatsNewScreen()),
      ),
    );
    await tester.pump();

    // The release is still announced — the guard withholds an action, not news.
    expect(find.textContaining('1.0.54'), findsWidgets);

    // Neither download action is offered. The browser link matters as much as
    // the button: it fetches the same APK with the same signature and fails
    // identically, so leaving it would spend the same ~220 MB to reach the same
    // dead end.
    expect(find.textContaining('Download v1.0.54'), findsNothing);
    expect(find.textContaining('Download via browser'), findsNothing);

    // Instead, the reason — the cause and the way out.
    expect(find.textContaining('cannot install a release APK'), findsOneWidget);
    expect(find.textContaining('flutter run --release'), findsOneWidget);
  });
}
