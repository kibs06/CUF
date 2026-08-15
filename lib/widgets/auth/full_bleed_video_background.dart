import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../constants/app_constants.dart';

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
