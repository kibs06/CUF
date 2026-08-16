import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../widgets/auth/sole_primary_auth_button.dart';

/// One-time celebration screen shown when a seller application is approved.
///
/// AuthGate routes here (instead of straight into SellerShell) the first
/// time an approved seller opens the app. It congratulates the applicant,
/// welcomes them into the CUFMAI family, and hands off to the dashboard via
/// [onGoToDashboard]. AuthGate persists a per-user "seen" flag, so this only
/// ever appears once — every subsequent launch goes straight to the shell.
///
/// Design: warm and celebratory but still on-brand — cream background,
/// a pulsing gold medallion, and a single clear CTA.
class SellerApprovedCelebrationScreen extends StatefulWidget {
  final String userName;
  final VoidCallback onGoToDashboard;

  const SellerApprovedCelebrationScreen({
    super.key,
    required this.userName,
    required this.onGoToDashboard,
  });

  @override
  State<SellerApprovedCelebrationScreen> createState() =>
      _SellerApprovedCelebrationScreenState();
}

class _SellerApprovedCelebrationScreenState
    extends State<SellerApprovedCelebrationScreen>
    with SingleTickerProviderStateMixin {
  /// Drives the medallion's pulsing gold halo.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  late final Animation<double> _ring =
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firstName = widget.userName.trim().split(RegExp(r'\s+')).first;
    final displayName = firstName.isEmpty ? 'there' : firstName;

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Medallion with pulsing halo ────────────────
                  Center(
                    child: SizedBox(
                      width: 112,
                      height: 112,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _ring,
                            builder: (context, child) {
                              final t = _ring.value;
                              return Transform.scale(
                                scale: 1 + t * 0.1,
                                child: Opacity(
                                  opacity: 1 - t * 0.45,
                                  child: child,
                                ),
                              );
                            },
                            child: Container(
                              width: 112,
                              height: 112,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppConstants.statusPendingColor
                                    .withValues(alpha: 0.16),
                              ),
                            ),
                          ),
                          Container(
                            width: 92,
                            height: 92,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFA4703A), Color(0xFF7A4C20)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppConstants.primary.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.celebration_rounded,
                              color: Colors.white,
                              size: 44,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Eyebrow + headline ─────────────────────────
                  Text(
                    'CONGRATULATIONS!',
                    textAlign: TextAlign.center,
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: AppConstants.statusPendingColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'You’re now part of the\nCUFMAI family!',
                    textAlign: TextAlign.center,
                    style: AppConstants.headlineStyle(fontSize: 28),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Welcome aboard, $displayName. Your application was '
                    'approved — you’re now a certified CUFMAI seller. '
                    'Your store is ready: set it up, list your products, '
                    'and start selling to the Carcar community.',
                    textAlign: TextAlign.center,
                    style: AppConstants.bodyStyle(
                      fontSize: 14,
                      color: AppConstants.secondary.withValues(alpha: 0.7),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── What you can do now (white card) ──────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: AppConstants.premiumCardRadius,
                      border: Border.all(
                        color: AppConstants.borderGray.withValues(alpha: 0.5),
                      ),
                      boxShadow: AppConstants.premiumCardShadow,
                    ),
                    child: Column(
                      children: [
                        _BenefitRow(
                          icon: Icons.storefront_rounded,
                          title: 'Set up your store',
                          caption: 'Name, banner, and tags are already '
                              'pre-filled from your application.',
                        ),
                        const _BenefitDivider(),
                        _BenefitRow(
                          icon: Icons.inventory_2_outlined,
                          title: 'List your products',
                          caption: 'Add your handmade shoes and start '
                              'receiving orders.',
                        ),
                        const _BenefitDivider(),
                        _BenefitRow(
                          icon: Icons.people_outline_rounded,
                          title: 'Grow with CUFMAI',
                          caption: 'Reach the local community as a '
                              'certified member.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'A confirmation email is on its way — if you don’t '
                    'see it, check your spam or promotions folder.',
                    textAlign: TextAlign.center,
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: AppConstants.secondary.withValues(alpha: 0.5),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── CTA ────────────────────────────────────────
                  SolePrimaryAuthButton(
                    label: 'Go to dashboard  →',
                    onPressed: widget.onGoToDashboard,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One benefit row in the white card.
class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String caption;

  const _BenefitRow({
    required this.icon,
    required this.title,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppConstants.primary.withValues(alpha: 0.1),
          ),
          child: Icon(icon, size: 19, color: AppConstants.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppConstants.bodyStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.secondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary.withValues(alpha: 0.6),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Faint horizontal divider between benefit rows.
class _BenefitDivider extends StatelessWidget {
  const _BenefitDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Container(
        height: 1,
        color: AppConstants.borderGray.withValues(alpha: 0.35),
      ),
    );
  }
}
