import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import 'dev_mode_badge.dart';

/// Shared 4px/8px spacing scale for every auth/signup screen, so the
/// rhythm is identical across the role-choice, customer and seller flows.
/// Use these instead of ad-hoc EdgeInsets values in the auth module.
class AuthSpacing {
  AuthSpacing._();

  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s56 = 56;
}

/// The shared page chrome for every new signup screen: warm cream
/// background + noise, a small-caps eyebrow, a serif display headline and
/// a sans subtitle, a scrollable body, and an optional pinned footer.
///
/// Two optional modes keep every auth screen on one scaffold:
/// - [background] paints a full-bleed layer behind everything (e.g. the
///   role-choice video hero). When set, the noise overlay is skipped and the
///   screen renders in [lightContent] colors by default.
/// - [lightContent] flips the chrome to sit over dark footage: cream
///   eyebrow, white headline, translucent white subtitle, cream back button,
///   and a transparent footer. The header block then reads as a pinned hero
///   header and the footer as a pinned actions bar, with the video showing
///   through the empty middle (SignupScaffold's scroll view still handles
///   overflow on short screens / large accessibility text — the footer stays
///   pinned while the header scrolls).
///
/// Typography and spacing are deliberately consistent across every caller
/// (the type scale is 30 / 24 / 18 / 15 / 13 / 12 — see the design spec).
class SignupScaffold extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final bool showBackButton;

  /// Optional back handler. When provided it replaces the default
  /// `Navigator.maybePop()` — used by the seller flow so back moves to the
  /// previous step instead of leaving the flow.
  final VoidCallback? onBack;

  final List<Widget>? appBarActions;
  final EdgeInsetsGeometry contentPadding;

  /// Full-bleed layer painted behind everything (video hero, image, etc.).
  /// The noise overlay is skipped while a background is present.
  final Widget? background;

  /// Light chrome for dark/video backdrops — cream eyebrow, white headline,
  /// translucent subtitle, cream back button and a transparent footer.
  final bool lightContent;

  /// Renders the top bar (back button row) at all. Disabled for full-bleed
  /// hero screens so the header block starts right under the status bar.
  final bool showTopBar;

  const SignupScaffold({
    super.key,
    this.eyebrow,
    required this.title,
    this.subtitle,
    required this.child,
    this.footer,
    this.showBackButton = true,
    this.onBack,
    this.appBarActions,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 24),
    this.background,
    this.lightContent = false,
    this.showTopBar = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Dark base when lightContent so there is never a cream flash before
      // the video/backdrop paints (and a safe fallback if it fails to load).
      backgroundColor:
          lightContent ? AppConstants.surfaceDark : AppConstants.surfaceLight,
      body: Stack(
        children: [
          if (background != null) Positioned.fill(child: background!),
          if (!lightContent) AppConstants.noiseOverlay(opacity: 0.04),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showTopBar) _buildTopBar(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: contentPadding.horizontal / 2,
                      right: contentPadding.horizontal / 2,
                      top: lightContent ? AuthSpacing.s8 : 0,
                      // Zero-overlap clearance: when a pinned footer is
                      // present the scroll content needs generous bottom
                      // padding so the last card never sits flush against it.
                      bottom:
                          footer == null ? AuthSpacing.s40 : AuthSpacing.s56,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (eyebrow != null) ...[
                          Text(
                            eyebrow!.toUpperCase(),
                            style: lightContent
                                ? AppConstants.bodyStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.6,
                                    color: AppConstants.surfaceLight,
                                  )
                                : AppConstants.bodyStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.6,
                                    color: AppConstants.primary,
                                  ),
                          ),
                          const SizedBox(height: AuthSpacing.s8),
                        ],
                        Text(
                          title,
                          style: lightContent
                              ? AppConstants.headlineStyle(
                                  fontSize: 28, color: Colors.white)
                              : AppConstants.headlineStyle(fontSize: 30),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: AuthSpacing.s8),
                          Text(
                            subtitle!,
                            style: lightContent
                                ? AppConstants.bodyStyle(
                                    fontSize: 14,
                                    color: Colors.white.withValues(alpha: 0.85),
                                    height: 1.45,
                                  )
                                : AppConstants.bodyStyle(
                                    fontSize: 15,
                                    color: AppConstants.secondary
                                        .withValues(alpha: 0.65),
                                    height: 1.45,
                                  ),
                          ),
                        ],
                        const SizedBox(height: AuthSpacing.s24),
                        child,
                      ],
                    ),
                  ),
                ),
                if (footer != null) ...[
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(
                      AuthSpacing.s24,
                      AuthSpacing.s12,
                      AuthSpacing.s24,
                      AuthSpacing.s16,
                    ),
                    // Over a full-bleed video the footer is transparent — the
                    // actions block draws its own divider. On the light
                    // screens it keeps the cream bar + hairline.
                    decoration: lightContent
                        ? null
                        : const BoxDecoration(
                            color: AppConstants.surfaceLight,
                            border: Border(
                              top: BorderSide(color: AppConstants.borderGray),
                            ),
                          ),
                    child: footer,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AuthSpacing.s8,
        AuthSpacing.s8,
        AuthSpacing.s8,
        0,
      ),
      child: Row(
        children: [
          if (showBackButton)
            // 44x44 minimum tap target with a screen-reader label.
            IconButton(
              onPressed:
                  onBack ?? () => Navigator.of(context).maybePop(),
              tooltip: 'Back',
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 20,
                color: lightContent
                    ? AppConstants.surfaceLight
                    : AppConstants.secondary,
              ),
              constraints: const BoxConstraints(
                minWidth: 44,
                minHeight: 44,
              ),
            )
          else
            const SizedBox(width: 44),
          const Spacer(),
          // ⚠️ DEV MODE — REMOVE BEFORE RELEASE (docs/AI/DEV_MODE_ARCHITECTURE.md):
          // persistent chip while the UI-only skip mode is active.
          const DevModeBadge(),
          ...?appBarActions,
        ],
      ),
    );
  }
}
