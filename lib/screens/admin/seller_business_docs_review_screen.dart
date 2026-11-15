import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      // A retry after a rejection is a row the admin already turned down
      // once. `created_at` never moves, so the queue's existing order buried
      // it behind first-time submissions that arrived later — lift it, and
      // keep the rest in the same newest-first order it arrived in.
      final sorted = List<Map<String, dynamic>>.from(docs)
        ..sort((a, b) {
          final aRetry = _isResubmission(a);
          final bRetry = _isResubmission(b);
          if (aRetry != bRetry) return aRetry ? -1 : 1;
          final aAt = DateTime.tryParse(a['created_at']?.toString() ?? '');
          final bAt = DateTime.tryParse(b['created_at']?.toString() ?? '');
          if (aAt == null || bAt == null) return 0;
          return bAt.compareTo(aAt);
        });
      if (mounted) setState(() => _docs = sorted);
    } catch (e) {
      debugPrint('[BizDocsReview] load failed: $e');
      if (mounted) {
        setState(() => _error = 'Could not load business verifications.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// A pending row that carries the resubmission stamp: the seller fixed a
  /// submission this queue had already rejected.
  bool _isResubmission(Map<String, dynamic> doc) =>
      doc['verification_status'] == AppConstants.bizStatusPending &&
      doc['resubmitted_at'] != null;

  int get _resubmissionCount => _docs.where(_isResubmission).length;

  Future<void> _verdict(
    String docId, {
    String? profileId,
    required bool verified,
  }) async {
    if (_busyDocId != null) return;
    setState(() => _busyDocId = docId);
    try {
      await _auth.setBusinessVerificationStatus(
        docId,
        verified: verified,
      );
      // The badge (profiles.seller_verified_at) and the in-app notification
      // are written by the DB triggers; the email and push are this call's
      // job.
      if (verified) {
        _sendVerifiedEmail(profileId);
        _sendVerifiedPush(profileId);
      }
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

  /// Fire-and-forget: tell the seller (by email) that the Verified Seller
  /// badge is live. Sent as the existing `approved` outcome plus the additive
  /// `verified` flag, so an older deployed copy of the function still sends
  /// the approval mail rather than mis-reading a new outcome as a rejection.
  /// A failed email never fails the verdict.
  void _sendVerifiedEmail(String? profileId) {
    if (profileId == null || profileId.isEmpty) return;
    try {
      Supabase.instance.client.functions
          .invoke('send-approval-email', body: {
        'userId': profileId,
        'outcome': 'approved',
        'verified': true,
      }).catchError((Object e) {
        debugPrint('[BizDocsReview] verified email trigger failed: $e');
        return FunctionResponse(status: 500);
      });
    } catch (e) {
      debugPrint('[BizDocsReview] verified email trigger failed: $e');
    }
  }

  /// Fire-and-forget: wake the seller's lock screen with the same notice the
  /// DB trigger just wrote to their bell. The in-app row is authoritative;
  /// a failed push never fails the verdict.
  void _sendVerifiedPush(String? profileId) {
    if (profileId == null || profileId.isEmpty) return;
    try {
      Supabase.instance.client.functions
          .invoke('send-notification-push', body: {
        'recipientUserId': profileId,
        'title': 'You\'re a verified seller ✅',
        'body': 'Your business documents were approved. Your Verified Seller '
            'badge is now showing on your profile and store page.',
        'type': 'verified_seller',
        'screen': 'seller_notifications',
      }).catchError((Object e) {
        debugPrint('[BizDocsReview] verified push trigger failed: $e');
        return FunctionResponse(status: 500);
      });
    } catch (e) {
      debugPrint('[BizDocsReview] verified push trigger failed: $e');
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
        itemCount: _docs.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The alert. A resubmission is the one row in this queue
                  // whose author is waiting on a verdict they have already
                  // been refused once — say so before the explanation does.
                  if (_resubmissionCount > 0) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC47D00).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFC47D00).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.fact_check_outlined,
                            color: Color(0xFFC47D00),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _resubmissionCount == 1
                                  ? '1 seller resubmitted after a rejection '
                                      '— they are first in the list.'
                                  : '$_resubmissionCount sellers resubmitted '
                                      'after a rejection — they are first in '
                                      'the list.',
                              style: AppConstants.bodyStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFC47D00),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    'Verifying grants the seller the Verified Seller badge on their '
                    'profile and public store page, and tells them in-app and by '
                    'email. Rejecting withdraws the badge. Approving a seller in '
                    'the Applications tab verifies their documents automatically.',
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: AppConstants.secondary.withValues(alpha: 0.65),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            );
          }
          final doc = _docs[index - 1];
          return _DocCard(
            doc: doc,
            busy: _busyDocId == doc['id'].toString(),
            onVerdict: (verified) => _verdict(
              doc['id'].toString(),
              profileId: doc['profile_id']?.toString(),
              verified: verified,
            ),
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
        color: AppConstants.surfaceLight,
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
                    // "Second attempt" is not decoration: it tells the
                    // reviewer this seller has already been refused once and
                    // came back, which is exactly the row that must not sit.
                    if (status == 'pending' &&
                        doc['resubmitted_at'] != null) ...[
                      const SizedBox(height: 6),
                      _ResubmittedChip(
                        at: DateTime.tryParse(
                          doc['resubmitted_at'].toString(),
                        ),
                      ),
                    ],
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

/// Amber pill marking a retry, with how long it has been waiting.
class _ResubmittedChip extends StatelessWidget {
  final DateTime? at;

  const _ResubmittedChip({this.at});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFC47D00).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.replay, size: 12, color: Color(0xFFC47D00)),
          const SizedBox(width: 4),
          Text(
            'Resubmitted ${_relativeAgo(at)}',
            style: AppConstants.bodyStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFC47D00),
            ),
          ),
        ],
      ),
    );
  }
}

String _relativeAgo(DateTime? at) {
  if (at == null) return 'recently';
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
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
