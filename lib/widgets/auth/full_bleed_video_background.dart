import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../constants/app_constants.dart';

/// The complete full-bleed background stack for the merged account entry
/// screen (create-account + sign-in modes): the looping video, a subtle
/// global dim, and the top/bottom scrims tuned to the measured luminance
/// of `video/locals.mp4` (see the [FullBleedVideoBackground] doc).
///
/// Scrim values are tuned to ffmpeg `signalstats` measurements so the
/// white/cream chrome keeps ≥ 4.5:1 contrast on every frame that matters:
///
/// - **Global dim** `surfaceDark @ 0.20` — a subtle full-frame veil so the
///   empty middle band can never blow out.
/// - **Top scrim** `0.95 → 0.70 → 0` over `0 → 32% → 75%` height — protects
///   the pinned header block (worst-case top-band frame, luma ≈ 146, →
///   ≥ 4.8:1 on the 85%-white subtitle, higher on the eyebrow and title).
///   The tail extends to 75% (vs the old 55%) so the sign-in fields, which
///   sit higher than the create-mode actions, never fall into a scrim gap.
/// - **Bottom scrim** `0.22 → 0.98` over `18% → 100%` height — protects the
///   pinned content block (worst-case bottom frame, luma ≈ 118, → ≥ 4.9:1
///   on the cream link rows). Starting at 18% (vs the old 25%) closes the
///   remaining 40–60% band gap together with the extended top scrim.
///
/// No glassmorphism/blur: `backdrop-filter` over a *playing* video is
/// expensive and can drop frames on weaker GPUs — the gradient scrims do
/// all the legibility work.
class VideoHeroBackground extends StatelessWidget {
  const VideoHeroBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const FullBleedVideoBackground(asset: 'video/locals.mp4'),
        // Subtle full-frame veil (measured mean luma ≈ 89 → never needs
        // more than this to protect the empty middle band).
        ColoredBox(
          color: AppConstants.surfaceDark.withValues(alpha: 0.20),
        ),
        // Top scrim — keeps the pinned header block readable even on the
        // brightest top-band frames (luma up to ≈ 146), and keeps the
        // sign-in fields (which sit as high as ~33–55% on short devices)
        // out of the scrim gap: the tail now fades to 0 only at 75% height.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.32, 0.75],
              colors: [
                Color(0xF21A1208), // surfaceDark @ 0.95
                Color(0xB31A1208), // surfaceDark @ 0.70
                Color(0x001A1208), // transparent
              ],
            ),
          ),
        ),
        // Bottom scrim — keeps the content block readable over the bottom
        // band (luma up to ≈ 118). Starts at 18% with a 0.22 floor so it
        // overlaps the top scrim's tail: together they close the 40–60%
        // band where the sign-in fields sit on short devices.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.18, 1.0],
              colors: [
                Color(0x381A1208), // surfaceDark @ 0.22
                Color(0xFA1A1208), // surfaceDark @ 0.98
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-bleed looping, muted, autoplaying background video with `cover`
/// fit and no controls. Used as `SignupScaffold.background` for the
/// role-choice hero.
///
/// Contrast notes (the caller layers its own scrims on top): the asset
/// (`video/locals.mp4`, 2160×3840 portrait, 143s) was measured with ffmpeg
/// `signalstats` — full-frame mean luma ≈ 89/255, worst-case ≈ 146 in the
/// top 20% band and ≈ 118 in the bottom 28% band. So white/cream text needs
/// real scrims, and this widget paints a dark base while loading so the
/// screen never flashes cream.
///
/// Error handling: if the asset cannot be initialized (missing on a
/// platform, codec issue), the widget silently falls back to the dark base
/// — the scrims still keep the screen fully readable.
class FullBleedVideoBackground extends StatefulWidget {
  final String asset;

  const FullBleedVideoBackground({super.key, required this.asset});

  @override
  State<FullBleedVideoBackground> createState() =>
      _FullBleedVideoBackgroundState();
}

class _FullBleedVideoBackgroundState extends State<FullBleedVideoBackground> {
  VideoPlayerController? _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.asset(widget.asset)
      ..setLooping(true)
      ..setVolume(0); // muted — the background is ambience, never audio
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() => _initialized = true);
      await controller.play();
    } catch (_) {
      // Fall back to the dark base (still fully legible under the scrims).
      debugPrint('FullBleedVideoBackground: failed to load ${widget.asset}');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ColoredBox(
      color: AppConstants.surfaceDark,
      child: (_initialized && controller != null)
          ? FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            )
          : null,
    );
  }
}
