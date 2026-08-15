import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';

/// Primary CTA used by the auth screens (role choice + seller flow steps).
/// Wraps the app's standard SolePrimaryButton styling so the auth module
/// keeps one button look; adds an inline loading spinner for async actions.
///
/// [borderRadius] and [boxShadow] are optional so the video-hero role-choice
/// screen can drop the button onto footage (14px corners + a subtle shadow so
/// it reads as tappable over the moving background) without changing the
/// seller flow's default look.
class SolePrimaryAuthButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double borderRadius;
  final List<BoxShadow>? boxShadow;

  const SolePrimaryAuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.borderRadius = 12,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: boxShadow,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppConstants.primary,
            disabledBackgroundColor: AppConstants.primary.withValues(alpha: 0.6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(borderRadius),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  label,
                  style: AppConstants.bodyStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}
