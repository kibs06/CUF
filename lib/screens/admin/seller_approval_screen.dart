import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/order_provider.dart';
import '../../services/verification_document_service.dart';
import '../../widgets/admin/verification_doc_viewer.dart';
import '../../widgets/seller/tag_selector.dart';
import '../../widgets/sole_card.dart';
import 'seller_business_docs_review_screen.dart';

/// Admin seller queue — now split into two tabs:
///
///   1. **Seller Applications** — pending Tier 1 applications, each with an
///      expandable document review (government ID, selfie, CUFMAI member ID
///      or barangay proof, store name/description). Tap any
///      photo to view it full-size (pinch to zoom). Approve/Reject uses the
///      unchanged state machine.
///   2. **Business Docs** — optional Tier 2 submissions (DTI/BIR/permit),
///      reviewed separately since they never block selling.
class SellerApprovalScreen extends StatefulWidget {
  final bool isStandalonePage;

  const SellerApprovalScreen({super.key, this.isStandalonePage = false});

  @override
  State<SellerApprovalScreen> createState() => _SellerApprovalScreenState();
}

class _SellerApprovalScreenState extends State<SellerApprovalScreen> {
  int _tab = 0;
  String? _busyUserId;
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<OrderProvider>(context, listen: false).loadProfiles();
    });
  }

  void _handleApproval(String userId, String name, bool approve) async {
    String? rejectionReason;

    if (approve) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppConstants.surfaceLight,
          title: Text(
            'Approve Seller?',
            style: AppConstants.headlineStyle(fontSize: 18),
          ),
          content: Text(
            'Authorize "$name" to upload products and execute register POS sales?',
            style: AppConstants.bodyStyle(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: AppConstants.bodyStyle(color: AppConstants.secondary),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppConstants.success,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Approve',
                style: AppConstants.bodyStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    } else {
      // Reject — collect an optional reason FIRST (it goes into the
      // rejection email via the send-approval-email edge function), then
      // confirm. Cancelling (null) aborts; an empty reason is allowed.
      rejectionReason = await _promptRejectionReason(name);
      if (rejectionReason == null || !mounted) return;
    }

    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    setState(() => _busyUserId = userId);
    final success = approve
        ? await orderProvider.approveSeller(userId)
        : await orderProvider.rejectSeller(
            userId,
            reason: rejectionReason,
          );
    if (mounted) setState(() => _busyUserId = null);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? approve
                    ? '$name is now an authorized Seller!'
                    : 'Application rejected.'
              : 'Unable to update seller application.',
        ),
        backgroundColor: success ? AppConstants.success : AppConstants.error,
      ),
    );
  }

  /// Reject dialog — collects an optional reason that is included in the
  /// rejection email sent to the applicant (via the `send-approval-email`
  /// edge function). Returns the trimmed reason, or null when cancelled.
  /// An empty-string reason is allowed (the email simply omits the reason
  /// line).
  Future<String?> _promptRejectionReason(String name) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.surfaceLight,
        title: Text(
          'Reject Request?',
          style: AppConstants.headlineStyle(fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reject seller registration application for "$name"?',
              style: AppConstants.bodyStyle(),
            ),
            const SizedBox(height: 12),
            Text(
              'The reason (optional) is included in the email sent to the '
              'applicant.',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              maxLines: 3,
              maxLength: 300,
              style: AppConstants.bodyStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'e.g. Incomplete business documents',
                hintStyle: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: Colors.black38,
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: AppConstants.bodyStyle(color: AppConstants.secondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppConstants.error,
            ),
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(
              'Reject',
              style: AppConstants.bodyStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Seller Verification',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: widget.isStandalonePage
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: AppConstants.secondary,
                ),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      label: Text('Applications'),
                      icon: Icon(Icons.verified_user_outlined, size: 18),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('Business Docs'),
                      icon: Icon(Icons.business_center_outlined, size: 18),
                    ),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (selection) {
                    setState(() => _tab = selection.first);
                  },
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor:
                        AppConstants.primary.withValues(alpha: 0.12),
                    selectedForegroundColor: AppConstants.primary,
                    side: BorderSide(
                      color: AppConstants.borderGray.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _tab == 0
                    ? _buildApplicationsTab(context)
                    : const SellerBusinessDocsReviewScreen(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildApplicationsTab(BuildContext context) {
    final orderProvider = context.watch<OrderProvider>();
    final pendingSellers = orderProvider.profiles
        .where((p) => p['seller_status'] == AppConstants.statusPending)
        .toList();

    if (orderProvider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppConstants.primary),
      );
    }

    if (pendingSellers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 48,
              color: AppConstants.success.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'All seller applications are settled.',
              style: AppConstants.bodyStyle(
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: pendingSellers.length,
      itemBuilder: (context, index) {
        final applicant = pendingSellers[index];
        final name = applicant['full_name'] ?? 'Unnamed Artisan';
        final email = applicant['email'] ?? '';
        final userId = applicant['id'].toString();
        final isBusy = _busyUserId == userId;
        final isExpanded = _expanded.contains(userId);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: SoleCard(
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          AppConstants.primary.withValues(alpha: 0.1),
                      child: const Icon(
                        Icons.workspace_premium,
                        color: AppConstants.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: AppConstants.bodyStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            email,
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // ── Review documents (Tier 1) ──────────────────
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      if (isExpanded) {
                        _expanded.remove(userId);
                      } else {
                        _expanded.add(userId);
                      }
                    });
                  },
                  icon: Icon(
                    isExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 18,
                    color: AppConstants.primary,
                  ),
                  label: Text(
                    isExpanded
                        ? 'Hide documents'
                        : 'Review documents & store',
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.primary,
                    ),
                  ),
                ),

                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  child: isExpanded
                      ? _Tier1Review(applicant: applicant)
                      : const SizedBox(width: double.infinity),
                ),

                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: isBusy
                          ? null
                          : () => _handleApproval(userId, name, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppConstants.error),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Reject',
                        style: AppConstants.bodyStyle(
                          color: AppConstants.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: isBusy
                          ? null
                          : () => _handleApproval(userId, name, true),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppConstants.success),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Approve',
                        style: AppConstants.bodyStyle(
                          color: AppConstants.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Expanded Tier 1 review: ID + selfie + community proof thumbnails and the
/// storefront summary from the applicant's profile row.
class _Tier1Review extends StatelessWidget {
  final Map<String, dynamic> applicant;

  const _Tier1Review({required this.applicant});

  @override
  Widget build(BuildContext context) {
    final memberId = _text(applicant['cufmai_member_id']);
    final storeName = _text(applicant['store_name']);
    final storeDescription = _text(applicant['store_description']);
    final birthday = _text(applicant['birthday']);
    final gender = _text(applicant['gender']);
    final storeLocation = _text(applicant['store_location']);
    final hasId = applicant['id_document_url'] != null;
    final hasSelfie = applicant['selfie_url'] != null;
    final hasBarangay = applicant['barangay_proof_url'] != null;
    // Step 4 business docs arrive nested via the FK join. PostgREST can
    // embed a single row as a Map or a one-element List — handle both.
    final bizRaw = applicant['seller_business_docs'];
    final Map<String, dynamic>? bizDocs = bizRaw is Map
        ? Map<String, dynamic>.from(bizRaw)
        : (bizRaw is List && bizRaw.isNotEmpty && bizRaw.first is Map)
            ? Map<String, dynamic>.from(bizRaw.first as Map)
            : null;
    final idTypeLabel = AppConstants.govIdTypeLabel(
      applicant['id_type']?.toString(),
    );
    // Store tags (Step 5) — stored ids, displayed via the shared resolver.
    final storeTags = (applicant['store_tags'] as List?)
            ?.map((e) => e?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    // The 5 product photos live in a Postgres TEXT[] column.
    final productPaths = (applicant['product_photo_urls'] as List?)
            ?.map((e) => e?.toString())
            .where((e) => e != null && e.isNotEmpty)
            .toList() ??
        const <String?>[];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConstants.surfaceLight.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.borderGray.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Identity documents
          Row(
            children: [
              _ThumbColumn(
                label: 'Government ID',
                storagePath: applicant['id_document_url']?.toString(),
              ),
              const SizedBox(width: 12),
              _ThumbColumn(
                label: 'Selfie',
                storagePath: applicant['selfie_url']?.toString(),
              ),
              if (!hasId && !hasSelfie)
                Expanded(
                  child: Text(
                    'No identity photos submitted (legacy application).',
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: AppConstants.secondary.withValues(alpha: 0.55),
                    ),
                  ),
                ),
            ],
          ),
          // Selected government ID type (missing on legacy applications)
          if (idTypeLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Government ID type: $idTypeLabel',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Community proof
          if (memberId.isNotEmpty || hasBarangay) ...[
            Text(
              memberId.isNotEmpty
                  ? 'CUFMAI Member ID: $memberId'
                  : 'Barangay proof (non-member)',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (hasBarangay) ...[
              const SizedBox(height: 8),
              VerificationDocThumb(
                storagePath: applicant['barangay_proof_url']?.toString(),
                label: 'Barangay proof',
                size: 72,
              ),
            ],
            const SizedBox(height: 12),
          ],

          // Personal details + store location (application v2, Step 3)
          if (birthday.isNotEmpty ||
              gender.isNotEmpty ||
              storeLocation.isNotEmpty) ...[
            Text(
              'Personal details',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            if (birthday.isNotEmpty)
              Text(
                'Birthday: $birthday',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary.withValues(alpha: 0.7),
                ),
              ),
            if (gender.isNotEmpty)
              Text(
                'Gender: $gender',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary.withValues(alpha: 0.7),
                ),
              ),
            if (storeLocation.isNotEmpty)
              Text(
                '📍 $storeLocation',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary.withValues(alpha: 0.7),
                ),
              ),
            const SizedBox(height: 12),
          ],

          // Business documents (application v2, Step 4 — all required)
          if (bizDocs != null) ...[
            Text(
              'Business documents (required)',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _ThumbColumn(
                  label: 'DTI cert',
                  storagePath: bizDocs['dti_cert_url']?.toString(),
                ),
                _ThumbColumn(
                  label: 'BIR COR',
                  storagePath: bizDocs['bir_cor_url']?.toString(),
                ),
                _ThumbColumn(
                  label: 'Permit',
                  storagePath: bizDocs['permit_url']?.toString(),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],

          // Storefront
          if (storeName.isNotEmpty) ...[
            Text(
              'Store: $storeName',
              style: AppConstants.bodyStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (storeDescription.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                storeDescription,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary.withValues(alpha: 0.7),
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 8),
            // Store tags (Step 5 — same vocabulary as product tags)
            if (storeTags.isNotEmpty)
              Text(
                'Tags: ${storeTags.map(tagDisplayLabel).join(' · ')}',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],

          // Store photos (storefront becomes the banner; the 5 product
          // photos are proof of stock)
          if (applicant['store_front_url'] != null ||
              productPaths.isNotEmpty) ...[
            Text(
              'Store photos',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _ThumbColumn(
                  label: 'Store front',
                  storagePath: applicant['store_front_url']?.toString(),
                  // The store-front photo lives in the PUBLIC store-assets
                  // bucket (it doubles as the store banner).
                  bucket: 'store-assets',
                ),
                for (var i = 0; i < productPaths.length; i++)
                  _ThumbColumn(
                    label: 'Product ${i + 1}',
                    storagePath: productPaths[i],
                  ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  String _text(dynamic value) {
    final s = value?.toString() ?? '';
    return s.trim();
  }
}

class _ThumbColumn extends StatelessWidget {
  final String label;
  final String? storagePath;
  final String bucket;

  const _ThumbColumn({
    required this.label,
    required this.storagePath,
    this.bucket = VerificationDocumentService.bucket,
  });

  @override
  Widget build(BuildContext context) {
    if (storagePath == null || storagePath!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VerificationDocThumb(
          storagePath: storagePath,
          label: label,
          bucket: bucket,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppConstants.bodyStyle(
            fontSize: 10,
            color: AppConstants.secondary.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}
