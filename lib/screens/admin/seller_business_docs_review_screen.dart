import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../services/auth_service.dart';
import '../../widgets/admin/verification_doc_viewer.dart';

/// Lightweight admin review list for TIER 2 business-document submissions
/// (DTI cert, BIR COR, permit). Deliberately separate from the seller
/// approval queue — verifying these never blocks selling, so it's a
/// background trust task rather than a gate.
class SellerBusinessDocsReviewScreen extends StatefulWidget {
  const SellerBusinessDocsReviewScreen({super.key});

  @override
  State<SellerBusinessDocsReviewScreen> createState() =>
      _SellerBusinessDocsReviewScreenState();
}

class _SellerBusinessDocsReviewScreenState
    extends State<SellerBusinessDocsReviewScreen> {
  final AuthService _auth = AuthService.instance;

  List<Map<String, dynamic>> _docs = [];
  bool _isLoading = true;
  String? _error;
  String? _busyDocId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final docs = await _auth.fetchAllBusinessVerifications();
      if (mounted) setState(() => _docs = docs);
    } catch (e) {
      debugPrint('[BizDocsReview] load failed: $e');
      if (mounted) {
        setState(() => _error = 'Could not load business verifications.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verdict(
    String docId, {
    required bool verified,
  }) async {
    if (_busyDocId != null) return;
    setState(() => _busyDocId = docId);
    try {
      await _auth.setBusinessVerificationStatus(
        docId,
        verified: verified,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              verified
                  ? 'Business documents verified.'
                  : 'Business documents rejected.',
            ),
            backgroundColor: verified
                ? AppConstants.success
                : AppConstants.error,
          ),
        );
      }
    } catch (e) {
      debugPrint('[BizDocsReview] verdict failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update verification status.'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyDocId = null);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
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
              Icons.cloud_off_rounded,
              size: 40,
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

    if (_docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.business_center_outlined,
              size: 48,
              color: AppConstants.success.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No business verifications yet.',
              style: AppConstants.bodyStyle(
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _docs.length,
        itemBuilder: (context, index) {
          final doc = _docs[index];
          return _DocCard(
            doc: doc,
            busy: _busyDocId == doc['id'].toString(),
            onVerdict: (verified) =>
                _verdict(doc['id'].toString(), verified: verified),
          );
        },
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  final Map<String, dynamic> doc;
  final bool busy;
  final void Function(bool verified) onVerdict;

  const _DocCard({
    required this.doc,
    required this.busy,
    required this.onVerdict,
  });

  @override
  Widget build(BuildContext context) {
    final profile = (doc['profiles'] as Map?) ?? const {};
    final name = profile['full_name']?.toString() ?? 'Unnamed artisan';
    final storeName = profile['store_name']?.toString();
    final email = profile['email']?.toString() ?? '';
    final status = doc['verification_status']?.toString() ?? 'none';
    final hasDocs =
        _notEmpty(doc['dti_cert_url']) ||
        _notEmpty(doc['bir_cor_url']) ||
        _notEmpty(doc['permit_url']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppConstants.borderGray.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppConstants.accent.withValues(alpha: 0.15),
                child: const Icon(
                  Icons.business_center_outlined,
                  size: 18,
                  color: AppConstants.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (storeName != null && storeName.isNotEmpty)
                      Text(
                        storeName,
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          color: AppConstants.secondary.withValues(alpha: 0.6),
                        ),
                      ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: AppConstants.bodyStyle(
                          fontSize: 11,
                          color: Colors.black45,
                        ),
                      ),
                  ],
                ),
              ),
              _StatusChip(status: status),
            ],
          ),
          if (hasDocs) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                VerificationDocThumb(
                  storagePath: doc['dti_cert_url']?.toString(),
                  label: 'DTI certificate',
                ),
                const SizedBox(width: 8),
                VerificationDocThumb(
                  storagePath: doc['bir_cor_url']?.toString(),
                  label: 'BIR COR',
                ),
                const SizedBox(width: 8),
                VerificationDocThumb(
                  storagePath: doc['permit_url']?.toString(),
                  label: 'Mayor’s / barangay permit',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Tap a document to view it full-size.',
              style: AppConstants.bodyStyle(
                fontSize: 11,
                color: AppConstants.secondary.withValues(alpha: 0.45),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'No documents submitted yet.',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ),
            ),
          ],
          if (status == 'pending' || status == 'rejected') ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: busy ? null : () => onVerdict(false),
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
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: busy ? null : () => onVerdict(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppConstants.success,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Verify'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool _notEmpty(dynamic value) =>
      value != null && value.toString().trim().isNotEmpty;
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'verified' => (AppConstants.success, 'Verified'),
      'pending' => (AppConstants.statusPendingColor, 'Pending'),
      'rejected' => (AppConstants.error, 'Rejected'),
      _ => (AppConstants.borderGray, 'None'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppConstants.bodyStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
