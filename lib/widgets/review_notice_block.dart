import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import 'sole_star_rating.dart';

/// Rich body for review-related notification cards: the star rating plus
/// the quoted snippet (the review, or the seller's reply). Shared by the
/// customer bell and the seller bell so a review notice reads the same on
/// both sides. Renders from the notice metadata — no extra fetch.
///
/// [label] names whose words are shown ('Seller reply', 'Your review',
/// 'New review'); [snippet] is shown quoted, up to two lines.
class ReviewNoticeBlock extends StatelessWidget {
  final int rating;
  final String snippet;
  final String label;

  const ReviewNoticeBlock({
    super.key,
    required this.rating,
    required this.snippet,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = rating.clamp(1, 5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SoleStarRating(rating: clamped, size: 12),
            const SizedBox(width: 6),
            Text(
              '$clamped.0',
              style: AppConstants.bodyStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppConstants.secondary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  color: AppConstants.secondary.withValues(alpha: 0.5),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (snippet.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '“$snippet”',
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.75),
              height: 1.35,
            ).copyWith(fontStyle: FontStyle.italic),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
