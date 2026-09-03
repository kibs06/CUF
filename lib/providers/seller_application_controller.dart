import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';
import '../models/seller_application_data.dart';
import '../services/auth_service.dart';
import '../services/seller_application_draft_store.dart';
import '../services/verification_document_service.dart';
import '../utils/auth_error_messages.dart';
import '../widgets/auth/document_upload_tile.dart';

/// Lifecycle state of one verification document inside the seller flow.
/// Held here (not in the widgets) so entered data survives navigation
/// between steps AND leaving/re-entering the flow during the same session.
class SellerDocState {
  String? localPath;
  String? storagePath;
  DocumentUploadStatus status = DocumentUploadStatus.empty;
  String? errorMessage;
}

/// Scoped ChangeNotifier that owns the seller application's form + upload
/// state across all four steps, plus the final submission sequence.
///
/// ARCHITECTURE NOTE (why the account is created here and not at Step 1):
/// the Supabase Auth user is created ONLY on final submit. Abandoning the
/// flow mid-way therefore never leaves an orphaned auth user or a profile
/// with no application data — the exact edge case the spec calls out. All
/// uploaded files are kept as local paths until then; uploads happen into
/// the private `seller-verification-docs` bucket right after the account
/// exists, and every step of that sequence is individually retryable.
class SellerApplicationController extends ChangeNotifier {
  SellerApplicationController({Map<String, dynamic>? prefillProfile}) {
    if (prefillProfile != null) {
      final isReapply = (prefillProfile['seller_status'] ?? '') ==
          AppConstants.statusRejected;
      _isReapply = isReapply;
      fullName = prefillProfile['full_name']?.toString() ?? '';
      email = prefillProfile['email']?.toString() ?? '';
      phone = prefillProfile['phone']?.toString() ?? '';
      cufmaiMemberId =
          prefillProfile['cufmai_member_id']?.toString() ?? '';
      birthday = DateTime.tryParse(
          prefillProfile['birthday']?.toString() ?? '');
      gender = prefillProfile['gender']?.toString();
      storeLocation = prefillProfile['store_location']?.toString() ?? '';
      storeLat = (prefillProfile['store_lat'] as num?)?.toDouble();
      storeLng = (prefillProfile['store_lng'] as num?)?.toDouble();
      storeTags = _stringListOf(prefillProfile['store_tags']);
      storeName = prefillProfile['store_name']?.toString() ?? '';
      storeDescription =
          prefillProfile['store_description']?.toString() ?? '';
    }
  }

  static const int stepCount = 5;

  /// Re-apply: the user already has a session (rejected seller), so no
  /// password is collected and ensureUser reuses the existing account.
  bool _isReapply = false;
  bool get isReapply => _isReapply;

  // ── Step navigation ───────────────────────────────────────────
  int _step = 0;
  int get step => _step;
  void nextStep() {
    if (_step < stepCount - 1) {
      _step++;
      notifyListeners();
    }
  }

  void backStep() {
    if (_step > 0) {
      _step--;
      notifyListeners();
    }
  }

  /// Jumps to an arbitrary step (used to send the user back to the start
  /// after dismissing a failed submission view).
  void jumpToStep(int index) {
    if (index >= 0 && index < stepCount) {
      _step = index;
      notifyListeners();
    }
  }

  // ── Step 1 · Account ──────────────────────────────────────────
  String fullName = '';
  String email = '';
  String phone = '';
  String password = '';
  String? emailExistsError;

  // Notifying getter/setter (NOT a plain field): the TermsPolicyTile on
  // Step 1 sets this when the user agrees inside the read-and-agree flow,
  // and the UI must repaint its checkbox the moment that happens. A plain
  // field would store the value but leave the box visually unchecked.
  bool _termsAccepted = false;
  bool get termsAccepted => _termsAccepted;
  set termsAccepted(bool value) {
    if (value == _termsAccepted) return;
    _termsAccepted = value;
    notifyListeners();
  }

  // ── Step 2 · Identity ─────────────────────────────────────────
  /// Selected government ID type (one of `AppConstants.govIdTypes`
  /// values). Required before the ID photo can be accepted.
  String? _idType;
  String? get idType => _idType;

  set idType(String? value) {
    if (value == _idType) return;
    _idType = value;
    notifyListeners();
  }

  final SellerDocState idDocument = SellerDocState();
  final SellerDocState selfie = SellerDocState();

  // ── Step 3 · Community ────────────────────────────────────────
  /// Whether the applicant is a CUFMAI member (vs. a non-member proving
  /// local residence with a barangay proof). Notifies on change so the
  /// Community step's segmented toggle AND the barangay/member-ID section
  /// swap repaint — a plain field here made "Not a member" appear
  /// unclickable (state changed but the UI never rebuilt).
  bool _isCufmaiMember = true;
  bool get isCufmaiMember => _isCufmaiMember;

  set isCufmaiMember(bool value) {
    if (value == _isCufmaiMember) return;
    _isCufmaiMember = value;
    notifyListeners();
  }

  String cufmaiMemberId = '';
  final SellerDocState barangayProof = SellerDocState();

  // ── Personal details (Step 1) + store location (Step 3) ────────
  // Notifying so the steps repaint (and the draft autosaves) the moment
  // the date/location pickers or gender chips change.
  DateTime? _birthday;
  DateTime? get birthday => _birthday;
  set birthday(DateTime? value) {
    if (value == _birthday) return;
    _birthday = value;
    notifyListeners();
  }

  String? _gender;
  String? get gender => _gender;
  set gender(String? value) {
    if (value == _gender) return;
    _gender = value;
    notifyListeners();
  }

  String _storeLocation = '';
  String get storeLocation => _storeLocation;
  set storeLocation(String value) {
    if (value == _storeLocation) return;
    _storeLocation = value;
    notifyListeners();
  }

  double? storeLat;
  double? storeLng;

  // ── Step 4 · Business verification (REQUIRED) ─────────────────
  final SellerDocState dti = SellerDocState();
  final SellerDocState bir = SellerDocState();
  final SellerDocState permit = SellerDocState();

  // ── Step 5 · Storefront ───────────────────────────────────────
  String storeName = '';
  String storeDescription = '';

  /// Store tag ids (same preset vocabulary as product tags — see
  /// lib/widgets/seller/tag_selector.dart). Serialized by the TagSelector.
  List<String> _storeTags = [];
  List<String> get storeTags => List.unmodifiable(_storeTags);
  set storeTags(List<String> value) {
    _storeTags = List.of(value);
    notifyListeners();
  }

  /// Photo of the front of the applicant's store — uploaded to the PUBLIC
  /// `store-assets` bucket (doubles as the store banner) and stored as
  /// `profiles.store_front_url`.
  final SellerDocState storeFront = SellerDocState();

  /// The applicant's 5 product photos — private verification docs. All
  /// five are required so admins can verify the store actually has stock.
  final List<SellerDocState> productPhotos =
      List.generate(5, (_) => SellerDocState());

  // ── Submission state ──────────────────────────────────────────
  bool isSubmitting = false;
  String? submitError;
  bool accountCreated = false;
  bool applicationSaved = false;

  /// Whether the animated submission checklist is on screen. Stays true
  /// after a failure so the designed error + retry state remains visible
  /// (instead of snapping back to the form and hiding the error); the user
  /// dismisses it explicitly via [dismissSubmission].
  bool _showSubmission = false;
  bool get showSubmission => _showSubmission;

  void dismissSubmission() {
    _showSubmission = false;
    notifyListeners();
  }

  /// Restores a persisted draft (from an app restart within the draft's
  /// expiry window) into this controller — step, text fields, toggles, and
  /// any picked verification images whose temp files still exist.
  ///
  /// Only called for the fresh "Apply to sell" entry (no `prefillProfile`),
  /// so a re-apply's prefilled account data is never clobbered.
  void restoreDraft(SellerApplicationDraft draft) {
    _step = draft.step.clamp(0, stepCount - 1);
    fullName = draft.fullName;
    email = draft.email;
    phone = draft.phone;
    password = draft.password;
    _termsAccepted = draft.termsAccepted;
    _isCufmaiMember = draft.isCufmaiMember;
    cufmaiMemberId = draft.cufmaiMemberId;
    _idType = draft.idType;
    birthday = draft.birthday;
    gender = draft.gender;
    storeLocation = draft.storeLocation;
    storeTags = List.of(draft.storeTags);
    storeName = draft.storeName;
    storeDescription = draft.storeDescription;
    _restoreLocalFile(idDocument, draft.idDocumentPath);
    _restoreLocalFile(selfie, draft.selfiePath);
    _restoreLocalFile(barangayProof, draft.barangayProofPath);
    _restoreLocalFile(dti, draft.dtiPath);
    _restoreLocalFile(bir, draft.birPath);
    _restoreLocalFile(permit, draft.permitPath);
    _restoreLocalFile(storeFront, draft.storeFrontPath);
    for (var i = 0; i < productPhotos.length; i++) {
      final paths = draft.productPhotoPaths;
      _restoreLocalFile(
        productPhotos[i],
        i < paths.length ? paths[i] : null,
      );
    }
    notifyListeners();
  }

  void _restoreLocalFile(SellerDocState doc, String? path) {
    if (path == null || path.isEmpty) return;
    try {
      if (File(path).existsSync()) {
        doc
          ..localPath = path
          ..status = DocumentUploadStatus.picked;
      }
    } catch (_) {
      // Unreadable/missing temp file — the user simply re-picks it.
    }
  }

  Future<void> pickDocument(SellerDocState doc, ImageSource source) async {
    final result = await VerificationDocumentService.instance
        .pickDocumentImage(source: source);
    // User dismissed the picker without selecting a file — leave current
    // state unchanged (no repainted empty state or stale error).
    if (result.isCancelled) return;
    if (result.isFailed) {
      // Validation rejected the file — show the error inline so the
      // applicant knows what to fix (reuses the existing error-state
      // pattern in DocumentUploadTile).
      doc
        ..localPath = null
        ..storagePath = null
        ..status = DocumentUploadStatus.error
        ..errorMessage = result.error;
      notifyListeners();
      return;
    }
    // Validation passed — accept the file for upload at submit time.
    doc
      ..localPath = result.path!
      ..storagePath = null
      ..status = DocumentUploadStatus.picked
      ..errorMessage = null;
    notifyListeners();
  }

  void removeDocument(SellerDocState doc) {
    // Best-effort cleanup of any file already uploaded during a failed
    // submit — never leaves an orphaned private document behind.
    final uploaded = doc.storagePath;
    if (uploaded != null) {
      VerificationDocumentService.instance.deleteDocument(uploaded);
    }
    doc
      ..localPath = null
      ..storagePath = null
      ..status = DocumentUploadStatus.empty
      ..errorMessage = null;
    notifyListeners();
  }

  /// Number of documents that must be uploaded for the submission view's
  /// checklist (ID + selfie + business docs (DTI/BIR/permit) + store-front
  /// + 5 product photos always; barangay proof only when the applicant is
  /// not a CUFMAI member).
  int get requiredUploadCount => isCufmaiMember ? 11 : 12;

  int get completedUploadCount => [
        idDocument,
        selfie,
        dti,
        bir,
        permit,
        storeFront,
        ...productPhotos,
        if (!isCufmaiMember) barangayProof,
      ].where((doc) => doc.status == DocumentUploadStatus.uploaded).length;

  Future<void> _uploadIfNeeded(
    String userId,
    String docKey,
    SellerDocState doc, {
    String bucket = VerificationDocumentService.bucket,
  }) async {
    if (doc.status == DocumentUploadStatus.uploaded) return;
    if (doc.localPath == null) {
      throw StateError('No image picked for $docKey');
    }

    doc
      ..status = DocumentUploadStatus.uploading
      ..errorMessage = null;
    notifyListeners();

    try {
      final path = await VerificationDocumentService.instance.uploadDocument(
        userId: userId,
        docKey: docKey,
        filePath: doc.localPath!,
        bucket: bucket,
      );

      // Layer 3: server-side magic-byte verification. The Edge Function
      // reads the actual file bytes and checks them against JPEG/PNG
      // signatures — independent of the extension or Content-Type header.
      // If validation fails, the function deletes the file from storage.
      final valid = await VerificationDocumentService.instance
          .validateUploadedFile(storagePath: path, bucket: bucket);
      if (!valid) {
        // File was rejected server-side and deleted. Show the error so
        // the applicant can retry with a real image. Do NOT rethrow —
        // the doc state is set to error below, and rethrowing would
        // interrupt the submission sequence for other docs.
        doc
          ..storagePath = null
          ..status = DocumentUploadStatus.error
          ..errorMessage =
              'This file doesn\'t appear to be a valid image. '
              'Please choose a photo taken with your camera or a proper scan.';
        notifyListeners();
        return;
      }

      doc
        ..storagePath = path
        ..status = DocumentUploadStatus.uploaded;
      notifyListeners();
    } catch (e) {
      doc
        ..status = DocumentUploadStatus.error
        ..errorMessage = 'Upload failed. Check your connection and retry.';
      notifyListeners();
      rethrow;
    }
  }

  /// Runs the full submission sequence: create the account (only now!),
  /// upload every pending document, then persist the application and let
  /// the AuthProvider adopt the new session (which routes AuthGate to the
  /// PendingApprovalScreen).
  ///
  /// Idempotent-by-design: already-uploaded documents are skipped on retry,
  /// ensureUser reuses an existing matching session, and the profile upsert
  /// overwrites cleanly — so tapping Retry after a mid-sequence failure
  /// never duplicates work or files.
  Future<bool> submit({
    required Future<bool> Function(SellerApplicationData data) signUpSeller,
  }) async {
    if (isSubmitting) return false;

    isSubmitting = true;
    _showSubmission = true;
    submitError = null;
    accountCreated = false;
    applicationSaved = false;
    notifyListeners();

    try {
      // 1. Account (create only at the end — no orphaned accounts).
      final auth = AuthService.instance;
      final user = await auth.ensureUser(
        email: email,
        password: isReapply ? null : password,
        fullName: fullName,
      );
      accountCreated = true;
      notifyListeners();

      // 2. Upload documents into the private bucket.
      await _uploadIfNeeded(user.id, 'id_document', idDocument);
      await _uploadIfNeeded(user.id, 'selfie', selfie);
      // Business verification docs — DTI certificate, BIR COR, and
      // mayor's/barangay permit (all required in Step 4). Stored in the
      // private verification bucket; written to seller_business_docs.
      await _uploadIfNeeded(user.id, 'dti_cert', dti);
      await _uploadIfNeeded(user.id, 'bir_cor', bir);
      await _uploadIfNeeded(user.id, 'permit', permit);
      // Store-front photo goes to the PUBLIC store-assets bucket so it can
      // double as the store banner post-approval (StoreService.createStore
      // falls back to profiles.store_front_url).
      await _uploadIfNeeded(
        user.id,
        'storefront',
        storeFront,
        bucket: 'store-assets',
      );
      for (var i = 0; i < productPhotos.length; i++) {
        await _uploadIfNeeded(
          user.id,
          'product_photo_${i + 1}',
          productPhotos[i],
        );
      }
      if (!isCufmaiMember) {
        await _uploadIfNeeded(user.id, 'barangay_proof', barangayProof);
      }

      // 3. Persist the application + adopt the session.
      final data = SellerApplicationData(
        fullName: fullName,
        email: email,
        phone: phone,
        password: password,
        idType: idType,
        idDocumentPath: idDocument.storagePath,
        selfiePath: selfie.storagePath,
        storeFrontPath: storeFront.storagePath,
        productPhotoPaths: productPhotos
            .map((doc) => doc.storagePath)
            .whereType<String>()
            .toList(),
        cufmaiMemberId: isCufmaiMember && cufmaiMemberId.trim().isNotEmpty
            ? cufmaiMemberId.trim()
            : null,
        barangayProofPath: isCufmaiMember ? null : barangayProof.storagePath,
        birthday: birthday,
        gender: gender,
        storeLocation: storeLocation.trim().isEmpty ? null : storeLocation.trim(),
        storeLat: storeLat,
        storeLng: storeLng,
        dtiCertPath: dti.storagePath,
        birCorPath: bir.storagePath,
        permitPath: permit.storagePath,
        storeName: storeName,
        storeDescription: storeDescription,
        storeTags: List.of(storeTags),
      );

      final ok = await signUpSeller(data);
      if (!ok) {
        submitError =
            'We could not save your application. Please try again.';
        notifyListeners();
        return false;
      }
      applicationSaved = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[SellerApplication] submit failed: $e');
      // Auth failures (duplicate email, weak password, rate limits…) go
      // through the SAME code-keyed mapper as login/customer signup so the
      // two flows never drift into inconsistent wording. Non-auth failures
      // (uploads, network) get a connection-aware generic message.
      submitError = e is AuthException
          ? friendlyAuthError(e)
          : 'Something went wrong. Check your connection and try again.';
      notifyListeners();
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  /// Coerces a PostgREST TEXT[] cell (or a plain list) into a list of
  /// strings — used when pre-filling a re-apply from the profile row.
  static List<String> _stringListOf(dynamic value) {
    if (value is List) {
      return value.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }
}
