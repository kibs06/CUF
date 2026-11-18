import 'dart:convert';
import 'dart:io';

import 'package:geocoding/geocoding.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';

/// A place returned by the geocode-proxy's MapTiler reverse lookup, reduced
/// to the fields the delivery-address form and pin sheet need.
///
/// The device geocoder is only a fallback: on Android it frequently returns
/// a Plus Code (for example `5PRQ+5H9`) instead of a street/barangay, and
/// those codes are filtered out here rather than being written into the form.
class ReverseGeocodeResult {
  const ReverseGeocodeResult({
    required this.displayAddress,
    required this.region,
    required this.province,
    required this.city,
    required this.barangay,
    this.purok = '',
    required this.street,
  });

  /// Human-readable label for the pin sheet, e.g.
  /// `Inoburan, Naga, Cebu`.
  final String displayAddress;
  final String region;
  final String province;
  final String city;
  final String barangay;
  final String purok;
  final String street;

  bool get isEmpty =>
      displayAddress.isEmpty &&
      region.isEmpty &&
      province.isEmpty &&
      city.isEmpty &&
      barangay.isEmpty &&
      purok.isEmpty &&
      street.isEmpty;

  /// The label both map pickers show above their confirm button and store
  /// as the selected location: Purok, Barangay, City, Province when known;
  /// street/region only as a fallback.
  String get areaLabel {
    final area = [
      purok,
      barangay,
      city,
      province,
    ].where((part) => part.trim().isNotEmpty).toList();
    if (area.isNotEmpty) return area.join(', ');

    final fallback = [
      street,
      region,
    ].where((part) => part.trim().isNotEmpty).toList();
    if (fallback.isNotEmpty) return fallback.join(', ');
    return displayAddress;
  }

  /// Fills fields the primary result is missing from [fallback] without
  /// replacing anything MapTiler already provided.
  ReverseGeocodeResult mergedWith(ReverseGeocodeResult? fallback) {
    if (fallback == null) return this;
    String first(String a, String b) => a.isNotEmpty ? a : b;
    return ReverseGeocodeResult(
      displayAddress: first(displayAddress, fallback.displayAddress),
      region: first(region, fallback.region),
      province: first(province, fallback.province),
      city: first(city, fallback.city),
      barangay: first(barangay, fallback.barangay),
      purok: first(purok, fallback.purok),
      street: first(street, fallback.street),
    );
  }

  /// Builds the result from the proxy's normalized `place` object.
  ///
  /// MapTiler context ids carry a database suffix (`locality.46425`); the
  /// proxy strips it, but splitting again keeps this parser safe if the
  /// function is deployed without the normalization.
  factory ReverseGeocodeResult.fromPlace(Map<String, dynamic> place) {
    final context = <String, String>{};
    for (final item in (place['context'] as List? ?? const [])) {
      if (item is! Map) continue;
      final id = item['id']?.toString().split('.').first ?? '';
      final text = item['text']?.toString().trim() ?? '';
      if (id.isNotEmpty && text.isNotEmpty) {
        context.putIfAbsent(id, () => text);
      }
    }

    String pick(List<String> ids) {
      for (final id in ids) {
        final value = context[id];
        if (value != null && value.isNotEmpty) return value;
      }
      return '';
    }

    const cityTypes = {'locality', 'municipality', 'city', 'town'};
    const barangayTypes = {
      'neighborhood',
      'suburb',
      'quarter',
      'hamlet',
      'village',
    };
    const provinceTypes = {'county', 'subregion'};
    const regionTypes = {'region', 'state'};
    const adminTypes = {
      ...cityTypes,
      ...barangayTypes,
      ...provinceTypes,
      ...regionTypes,
      'country',
      'place',
    };

    final placeTypes = <String>{
      for (final type in (place['place_types'] as List? ?? const []))
        if (type != null) type.toString(),
    };
    final kind = place['kind']?.toString() ?? '';
    final featureText = _cleanPart(place['text']?.toString());
    final houseNumber = _cleanPart(place['house_number']?.toString());

    final isRoad =
        placeTypes.contains('road') ||
        placeTypes.contains('street') ||
        kind == 'road' ||
        kind == 'street';
    final isAddress = placeTypes.contains('address') || kind == 'address';

    var region = pick(['region', 'state']);
    var province = pick(['county', 'subregion', 'state']);
    var city = pick(['locality', 'municipality', 'city', 'town']);
    var barangay = pick([
      'neighborhood',
      'suburb',
      'quarter',
      'hamlet',
      'village',
    ]);
    // MapTiler labels many Philippine barangays as a generic "place" and
    // omits the city; use that as the barangay rather than losing it.
    final placeContext = context['place'] ?? '';
    if (barangay.isEmpty &&
        city.isEmpty &&
        placeContext.isNotEmpty &&
        placeContext != province &&
        placeContext != region) {
      barangay = placeContext;
    }

    // The feature itself may be the administrative area when the pin sits
    // on a place rather than inside one.
    if (region.isEmpty && placeTypes.any(regionTypes.contains)) {
      region = featureText;
    }
    if (province.isEmpty && placeTypes.any(provinceTypes.contains)) {
      province = featureText;
    }
    if (city.isEmpty && placeTypes.any(cityTypes.contains)) {
      city = featureText;
    }
    if (barangay.isEmpty && placeTypes.any(barangayTypes.contains)) {
      barangay = featureText;
    }

    final rawPlaceName = place['place_name']?.toString() ?? '';
    var purok = extractPurok([featureText, rawPlaceName, ...context.values]);
    // A feature can be the purok itself; move its parent into Barangay so
    // the two fields don't repeat the same value.
    if (purok.isNotEmpty && barangay.toLowerCase() == purok.toLowerCase()) {
      barangay = placeContext.toLowerCase() == purok.toLowerCase()
          ? ''
          : placeContext;
    }

    final street = (isRoad || isAddress) && featureText.isNotEmpty
        ? [houseNumber, featureText].where((part) => part.isNotEmpty).join(' ')
        : '';
    // A POI/building is useful context ("Naga City Hall, Naga, Cebu"), but
    // don't repeat a road/neighborhood that is already represented.
    final placeLabel =
        !isRoad && !isAddress && !placeTypes.any(adminTypes.contains)
        ? featureText
        : '';

    final composed = _joinDistinct([
      purok,
      street,
      if (placeLabel.isNotEmpty && !street.contains(placeLabel)) placeLabel,
      barangay,
      city,
      province,
    ]);
    final rawName = _cleanPlaceName(rawPlaceName);

    return ReverseGeocodeResult(
      displayAddress: composed.isNotEmpty ? composed : rawName,
      region: region,
      province: province,
      city: city,
      barangay: barangay,
      purok: purok,
      street: street,
    );
  }

  /// The Open Location Code alphabet excludes I, L, O and U.
  static final RegExp _plusCodePattern = RegExp(
    r'^[23456789CFGHJMPQRVWX]{4}\+[23456789CFGHJMPQRVWX]{2,3}',
    caseSensitive: false,
  );
  static final RegExp _purokPattern = RegExp(
    r'\b(?:Purok|Sitio)\s+[^,]+',
    caseSensitive: false,
  );

  /// Finds a Purok/Sitio name in MapTiler text or in a device placemark.
  static String extractPurok(Iterable<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) continue;
      final match = _purokPattern.firstMatch(trimmed);
      if (match == null) continue;
      final purok = match.group(0)!.trim();
      if (purok.length <= 32) return purok;
    }
    return '';
  }

  /// True when [value] starts with a Plus Code, e.g. `5PRQ+5H9`.
  static bool isPlusCode(String value) =>
      _plusCodePattern.hasMatch(value.trim());

  static String _cleanPart(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty || isPlusCode(trimmed)) return '';
    return trimmed;
  }

  static String _cleanPlaceName(String? value) {
    if (value == null) return '';
    return _joinDistinct(value.split(',').map(_cleanPart));
  }

  static String _joinDistinct(Iterable<String> values) {
    final seen = <String>{};
    final parts = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed.toLowerCase())) parts.add(trimmed);
    }
    return parts.join(', ');
  }
}

/// Calls the geocode-proxy reverse endpoint. Returns `null` on any failure so
/// the screen can fall back to the device geocoder.
class ReverseGeocodeService {
  const ReverseGeocodeService();

  Future<ReverseGeocodeResult?> lookup({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse('${AppConstants.geocodeProxyBaseUrl}/reverse')
        .replace(
          queryParameters: {
            'lat': latitude.toString(),
            'lng': longitude.toString(),
          },
        );

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'com.solevision.app');
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        debugPrint('[REVERSE] HTTP ${response.statusCode}: $body');
        return null;
      }

      final data = json.decode(body);
      if (data is! Map<String, dynamic>) return null;
      final place = data['place'];
      if (place is! Map<String, dynamic>) return null;

      final result = ReverseGeocodeResult.fromPlace(place);
      return result.isEmpty ? null : result;
    } catch (e) {
      debugPrint('[REVERSE] Lookup failed: $e');
      return null;
    } finally {
      client.close();
    }
  }

  /// Same lookup the customer address picker uses: MapTiler first, then the
  /// device geocoder only for fields MapTiler omitted (it usually knows the
  /// city when MapTiler omits it). Both map pickers call this so their pin
  /// labels and saved location strings cannot drift apart.
  Future<ReverseGeocodeResult?> lookupWithDeviceFallback({
    required double latitude,
    required double longitude,
  }) async {
    final proxy = await lookup(latitude: latitude, longitude: longitude);
    final needsDevice =
        proxy == null || proxy.city.isEmpty || proxy.barangay.isEmpty;
    final device = needsDevice
        ? await _lookupDevice(latitude: latitude, longitude: longitude)
        : null;

    if (proxy == null) return device;
    return proxy.mergedWith(device);
  }

  Future<ReverseGeocodeResult?> _lookupDevice({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final placemarks = await Geocoding()
          .placemarkFromCoordinates(latitude, longitude)
          .timeout(const Duration(seconds: 5));
      if (placemarks.isEmpty) return null;

      final place = placemarks.first;
      String clean(String? value) {
        final trimmed = value?.trim() ?? '';
        return trimmed.isEmpty || ReverseGeocodeResult.isPlusCode(trimmed)
            ? ''
            : trimmed;
      }

      final street = [
        clean(place.subThoroughfare),
        clean(place.thoroughfare),
      ].where((part) => part.isNotEmpty).join(' ');
      var barangay = clean(place.subLocality);
      final purok = ReverseGeocodeResult.extractPurok([
        place.name,
        place.subLocality,
        place.thoroughfare,
        place.subThoroughfare,
      ]);
      if (purok.isNotEmpty && barangay.toLowerCase() == purok.toLowerCase()) {
        barangay = '';
      }
      final locality = clean(place.locality);
      final city = locality.isNotEmpty ? locality : clean(place.subLocality);
      final province = clean(place.subAdministrativeArea);
      final region = clean(place.administrativeArea);
      final display = [
        purok,
        street,
        barangay,
        city,
        province,
      ].where((part) => part.isNotEmpty).join(', ');

      return ReverseGeocodeResult(
        displayAddress: display,
        region: region,
        province: province,
        city: city,
        barangay: barangay,
        purok: purok,
        street: street,
      );
    } catch (e) {
      debugPrint('[REVERSE] Device fallback failed: $e');
      return null;
    }
  }
}
