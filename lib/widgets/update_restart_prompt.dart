import 'package:flutter/material.dart';
import 'package:restart_app/restart_app.dart';

import '../constants/app_constants.dart';

/// Shown after the new APK has been handed to Android's system installer.
///
/// The system install runs outside the app and reports nothing back, so this
/// prompt does not claim the install is done — it tells the user to finish
/// it in the system screen, then choose: restart CUFMAI now to start using
/// the new version, or stay a little longer on this one.
Future<void> showUpdateRestartPrompt(
  BuildContext context, {
  required String version,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppConstants.surfaceLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Finish the update',
        style: AppConstants.headlineStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Text(
        'The installer is open — complete the installation there, then '
        'restart CUFMAI to start using v$version.',
        style: AppConstants.bodyStyle(
          fontSize: 13,
          height: 1.45,
          color: AppConstants.secondary.withValues(alpha: 0.75),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(
            'Not yet',
            style: AppConstants.bodyStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppConstants.secondary.withValues(alpha: 0.6),
            ),
          ),
        ),
        FilledButton(
          onPressed: () => Restart.restartApp(),
          style: FilledButton.styleFrom(
            backgroundColor: AppConstants.accent,
            shape: RoundedRectangleBorder(
              borderRadius: AppConstants.buttonRadius,
            ),
            elevation: 0,
          ),
          child: Text(
            'Restart now',
            style: AppConstants.headlineStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppConstants.secondary,
            ),
          ),
        ),
      ],
    ),
  );
}
