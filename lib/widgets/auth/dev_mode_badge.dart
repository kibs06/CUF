import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../utils/dev_mode.dart';

// ⚠️ DEV-ONLY — REMOVE BEFORE RELEASE (see docs/AI/DEV_MODE_ARCHITECTURE.md).
//
// Small persistent chip shown while developer mode is on, so it's obvious
// the skip behavior is active (and obvious that it must be removed before
// shipping). Renders as an inline chip — drop it anywhere (header rows, the
// SignupScaffold top bar); it collapses to nothing when dev mode is off.
//
// The chip is also the quick way to turn dev mode OFF from anywhere inside
// a flow: tapping it toggles dev mode off and confirms with a SnackBar.
// (It can only ever be visible while dev mode is on, so tap always = off.)
class DevModeBadge extends StatelessWidget {
  const DevModeBadge({super.key});

  void _turnOff(BuildContext context) {
    DevMode.instance.toggle();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Developer mode OFF'),
          duration: Duration(seconds: 2),
          backgroundColor: AppConstants.secondary,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DevMode.instance.enabledListenable,
      builder: (context, enabled, _) {
        if (!enabled) return const SizedBox.shrink();
        return Tooltip(
          message: 'Tap to turn off developer mode',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _turnOff(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppConstants.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'DEV MODE',
                style: AppConstants.bodyStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: AppConstants.surfaceLight,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
