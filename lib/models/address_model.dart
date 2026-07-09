/// Model for a customer delivery address.
class Address {
  final String? id;
  final String userId;
  final String label;
  final String recipientName;
  final String recipientPhone;
  final String region;
  final String province;
  final String cityMunicipality;
  final String barangay;
  final String streetAddress;
  final String? landmark;
  final double latitude;
  final double longitude;
  final bool isDefault;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Address({
    this.id,
    required this.userId,
    this.label = 'Home',
    required this.recipientName,
    required this.recipientPhone,
    required this.region,
    required this.province,
    required this.cityMunicipality,
    required this.barangay,
    required this.streetAddress,
    this.landmark,
    required this.latitude,
    required this.longitude,
    this.isDefault = false,
    this.createdAt,
    this.updatedAt,
  });

  /// Full formatted address line (e.g. for display on cards / checkout).
  String get formattedAddress =>
      '$streetAddress, $barangay, $cityMunicipality, $province, $region';

  /// Compact one-line display for checkout.
  String get shortAddress =>
      '$barangay, $cityMunicipality, $province';

  /// Snapshot as JSONB for storing on the orders table.
  Map<String, dynamic> toSnapshot() => {
        'label': label,
        'recipient_name': recipientName,
        'recipient_phone': recipientPhone,
        'region': region,
        'province': province,
        'city_municipality': cityMunicipality,
        'barangay': barangay,
        'street_address': streetAddress,
        'landmark': landmark,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory Address.fromMap(Map<String, dynamic> map) {
    return Address(
      id: map['id']?.toString(),
      userId: map['user_id']?.toString() ?? '',
      label: map['label']?.toString() ?? 'Home',
      recipientName: map['recipient_name']?.toString() ?? '',
      recipientPhone: map['recipient_phone']?.toString() ?? '',
      region: map['region']?.toString() ?? '',
      province: map['province']?.toString() ?? '',
      cityMunicipality: map['city_municipality']?.toString() ?? '',
      barangay: map['barangay']?.toString() ?? '',
      streetAddress: map['street_address']?.toString() ?? '',
      landmark: map['landmark']?.toString(),
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      isDefault: map['is_default'] as bool? ?? false,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  /// Reconstruct an Address from an order's shipping_address snapshot.
  factory Address.fromSnapshot(Map<String, dynamic> snap, {String? userId}) {
    return Address(
      userId: userId ?? '',
      label: snap['label']?.toString() ?? 'Home',
      recipientName: snap['recipient_name']?.toString() ?? '',
      recipientPhone: snap['recipient_phone']?.toString() ?? '',
      region: snap['region']?.toString() ?? '',
      province: snap['province']?.toString() ?? '',
      cityMunicipality: snap['city_municipality']?.toString() ?? '',
      barangay: snap['barangay']?.toString() ?? '',
      streetAddress: snap['street_address']?.toString() ?? '',
      landmark: snap['landmark']?.toString(),
      latitude: (snap['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (snap['longitude'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'user_id': userId,
        'label': label,
        'recipient_name': recipientName,
        'recipient_phone': recipientPhone,
        'region': region,
        'province': province,
        'city_municipality': cityMunicipality,
        'barangay': barangay,
        'street_address': streetAddress,
        'landmark': landmark,
        'latitude': latitude,
        'longitude': longitude,
        'is_default': isDefault,
      };

  Map<String, dynamic> toUpdateMap() => {
        'label': label,
        'recipient_name': recipientName,
        'recipient_phone': recipientPhone,
        'region': region,
        'province': province,
        'city_municipality': cityMunicipality,
        'barangay': barangay,
        'street_address': streetAddress,
        'landmark': landmark,
        'latitude': latitude,
        'longitude': longitude,
        'is_default': isDefault,
      };

  Address copyWith({
    String? id,
    String? userId,
    String? label,
    String? recipientName,
    String? recipientPhone,
    String? region,
    String? province,
    String? cityMunicipality,
    String? barangay,
    String? streetAddress,
    String? landmark,
    double? latitude,
    double? longitude,
    bool? isDefault,
  }) {
    return Address(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      label: label ?? this.label,
      recipientName: recipientName ?? this.recipientName,
      recipientPhone: recipientPhone ?? this.recipientPhone,
      region: region ?? this.region,
      province: province ?? this.province,
      cityMunicipality: cityMunicipality ?? this.cityMunicipality,
      barangay: barangay ?? this.barangay,
      streetAddress: streetAddress ?? this.streetAddress,
      landmark: landmark ?? this.landmark,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
