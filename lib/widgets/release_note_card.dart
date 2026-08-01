import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/update_info.dart';
import 'sole_badge.dart';

/// A single release entry in the changelog: version heading, release date,
/// and a bulleted list of notes. Styled to match the app's card language
/// (white `SoleCard` surface, warm shadow, 16px radius).
class ReleaseNoteCard extends StatelessWidget {
  const ReleaseNoteCard({
    super.key,
    required this.release,
    this.isLatest = false,
  });

  final UpdateInfo release;
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    final notes = release.notes;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
        boxShadow: AppConstants.warmShadow,
        border: Border.all(
          color: isLatest
              ? AppConstants.accent.withValues(alpha: 0.5)
              : AppConstants.borderGray.withValues(alpha: 0.3),
          width: isLatest ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Version + date row ────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isLatest
                      ? AppConstants.accent.withValues(alpha: 0.14)
                      : AppConstants.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'v${release.version}',
                  style: AppConstants.monoStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isLatest ? AppConstants.secondary : AppConstants.primary,
                  ),
                ),
              ),
              if (isLatest) ...[
                const SizedBox(width: 8),
                const SoleBadge(
                  label: 'Latest',
                  backgroundColor: AppConstants.accent,
                  textColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                ),
              ],
              const Spacer(),
              if (release.releasedAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    _formatDate(release.releasedAt!),
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      color: AppConstants.secondary.withValues(alpha: 0.45),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Notes (bulleted, wrapping) ────────────────────────
          if (notes.isEmpty)
            Text(
              'No details for this release.',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ),
            )
          else
            ...notes.map((note) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: AppConstants.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        note,
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          color: AppConstants.secondary.withValues(alpha: 0.8),
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
