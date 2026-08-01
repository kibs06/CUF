import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/models/update_info.dart';
import 'package:app/services/update_checker.dart';

void main() {
  setUp(() {
    // Reset the SharedPreferences cache between tests.
    SharedPreferences.setMockInitialValues({});
  });

  group('compareVersions', () {
    test('detects newer semantic versions', () {
      expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
      expect(compareVersions('2.0.0', '1.99.99'), greaterThan(0));
      expect(compareVersions('1.4.1', '1.4.0'), greaterThan(0));
    });

    test('detects older semantic versions', () {
      expect(compareVersions('1.9.0', '1.10.0'), lessThan(0));
      expect(compareVersions('1.0.0', '1.0.1'), lessThan(0));
    });

    test('handles equal versions and build metadata', () {
      expect(compareVersions('1.4.0', '1.4.0'), 0);
      expect(compareVersions('1.4.0+3', '1.4.0'), 0);
      expect(compareVersions('1.4.0-beta', '1.4.0'), 0);
    });

    test('handles differing segment counts', () {
      expect(compareVersions('1.4', '1.4.0'), 0);
      expect(compareVersions('1.4.0.1', '1.4.0'), greaterThan(0));
    });

    test('is not fooled by string ordering', () {
      // String comparison would say "1.9.0" > "1.10.0" — numeric must not.
      expect('1.9.0'.compareTo('1.10.0'), greaterThan(0)); // proof string is wrong
      expect(compareVersions('1.9.0', '1.10.0'), lessThan(0)); // numeric is right
    });
  });

  group('UpdateInfo', () {
    test('parses full manifest JSON', () {
      final info = UpdateInfo.fromJson({
        'latest_version': '1.4.0',
        'apk_url': 'https://example.com/app-release-1.4.0.apk',
        'released_at': '2026-08-01',
        'notes': ['Fixed login crash', 'Improved startup time'],
      });

      expect(info.version, '1.4.0');
      expect(info.apkUrl, 'https://example.com/app-release-1.4.0.apk');
      expect(info.releasedAt, DateTime(2026, 8, 1));
      expect(info.notes, ['Fixed login crash', 'Improved startup time']);
    });

    test('handles missing optional fields', () {
      final info = UpdateInfo.fromJson({'latest_version': '1.4.0'});

      expect(info.version, '1.4.0');
      expect(info.apkUrl, isEmpty);
      expect(info.releasedAt, isNull);
      expect(info.notes, isEmpty);
    });

    test('supports changelog entries via latest_version key', () {
      final info = UpdateInfo.fromJson({'latest_version': '1.3.2'});
      expect(info.version, '1.3.2');
    });
  });

  group('UpdateCheckerService', () {
    test('returns update when hosted version is newer', () async {
      final service = UpdateCheckerService(
        client: MockClient((request) async {
          expect(request.url.path, endsWith('version.json'));
          return http.Response(
            jsonEncode({
              'latest_version': '1.4.0',
              'apk_url': 'https://example.com/app-release-1.4.0.apk',
              'released_at': '2026-08-01',
              'notes': ['Fixed login crash'],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        installedVersionReader: () async => '1.3.2',
      );

      final update = await service.checkForUpdate();
      expect(update, isNotNull);
      expect(update!.version, '1.4.0');
      expect(update.apkUrl, 'https://example.com/app-release-1.4.0.apk');
    });

    test('returns null when installed version equals hosted version', () async {
      final service = UpdateCheckerService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({'latest_version': '1.3.2'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        installedVersionReader: () async => '1.3.2',
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('returns null when installed version is newer', () async {
      final service = UpdateCheckerService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({'latest_version': '1.3.2'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        installedVersionReader: () async => '1.4.0',
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('handles multi-digit minor versions (1.10 vs 1.9)', () async {
      final service = UpdateCheckerService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({'latest_version': '1.10.0'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        installedVersionReader: () async => '1.9.0',
      );

      final update = await service.checkForUpdate();
      expect(update, isNotNull);
      expect(update!.version, '1.10.0');
    });

    test('fails silently on HTTP error', () async {
      final service = UpdateCheckerService(
        client: MockClient((request) async => http.Response('nope', 500)),
        installedVersionReader: () async => '1.0.0',
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('fails silently on malformed JSON', () async {
      final service = UpdateCheckerService(
        client: MockClient((request) async => http.Response('not json', 200)),
        installedVersionReader: () async => '1.0.0',
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('fails silently on network exception', () async {
      final service = UpdateCheckerService(
        client: MockClient((request) async => throw Exception('no internet')),
        installedVersionReader: () async => '1.0.0',
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('fails silently when installed version cannot be read', () async {
      final service = UpdateCheckerService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({'latest_version': '1.4.0'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        installedVersionReader: () async => null,
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('fetches changelog list newest first', () async {
      final service = UpdateCheckerService(
        client: MockClient((request) async {
          expect(request.url.path, endsWith('changelog.json'));
          return http.Response(
            jsonEncode([
              {
                'latest_version': '1.4.0',
                'released_at': '2026-08-01',
                'notes': ['A'],
              },
              {
                'latest_version': '1.3.2',
                'released_at': '2026-07-20',
                'notes': ['B'],
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final changelog = await service.fetchChangelog();
      expect(changelog.length, 2);
      expect(changelog.first.version, '1.4.0');
      expect(changelog.last.version, '1.3.2');
    });

    test('throws on changelog HTTP error (so UI can show error + retry)', () async {
      final service = UpdateCheckerService(
        client: MockClient((request) async => http.Response('nope', 404)),
      );

      expect(service.fetchChangelog(), throwsException);
    });

    test('throws on non-list changelog JSON', () async {
      final service = UpdateCheckerService(
        client: MockClient(
          (request) async => http.Response('{"not": "a list"}', 200),
        ),
      );

      expect(service.fetchChangelog(), throwsException);
    });

    test('fetchLatestUpdate throws on manifest HTTP error', () async {
      final service = UpdateCheckerService(
        client: MockClient((request) async => http.Response('nope', 500)),
        installedVersionReader: () async => '1.0.0',
      );

      expect(service.fetchLatestUpdate(), throwsException);
    });

    test('fetchLatestUpdate returns null when up to date', () async {
      final service = UpdateCheckerService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({'latest_version': '1.3.2'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        installedVersionReader: () async => '1.3.2',
      );

      expect(await service.fetchLatestUpdate(), isNull);
    });

    test('serves fresh cache without hitting the network', () async {
      // Pre-seed a fresh cache.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        UpdateCheckerService.changelogCacheKey,
        jsonEncode([
          {'latest_version': '1.4.0', 'notes': ['cached note']},
        ]),
      );
      await prefs.setString(
        UpdateCheckerService.changelogCacheTimeKey,
        DateTime.now().toIso8601String(),
      );

      // Network must NOT be called for a fresh cache.
      final service = UpdateCheckerService(
        client: MockClient((request) async {
          throw StateError('network should not be called');
        }),
      );

      final changelog = await service.fetchChangelog();
      expect(changelog.length, 1);
      expect(changelog.first.version, '1.4.0');
      expect(changelog.first.notes, ['cached note']);
    });

    test('refetches when cache is stale', () async {
      // Pre-seed a stale cache (older than the 24h TTL).
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        UpdateCheckerService.changelogCacheKey,
        jsonEncode([{'latest_version': '1.3.0'}]),
      );
      await prefs.setString(
        UpdateCheckerService.changelogCacheTimeKey,
        DateTime.now()
            .subtract(const Duration(hours: 48))
            .toIso8601String(),
      );

      final service = UpdateCheckerService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode([{'latest_version': '1.4.0'}]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final changelog = await service.fetchChangelog();
      expect(changelog.length, 1);
      expect(changelog.first.version, '1.4.0'); // fresh data, not 1.3.0
    });

    test('falls back to stale cache when offline', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        UpdateCheckerService.changelogCacheKey,
        jsonEncode([{'latest_version': '1.4.0'}]),
      );
      await prefs.setString(
        UpdateCheckerService.changelogCacheTimeKey,
        DateTime.now()
            .subtract(const Duration(days: 5))
            .toIso8601String(),
      );

      final service = UpdateCheckerService(
        client: MockClient((request) async => throw Exception('no internet')),
      );

      final changelog = await service.fetchChangelog();
      expect(changelog.length, 1);
      expect(changelog.first.version, '1.4.0');
    });

    test('throws when offline and no cache exists', () async {
      final service = UpdateCheckerService(
        client: MockClient((request) async => throw Exception('no internet')),
      );

      expect(service.fetchChangelog(), throwsException);
    });

    test('writes fetched changelog to cache for next time', () async {
      final service = UpdateCheckerService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode([{'latest_version': '1.4.0'}]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await service.fetchChangelog();

      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(UpdateCheckerService.changelogCacheKey);
      expect(cached, isNotNull);
      expect(
        prefs.getString(UpdateCheckerService.changelogCacheTimeKey),
        isNotNull,
      );
    });

    test('decodes non-ASCII release notes as UTF-8', () async {
      // raw.githubusercontent.com serves JSON as text/plain without a charset,
      // so the body must be decoded from bytes as UTF-8 (response.body would
      // fall back to latin-1 and garble these notes).
      const note = '🎉 Fixed crash \u2014 m\u00e1s r\u00e1pido';
      final service = UpdateCheckerService(
        client: MockClient((request) async {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode([{'latest_version': '1.4.0', 'notes': [note]}]),
            ),
            200,
          );
        }),
      );

      final changelog = await service.fetchChangelog();
      expect(changelog.first.notes.single, note);
    });
  });
}
