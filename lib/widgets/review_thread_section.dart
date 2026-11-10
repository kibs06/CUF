import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';
import '../services/review_service.dart';

/// Discussion thread under a product review.
///
/// The review author can reply under the seller's reply, and any other
/// signed-in customer can comment on the thread too. Collapsed to a
/// single "Discussion" row until tapped (comments load lazily, so review
/// lists never pay N extra queries); the composer posts as the current
/// user and notifies the author + seller fire-and-forget.
///
/// Never rendered for demo reviews (see `SoleReviewCard` / seller card
/// guards) — demo ids exist only on-device, so there is no DB thread.
class ReviewThreadSection extends StatefulWidget {
  final String reviewId;

  const ReviewThreadSection({super.key, required this.reviewId});

  @override
  State<ReviewThreadSection> createState() => _ReviewThreadSectionState();
}

class _ReviewThreadSectionState extends State<ReviewThreadSection> {
  bool _expanded = false;
  bool _loading = false;
  bool _loaded = false;
  bool _posting = false;
  List<Map<String, dynamic>> _comments = [];
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    setState(() => _expanded = !_expanded);
    if (_expanded && !_loaded) await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final comments =
        await ReviewService.instance.getReviewComments(widget.reviewId);
    if (mounted) {
      setState(() {
        _comments = comments;
        _loading = false;
        _loaded = true;
      });
    }
  }

  Future<void> _post() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _posting) return;
    setState(() => _posting = true);
    final ok = await ReviewService.instance.addReviewComment(
      reviewId: widget.reviewId,
      text: text,
    );
    if (!mounted) return;
    setState(() => _posting = false);
    if (ok) {
      _controller.clear();
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not post reply. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _toggle,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Icon(
                Icons.forum_outlined,
                size: 15,
                color: AppConstants.primary,
              ),
              const SizedBox(width: 6),
              Text(
                _loaded && _comments.isNotEmpty
                    ? 'Discussion (${_comments.length})'
                    : 'Discussion',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.primary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                _expanded
                    ? Icons.expand_less_outlined
                    : Icons.expand_more_outlined,
                size: 16,
                color: AppConstants.primary,
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_comments.isEmpty)
            Text(
              'No replies yet — start the discussion.',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ),
            )
          else
            for (final c in _comments) _commentRow(c),
          const SizedBox(height: 8),
          _composer(),
        ],
      ],
    );
  }

  Widget _commentRow(Map<String, dynamic> c) {
    final name = c['author_name']?.toString() ?? 'Customer';
    final avatar = c['author_avatar']?.toString();
    final text = c['comment']?.toString() ?? '';
    final date = _formatDate(c['created_at']?.toString());
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppConstants.primary.withValues(alpha: 0.1),
            backgroundImage:
                avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
            child: avatar == null || avatar.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.primary,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppConstants.borderGray.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.secondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (date.isNotEmpty)
                        Text(
                          date,
                          style: AppConstants.bodyStyle(
                            fontSize: 10,
                            color: AppConstants.secondary
                                .withValues(alpha: 0.4),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    text,
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: AppConstants.secondary.withValues(alpha: 0.8),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    final signedIn =
        Supabase.instance.client.auth.currentUser != null;
    if (!signedIn) {
      return Text(
        'Sign in to join the discussion.',
        style: AppConstants.bodyStyle(
          fontSize: 12,
          color: AppConstants.secondary.withValues(alpha: 0.5),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            maxLines: 3,
            minLines: 1,
            maxLength: 500,
            decoration: InputDecoration(
              hintText: 'Write a reply...',
              hintStyle: AppConstants.bodyStyle(
                color: AppConstants.secondary.withValues(alpha: 0.4),
                fontSize: 12,
              ),
              filled: true,
              fillColor: AppConstants.borderGray.withValues(alpha: 0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              counterText: '',
            ),
            style: AppConstants.bodyStyle(fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _posting ? null : _post,
          icon: _posting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.send_outlined,
                  size: 20, color: AppConstants.primary),
          tooltip: 'Post reply',
        ),
      ],
    );
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.month}/${dt.day}/${dt.year}';
    } catch (_) {
      return '';
    }
  }
}
