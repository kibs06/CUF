import 'package:app/services/reverse_geocode_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// MapTiler reverse results are the only place the address form gets a
/// barangay. Android's own geocoder returns Plus Codes for many Philippine
/// points, so these tests pin the replacement behavior: use the context
/// hierarchy, never write a code into a field, and leave the result empty
/// when there is nothing human-readable so the screen can fall back.
void main() {
  Map<String, dynamic> place({
    String placeName = '',
    String text = '',
    String houseNumber = '',
    List<String> types = const [],
    String kind = '',
    List<Map<String, String>> context = const [],
  }) {
    return {
      'place_name': placeName,
      'text': text,
      'house_number': houseNumber,
      'place_types': types,
      'kind': kind,
      'context': context,
    };
  }

  test('fills barangay, city and province from context, not the Plus Code', () {
    final result = ReverseGeocodeResult.fromPlace(
      place(
        placeName: '5PRQ+5H9, Naga, Cebu, Philippines',
        text: '5PRQ+5H9',
        types: ['neighborhood'],
        kind: 'place',
        context: [
          {'id': 'neighborhood.123', 'text': 'Inoburan'},
          {'id': 'locality.456', 'text': 'Naga'},
          {'id': 'county.789', 'text': 'Cebu'},
          {'id': 'region.101', 'text': 'Central Visayas'},
          {'id': 'country.112', 'text': 'Philippines'},
        ],
      ),
    );

    expect(result.barangay, 'Inoburan');
    expect(result.city, 'Naga');
    expect(result.province, 'Cebu');
    expect(result.region, 'Central Visayas');
    expect(result.street, isEmpty);
    expect(result.displayAddress, 'Inoburan, Naga, Cebu');
  });

  test('uses a road for Street and a POI name for the pin label', () {
    final context = [
      {'id': 'neighborhood', 'text': 'Inoburan'},
      {'id': 'locality', 'text': 'Naga'},
      {'id': 'county', 'text': 'Cebu'},
    ];

    final road = ReverseGeocodeResult.fromPlace(
      place(
        text: 'Cebu South Coastal Rd',
        types: ['road'],
        kind: 'road',
        context: context,
      ),
    );
    expect(road.street, 'Cebu South Coastal Rd');
    expect(road.displayAddress, 'Cebu South Coastal Rd, Inoburan, Naga, Cebu');

    final poi = ReverseGeocodeResult.fromPlace(
      place(
        placeName: 'Naga City Hall, Naga, Cebu, Philippines',
        text: 'Naga City Hall',
        types: ['poi'],
        kind: 'poi',
        context: context,
      ),
    );
    expect(poi.street, isEmpty);
    expect(poi.barangay, 'Inoburan');
    expect(poi.displayAddress, 'Naga City Hall, Inoburan, Naga, Cebu');
  });

  test('extracts a Purok and keeps its parent place as barangay', () {
    final result = ReverseGeocodeResult.fromPlace(
      place(
        placeName: 'Purok 3, Inoburan, Naga, Cebu, Philippines',
        text: 'Purok 3',
        types: ['neighborhood'],
        kind: 'place',
        context: [
          {'id': 'neighborhood', 'text': 'Purok 3'},
          {'id': 'place', 'text': 'Inoburan'},
          {'id': 'locality', 'text': 'Naga'},
          {'id': 'county', 'text': 'Cebu'},
        ],
      ),
    );

    expect(result.purok, 'Purok 3');
    expect(result.barangay, 'Inoburan');
    expect(result.city, 'Naga');
    expect(result.displayAddress, 'Purok 3, Inoburan, Naga, Cebu');
    expect(result.areaLabel, 'Purok 3, Inoburan, Naga, Cebu');
  });

  test('uses a place context as barangay when MapTiler omits the city', () {
    // Shape returned by the live proxy for the Naga pin in the bug report:
    // the road is the feature, Inoburan is only a `place` context, and the
    // city is absent entirely (the device geocoder supplies Naga).
    final result = ReverseGeocodeResult.fromPlace(
      place(
        placeName:
            'Inoburan-Cabungahan-Jaguimit-Patag-Lutac Road, 6037 Cebu, Philippines',
        text: 'Inoburan-Cabungahan-Jaguimit-Patag-Lutac Road',
        types: ['address'],
        kind: 'street',
        context: [
          {'id': 'postal_code', 'text': '6037'},
          {'id': 'place', 'text': 'Inoburan'},
          {'id': 'county', 'text': 'Cebu'},
          {'id': 'region', 'text': 'Central Visayas'},
          {'id': 'major_landform', 'text': 'Cebu'},
          {'id': 'country', 'text': 'Philippines'},
        ],
      ),
    );

    expect(result.barangay, 'Inoburan');
    expect(result.city, isEmpty);
    expect(result.province, 'Cebu');
    expect(result.region, 'Central Visayas');
    expect(result.street, 'Inoburan-Cabungahan-Jaguimit-Patag-Lutac Road');
    expect(
      result.displayAddress,
      'Inoburan-Cabungahan-Jaguimit-Patag-Lutac Road, Inoburan, Cebu',
    );
  });

  test('combines a house number with the street', () {
    final result = ReverseGeocodeResult.fromPlace(
      place(
        text: 'Rizal St',
        houseNumber: '12',
        types: ['address'],
        kind: 'address',
        context: [
          {'id': 'locality', 'text': 'Naga'},
          {'id': 'county', 'text': 'Cebu'},
        ],
      ),
    );

    expect(result.street, '12 Rizal St');
    expect(result.displayAddress, '12 Rizal St, Naga, Cebu');
  });

  test('merging the device city keeps MapTiler barangay and label', () {
    final proxy = ReverseGeocodeResult.fromPlace(
      place(
        placeName:
            'Inoburan-Cabungahan-Jaguimit-Patag-Lutac Road, 6037 Cebu, Philippines',
        text: 'Inoburan-Cabungahan-Jaguimit-Patag-Lutac Road',
        types: ['address'],
        kind: 'street',
        context: [
          {'id': 'place', 'text': 'Inoburan'},
          {'id': 'county', 'text': 'Cebu'},
          {'id': 'region', 'text': 'Central Visayas'},
        ],
      ),
    );
    const device = ReverseGeocodeResult(
      displayAddress: 'Naga, Cebu',
      region: 'Central Visayas',
      province: 'Cebu',
      city: 'Naga',
      barangay: '',
      street: '',
    );

    final merged = proxy.mergedWith(device);
    expect(merged.barangay, 'Inoburan');
    expect(merged.city, 'Naga');
    expect(merged.street, contains('Inoburan-Cabungahan'));
    expect(merged.areaLabel, 'Inoburan, Naga, Cebu');
  });

  test('a Plus Code with no context is empty so the screen can fall back', () {
    final result = ReverseGeocodeResult.fromPlace(
      place(placeName: '5PRQ+5H9', text: '5PRQ+5H9'),
    );

    expect(result.isEmpty, isTrue);
    expect(result.displayAddress, isEmpty);
    expect(result.street, isEmpty);
  });
}
