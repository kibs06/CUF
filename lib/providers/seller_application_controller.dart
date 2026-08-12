import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';
import '../models/seller_application_data.dart';
import '../services/auth_service.dart';
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
      storeName = prefillProfile['store_name']?.toString() ?? '';
      if (prefillProfile['payout_method']?.toString() == AppConstants.payoutBank) {
        payoutMethod = AppConstants.payoutBank;
      }
      payoutDetails = prefillProfile['payout_details']?.toString() ?? '';
    }
  }

  static const int stepCount = 4;

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
  final SellerDocState idDocument = SellerDocState();
  final SellerDocState selfie = SellerDocState();

  // ── Step 3 · Community ────────────────────────────────────────
  bool isCufmaiMember = true;
  String cufmaiMemberId = '';
  final SellerDocState barangayProof = SellerDocState();

  // ── Step 4 · Storefront ───────────────────────────────────────
  String storeName = '';
  String storeDescription = '';
  String payoutMethod = AppConstants.payoutGcash;
  String payoutDetails = '';

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

  Future<void> pickDocument(SellerDocState doc, ImageSource source) async {
    final path = await VerificationDocumentService.instance
        .pickDocumentImage(source: source);
    if (path == null) return;
    doc
      ..localPath = path
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
  /// checklist (ID + selfie always; barangay proof only when the applicant
  /// is not a CUFMAI member).
  int get requiredUploadCount => isCufmaiMember ? 2 : 3;

  int get completedUploadCount =>
      [idDocument, selfie, if (!isCufmaiMember) barangayProof]
          .where((doc) => doc.status == DocumentUploadStatus.uploaded)
          .length;

  Future<void> _uploadIfNeeded(
    String userId,
    String docKey,
    SellerDocState doc,
  ) async {
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
      );
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
      if (!isCufmaiMember) {
        await _uploadIfNeeded(user.id, 'barangay_proof', barangayProof);
      }

      // 3. Persist the application + adopt the session.
      final data = SellerApplicationData(
        fullName: fullName,
        email: email,
        phone: phone,
        password: password,
        idDocumentPath: idDocument.storagePath,
        selfiePath: selfie.storagePath,
        cufmaiMemberId: isCufmaiMember && cufmaiMemberId.trim().isNotEmpty
            ? cufmaiMemberId.trim()
            : null,
        barangayProofPath: isCufmaiMember ? null : barangayProof.storagePath,
        storeName: storeName,
        storeDescription: storeDescription,
        payoutMethod: payoutMethod,
        payoutDetails: payoutDetails,
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
}
