import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../utils/dev_mode.dart';

// ⚠️ DEV-ONLY — REMOVE BEFORE RELEASE (see docs/AI/DEV_MODE_ARCHITECTURE.md).
//
// Wraps the "Create your account" screen body and listens for the unlock
// swipe code (2 up, 2 down, 2 right, 2 left). It uses a raw [Listener], so
// it never competes with the screen's scroll views in the gesture arena —
// it just observes pointer deltas and never consumes taps/scrolls. Swiping
// the same code again toggles dev mode back off.
class DevModeSwipeDetector extends StatefulWidget {
  final Widget child;

  const DevModeSwipeDetector({super.key, required this.child});

  @override
  State<DevModeSwipeDetector> createState() => _DevModeSwipeDetectorState();
}

class _DevModeSwipeDetectorState extends State<DevModeSwipeDetector> {
  final DevModeSwipeTracker _tracker = DevModeSwipeTracker();

  /// Only one finger is tracked at a time; a second finger is ignored.
  int? _activePointer;
  Offset _downPosition = Offset.zero;

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _downPosition = event.position;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;

    final direction = classifySwipe(event.position - _downPosition);
    if (direction == null) return;
    if (!_tracker.onSwipe(direction)) return;

    final nowOn = !DevMode.instance.isEnabled;
    DevMode.instance.toggle();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            nowOn
                ? 'Developer mode ON — Continue buttons now skip the flows.'
                : 'Developer mode OFF',
          ),
          duration: const Duration(seconds: 2),
          backgroundColor:
              nowOn ? AppConstants.primary : AppConstants.secondary,
        ),
      );
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer == _activePointer) _activePointer = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }
}
