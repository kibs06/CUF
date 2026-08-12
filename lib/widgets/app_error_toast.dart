import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Toast text colors per the toast spec — warm creams on the dark espresso
/// surface. Kept local (not AppConstants.surfaceLight) because they are the
/// toast's own tones, and so the text style below can be fully explicit.
const Color _toastHeadlineColor = Color(0xFFF3ECE1); // cream headline
const Color _toastSubtextColor = Color(0xFFD9CBB8); // muted cream subtext

/// Floating, auto-dismissing error toast.
///
/// Rendered on the app's ROOT [Overlay], so it floats above whatever is on
/// screen — it never pushes the underlying form layout the way a pinned
/// [SnackBar] (default `fixed` behavior) can. Slides + fades in (~200ms),
/// auto-dismisses after a few seconds, and can be closed manually.
///
/// Reusable beyond auth: any error case (network failures, uploads) can call
/// [AppErrorToast.show] with already-human-readable copy — this widget never
/// receives or formats raw exception text itself.
class AppErrorToast {
  AppErrorToast._();

  /// Toasts currently on screen, so a new toast replaces the old instead of
  /// stacking two dark bars at the bottom.
  static final List<OverlayEntry> _active = <OverlayEntry>[];

  /// Shows the toast on the root overlay.
  ///
  /// [message] is the short bolded headline; [detail] is an optional one-line
  /// secondary guidance under it. [duration] controls how long it stays up
  /// before auto-dismissing.
  static void show(
    BuildContext context, {
    required String message,
    String? detail,
    Duration duration = const Duration(milliseconds: 4500),
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);

    // Replace any toast already on screen so they never stack.
    for (final entry in _active) {
      if (entry.mounted) entry.remove();
    }
    _active.clear();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _AppErrorToastOverlay(
        message: message,
        detail: detail,
        duration: duration,
        onDismissed: () {
          if (entry.mounted) entry.remove();
          _active.remove(entry);
        },
      ),
    );
    _active.add(entry);
    overlay.insert(entry);
  }
}

class _AppErrorToastOverlay extends StatefulWidget {
  final String message;
  final String? detail;
  final Duration duration;
  final VoidCallback onDismissed;

  const _AppErrorToastOverlay({
    required this.message,
    this.detail,
    required this.duration,
    required this.onDismissed,
  });

  @override
  State<_AppErrorToastOverlay> createState() => _AppErrorToastOverlayState();
}

class _AppErrorToastOverlayState extends State<_AppErrorToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _controller.forward();
    _dismissTimer = Timer(widget.duration, _dismiss);
  }

  void _dismiss() {
    if (!mounted || _controller.status == AnimationStatus.reverse) return;
    _dismissTimer?.cancel();
    _controller.reverse().whenCompleteOrCancel(widget.onDismissed);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Positioned(
      left: 16,
      right: 16,
      // Lift above the on-screen keyboard too — auth errors (wrong password,
      // etc.) surface while the keyboard is still up, and the root overlay
      // renders BEHIND it. viewInsets is 0 when the keyboard is closed.
      bottom: viewInsets.bottom + 16,
      child: SafeArea(
        child: Semantics(
          // Announce the error to screen readers the moment it appears.
          liveRegion: true,
          container: true,
          label: widget.message,
          child: FadeTransition(
            opacity: _animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.2),
                end: Offset.zero,
              ).animate(_animation),
              child: _buildToast(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToast() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      decoration: BoxDecoration(
        // Deep espresso (same brown as the login hero) reads as clearly
        // error-toned without a harsh stock-red bar.
        color: AppConstants.secondary,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Amber warning icon — accent color on the dark surface only.
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.warning_amber_rounded,
              size: 20,
              color: AppConstants.statusPendingColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.message,
                  style: _noDecoration(AppConstants.bodyStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: _toastHeadlineColor,
                    height: 1.35,
                  )),
                ),
                if (widget.detail != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.detail!,
                    style: _noDecoration(AppConstants.bodyStyle(
                      fontSize: 12.5,
                      color: _toastSubtextColor,
                      height: 1.35,
                    )),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          // Explicit close control with a proper label (the tooltip provides
          // the semantics label), so slow readers aren't forced to wait for
          // auto-dismiss.
          IconButton(
            onPressed: _dismiss,
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppConstants.surfaceLight,
            ),
          ),
        ],
      ),
    );
  }

  /// Locks a text style so NO underline can ever render on toast text.
  ///
  /// `Text` merges its style with the ambient [DefaultTextStyle] (theme
  /// textTheme, link styles, etc.) unless told not to. The toast message is
  /// deliberately plain text — nothing should decorate it — so the style is
  /// made fully self-contained: `inherit: false` drops ALL ambient style,
  /// and `decoration: none` explicitly overrides any decoration that might
  /// otherwise merge in (the cause of stray yellow underlines on device).
  static TextStyle _noDecoration(TextStyle base) => base.copyWith(
        inherit: false,
        decoration: TextDecoration.none,
        decorationColor: null,
        decorationStyle: null,
      );
}
