import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

// ⚠️⚠️⚠️ DEV-ONLY SCAFFOLDING — REMOVE BEFORE RELEASE ⚠️⚠️⚠️
//
// Developer mode is a UI-only shortcut for walking the signup flows while
// testing. It must NOT ship. The full design + removal checklist live in
// docs/AI/DEV_MODE_ARCHITECTURE.md — read that doc before touching anything
// in here.
//
// What it does:
//   • Unlocked by swiping 2 up, 2 down, 2 right, 2 left on the
//     "Create your account" screen (AccountEntryScreen, via
//     DevModeSwipeDetector).
//   • While enabled, every Continue / Create-account / Submit button in the
//     customer + seller flows skips validation and advances WITHOUT touching
//     Supabase — no account is ever created (the UI-only contract).
//   • A persistent "DEV MODE" chip (DevModeBadge) is shown so it's obvious
//     the skip behavior is active — tapping the chip toggles dev mode OFF
//     from any screen in a flow.
//
// To remove: delete this file, lib/widgets/auth/dev_mode_swipe_detector.dart,
// lib/widgets/auth/dev_mode_badge.dart, delete every
// `DevMode.instance.isEnabled` guard in the auth screens (and the badge
// placements in account_entry_screen.dart + signup_scaffold.dart), and drop
// docs/AI/DEV_MODE_ARCHITECTURE.md.
class DevMode {
  DevMode._();

  static final DevMode instance = DevMode._();

  final ValueNotifier<bool> _enabled = ValueNotifier<bool>(false);

  ValueListenable<bool> get enabledListenable => _enabled;
  bool get isEnabled => _enabled.value;

  void toggle() => _enabled.value = !_enabled.value;
}

/// One directional swipe in the unlock sequence.
enum DevSwipeDirection { up, down, left, right }

/// The unlock code: swipe **2 up, 2 down, 2 right, 2 left**.
const List<DevSwipeDirection> devModeUnlockCode = [
  DevSwipeDirection.up,
  DevSwipeDirection.up,
  DevSwipeDirection.down,
  DevSwipeDirection.down,
  DevSwipeDirection.right,
  DevSwipeDirection.right,
  DevSwipeDirection.left,
  DevSwipeDirection.left,
];

/// Classifies a drag [delta] into a swipe direction, or returns null when
/// the drag is too short (or too diagonal) to count as a deliberate swipe.
DevSwipeDirection? classifySwipe(Offset delta, {double threshold = 48}) {
  if (delta.distance < threshold) return null;
  if (delta.dx.abs() > delta.dy.abs()) {
    return delta.dx > 0 ? DevSwipeDirection.right : DevSwipeDirection.left;
  }
  return delta.dy > 0 ? DevSwipeDirection.down : DevSwipeDirection.up;
}

/// Accumulates classified swipes and reports when the unlock code has been
/// completed. Uses a sliding window of the last N swipes, so an accidental
/// scroll swipe in the middle of the sequence doesn't reset progress —
/// the code simply needs to appear as the last 8 swipes.
class DevModeSwipeTracker {
  final List<DevSwipeDirection> _entered = <DevSwipeDirection>[];

  /// Feeds one classified swipe. Returns true when the full code just
  /// completed (and resets the buffer).
  bool onSwipe(DevSwipeDirection direction) {
    _entered.add(direction);
    if (_entered.length > devModeUnlockCode.length) {
      _entered.removeAt(0);
    }
    if (_entered.length == devModeUnlockCode.length) {
      var matches = true;
      for (var i = 0; i < _entered.length; i++) {
        if (_entered[i] != devModeUnlockCode[i]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        _entered.clear();
        return true;
      }
    }
    return false;
  }
}
