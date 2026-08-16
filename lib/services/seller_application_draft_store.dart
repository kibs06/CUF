import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A snapshot of the seller application form, persisted so a user who
/// accidentally closes the app can resume where they left off.
///
/// Everything except the password lives in `SharedPreferences` (plain,
/// non-sensitive form data); the password is written to
/// [FlutterSecureStorage] — never plaintext on disk.
class SellerApplicationDraft {
  final int step;
  final String fullName;
  final String email;
  final String phone;
  final String password;
  final bool termsAccepted;
  final bool isCufmaiMember;
  final String cufmaiMemberId;

  /// Selected government ID type (one of `AppConstants.govIdTypes` values).
  final String? idType;

  /// Personal details + location (application v2, Community step)
  final DateTime? birthday;
  final String? gender;
  final String storeLocation;
  final List<String> storeTags;

  final String storeName;
  final String storeDescription;

  /// Local paths of picked verification images (best-effort — the temp
  /// files may be purged by the OS; the restore validates existence).
  final String? idDocumentPath;
  final String? selfiePath;
  final String? barangayProofPath;
  final String? storeFrontPath;
  final String? dtiPath;
  final String? birPath;
  final String? permitPath;

  /// Local paths of the applicant's 5 product photos (best-effort like the
  /// other picked images — the temp files may be purged).
  final List<String?> productPhotoPaths;

  /// When the snapshot was written — used for the 30-minute expiry.
  final DateTime savedAt;

  const SellerApplicationDraft({
    required this.step,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.password,
    required this.termsAccepted,
    required this.isCufmaiMember,
    required this.cufmaiMemberId,
    this.idType,
    this.birthday,
    this.gender,
    this.storeLocation = '',
    this.storeTags = const [],
    required this.storeName,
    required this.storeDescription,
    this.idDocumentPath,
    this.selfiePath,
    this.barangayProofPath,
    this.storeFrontPath,
    this.dtiPath,
    this.birPath,
    this.permitPath,
    this.productPhotoPaths = const [],
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'step': step,
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'terms_accepted': termsAccepted,
        'is_cufmai_member': isCufmaiMember,
        'id_type': idType,
        'cufmai_member_id': cufmaiMemberId,
        'birthday': birthday?.toIso8601String(),
        'gender': gender,
        'store_location': storeLocation,
        'store_tags': storeTags,
        'store_name': storeName,
        'store_description': storeDescription,
        'id_document_path': idDocumentPath,
        'selfie_path': selfiePath,
        'barangay_proof_path': barangayProofPath,
        'store_front_path': storeFrontPath,
        'dti_path': dtiPath,
        'bir_path': birPath,
        'permit_path': permitPath,
        'product_photo_paths': productPhotoPaths,
        'saved_at': savedAt.toIso8601String(),
      };

  factory SellerApplicationDraft.fromJson(Map<String, dynamic> json) {
    final savedAt = DateTime.tryParse(json['saved_at']?.toString() ?? '');
    return SellerApplicationDraft(
      step: (json['step'] as num?)?.toInt() ?? 0,
      fullName: json['full_name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      password: json['password']?.toString() ?? '',
      termsAccepted: json['terms_accepted'] == true,
      isCufmaiMember: json['is_cufmai_member'] != false,
      cufmaiMemberId: json['cufmai_member_id']?.toString() ?? '',
      idType: json['id_type']?.toString(),
      birthday: DateTime.tryParse(json['birthday']?.toString() ?? ''),
      gender: json['gender']?.toString(),
      storeLocation: json['store_location']?.toString() ?? '',
      storeTags: (json['store_tags'] as List?)
              ?.map((e) => e?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
      storeName: json['store_name']?.toString() ?? '',
      storeDescription: json['store_description']?.toString() ?? '',
      idDocumentPath: json['id_document_path']?.toString(),
      selfiePath: json['selfie_path']?.toString(),
      barangayProofPath: json['barangay_proof_path']?.toString(),
      storeFrontPath: json['store_front_path']?.toString(),
      dtiPath: json['dti_path']?.toString(),
      birPath: json['bir_path']?.toString(),
      permitPath: json['permit_path']?.toString(),
      productPhotoPaths: (json['product_photo_paths'] as List?)
              ?.map((e) => e?.toString())
              .toList() ??
          const [],
      // A corrupt/legacy row without a timestamp is treated as expired.
      savedAt: savedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Persists and restores the seller application draft.
///
/// All methods are best-effort and swallow errors: if storage is
/// unavailable (e.g. in a widget test without platform mocks) the draft
/// simply isn't saved — the flow still works, it just doesn't resume.
class SellerApplicationDraftStore {
  SellerApplicationDraftStore._();

  static final SellerApplicationDraftStore instance =
      SellerApplicationDraftStore._();

  static const String _prefsKey = 'seller_application_draft_v1';
  static const String _passwordKey = 'seller_application_draft_password_v1';

  /// How long a saved draft stays valid. After this window the draft is
  /// discarded on load, so a stale half-finished application never
  /// resurfaces days later.
  static const Duration expiry = Duration(minutes: 30);

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// Loads the draft if one exists and is still inside the [expiry]
  /// window. Expired (or unreadable) drafts are deleted and `null` is
  /// returned.
  Future<SellerApplicationDraft?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return null;

      final draft = SellerApplicationDraft.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      final age = DateTime.now().difference(draft.savedAt);
      if (age > expiry || age.isNegative) {
        await clear();
        return null;
      }

      // The password is stored separately in secure storage.
      String? password;
      try {
        password = await _secureStorage.read(key: _passwordKey);
      } catch (e) {
        debugPrint('[SellerDraft] secure read failed (ignored): $e');
      }

      return SellerApplicationDraft(
        step: draft.step,
        fullName: draft.fullName,
        email: draft.email,
        phone: draft.phone,
        password: password ?? '',
        termsAccepted: draft.termsAccepted,
        isCufmaiMember: draft.isCufmaiMember,
        cufmaiMemberId: draft.cufmaiMemberId,
        idType: draft.idType,
        birthday: draft.birthday,
        gender: draft.gender,
        storeLocation: draft.storeLocation,
        storeTags: draft.storeTags,
        storeName: draft.storeName,
        storeDescription: draft.storeDescription,
        idDocumentPath: draft.idDocumentPath,
        selfiePath: draft.selfiePath,
        barangayProofPath: draft.barangayProofPath,
        storeFrontPath: draft.storeFrontPath,
        dtiPath: draft.dtiPath,
        birPath: draft.birPath,
        permitPath: draft.permitPath,
        productPhotoPaths: draft.productPhotoPaths,
        savedAt: draft.savedAt,
      );
    } catch (e) {
      debugPrint('[SellerDraft] load failed (ignored): $e');
      return null;
    }
  }

  Future<void> save(SellerApplicationDraft draft) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(draft.toJson()));
      if (draft.password.isNotEmpty) {
        await _secureStorage.write(key: _passwordKey, value: draft.password);
      }
    } catch (e) {
      debugPrint('[SellerDraft] save failed (ignored): $e');
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
      await _secureStorage.delete(key: _passwordKey);
    } catch (e) {
      debugPrint('[SellerDraft] clear failed (ignored): $e');
    }
  }
}
