import 'dart:convert';

import 'package:app/providers/update_provider.dart';
import 'package:app/services/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockHttpClient mockClient;
  late UpdateProvider provider;

  void stubManifest(Map<String, dynamic> json) {
    when(() => mockClient.get(any())).thenAnswer(
      (_) async => http.Response(jsonEncode(json), 200),
    );
  }

  setUp(() {
    mockClient = MockHttpClient();
    SharedPreferences.setMockInitialValues({});
    provider = UpdateProvider(
      service: UpdateCheckerService(
        client: mockClient,
        installedVersionReader: () async => '1.0.20',
      ),
    );
  });

  setUpAll(() {
    // mocktail needs a fallback value for any(Uri) in sound null safety.
    registerFallbackValue(Uri.parse('https://example.com/version.json'));
  });

  group('emulator gating of the update overlay', () {
    test('real device: shouldShowUpdateOverlay is true when newer release exists',
        () async {
      provider.setEmulatorForTesting(false);
      stubManifest({
        'latest_version': '1.0.22',
        'apk_url': 'https://example.com/app-release-1.0.22.apk',
        'released_at': '2026-09-05',
        'notes': ['T5 fix'],
      });

      await provider.checkForUpdate();

      expect(provider.latestUpdate, isNotNull);
      expect(provider.isEmulator, isFalse);
      expect(provider.shouldShowUpdateOverlay, isTrue);
    });

    test('emulator: shouldShowUpdateOverlay is false (info still loads)',
        () async {
      provider.setEmulatorForTesting(true);
      stubManifest({
        'latest_version': '1.0.22',
        'apk_url': 'https://example.com/app-release-1.0.22.apk',
        'released_at': '2026-09-05',
        'notes': ['T5 fix'],
      });

      await provider.checkForUpdate();

      // Release info is still fetched — What's New still shows it.
      expect(provider.latestUpdate, isNotNull);
      expect(provider.isEmulator, isTrue);
      // …but the intrusive overlay is suppressed.
      expect(provider.shouldShowUpdateOverlay, isFalse);
    });

    test('emulator: no update when already on latest', () async {
      provider.setEmulatorForTesting(true);
      stubManifest({
        'latest_version': '1.0.20',
        'apk_url': 'https://example.com/app-release-1.0.20.apk',
      });

      await provider.checkForUpdate();

      expect(provider.latestUpdate, isNull);
      expect(provider.shouldShowUpdateOverlay, isFalse);
    });
  });
}
