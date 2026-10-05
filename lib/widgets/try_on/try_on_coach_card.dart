import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../utils/try_on_coach.dart';
import '../foot_size_v2/glass_card.dart';

/// **V4.5's coach card** — the sentence between the customer and a locked shoe.
///
/// A pure function of [cue]: the controller decides *which* cue is true
/// (`lib/utils/try_on_coach.dart`), this decides what it looks like and says,
/// the same split the phase machine's own doc asks for. It renders **nothing**
/// for a null cue — the state every build with the foot-tracking switch off
/// spends its whole life in.
///
/// The visual language is the scan's own [GlassCard] (the architecture's plan
/// for this widget: "same visual language as the scan's coach card"), because a
/// customer who has measured a foot already knows what these panels mean.
///
/// Two cues are interactive-adjacent: [TryOnCoachCue.manual] is the offer §2.12
/// asks for after 15 s without a lock, and its button hands control back with
/// [onPlaceManually] (`TryOnSessionController.dismissManualOffer`), after which
/// the cue becomes [TryOnCoachCue.placeByTap] and the card says where to tap.
/// The tapping itself is V3.4's path — the native view already places the shoe
/// on a touch, so nothing here calls a channel.
class TryOnCoachCard extends StatelessWidget {
  /// What to say, or null for no card at all.
  final TryOnCoachCue? cue;

  /// Invoked when the customer accepts the manual-placement offer.
  final VoidCallback? onPlaceManually;

  const TryOnCoachCard({
    super.key,
    required this.cue,
    this.onPlaceManually,
  });

  @override
  Widget build(BuildContext context) {
    final active = cue;
    if (active == null) return const SizedBox.shrink();

    final copy = _copyFor(active);
    final offer = active == TryOnCoachCue.manual && onPlaceManually != null;

    return GlassCard(
      tone: copy.tone,
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(copy.icon, size: 22, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      copy.title,
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (copy.body != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        copy.body!,
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.85),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (offer) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onPlaceManually,
              style: FilledButton.styleFrom(
                backgroundColor: AppConstants.accent,
                foregroundColor: AppConstants.secondary,
                shape: const RoundedRectangleBorder(
                  borderRadius: AppConstants.stadiumRadius,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
              ),
              icon: const Icon(Icons.touch_app, size: 18),
              label: Text(
                'Place it myself',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.secondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Copy and tone per cue — the whole English of V4.5, in one place.
class _CueCopy {
  final IconData icon;
  final String title;
  final String? body;
  final GlassTone tone;

  const _CueCopy(this.icon, this.title, this.body, this.tone);
}

_CueCopy _copyFor(TryOnCoachCue cue) {
  switch (cue) {
    case TryOnCoachCue.pointAtFoot:
      return const _CueCopy(
        Icons.center_focus_strong,
        'Point the camera at your foot',
        'Bare feet work best — keep the whole foot in view.',
        GlassTone.neutral,
      );
    case TryOnCoachCue.improveScene:
      return const _CueCopy(
        Icons.wb_sunny,
        'Keep the floor in view',
        'Move somewhere brighter — tracking needs the floor and even light.',
        GlassTone.neutral,
      );
    case TryOnCoachCue.moveCloser:
      return const _CueCopy(
        Icons.zoom_in,
        'Move the phone closer',
        'Your foot looks small in the frame.',
        GlassTone.neutral,
      );
    case TryOnCoachCue.moveBack:
      return const _CueCopy(
        Icons.zoom_out_map,
        'Move the phone back',
        'Your foot fills the frame — a little more distance helps.',
        GlassTone.neutral,
      );
    case TryOnCoachCue.holdStill:
      return const _CueCopy(
        Icons.pan_tool,
        'Hold still',
        'Locking onto your foot…',
        GlassTone.active,
      );
    case TryOnCoachCue.locked:
      return const _CueCopy(
        Icons.check_circle,
        'Locked on',
        'The shoe is following your foot.',
        GlassTone.success,
      );
    case TryOnCoachCue.regain:
      return const _CueCopy(
        Icons.refresh,
        'Bring your foot back into view',
        'The lock dropped — step back into frame.',
        GlassTone.warning,
      );
    case TryOnCoachCue.manual:
      return const _CueCopy(
        Icons.view_in_ar,
        'Place the shoe yourself',
        'Tap the floor where you want the shoe to sit.',
        GlassTone.active,
      );
    case TryOnCoachCue.placeByTap:
      return const _CueCopy(
        Icons.touch_app_outlined,
        'Tap the floor to place the shoe',
        null,
        GlassTone.neutral,
      );
  }
}
