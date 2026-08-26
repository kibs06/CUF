import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../providers/v2/scan_phase.dart';

/// Animated 4-segment progress stepper for the v2 scan session.
///
/// One segment per [CaptureStep] (Left·Top → Left·Side → Right·Top →
/// Right·Side), docked across the top of the camera view:
/// - Completed segments fill solid + draw an animated checkmark.
/// - The active segment shows a shimmering fill whose extent tracks capture
///   progress (0.0–1.0) while capturing, or a slow pulse while ready.
/// - Upcoming segments are dim outlines.
///
/// Purely presentational — the controller owns the state, this widget paints it.
class ScanStepper extends StatelessWidget {
  /// Index of the currently active step (0–3). `null` when no step is
  /// active (e.g. positioning/processing phases — all segments dim).
  final int? activeIndex;

  /// Capture progress (0.0–1.0) for the active segment's fill.
  final double activeProgress;

  /// Whether the active segment is actively sampling (vs waiting).
  final bool capturing;

  const ScanStepper({
    super.key,
    required this.activeIndex,
    this.activeProgress = 0,
    this.capturing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < CaptureStep.values.length; i++) ...[
          if (i > 0)
            Expanded(
              child: _Connector(
                connected: activeIndex != null && i <= activeIndex!,
              ),
            ),
          _StepDot(
            key: ValueKey('step-dot-$i'),
            state: i == activeIndex
                ? (capturing ? _StepState.capturing : _StepState.ready)
                : (activeIndex != null && i < activeIndex!
                    ? _StepState.done
                    : _StepState.upcoming),
            progress: i == activeIndex ? activeProgress.clamp(0.0, 1.0) : 0,
            label: CaptureStep.values[i].shortLabel,
          ),
        ],
      ],
    );
  }
}

extension on CaptureStep {
  /// Two-letter badge for the dot ("LT", "LS", "RT", "RS").
  String get shortLabel {
    switch (this) {
      case CaptureStep.leftTop:
        return 'L·T';
      case CaptureStep.leftSide:
        return 'L·S';
      case CaptureStep.rightTop:
        return 'R·T';
      case CaptureStep.rightSide:
        return 'R·S';
    }
  }
}

enum _StepState { upcoming, ready, capturing, done }

class _StepDot extends StatelessWidget {
  final _StepState state;
  final double progress;
  final String label;

  const _StepDot({
    super.key,
    required this.state,
    required this.progress,
    required this.label,
  });

  Color get _fill {
    switch (state) {
      case _StepState.upcoming:
        return Colors.white.withValues(alpha: 0.14);
      case _StepState.ready:
        return Colors.white.withValues(alpha: 0.3);
      case _StepState.capturing:
        return AppConstants.accent;
      case _StepState.done:
        return AppConstants.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDone = state == _StepState.done;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _fill,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: isDone
              ? const Icon(Icons.check_rounded,
                  key: ValueKey('check'), size: 18, color: Colors.white)
              : Text(
                  key: ValueKey(label),
                  label,
                  style: AppConstants.monoStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Thin line between dots; brightens once reached.
class _Connector extends StatelessWidget {
  final bool connected;

  const _Connector({required this.connected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 2,
      decoration: BoxDecoration(
        color: connected
            ? AppConstants.accent.withValues(alpha: 0.7)
            : Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}
