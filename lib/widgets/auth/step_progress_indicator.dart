import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import 'signup_scaffold.dart';

/// Horizontal stepper for the seller application flow — numbered circles
/// connected by animated lines, with short labels beneath each step so the
/// applicant always knows how many steps remain and what comes next.
///
/// [currentStep] is zero-based. Completed steps fill with the brand color
/// and show a check; the current step is a bold outlined circle.
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
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < totalSteps; i++) ...[
              if (i > 0)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 15),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 2,
                      color: i <= currentStep
                          ? AppConstants.primary
                          : AppConstants.borderGray.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              _StepCircle(
                index: i,
                isCurrent: i == currentStep,
                isCompleted: i < currentStep,
              ),
            ],
          ],
        ),
        const SizedBox(height: AuthSpacing.s8),
        Row(
          children: [
            for (var i = 0; i < totalSteps; i++) ...[
              if (i > 0)
                Expanded(
                  child: SizedBox(
                    height: 14,
                    child: Center(
                      child: Text(
                        labels[i],
                        overflow: TextOverflow.ellipsis,
                        style: AppConstants.bodyStyle(
                          fontSize: 11,
                          fontWeight:
                              i == currentStep ? FontWeight.bold : FontWeight.w500,
                          color: i <= currentStep
                              ? AppConstants.secondary
                              : AppConstants.secondary.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ),
                ),
              SizedBox(
                width: 32,
                child: Center(
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      fontWeight:
                          i == currentStep ? FontWeight.bold : FontWeight.w500,
                      color: i <= currentStep
                          ? AppConstants.secondary
                          : AppConstants.secondary.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _StepCircle extends StatelessWidget {
  final int index;
  final bool isCurrent;
  final bool isCompleted;

  const _StepCircle({
    required this.index,
    required this.isCurrent,
    required this.isCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCompleted
            ? AppConstants.primary
            : (isCurrent ? Colors.white : AppConstants.surfaceLight),
        border: Border.all(
          color: isCurrent
              ? AppConstants.primary
              : (isCompleted
                  ? AppConstants.primary
                  : AppConstants.borderGray),
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: isCompleted
              ? const Icon(
                  Icons.check_rounded,
                  key: ValueKey('check'),
                  size: 18,
                  color: Colors.white,
                )
              : Text(
                  '${index + 1}',
                  key: const ValueKey('number'),
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isCurrent
                        ? AppConstants.primary
                        : AppConstants.secondary.withValues(alpha: 0.4),
                  ),
                ),
        ),
      ),
    );
  }
}
