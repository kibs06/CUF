import 'dart:ui';

import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';

/// Frosted-glass panel used across the Foot Size 2.0 scan UI.
///
/// A [ClipRRect] + [BackdropFilter] capsule/panel that stays legible over
/// the live camera preview. The v2 scan screens dock these above the camera
/// for coaching hints, the live readout, and error sheets.
///
/// Tone variants tint the glass: [GlassTone.neutral] is a plain dark smoke,
/// [active] adds an accent edge, [success]/[warning] shift toward their
/// semantic colors. All tones keep white-ish foreground text since they sit
/// on camera imagery.
enum GlassTone { neutral, active, success, warning }

class GlassCard extends StatelessWidget {
  final Widget child;

  /// Visual variant — tints the blur layer and (for non-neutral) draws a
  /// 1px colored edge.
  final GlassTone tone;

  /// Corner radius. Defaults to the full stadium so hint capsules read as
  /// floating pills; use [BorderRadius.circular(16)]-style radii for larger
  /// sheets.
  final BorderRadius borderRadius;

  final EdgeInsetsGeometry padding;

  const GlassCard({
    super.key,
    required this.child,
    this.tone = GlassTone.neutral,
    this.borderRadius = AppConstants.stadiumRadius,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  });

  Color get _tint {
    switch (tone) {
      case GlassTone.neutral:
        return Colors.black.withValues(alpha: 0.45);
      case GlassTone.active:
        return AppConstants.accent.withValues(alpha: 0.28);
      case GlassTone.success:
        return AppConstants.success.withValues(alpha: 0.35);
      case GlassTone.warning:
        return AppConstants.statusPendingColor.withValues(alpha: 0.38);
    }
  }

  Color get _edge {
    switch (tone) {
      case GlassTone.neutral:
        return Colors.white.withValues(alpha: 0.14);
      case GlassTone.active:
        return AppConstants.accent.withValues(alpha: 0.6);
      case GlassTone.success:
        return AppConstants.success.withValues(alpha: 0.7);
      case GlassTone.warning:
        return AppConstants.statusPendingColor.withValues(alpha: 0.7);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      // BackdropFilter needs a Stack sibling decoration so the tint paints
      // OVER the blurred backdrop (a Container inside the filter would blur
      // nothing — the filter only affects what's painted behind it).
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: _tint,
            borderRadius: borderRadius,
            border: Border.all(color: _edge, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}
