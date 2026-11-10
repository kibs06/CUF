import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';
import '../services/review_service.dart';

/// Thumbs up / thumbs down on a review — "was this helpful?".
///
/// Self-sufficient: loads its own totals + the viewer's vote, handles
/// voting with an optimistic update, and rolls back on failure. Used by
/// [SoleReviewCard], so it shows on customer and seller surfaces alike.
class ReviewVoteButtons extends StatefulWidget {
  final String reviewId;

  const ReviewVoteButtons({super.key, required this.reviewId});

  @override
  State<ReviewVoteButtons> createState() => _ReviewVoteButtonsState();
}

class _ReviewVoteButtonsState extends State<ReviewVoteButtons> {
  int _helpful = 0;
  int _notHelpful = 0;
  bool? _myVote;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final summary =
        await ReviewService.instance.getReviewVote(widget.reviewId);
    if (!mounted) return;
    setState(() {
      _helpful = summary.helpful;
      _notHelpful = summary.notHelpful;
      _myVote = summary.myVote;
    });
  }

  Future<void> _tap(bool value) async {
    if (_busy || widget.reviewId.isEmpty) return;
    if (Supabase.instance.client.auth.currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to vote on reviews.')),
      );
      return;
    }

    // Optimistic update; the service call either confirms or rolls back.
    final previous = _myVote;
    final prevHelpful = _helpful;
    final prevNotHelpful = _notHelpful;
    setState(() {
      _busy = true;
      if (previous == value) {
        // Tapping the active vote removes it.
        _myVote = null;
        if (value) {
          _helpful--;
        } else {
          _notHelpful--;
        }
      } else {
        if (previous == true) _helpful--;
        if (previous == false) _notHelpful--;
        _myVote = value;
        if (value) {
          _helpful++;
        } else {
          _notHelpful++;
        }
      }
    });

    try {
      if (previous == value) {
        await ReviewService.instance.removeVote(widget.reviewId);
      } else {
        await ReviewService.instance
            .voteReview(reviewId: widget.reviewId, isHelpful: value);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _myVote = previous;
        _helpful = prevHelpful;
        _notHelpful = prevNotHelpful;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save your vote.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Was this helpful?',
          style: AppConstants.bodyStyle(
            fontSize: 11,
            color: AppConstants.secondary.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(width: 8),
        _VotePill(
          icon: Icons.thumb_up_outlined,
          activeIcon: Icons.thumb_up,
          count: _helpful,
          active: _myVote == true,
          onTap: () => _tap(true),
        ),
        const SizedBox(width: 8),
        _VotePill(
          icon: Icons.thumb_down_outlined,
          activeIcon: Icons.thumb_down,
          count: _notHelpful,
          active: _myVote == false,
          onTap: () => _tap(false),
        ),
      ],
    );
  }
}

class _VotePill extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final int count;
  final bool active;
  final VoidCallback onTap;

  const _VotePill({
    required this.icon,
    required this.activeIcon,
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? AppConstants.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? AppConstants.primary
                : AppConstants.secondary.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? activeIcon : icon,
              size: 14,
              color: active
                  ? AppConstants.primary
                  : AppConstants.secondary.withValues(alpha: 0.5),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                count.toString(),
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: active
                      ? AppConstants.primary
                      : AppConstants.secondary.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
