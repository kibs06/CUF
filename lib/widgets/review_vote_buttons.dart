import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';
import '../services/review_service.dart';

/// Thumbs up / thumbs down on a review — "was this helpful?".
///
/// Right-aligned, borderless, with a like-button micro-interaction: the
/// icon presses in under the finger, then pops with a spring overshoot as
/// it fills, the count ticks over, and a light haptic confirms the vote.
/// Self-sufficient: loads its own totals + the viewer's vote, votes with
/// an optimistic update, rolls back on failure. Used by [SoleReviewCard],
/// so it shows on customer and seller surfaces alike.
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

    HapticFeedback.lightImpact();

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
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          'Was this helpful?',
          style: AppConstants.bodyStyle(
            fontSize: 11,
            color: AppConstants.secondary.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(width: 2),
        _SpringVoteButton(
          selected: _myVote == true,
          count: _helpful,
          outlineIcon: Icons.thumb_up_outlined,
          filledIcon: Icons.thumb_up,
          semanticLabel: 'Mark review helpful',
          onTap: () => _tap(true),
        ),
        _SpringVoteButton(
          selected: _myVote == false,
          count: _notHelpful,
          outlineIcon: Icons.thumb_down_outlined,
          filledIcon: Icons.thumb_down,
          semanticLabel: 'Mark review not helpful',
          onTap: () => _tap(false),
        ),
      ],
    );
  }
}

/// One borderless vote button with a spring-pop micro-interaction.
///
/// The press sinks the icon to 0.92 while the finger is down; on selection
/// it springs to ~1.3 with an overshoot curve and settles back, while the
/// icon cross-fades from outline to filled. The count ticks with a small
/// vertical slide. Only transform + opacity animate, so it stays jank-free.
class _SpringVoteButton extends StatefulWidget {
  final bool selected;
  final int count;
  final IconData outlineIcon;
  final IconData filledIcon;
  final String semanticLabel;
  final VoidCallback onTap;

  const _SpringVoteButton({
    required this.selected,
    required this.count,
    required this.outlineIcon,
    required this.filledIcon,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  State<_SpringVoteButton> createState() => _SpringVoteButtonState();
}

class _SpringVoteButtonState extends State<_SpringVoteButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop;
  late final Animation<double> _scale;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    // Overshoot past the target and back — the spring that makes the tap
    // feel physical rather than flat.
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.32)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 38,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.32, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 62,
      ),
    ]).animate(_pop);
  }

  @override
  void didUpdateWidget(covariant _SpringVoteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pop only when the button BECOMES selected (the vote landing), not
    // when it clears — removal stays quiet.
    if (!oldWidget.selected && widget.selected) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  Color _iconColor(BuildContext context) => widget.selected
      ? AppConstants.primary
      : AppConstants.secondary.withValues(alpha: 0.42);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: Padding(
          // Generous touch target with no visible chrome.
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: AnimatedScale(
            scale: _pressed ? 0.9 : 1.0,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            child: ScaleTransition(
              scale: _scale,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: Icon(
                      widget.selected
                          ? widget.filledIcon
                          : widget.outlineIcon,
                      key: ValueKey(widget.selected),
                      size: 19,
                      color: _iconColor(context),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, animation) =>
                        SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.45),
                            end: Offset.zero,
                          ).animate(animation),
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        ),
                    child: widget.count > 0
                        ? Padding(
                            key: ValueKey(widget.count),
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              widget.count > 999
                                  ? '${(widget.count / 1000).toStringAsFixed(1)}k'
                                  : widget.count.toString(),
                              style: AppConstants.bodyStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _iconColor(context),
                              ),
                            ),
                          )
                        : const SizedBox(key: ValueKey('empty'), width: 0),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
