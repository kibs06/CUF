import 'package:app/models/address_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Address address() => const Address(
    userId: 'user-1',
    recipientName: 'Maria',
    recipientPhone: '+639000000000',
    region: 'Central Visayas',
    province: 'Cebu',
    cityMunicipality: 'Naga',
    barangay: 'Inoburan',
    purok: 'Purok 3',
    streetAddress: '123 Main St',
    latitude: 10.1905,
    longitude: 123.73842,
  );

  test('Purok is part of the formatted delivery address', () {
    expect(
      address().formattedAddress,
      '123 Main St, Purok 3, Inoburan, Naga, Cebu, Central Visayas',
    );
    expect(address().shortAddress, 'Purok 3, Inoburan, Naga, Cebu');
  });

  test('Purok survives inserts, reads and order snapshots', () {
    final original = address();

    final inserted = Address.fromMap({
      ...original.toInsertMap(),
      'id': 'address-1',
      'is_default': false,
    });
    expect(inserted.purok, 'Purok 3');

    final snapshot = Address.fromSnapshot(original.toSnapshot());
    expect(snapshot.purok, 'Purok 3');
    expect(original.toSnapshot()['purok'], 'Purok 3');
    expect(original.copyWith(purok: 'Purok 4').purok, 'Purok 4');
  });
}
