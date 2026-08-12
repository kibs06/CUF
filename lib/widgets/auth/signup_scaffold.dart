import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';

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
/// Typography and spacing are deliberately consistent across every caller
/// (the type scale is 30 / 24 / 18 / 15 / 13 / 12 — see the design spec).
class SignupScaffold extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final bool showBackButton;
  final List<Widget>? appBarActions;
  final EdgeInsetsGeometry contentPadding;

  const SignupScaffold({
    super.key,
    this.eyebrow,
    required this.title,
    this.subtitle,
    required this.child,
    this.footer,
    this.showBackButton = true,
    this.appBarActions,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 24),
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.04),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopBar(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: contentPadding.horizontal / 2,
                      right: contentPadding.horizontal / 2,
                      bottom: footer == null ? AuthSpacing.s40 : AuthSpacing.s16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (eyebrow != null) ...[
                          Text(
                            eyebrow!.toUpperCase(),
                            style: AppConstants.bodyStyle(
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
                          style: AppConstants.headlineStyle(fontSize: 30),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: AuthSpacing.s8),
                          Text(
                            subtitle!,
                            style: AppConstants.bodyStyle(
                              fontSize: 15,
                              color:
                                  AppConstants.secondary.withValues(alpha: 0.65),
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
                    decoration: const BoxDecoration(
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
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: 'Back',
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 20,
                color: AppConstants.secondary,
              ),
              constraints: const BoxConstraints(
                minWidth: 44,
                minHeight: 44,
              ),
            )
          else
            const SizedBox(width: 44),
          const Spacer(),
          ...?appBarActions,
        ],
      ),
    );
  }
}
