import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/auth/signup_scaffold.dart';

/// Locked screen for seller applicants awaiting admin approval.
///
/// Redesigned from the legacy one-message stub: it now shows exactly which
/// Tier 1 items were submitted (driving trust that nothing was lost),
/// explains that Tier 2 business verification is OPTIONAL and never gates
/// selling, and keeps the Log Out behavior unchanged.
class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = auth.profile ?? const <String, dynamic>{};

    final firstName = _firstName(auth.displayName);
    final hasId = _notEmpty(profile['id_document_url']);
    final hasSelfie = _notEmpty(profile['selfie_url']);
    final hasCommunity =
        _notEmpty(profile['cufmai_member_id']) ||
        _notEmpty(profile['barangay_proof_url']);
    final hasStore = _notEmpty(profile['store_name']);
    final hasPayout =
        _notEmpty(profile['payout_details']) ||
        _notEmpty(profile['payout_method']);

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AuthSpacing.s24,
                AuthSpacing.s24,
                AuthSpacing.s24,
                AuthSpacing.s40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: AppConstants.statusPendingColor.withValues(
                          alpha: 0.14,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppConstants.statusPendingColor.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      child: const Icon(
                        Icons.hourglass_top_rounded,
                        color: AppConstants.statusPendingColor,
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(height: AuthSpacing.s20),
                  Text(
                    'Application under review',
                    textAlign: TextAlign.center,
                    style: AppConstants.headlineStyle(fontSize: 26),
                  ),
                  const SizedBox(height: AuthSpacing.s8),
                  Text(
                    'Thanks, $firstName! Your seller application is now with our team. We’ll open your seller dashboard as soon as an admin approves you.',
                    textAlign: TextAlign.center,
                    style: AppConstants.bodyStyle(
                      fontSize: 14,
                      color: AppConstants.secondary.withValues(alpha: 0.7),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: AuthSpacing.s24),

                  // ── What we received ──────────────────────────
                  _SectionCard(
                    title: 'What we received',
                    icon: Icons.verified_outlined,
                    children: [
                      _ReceivedRow(
                        icon: Icons.person_outline,
                        label: 'Full name & contact details',
                        done: true,
                      ),
                      _ReceivedRow(
                        icon: Icons.badge_outlined,
                        label: 'Government ID photo',
                        done: hasId,
                      ),
                      _ReceivedRow(
                        icon: Icons.face_outlined,
                        label: 'Liveness selfie',
                        done: hasSelfie,
                      ),
                      _ReceivedRow(
                        icon: Icons.groups_outlined,
                        label: 'CUFMAI membership / barangay proof',
                        done: hasCommunity,
                      ),
                      _ReceivedRow(
                        icon: Icons.storefront_outlined,
                        label: 'Store name & description',
                        done: hasStore,
                      ),
                      _ReceivedRow(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Payout details',
                        done: hasPayout,
                      ),
                    ],
                  ),
                  const SizedBox(height: AuthSpacing.s16),

                  // ── Tier 2 explainer ──────────────────────────
                  Container(
                    padding: const EdgeInsets.all(AuthSpacing.s16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppConstants.primary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppConstants.accent.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.business_center_outlined,
                                color: AppConstants.accent,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: AuthSpacing.s12),
                            Expanded(
                              child: Text(
                                'Optional: Business verification (Tier 2)',
                                style: AppConstants.bodyStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AuthSpacing.s12),
                        Text(
                          'Once you’re approved, you can add your DTI certificate, BIR COR or mayor’s/barangay permit from your Profile → Settings. It’s completely optional — most artisans start without it — and it never affects your ability to sell.',
                          style: AppConstants.bodyStyle(
                            fontSize: 13,
                            color: AppConstants.secondary.withValues(alpha: 0.7),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AuthSpacing.s24),

                  // ── Actions ───────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () => context.read<AuthProvider>().logout(),
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Log out'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppConstants.error,
                        side: BorderSide(
                          color: AppConstants.error.withValues(alpha: 0.4),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _notEmpty(dynamic value) =>
      value != null && value.toString().trim().isNotEmpty;

  String _firstName(String fullName) {
    final first = fullName.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? 'there' : first;
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AuthSpacing.s16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppConstants.borderGray.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppConstants.primary),
              const SizedBox(width: AuthSpacing.s8),
              Text(
                title,
                style: AppConstants.bodyStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AuthSpacing.s12),
          ...children,
        ],
      ),
    );
  }
}

class _ReceivedRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool done;

  const _ReceivedRow({
    required this.icon,
    required this.label,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AuthSpacing.s4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: done
                ? AppConstants.success
                : AppConstants.secondary.withValues(alpha: 0.35),
          ),
          const SizedBox(width: AuthSpacing.s12),
          Expanded(
            child: Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: done
                    ? AppConstants.secondary
                    : AppConstants.secondary.withValues(alpha: 0.45),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: done
                ? const Icon(
                    Icons.check_circle_rounded,
                    key: ValueKey('done'),
                    size: 19,
                    color: AppConstants.success,
                  )
                : const Icon(
                    Icons.radio_button_unchecked_rounded,
                    key: ValueKey('pending'),
                    size: 19,
                    color: AppConstants.borderGray,
                  ),
          ),
        ],
      ),
    );
  }
}
