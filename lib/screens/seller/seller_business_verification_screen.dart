import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/seller_application_controller.dart';
import '../../services/auth_service.dart';
import '../../services/verification_document_service.dart';
import '../../widgets/auth/document_upload_tile.dart';

/// TIER 2 — optional business verification (DTI certificate, BIR COR,
/// mayor's/barangay permit).
///
/// Reachable only from the seller's Profile after approval. Deliberately
/// DECOUPLED from the approval gate: submitting here never changes
/// seller_status and never blocks selling — it just upgrades marketplace
/// trust. Uploads happen immediately on pick (into the private
/// seller-verification-docs bucket), and the docs are submitted together.
class SellerBusinessVerificationScreen extends StatefulWidget {
  const SellerBusinessVerificationScreen({super.key});

  @override
  State<SellerBusinessVerificationScreen> createState() =>
      _SellerBusinessVerificationScreenState();
}

class _SellerBusinessVerificationScreenState
    extends State<SellerBusinessVerificationScreen> {
  final AuthService _auth = AuthService.instance;

  final SellerDocState _dti = SellerDocState();
  final SellerDocState _bir = SellerDocState();
  final SellerDocState _permit = SellerDocState();

  Map<String, dynamic>? _row;
  bool _loading = true;
  String? _loadError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final userId = context.read<AuthProvider>().currentUser?['id']?.toString();
      final row = userId == null ? null : await _auth.fetchBusinessVerification(userId);
      if (!mounted) return;
      setState(() {
        _row = row;
        // Reflect previously uploaded documents.
        _seedFromRow(_dti, row?['dti_cert_url']);
        _seedFromRow(_bir, row?['bir_cor_url']);
        _seedFromRow(_permit, row?['permit_url']);
      });
    } catch (e) {
      debugPrint('[BizVerification] load failed: $e');
      if (mounted) setState(() => _loadError = 'Could not load your verification status.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _seedFromRow(SellerDocState doc, dynamic storagePath) {
    if (storagePath == null || storagePath.toString().isEmpty) return;
    doc
      ..storagePath = storagePath.toString()
      ..status = DocumentUploadStatus.uploaded;
  }

  String? _userId() =>
      context.read<AuthProvider>().currentUser?['id']?.toString();

  Future<void> _pickAndUpload(SellerDocState doc, String docKey) async {
    if (_saving) return;
    final source = await showVerificationImageSourceSheet(context);
    if (source == null) return;
    final userId = _userId();
    if (userId == null) {
      _showMessage('Please log in again before uploading.', error: true);
      return;
    }

    final result =
        await VerificationDocumentService.instance.pickDocumentImage(source: source);
    if (result.isCancelled) return;
    
    if (result.isFailed) {
      _showMessage(result.error ?? 'Failed to pick document.', error: true);
      return;
    }
    
    final path = result.path;
    if (path == null) return; // Should not happen if isSuccess is true, but defensive
    
    await _upload(doc, docKey, userId, path);
  }

  Future<void> _upload(
    SellerDocState doc,
    String docKey,
    String userId,
    String localPath,
  ) async {
    setState(() {
      doc
        ..localPath = localPath
        ..status = DocumentUploadStatus.uploading
        ..errorMessage = null;
    });

    try {
      final storagePath = await VerificationDocumentService.instance
          .uploadDocument(userId: userId, docKey: docKey, filePath: localPath);
      if (!mounted) return;
      setState(() {
        doc
          ..storagePath = storagePath
          ..status = DocumentUploadStatus.uploaded;
      });
    } catch (e) {
      debugPrint('[BizVerification] upload failed for $docKey: $e');
      if (!mounted) return;
      setState(() {
        doc
          ..status = DocumentUploadStatus.error
          ..errorMessage = 'Upload failed. Check your connection and try again.';
      });
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    final userId = _userId();
    if (userId == null) {
      _showMessage('Please log in again.', error: true);
      return;
    }
    final hasAny =
        _dti.status == DocumentUploadStatus.uploaded ||
        _bir.status == DocumentUploadStatus.uploaded ||
        _permit.status == DocumentUploadStatus.uploaded;
    if (!hasAny) {
      _showMessage('Add at least one business document to submit.');
      return;
    }

    setState(() => _saving = true);
    try {
      final row = await _auth.submitBusinessVerification(
        profileId: userId,
        dtiCertPath: _dti.status == DocumentUploadStatus.uploaded
            ? _dti.storagePath
            : null,
        birCorPath: _bir.status == DocumentUploadStatus.uploaded
            ? _bir.storagePath
            : null,
        permitPath: _permit.status == DocumentUploadStatus.uploaded
            ? _permit.storagePath
            : null,
      );
      if (!mounted) return;
      setState(() => _row = row);
      _showMessage('Documents submitted for verification.');
    } catch (e) {
      debugPrint('[BizVerification] submit failed: $e');
      if (!mounted) return;
      _showMessage('Could not submit your documents. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _removeDoc(SellerDocState doc) {
    final uploaded = doc.storagePath;
    if (uploaded != null) {
      VerificationDocumentService.instance.deleteDocument(uploaded);
    }
    setState(() {
      doc
        ..localPath = null
        ..storagePath = null
        ..status = DocumentUploadStatus.empty
        ..errorMessage = null;
    });
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppConstants.error : AppConstants.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _row?['verification_status']?.toString() ??
        AppConstants.bizStatusNone;

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Business Verification',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppConstants.secondary,
          ),
        ),
        backgroundColor: AppConstants.surfaceLight,
        elevation: 0,
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          _buildBody(status),
        ],
      ),
    );
  }

  Widget _buildBody(String status) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppConstants.primary),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: AppConstants.error,
            ),
            const SizedBox(height: 12),
            Text(
              _loadError!,
              style: AppConstants.bodyStyle(
                color: AppConstants.secondary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _load,
              style: FilledButton.styleFrom(
                backgroundColor: AppConstants.primary,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusBanner(status: status),
          const SizedBox(height: 16),
          Text(
            'DTI CERTIFICATE',
            style: _eyebrowStyle(),
          ),
          const SizedBox(height: 8),
          DocumentUploadTile(
            title: 'DTI certificate',
            description: 'Your DTI Business Name Registration, if you have one.',
            status: _dti.status,
            imagePath: _dti.localPath,
            errorMessage: _dti.errorMessage,
            required: false,
            onPick: () => _pickAndUpload(_dti, 'dti_cert'),
            onRemove: () => _removeDoc(_dti),
            onRetry: () {
              final p = _dti.localPath;
              final uid = _userId();
              if (p != null && uid != null) _upload(_dti, 'dti_cert', uid, p);
            },
          ),
          const SizedBox(height: 16),
          Text('BIR COR', style: _eyebrowStyle()),
          const SizedBox(height: 8),
          DocumentUploadTile(
            title: 'BIR Certificate of Registration',
            description: 'Your BIR COR confirming your tax registration.',
            status: _bir.status,
            imagePath: _bir.localPath,
            errorMessage: _bir.errorMessage,
            required: false,
            onPick: () => _pickAndUpload(_bir, 'bir_cor'),
            onRemove: () => _removeDoc(_bir),
            onRetry: () {
              final p = _bir.localPath;
              final uid = _userId();
              if (p != null && uid != null) _upload(_bir, 'bir_cor', uid, p);
            },
          ),
          const SizedBox(height: 16),
          Text('MAYOR’S / BARANGAY PERMIT', style: _eyebrowStyle()),
          const SizedBox(height: 8),
          DocumentUploadTile(
            title: 'Mayor’s / barangay permit',
            description: 'Your business permit from the city or barangay.',
            status: _permit.status,
            imagePath: _permit.localPath,
            errorMessage: _permit.errorMessage,
            required: false,
            onPick: () => _pickAndUpload(_permit, 'permit'),
            onRemove: () => _removeDoc(_permit),
            onRetry: () {
              final p = _permit.localPath;
              final uid = _userId();
              if (p != null && uid != null) _upload(_permit, 'permit', uid, p);
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                _saving ? 'Submitting…' : 'Submit for verification',
                style: AppConstants.bodyStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppConstants.primary,
                disabledBackgroundColor:
                    AppConstants.primary.withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'This is optional and does not affect your ability to sell. Admins verify it separately from your seller application.',
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.55),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _eyebrowStyle() {
    return AppConstants.bodyStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.2,
      color: AppConstants.secondary.withValues(alpha: 0.6),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String status;

  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final (icon, color, title, body) = switch (status) {
      AppConstants.bizStatusVerified => (
          Icons.verified_rounded,
          AppConstants.success,
          'Verified',
          'Your business documents are verified. Thank you for building trust on SoleVision.'
        ),
      AppConstants.bizStatusPending => (
          Icons.hourglass_top_rounded,
          AppConstants.statusPendingColor,
          'Under review',
          'An admin is reviewing your business documents. You can keep selling while you wait.'
        ),
      AppConstants.bizStatusRejected => (
          Icons.error_outline_rounded,
          AppConstants.error,
          'Needs attention',
          'Your submission was not approved. Update the documents below and submit again.'
        ),
      _ => (
          Icons.business_center_outlined,
          AppConstants.primary,
          'Not yet verified',
          'Add your business documents below to upgrade your seller trust level. Completely optional.'
        ),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary.withValues(alpha: 0.75),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
