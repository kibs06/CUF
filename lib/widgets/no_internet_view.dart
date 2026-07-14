import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Reusable "No Internet Connection" empty-state view.
///
/// Used when a screen tries to load data for the first time and there's
/// no connection. Shows an icon, headline, supporting text, and a
/// "Try Again" button.
class NoInternetView extends StatelessWidget {
  final VoidCallback onRetry;

  const NoInternetView({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon in soft circular background — calm, not alarming
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppConstants.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 34,
                color: AppConstants.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Internet Connection',
              style: AppConstants.headlineStyle(fontSize: 20),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again.',
              style: AppConstants.bodyStyle(
                fontSize: 14,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try Again'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppConstants.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppConstants.buttonRadius,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
