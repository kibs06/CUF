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
  final String? idDocumentPath;
  final String? selfiePath;

  /// Community step — at least one of these must be present
  final String? cufmaiMemberId;
  final String? barangayProofPath;

  /// Storefront step
  final String storeName;
  final String storeDescription;
  final String payoutMethod; // 'gcash' | 'bank' (AppConstants.payoutGcash / payoutBank)
  final String payoutDetails;

  const SellerApplicationData({
    required this.fullName,
    required this.email,
    required this.phone,
    required this.password,
    required this.idDocumentPath,
    required this.selfiePath,
    required this.cufmaiMemberId,
    required this.barangayProofPath,
    required this.storeName,
    required this.storeDescription,
    required this.payoutMethod,
    required this.payoutDetails,
  });
}
