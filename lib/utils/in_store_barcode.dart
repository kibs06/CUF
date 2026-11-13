import 'dart:math';

/// In-store EAN-13 barcodes for seller products.
///
/// The app cannot issue globally registered GS1/UPC codes, so generated codes
/// stay inside GS1's restricted-circulation range (`200`–`299`). They are real
/// in the sense that matters at the counter — valid EAN-13 symbols with a
/// correct check digit that any standard scanner decodes — but they are only
/// meaningful inside this seller's catalog/POS, not in outside retail systems.
const String inStoreBarcodePrefix = '200';

/// Number of digits in a complete EAN-13 symbol, check digit included.
const int ean13Length = 13;

/// Computes the EAN-13 check digit for the first twelve digits.
int inStoreBarcodeCheckDigit(String firstTwelve) {
  if (firstTwelve.length != ean13Length - 1 ||
      int.tryParse(firstTwelve) == null) {
    throw ArgumentError.value(
      firstTwelve,
      'firstTwelve',
      'Must be exactly 12 digits',
    );
  }
  var sum = 0;
  for (var i = 0; i < firstTwelve.length; i++) {
    final digit = firstTwelve.codeUnitAt(i) - 0x30;
    sum += digit * (i.isEven ? 1 : 3);
  }
  return (10 - (sum % 10)) % 10;
}

/// Appends the correct check digit to twelve digits.
String inStoreBarcodeFromBase(String firstTwelve) =>
    '$firstTwelve${inStoreBarcodeCheckDigit(firstTwelve)}';

/// Whether [value] is a complete, checksum-valid EAN-13 symbol.
bool isValidEan13(String? value) {
  final code = value?.trim() ?? '';
  if (code.length != ean13Length || int.tryParse(code) == null) return false;
  return inStoreBarcodeCheckDigit(code.substring(0, ean13Length - 1)).toString() ==
      code.substring(ean13Length - 1);
}

/// Whether [value] is a valid EAN-13 inside the in-store `200`–`299` range.
bool isInStoreBarcode(String? value) {
  final code = value?.trim() ?? '';
  if (!isValidEan13(code)) return false;
  return code.startsWith('2');
}

/// Stable 32-bit FNV-1a hash, so the same store always maps to the same
/// segment. `String.hashCode` is not stable across runs, so it cannot be used
/// for persisted codes.
int _stableStoreHash(String storeSeed) {
  var hash = 0x811c9dc5;
  for (final unit in storeSeed.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// Generates one valid in-store EAN-13 code.
///
/// Layout is `200` + 4-digit store segment + 5 random digits + check digit.
/// Uniqueness against already-saved products is the caller's job (see
/// `ProductService.generateUniqueInStoreBarcode`); the random segment makes
/// collisions unlikely, and the service retries on conflict.
String generateInStoreBarcode({
  required String storeSeed,
  Random? random,
}) {
  final rng = random ?? Random.secure();
  final storePart = (_stableStoreHash(storeSeed) % 10000).toString().padLeft(4, '0');
  final randomPart = rng.nextInt(100000).toString().padLeft(5, '0');
  return inStoreBarcodeFromBase('$inStoreBarcodePrefix$storePart$randomPart');
}
