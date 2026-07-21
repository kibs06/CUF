import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';

/// Screen shown when a push notification was intended for a different account
/// than the one currently signed in (e.g. notification for seller account
/// but user is logged in as customer).
///
/// Shows a clear explanation and a button to log out and log into the
/// correct account. Stores [conversationId] so the app can deep-link
/// into the correct conversation after re-login.
class WrongAccountScreen extends StatelessWidget {
  final String conversationId;
  final String targetUserId;

  /// Static field to persist the pending conversation ID across logout/re-login.
  /// Checked by AuthGate after login to deep-link into the correct conversation.
  static String? pendingConversationId;

  const WrongAccountScreen({
    super.key,
    required this.conversationId,
    required this.targetUserId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppConstants.statusPendingColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.swap_horiz_rounded,
                    size: 40,
                    color: AppConstants.statusPendingColor,
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  'Wrong Account',
                  style: AppConstants.headlineStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Description
                Text(
                  'This notification was sent to a different account. '
                  'Please log out and sign in with the correct account to view this message.',
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    color: AppConstants.secondary.withValues(alpha: 0.7),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Log out button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      // Store the pending conversation ID so AuthGate can
                      // deep-link into it after re-login.
                      WrongAccountScreen.pendingConversationId = conversationId;

                      final auth = context.read<AuthProvider>();
                      await auth.logout();
                      if (context.mounted) {
                        // Pop back to auth gate — the user will need to
                        // log in with the correct account.
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      }
                    },
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Log Out'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppConstants.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Go back button
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Go Back',
                    style: AppConstants.bodyStyle(
                      color: AppConstants.secondary.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
