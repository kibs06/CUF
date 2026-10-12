import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/ip_geolocation_service.dart';

/// The real body `ipwho.is` returned for a Philippine mobile address, measured
/// 2026-10-12. Kept verbatim rather than trimmed to the fields this reads, so
/// the parser is exercised against what the service actually sends — including
/// the nesting (`connection.isp`) and the `readme` key.
const String _manilaBody =
    '{"ip":"112.198.115.20","success":true,"type":"IPv4",'
    '"continent":"Asia","continent_code":"AS","country":"Philippines",'
    '"country_code":"PH","region":"National Capital Region","region_code":"00",'
    '"city":"Manila","latitude":14.6042286,"longitude":120.9822266,'
    '"is_eu":false,"postal":"1001","calling_code":"63","capital":"Manila",'
    '"borders":"","connection":{"asn":132199,"org":"GLOBE-WIMAX-IP-POOL",'
    '"isp":"Globe Telecom Inc.","domain":"globe.com.ph"},'
    '"timezone":{"id":"Asia/Manila","abbr":"PST","is_dst":false,'
    '"offset":28800,"utc":"+08:00"},"readme":"https://ipwhois.io/docs"}';

void main() {
  group('IpLocation — reading a lookup body', () {
    test('names the place, the city centroid and the network', () {
      final location = IpLocation.fromJson({
        'success': true,
        'country': 'Philippines',
        'region': 'National Capital Region',
        'city': 'Manila',
        'latitude': 14.6042286,
        'longitude': 120.9822266,
        'connection': {'asn': 132199, 'isp': 'Globe Telecom Inc.'},
      });

      expect(location.place, 'Manila, National Capital Region, Philippines');
      expect(location.coordinates, '14.6042° N, 120.9822° E');
      expect(location.network, 'Globe Telecom Inc. (AS132199)');
      expect(location.hasAnything, isTrue);
    });

    test('a repeated name is one place, not two', () {
      final location = IpLocation.fromJson({
        'city': 'Singapore',
        'region': 'Singapore',
        'country': 'Singapore',
      });

      expect(location.place, 'Singapore');
    });

    test('reports only the parts that are known', () {
      expect(IpLocation.fromJson({'country': 'Japan'}).place, 'Japan');
      expect(
        IpLocation.fromJson({'country': 'Japan', 'city': 'Osaka'}).place,
        'Osaka, Japan',
      );
      expect(IpLocation.fromJson({}).place, '');
    });

    test('southern and western coordinates carry the right hemisphere', () {
      final sydney = IpLocation.fromJson({
        'latitude': -33.8678,
        'longitude': 151.2073,
      });
      expect(sydney.coordinates, '33.8678° S, 151.2073° E');

      final lima = IpLocation.fromJson({
        'latitude': -12.0464,
        'longitude': -77.0428,
      });
      expect(lima.coordinates, '12.0464° S, 77.0428° W');
    });

    test('half a coordinate pair is no coordinate pair', () {
      expect(IpLocation.fromJson({'latitude': 14.6042}).coordinates, '');
      expect(IpLocation.fromJson({'longitude': 120.9822}).coordinates, '');
    });

    test('falls back to the ASN when the network is unnamed', () {
      expect(
        IpLocation.fromJson({
          'connection': {'asn': 9299},
        }).network,
        'AS9299',
      );
      expect(IpLocation.fromJson({'connection': {}}).network, '');
      expect(IpLocation.fromJson({}).network, '');
    });

    test('tolerates a coordinate sent as a string, and junk in its place', () {
      // PostgREST hands back `double precision` as a JSON number, but a value
      // that has been through ::text upstream arrives as a string.
      final fromString = IpLocation.fromJson({
        'latitude': '14.6042',
        'longitude': '120.9822',
      });
      expect(fromString.coordinates, '14.6042° N, 120.9822° E');

      final junk = IpLocation.fromJson({
        'city': 42,
        'region': ['not', 'a', 'place'],
        'latitude': 'north-ish',
        'longitude': null,
      });
      expect(junk.coordinates, '');
      // A number where a place name belongs is not a place name. "42" on a
      // security alert would read as a city the attempt came from.
      expect(junk.place, '');
      expect(junk.hasAnything, isFalse);
    });

    test('an empty document knows nothing rather than guessing', () {
      final nothing = IpLocation.fromJson({});
      expect(nothing.place, '');
      expect(nothing.coordinates, '');
      expect(nothing.network, '');
      expect(nothing.hasAnything, isFalse);
    });
  });

  group('IpGeolocationService.lookup', () {
    test('asks ipwho.is over HTTPS for exactly the address given', () async {
      Uri? asked;
      final service = IpGeolocationService(
        fetcher: (uri) async {
          asked = uri;
          return _manilaBody;
        },
      );

      final location = await service.lookup('112.198.115.20');

      // HTTPS, not HTTP: the app's network security config permits cleartext
      // to loopback only, so a plain-http lookup would fail on every device.
      expect(asked!.scheme, 'https');
      expect(asked!.host, IpGeolocationService.host);
      expect(asked!.path, '/112.198.115.20');
      expect(location!.place, 'Manila, National Capital Region, Philippines');
      expect(location.coordinates, '14.6042° N, 120.9822° E');
      expect(location.network, 'Globe Telecom Inc. (AS132199)');
    });

    test('trims the address before asking', () async {
      Uri? asked;
      final service = IpGeolocationService(
        fetcher: (uri) async {
          asked = uri;
          return _manilaBody;
        },
      );

      await service.lookup('  112.198.115.20  ');

      expect(asked!.path, '/112.198.115.20');
    });

    test('a refused lookup is null, not a thrown error', () async {
      final service = IpGeolocationService(
        fetcher: (_) async =>
            '{"ip":"10.0.0.1","success":false,"message":"Reserved range"}',
      );

      expect(await service.lookup('10.0.0.1'), isNull);
    });

    test('an empty, non-JSON or non-object body is null', () async {
      for (final body in <String?>['', '   ', 'not json at all', '[]']) {
        final service = IpGeolocationService(fetcher: (_) async => body);
        expect(await service.lookup('112.198.115.20'), isNull, reason: '$body');
      }
    });

    test('a body with nothing usable in it is null, not an empty card',
        () async {
      final service = IpGeolocationService(
        fetcher: (_) async => '{"ip":"112.198.115.20","success":true}',
      );

      expect(await service.lookup('112.198.115.20'), isNull);
    });

    test('a transport failure is null — it must never fail the lockout',
        () async {
      final service = IpGeolocationService(
        fetcher: (_) => Future<String?>.error(Exception('socket closed')),
      );

      expect(await service.lookup('112.198.115.20'), isNull);
    });

    test('a lookup that hangs is abandoned at the timeout', () async {
      final service = IpGeolocationService(
        fetcher: (_) => Completer<String?>().future,
        timeout: const Duration(milliseconds: 20),
      );

      expect(await service.lookup('112.198.115.20'), isNull);
    });

    test('a blank address is not looked up at all', () async {
      var asked = 0;
      final service = IpGeolocationService(
        fetcher: (_) async {
          asked++;
          return _manilaBody;
        },
      );

      expect(await service.lookup(''), isNull);
      expect(await service.lookup('   '), isNull);
      // A lookup with no address would answer with the position of whatever
      // host ran it — the one thing this must never record as the attacker's.
      expect(asked, 0);
    });
  });
}
