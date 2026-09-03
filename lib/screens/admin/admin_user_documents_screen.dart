import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../services/auth_service.dart';
import '../../services/verification_document_service.dart';
import '../../widgets/admin/verification_doc_viewer.dart';

/// Admin screen to view all verification documents for a specific user.
/// 
/// Security measures:
/// - Only accessible by admins (enforced by RLS on storage and tables)
/// - Uses signed URLs with 1-hour expiry for private documents
/// - Documents are fetched via admin-privileged queries
/// - Access is logged for audit purposes
class AdminUserDocumentsScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const AdminUserDocumentsScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<AdminUserDocumentsScreen> createState() => _AdminUserDocumentsScreenState();
}

class _AdminUserDocumentsScreenState extends State<AdminUserDocumentsScreen> {
  final AuthService _auth = AuthService.instance;
  
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _businessDocs;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Fetch profile data (admin can read all profiles via RLS)
      final profile = await _auth.getProfile(widget.userId);
      
      // Fetch business docs if they exist
      Map<String, dynamic>? businessDocs;
      try {
        businessDocs = await _auth.fetchBusinessVerification(widget.userId);
      } catch (e) {
        // Business docs may not exist - that's okay
        debugPrint('[AdminUserDocs] No business docs for ${widget.userId}: $e');
      }

      if (mounted) {
        setState(() {
          _profile = profile;
          _businessDocs = businessDocs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[AdminUserDocs] Load failed: $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to load documents. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Documents: ${widget.userName}',
          style: AppConstants.headlineStyle(fontSize: 18),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _loadDocuments,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppConstants.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: AppConstants.error.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: AppConstants.bodyStyle(
                color: AppConstants.secondary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loadDocuments,
              style: FilledButton.styleFrom(backgroundColor: AppConstants.primary),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_profile == null) {
      return const Center(
        child: Text('User not found.'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildUserHeader(),
          const SizedBox(height: 20),
          _buildIdentityDocuments(),
          const SizedBox(height: 20),
          _buildBusinessDocuments(),
          const SizedBox(height: 20),
          _buildStorePhotos(),
        ],
      ),
    );
  }

  Widget _buildUserHeader() {
    final name = _profile!['full_name']?.toString() ?? 'Unknown';
    final email = _profile!['email']?.toString() ?? '';
    final role = _profile!['role']?.toString() ?? 'customer';
    final sellerStatus = _profile!['seller_status']?.toString() ?? 'none';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppConstants.borderGray.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppConstants.primary.withValues(alpha: 0.1),
            child: const Icon(Icons.person, color: AppConstants.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppConstants.bodyStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: Colors.black45,
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildBadge(role.toUpperCase(), AppConstants.primary),
                    const SizedBox(width: 8),
                    _buildBadge(sellerStatus.toUpperCase(), AppConstants.secondary),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppConstants.monoStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildIdentityDocuments() {
    final hasId = _profile!['id_document_url'] != null;
    final hasSelfie = _profile!['selfie_url'] != null;
    final hasBarangay = _profile!['barangay_proof_url'] != null;
    final idType = _profile!['id_type']?.toString();

    if (!hasId && !hasSelfie && !hasBarangay) {
      return _buildSection(
        title: 'Identity Documents',
        child: Text(
          'No identity documents submitted.',
          style: AppConstants.bodyStyle(
            fontSize: 13,
            color: AppConstants.secondary.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    return _buildSection(
      title: 'Identity Documents',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (idType != null && idType.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'ID Type: ${AppConstants.govIdTypeLabel(idType)}',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (hasId)
                _buildDocumentThumbnail(
                  storagePath: _profile!['id_document_url']?.toString(),
                  label: 'Government ID',
                ),
              if (hasSelfie)
                _buildDocumentThumbnail(
                  storagePath: _profile!['selfie_url']?.toString(),
                  label: 'Selfie',
                ),
              if (hasBarangay)
                _buildDocumentThumbnail(
                  storagePath: _profile!['barangay_proof_url']?.toString(),
                  label: 'Barangay Proof',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessDocuments() {
    if (_businessDocs == null) {
      return _buildSection(
        title: 'Business Documents (Tier 2)',
        child: Text(
          'No business documents submitted.',
          style: AppConstants.bodyStyle(
            fontSize: 13,
            color: AppConstants.secondary.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    final hasDti = _businessDocs!['dti_cert_url'] != null;
    final hasBir = _businessDocs!['bir_cor_url'] != null;
    final hasPermit = _businessDocs!['permit_url'] != null;
    final status = _businessDocs!['verification_status']?.toString() ?? 'none';

    if (!hasDti && !hasBir && !hasPermit) {
      return _buildSection(
        title: 'Business Documents (Tier 2)',
        child: Text(
          'No business documents submitted.',
          style: AppConstants.bodyStyle(
            fontSize: 13,
            color: AppConstants.secondary.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    return _buildSection(
      title: 'Business Documents (Tier 2)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBadge('Status: ${status.toUpperCase()}', _getStatusColor(status)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (hasDti)
                _buildDocumentThumbnail(
                  storagePath: _businessDocs!['dti_cert_url']?.toString(),
                  label: 'DTI Certificate',
                ),
              if (hasBir)
                _buildDocumentThumbnail(
                  storagePath: _businessDocs!['bir_cor_url']?.toString(),
                  label: 'BIR COR',
                ),
              if (hasPermit)
                _buildDocumentThumbnail(
                  storagePath: _businessDocs!['permit_url']?.toString(),
                  label: "Mayor's/Barangay Permit",
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStorePhotos() {
    final hasStoreFront = _profile!['store_front_url'] != null;
    final productPaths = (_profile!['product_photo_urls'] as List?)
            ?.map((e) => e?.toString())
            .where((e) => e != null && e.isNotEmpty)
            .toList() ??
        [];

    if (!hasStoreFront && productPaths.isEmpty) {
      return _buildSection(
        title: 'Store Photos',
        child: Text(
          'No store photos submitted.',
          style: AppConstants.bodyStyle(
            fontSize: 13,
            color: AppConstants.secondary.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    return _buildSection(
      title: 'Store Photos',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          if (hasStoreFront)
            _buildDocumentThumbnail(
              storagePath: _profile!['store_front_url']?.toString(),
              label: 'Store Front',
              bucket: 'store-assets', // Public bucket for store banners
            ),
          for (var i = 0; i < productPaths.length; i++)
            _buildDocumentThumbnail(
              storagePath: productPaths[i],
              label: 'Product ${i + 1}',
            ),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppConstants.borderGray.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppConstants.bodyStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppConstants.primary,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildDocumentThumbnail({
    required String? storagePath,
    required String label,
    String bucket = VerificationDocumentService.bucket,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VerificationDocThumb(
          storagePath: storagePath,
          label: label,
          bucket: bucket,
          size: 80,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppConstants.bodyStyle(
            fontSize: 11,
            color: AppConstants.secondary.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'verified':
        return AppConstants.success;
      case 'pending':
        return AppConstants.statusPendingColor;
      case 'rejected':
        return AppConstants.error;
      default:
        return AppConstants.secondary;
    }
  }
}