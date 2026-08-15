import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_constants.dart';
import '../../widgets/auth/full_bleed_video_background.dart';
import '../../widgets/auth/signup_scaffold.dart';
import '../../widgets/auth/sole_primary_auth_button.dart';
import 'customer_register_screen.dart';
import 'seller_application_flow.dart';

/// First screen of registration: a deliberate role choice instead of the
/// legacy single form with an "Apply as a seller" toggle buried at the
/// bottom.
///
/// The screen is a **full-bleed video hero**. `video/locals.mp4` loops
/// muted behind everything (measured with ffmpeg `signalstats`: full-frame
/// mean luma ≈ 89/255, worst-case ≈ 146 in the top band / 118 in the bottom
/// band), and the scrim values below are tuned to those measurements so the
/// white/cream chrome keeps ≥ 4.5:1 contrast on every frame that matters:
///
/// - **Global dim** `surfaceDark @ 0.20` — a subtle full-frame veil so the
///   empty middle band can never blow out.
/// - **Top scrim** `0.95 → 0.70 → 0` over `0 → 32% → 55%` height — protects
///   the pinned header block (worst-case top-band frame, luma 146, → ≥ 4.6:1
///   on the 85%-white subtitle, higher on the eyebrow and title).
/// - **Bottom scrim** `0 → 0.98` over `25% → 100%` height — protects the
///   pinned actions block (worst-case bottom frame, luma 118, → ≥ 4.5:1 on
///   the cream seller link, higher on the button and sign-in row).
///
/// Layout: header block pinned top, actions block pinned bottom, empty
/// middle where the video is unobstructed. On short screens / large
/// accessibility text `SignupScaffold`'s scroll view takes over while the
/// footer stays pinned (the documented fallback — nothing ever overlaps the
/// video). The app has no dark theme; this screen is inherently dark, so it
/// is light-theme-only like the rest of auth.
class RoleChoiceScreen extends StatelessWidget {
  const RoleChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SignupScaffold(
      background: const _VideoHero(),
      lightContent: true,
      showTopBar: false,
      showBackButton: false,
      eyebrow: 'CUFMAI',
      title: 'Create your account',
      subtitle: 'Join the home of Carcar footwear craftsmanship.',
      // Empty middle — the video stays unobstructed between the pinned
      // header and the pinned actions block.
      footer: const _ActionsBlock(),
      child: const SizedBox.shrink(),
    );
  }
}

/// The full-bleed background layer passed to `SignupScaffold.background`:
/// the looping video, a subtle global dim, and the top/bottom scrims tuned
/// to the measured luminance of `video/locals.mp4` (see the class doc).
class _VideoHero extends StatelessWidget {
  const _VideoHero();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const FullBleedVideoBackground(asset: 'video/locals.mp4'),
        // Subtle full-frame veil (measured mean luma ≈ 89 → never needs
        // more than this to protect the empty middle band).
        ColoredBox(
          color: AppConstants.surfaceDark.withValues(alpha: 0.20),
        ),
        // Top scrim — keeps the pinned header block readable even on the
        // brightest top-band frames (luma up to ≈ 146).
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.32, 0.55],
              colors: [
                Color(0xF21A1208), // surfaceDark @ 0.95
                Color(0xB31A1208), // surfaceDark @ 0.70
                Color(0x001A1208), // transparent
              ],
            ),
          ),
        ),
        // Bottom scrim — keeps the actions block readable over the bottom
        // band (luma up to ≈ 118). Starts a touch higher (25%) so the seller
        // link's cream copy clears 4.5:1 even on the single brightest frame.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.25, 1.0],
              colors: [
                Color(0x001A1208), // transparent
                Color(0xFA1A1208), // surfaceDark @ 0.98
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Pinned bottom actions: the primary customer CTA, the secondary seller
/// link, and the sign-in footer separated by a light hairline. The button is
/// the customer path; the seller row is a link-style affordance (no border,
/// no fill) that still gets a ≥44px tap target.
class _ActionsBlock extends StatelessWidget {
  const _ActionsBlock();

  void _openCustomer(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CustomerRegisterScreen()),
    );
  }

  void _openSeller(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SellerApplicationFlow()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PressScale(
          child: SolePrimaryAuthButton(
            label: 'Shop as customer?',
            borderRadius: 14,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
            onPressed: () => _openCustomer(context),
          ),
        ),
        const SizedBox(height: AuthSpacing.s16),
        _SellerLink(onTap: () => _openSeller(context)),
        const SizedBox(height: AuthSpacing.s16),
        // Light hairline separating the sign-in footer from the actions.
        Container(
          height: 1,
          color: Colors.white.withValues(alpha: 0.22),
        ),
        const SizedBox(height: AuthSpacing.s16),
        _SignInRow(),
      ],
    );
  }
}

/// "A shoemaker or artisan? Apply to sell" — a centered link-style row that
/// pushes into the existing 4-step seller application flow. The whole row is
/// the tap target (≥44px, `Semantics` button). Deliberately NOT a filled
/// button: no border, no fill — just the copy, so it reads clearly secondary
/// to the customer CTA without looking disabled.
class _SellerLink extends StatefulWidget {
  final VoidCallback onTap;

  const _SellerLink({required this.onTap});

  @override
  State<_SellerLink> createState() => _SellerLinkState();
}

class _SellerLinkState extends State<_SellerLink> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'A shoemaker or artisan? Apply to sell on SoleVision',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          scale: _pressed ? 0.99 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) {
              HapticFeedback.lightImpact();
              setState(() => _pressed = true);
            },
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) => setState(() => _pressed = false),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: AuthSpacing.s8,
                vertical: AuthSpacing.s8,
              ),
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.transparent,
              child: Text.rich(
                TextSpan(
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  children: [
                    const TextSpan(text: 'A shoemaker or artisan? '),
                    TextSpan(
                      text: 'Apply to sell',
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.surfaceLight,
                      ).copyWith(
                        decoration: TextDecoration.underline,
                        decorationColor: AppConstants.surfaceLight
                            .withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Already have an account? Sign in" — pops back to the login screen, the
/// same destination as the previous footer.
class _SignInRow extends StatelessWidget {
  const _SignInRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Already have an account? ',
          style: AppConstants.bodyStyle(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: AuthSpacing.s8,
            ),
            child: Text(
              'Sign in',
              style: AppConstants.bodyStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppConstants.surfaceLight,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Subtle press feedback consistent with the auth module's motion language
/// (scale + light haptic on press). Uses raw pointer events (not a tap
/// recognizer) so it never competes with the wrapped button's own `onPressed`
/// in the gesture arena — the scale is purely cosmetic feedback.
class _PressScale extends StatefulWidget {
  final Widget child;

  const _PressScale({required this.child});

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        HapticFeedback.lightImpact();
        setState(() => _pressed = true);
      },
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
