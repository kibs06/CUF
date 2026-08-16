import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import 'signup_scaffold.dart';

/// Segmented progress bar for the seller application flow — a row of thin,
/// equal-width segments that fill in as the applicant advances, with a
/// single caption line underneath (`Step X of 4 · Step name`).
///
/// Replaces the old numbered-circle stepper: at mobile widths the per-step
/// text labels truncated ("Acc...", "Iden..."), so the step name now lives
/// in the caption instead. Segments before the current step are fully
/// filled (completed), the current step's segment is filled (active, same
/// treatment — the caption already says where you are), and later segments
/// stay on the light track color.
///
/// [currentStep] is zero-based. Flat and minimal by design — no shadows,
/// gradients or borders — consistent with the cream form around it.
class StepProgressIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final List<String> labels;

  const StepProgressIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.labels,
  }) : assert(labels.length == totalSteps);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < totalSteps; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= currentStep
                        ? AppConstants.primary
                        : AppConstants.borderGray.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AuthSpacing.s12),
        // The only step label on screen — "Step 1 of 4 · Account".
        // Plain single line: no badges, no per-step labels to truncate.
        Text(
          'Step ${currentStep + 1} of $totalSteps · ${labels[currentStep]}',
          style: AppConstants.bodyStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppConstants.secondary.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}
