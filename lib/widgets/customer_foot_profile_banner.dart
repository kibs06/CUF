import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../providers/auth_provider.dart';
import '../screens/customer/foot_instructions_screen.dart';

/// Dismissible reminder banner for customers who skipped (or never
/// completed) their foot profile. One quiet placement on the home screen —
/// deliberately NOT a pop-up. Dismiss hides it for THIS session only
/// (in-memory, keyed per account), so "skip" never means "never ask again
/// silently": the invite comes back on the next session.
///
/// The banner disappears for good once the profile snapshot is written
/// (`foot_profile_source` = 'ar_scan'/'manual') — the home screen watches
/// [AuthProvider], which refreshes its profile on every save.
class CustomerFootProfileBanner extends StatefulWidget {
  const CustomerFootProfileBanner({super.key});

  @override
  State<CustomerFootProfileBanner> createState() =>
      _CustomerFootProfileBannerState();
}

class _CustomerFootProfileBannerState extends State<CustomerFootProfileBanner> {
  /// Session-only dismissal, keyed by profile id so switching accounts
  /// re-shows the banner for the new user.
  static final Set<String> _dismissedForSession = {};

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profileId = auth.profile?['id']?.toString() ?? '';
    final source = auth.profile?['foot_profile_source'];

    // Nothing to remind (completed), wrong account (no profile yet), or
    // already dismissed this session → stay out of the way.
    if (profileId.isEmpty) return const SizedBox.shrink();
    if (_dismissedForSession.contains(profileId)) {
      return const SizedBox.shrink();
    }
    if (!AppConstants.needsFootProfile(source)) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: AppConstants.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppConstants.accent.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppConstants.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.straighten_outlined,
              size: 20,
              color: AppConstants.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Discover your real shoe size',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.secondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '9 in 10 people wear the wrong size — scan your feet in under a minute.',
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: AppConstants.secondary.withValues(alpha: 0.65),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          // Complete — the direct link back into the same AR scan flow.
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FootInstructionsScreen(),
                  ),
                );
              },
              style: TextButton.styleFrom(
                foregroundColor: AppConstants.accent,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 40),
              ),
              child: Text(
                'Complete',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.accent,
                ),
              ),
            ),
          ),
          // Dismiss — this session only.
          IconButton(
            onPressed: () {
              setState(() => _dismissedForSession.add(profileId));
            },
            tooltip: 'Hide for now',
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppConstants.secondary,
            ),
            constraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
          ),
        ],
      ),
    );
  }
}
