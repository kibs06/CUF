import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// Standardized toggle switch used app-wide.
///
/// Uses the universal iOS/Android-style pattern:
/// - **On:** green track (`AppConstants.success`) with white thumb
/// - **Off:** light gray track with white thumb
///
/// This intentionally deviates from the app's brown accent for toggle
/// components specifically, since green is a universally understood
/// "on/active/enabled" signal distinct from brand colors used elsewhere.
///
/// The on/off state is communicated through thumb position + track fill
/// (not relying on color alone), satisfying accessibility requirements
/// for colorblind users.
class SoleSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const SoleSwitch({
    super.key,
    required this.value,
    this.onChanged,
  });

  /// Standard track color when ON — green.
  static const Color onColor = AppConstants.success;

  /// Standard track color when OFF — a subtle, neutral gray.
  static const Color offColor = Color(0xFFD1D5DB);

  /// Thumb is always white on both states (standard platform convention).
  static const Color thumbColor = Colors.white;

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: value,
      onChanged: onChanged,
      // Active (ON) state
      activeThumbColor: thumbColor,
      activeTrackColor: onColor,
      // Inactive (OFF) state
      inactiveThumbColor: thumbColor,
      inactiveTrackColor: offColor,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
