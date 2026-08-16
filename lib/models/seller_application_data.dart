/// Immutable snapshot of a completed seller application, passed from the
/// `SellerApplicationController` (which holds the live form + upload state)
/// to `AuthProvider.signUpSeller` / `AuthService.completeSellerApplication`
/// when the final step is submitted.
///
/// Storage fields are the *paths* returned by
/// `VerificationDocumentService.uploadDocument` (the private bucket), NOT
/// public URLs.
class SellerApplicationData {
  /// Account step
  final String fullName;
  final String email;
  final String phone;
  final String password;

  /// Identity step
  final String? idType; // AppConstants.govIdTypes value, e.g. 'philid'
  final String? idDocumentPath;
  final String? selfiePath;

  /// Community step — at least one of these must be present
  final String? cufmaiMemberId;
  final String? barangayProofPath;

  /// Community step — personal details + store location (map-picked)
  final DateTime? birthday;
  final String? gender;
  final String? storeLocation; // formatted address (profiles.store_location)
  final double? storeLat;
  final double? storeLng;

  /// Business step — REQUIRED DTI cert, BIR COR, mayor's/barangay permit
  /// (private verification bucket; written to seller_business_docs)
  final String? dtiCertPath;
  final String? birCorPath;
  final String? permitPath;

  /// Storefront step
  final String storeName;
  final String storeDescription;
  final List<String> storeTags; // same preset vocabulary as product tags
  final String? storeFrontPath; // PUBLIC bucket (store-assets) — doubles as the store banner
  final List<String> productPhotoPaths; // 5 paths, private verification bucket

  const SellerApplicationData({
    required this.fullName,
    required this.email,
    required this.phone,
    required this.password,
    required this.idType,
    required this.idDocumentPath,
    required this.selfiePath,
    required this.cufmaiMemberId,
    required this.barangayProofPath,
    this.birthday,
    this.gender,
    this.storeLocation,
    this.storeLat,
    this.storeLng,
    this.dtiCertPath,
    this.birCorPath,
    this.permitPath,
    required this.storeName,
    required this.storeDescription,
    this.storeTags = const [],
    required this.storeFrontPath,
    required this.productPhotoPaths,
  });
}
