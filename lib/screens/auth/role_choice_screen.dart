import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../widgets/auth/signup_scaffold.dart';
import 'customer_register_screen.dart';
import 'seller_application_flow.dart';

/// New first screen of registration: a deliberate role choice instead of
/// the legacy single form with a "Apply as a seller" toggle buried at the
/// bottom. Seller applicants now get an honest preview of the higher-stakes
/// flow (ID, selfie, community proof, admin review) BEFORE they start it.
class RoleChoiceScreen extends StatelessWidget {
  const RoleChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SignupScaffold(
      eyebrow: 'SOLEVISION',
      title: 'Create your account',
      subtitle:
          'Choose how you want to join the home of Carcar footwear craftsmanship.',
      showBackButton: false,
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Already have an account? ',
            style: AppConstants.bodyStyle(
              color: AppConstants.secondary.withValues(alpha: 0.7),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Text(
              'Sign in',
              style: AppConstants.bodyStyle(
                fontWeight: FontWeight.bold,
                color: AppConstants.primary,
              ),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RoleCard(
            icon: Icons.shopping_bag_outlined,
            iconColor: AppConstants.primary,
            title: 'Shop as a customer',
            description:
                'Browse artisan stores, order handcrafted footwear, and track every delivery.',
            bullets: const [
              'Custom-made shoes & virtual try-on',
              'GCash, card or cash on delivery',
              'Chat directly with artisans',
            ],
            buttonLabel: 'Continue as customer',
            buttonVariant: _RoleButtonVariant.primary,
            onTap: () => _open(context, const CustomerRegisterScreen()),
          ),
          const SizedBox(height: AuthSpacing.s16),
          _RoleCard(
            icon: Icons.storefront_outlined,
            iconColor: AppConstants.secondary,
            title: 'Apply as a seller',
            description:
                'Sell your handcrafted footwear to Carcar and beyond — with a real storefront and a POS.',
            bullets: const [
              '4-step application · about 5 minutes',
              'Needs a valid government ID + selfie',
              'Admin review before you can sell',
            ],
            buttonLabel: 'Apply as a seller',
            buttonVariant: _RoleButtonVariant.dark,
            onTap: () => _open(context, const SellerApplicationFlow()),
          ),
          const SizedBox(height: AuthSpacing.s24),
          _trustStrip(),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  Widget _trustStrip() {
    return Container(
      padding: const EdgeInsets.all(AuthSpacing.s16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppConstants.borderGray.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.shield_outlined,
            size: 20,
            color: AppConstants.success,
          ),
          const SizedBox(width: AuthSpacing.s12),
          Expanded(
            child: Text(
              'Your documents are private — only SoleVision admins can view them.',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _RoleButtonVariant { primary, dark }

class _RoleCard extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final List<String> bullets;
  final String buttonLabel;
  final _RoleButtonVariant buttonVariant;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.bullets,
    required this.buttonLabel,
    required this.buttonVariant,
    required this.onTap,
  });

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isPrimary = widget.buttonVariant == _RoleButtonVariant.primary;
    final buttonColor =
        isPrimary ? AppConstants.primary : AppConstants.secondary;

    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: const Duration(milliseconds: 120),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isPrimary
                ? AppConstants.primary.withValues(alpha: 0.35)
                : AppConstants.borderGray,
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) => setState(() => _pressed = false),
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(AuthSpacing.s20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: widget.iconColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          widget.icon,
                          color: widget.iconColor,
                          size: 24,
                        ),
                      ),
                      const Spacer(),
                      if (isPrimary)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppConstants.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Free',
                            style: AppConstants.bodyStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppConstants.success,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppConstants.statusPendingColor.withValues(
                              alpha: 0.14,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '4 steps · ~5 min',
                            style: AppConstants.bodyStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFB45309),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AuthSpacing.s16),
                  Text(
                    widget.title,
                    style: AppConstants.headlineStyle(fontSize: 20),
                  ),
                  const SizedBox(height: AuthSpacing.s8),
                  Text(
                    widget.description,
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: AppConstants.secondary.withValues(alpha: 0.65),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: AuthSpacing.s16),
                  for (final bullet in widget.bullets) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.check_circle_rounded,
                            size: 15,
                            color: isPrimary
                                ? AppConstants.success
                                : AppConstants.statusPendingColor,
                          ),
                        ),
                        const SizedBox(width: AuthSpacing.s8),
                        Expanded(
                          child: Text(
                            bullet,
                            style: AppConstants.bodyStyle(
                              fontSize: 12,
                              color: AppConstants.secondary.withValues(
                                alpha: 0.75,
                              ),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AuthSpacing.s8),
                  ],
                  const SizedBox(height: AuthSpacing.s12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: widget.onTap,
                      style: FilledButton.styleFrom(
                        backgroundColor: buttonColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        widget.buttonLabel,
                        style: AppConstants.bodyStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
