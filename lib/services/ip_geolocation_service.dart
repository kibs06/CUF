import 'dart:convert';
import 'dart:io' show HttpClient;

import 'package:flutter/foundation.dart';

/// Where an IP address roughly is — the attacker's side of a lockout.
///
/// ⚠️ **This is city-level, and the type says so rather than implying
/// otherwise.** An IP address is allocated to a network, not to a person: the
/// lookup resolves to the city the address block is registered in (a carrier
/// hub, a data-centre town, the ISP's catchment), which is why the platform
/// shows a place name and a coordinate pair and never a street address. A
/// mobile carrier's pool can land a device in a different city from the one it
/// is physically in, sometimes a different region — the coordinates are the
/// centroid of the resolved city, not a device position. Nothing here may be
/// presented to a customer or an admin as "this is where they are".
class IpLocation {
  final String? city;
  final String? region;
  final String? country;

  /// City-centroid coordinates from the lookup, or null when it did not
  /// report a pair.
  final double? latitude;
  final double? longitude;

  /// The network the address belongs to, when the lookup names it: the ISP
  /// (e.g. `Globe Telecom Inc.`) and its ASN (`AS132199`). On a lockout this
  /// is often more useful than the city — a carrier or a hosting provider
  /// says more about who is on the other end than a place name does.
  final String? isp;
  final int? asn;

  const IpLocation({
    this.city,
    this.region,
    this.country,
    this.latitude,
    this.longitude,
    this.isp,
    this.asn,
  });

  /// Parses an `ipwho.is` lookup body. Tolerant by design: this runs inside
  /// the login flow, so a missing or oddly-typed field must degrade to "not
  /// known" rather than throw.
  factory IpLocation.fromJson(Map<String, dynamic> json) => IpLocation(
    city: _textOrNull(json['city']),
    region: _textOrNull(json['region']),
    country: _textOrNull(json['country']),
    latitude: _doubleOrNull(json['latitude']),
    longitude: _doubleOrNull(json['longitude']),
    isp: _textOrNull(json['connection'] is Map
        ? (json['connection'] as Map)['isp']
        : null),
    asn: _intOrNull(
      json['connection'] is Map ? (json['connection'] as Map)['asn'] : null,
    ),
  );

  /// `Manila, National Capital Region, Philippines` — the parts that are
  /// known, in the order a person reads them, with a repeated name dropped
  /// (`Singapore, Singapore` is one place, not two).
  String get place {
    final parts = <String>[];
    for (final part in [city, region, country]) {
      final value = part?.trim() ?? '';
      if (value.isEmpty) continue;
      if (parts.isNotEmpty &&
          parts.last.toLowerCase() == value.toLowerCase()) {
        continue;
      }
      parts.add(value);
    }
    return parts.join(', ');
  }

  /// The coordinates for this location, or '' when the lookup gave no pair.
  String get coordinates => formatCoordinates(latitude, longitude);

  /// `14.6042° N, 120.9822° E`, or '' when either half is missing.
  ///
  /// Static because the pair is also read back from `failed_logins` (the
  /// admin's intruder view) where there is no lookup result to hang the
  /// formatting off. Four decimals because that is how the lookup reports it
  /// and rounding it further would be its own kind of lie — the honest caveat
  /// is the "city level" label next to it, not a shorter number.
  static String formatCoordinates(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return '';
    final lat = '${latitude.abs().toStringAsFixed(4)}° '
        '${latitude >= 0 ? 'N' : 'S'}';
    final lon = '${longitude.abs().toStringAsFixed(4)}° '
        '${longitude >= 0 ? 'E' : 'W'}';
    return '$lat, $lon';
  }

  /// `Globe Telecom Inc. (AS132199)`, or ''.
  String get network {
    final name = isp?.trim() ?? '';
    if (name.isEmpty) return asn == null ? '' : 'AS$asn';
    return asn == null ? name : '$name (AS$asn)';
  }

  /// True when the lookup produced anything worth showing.
  bool get hasAnything =>
      place.isNotEmpty || coordinates.isNotEmpty || network.isNotEmpty;

  /// Only a String is a place name. A number or a map in this position is
  /// nonsense from the lookup, and "42" is worse than nothing on a security
  /// alert — the card would show it as the city the attempt came from.
  static String? _textOrNull(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static double? _doubleOrNull(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static int? _intOrNull(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

/// Turns an IP address into an approximate [IpLocation].
///
/// The lookup is a single keyless HTTPS GET (`ipwho.is`, 1,000 requests/day
/// per client IP, commercial use allowed on the free endpoint). It is
/// **best-effort in every direction**: no network, a rate limit, a malformed
/// body or a timeout all return null, because this runs on the failing side of
/// a login attempt and may never make the lockout itself fail or stall.
///
/// It is deliberately called with the address the app already resolved (see
/// `AuthProvider._collectDeviceInfo`) instead of asking the service "where am
/// I" — one address, one lookup, and the coordinates stored are the ones
/// belonging to the IP the app recorded.
class IpGeolocationService {
  IpGeolocationService({
    Future<String?> Function(Uri uri)? fetcher,
    this.timeout = const Duration(seconds: 3),
  }) : _fetcher = fetcher ?? _httpGet;

  /// Swappable for tests; the default is a plain HTTPS GET.
  static IpGeolocationService instance = IpGeolocationService();

  final Future<String?> Function(Uri uri) _fetcher;
  final Duration timeout;

  static const host = 'ipwho.is';

  /// The lookup for [ipAddress], or null when there is nothing usable to
  /// show.
  Future<IpLocation?> lookup(String ipAddress) async {
    final ip = ipAddress.trim();
    if (ip.isEmpty) return null;

    try {
      final body = await _fetcher(
        Uri.https(host, '/$ip'),
      ).timeout(timeout);
      if (body == null || body.trim().isEmpty) return null;

      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      // `success: false` carries a `message` instead of the data (e.g.
      // "reserved range" for a private address).
      if (decoded['success'] == false) return null;

      final location = IpLocation.fromJson(Map<String, dynamic>.from(decoded));
      return location.hasAnything ? location : null;
    } catch (e) {
      debugPrint('[IpGeolocation] could not locate $ip: $e');
      return null;
    }
  }

  static Future<String?> _httpGet(Uri uri) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) return null;
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }
}
