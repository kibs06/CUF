import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import 'signup_scaffold.dart';

enum PasswordStrength { tooShort, weak, fair, good, strong }

/// A four-segment password strength meter with a live label.
///
/// Scores 0–4 from a combination of length and character-class coverage
/// (lower / upper / digit / symbol). The segments and label animate with
/// AnimatedContainer / AnimatedDefaultTextStyle so strength feedback feels
/// immediate — a micro-interaction the design spec calls for on auth forms.
class PasswordStrengthMeter extends StatelessWidget {
  final String password;

  const PasswordStrengthMeter({super.key, required this.password});

  static PasswordStrength strengthOf(String password) {
    if (password.isEmpty) return PasswordStrength.tooShort;

    var score = 0;
    if (password.length >= 6) score++;
    if (password.length >= 10) score++;
    final classes = [
      RegExp(r'[a-z]').hasMatch(password),
      RegExp(r'[A-Z]').hasMatch(password),
      RegExp(r'[0-9]').hasMatch(password),
      RegExp(r'[^A-Za-z0-9]').hasMatch(password),
    ].where((present) => present).length;
    if (classes >= 2) score++;
    if (classes >= 3) score++;
    return PasswordStrength.values[score.clamp(0, 4)];
  }

  static String labelFor(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.tooShort:
        return 'Too short';
      case PasswordStrength.weak:
        return 'Weak';
      case PasswordStrength.fair:
        return 'Fair';
      case PasswordStrength.good:
        return 'Good';
      case PasswordStrength.strong:
        return 'Strong';
    }
  }

  static Color colorFor(PasswordStrength strength) {
    switch (strength) {
      case PasswordStrength.tooShort:
        return AppConstants.borderGray;
      case PasswordStrength.weak:
        return AppConstants.error;
      case PasswordStrength.fair:
        return AppConstants.statusPendingColor;
      case PasswordStrength.good:
        return AppConstants.statusConfirmedColor;
      case PasswordStrength.strong:
        return AppConstants.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strength = strengthOf(password);
    final score = strength.index;
    final color = colorFor(strength);
    final visible = password.isNotEmpty;

    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: visible
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < 4; i++) ...[
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            height: 4,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: i < score
                                  ? color
                                  : AppConstants.borderGray.withValues(
                                      alpha: 0.4,
                                    ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 220),
                        style: AppConstants.bodyStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                        child: Text(labelFor(strength)),
                      ),
                    ],
                  ),
                  const SizedBox(height: AuthSpacing.s8),
                ],
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
