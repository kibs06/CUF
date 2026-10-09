import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import 'glass_card.dart';

/// How far the floor search has got, 0.0–1.0.
///
/// The floor locks at three of five probes on a plane (see
/// ScanSessionController), so hits count up to that point. The other half is
/// the floor height agreeing across two polls.
double floorSearchProgress({required int probeHits, required bool steady}) {
  final hitShare = probeHits.clamp(0, 3) / 3;
  return (hitShare * 0.6 + (steady ? 0.4 : 0.0)).clamp(0.0, 1.0);
}

/// Looping "move slowly over the floor" demo plus a progress bar that fills
/// as the floor locks. Drawn with CustomPaint; no assets.
class FloorSearchGuide extends StatefulWidget {
  final int probeHits;
  final bool steady;

  const FloorSearchGuide({
    super.key,
    required this.probeHits,
    required this.steady,
  });

  @override
  State<FloorSearchGuide> createState() => _FloorSearchGuideState();
}

class _FloorSearchGuideState extends State<FloorSearchGuide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        floorSearchProgress(probeHits: widget.probeHits, steady: widget.steady);
    final found = progress >= 1.0;
    final percent = (progress * 100).round();

    return GlassCard(
      borderRadius: BorderRadius.circular(20),
      tone: found ? GlassTone.success : GlassTone.neutral,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 220,
            height: 96,
            child: AnimatedBuilder(
              animation: _sweep,
              builder: (context, _) => CustomPaint(
                painter: _FloorSweepPainter(t: _sweep.value, found: found),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                color: found ? AppConstants.success : AppConstants.accent,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            found ? 'Floor found' : 'Finding the floor · $percent%',
            style: AppConstants.bodyStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// A phone glides in a slow figure-eight over a faint floor grid, leaving a
/// fading trail. The trail is the "keep moving over the floor" cue.
class _FloorSweepPainter extends CustomPainter {
  final double t; // 0..1 loop phase
  final bool found;

  _FloorSweepPainter({required this.t, required this.found});

  static const int _trailSamples = 24;
  static const double _trailSpan = 0.35; // loop fraction the trail covers

  Offset _pointAt(Size size, double phase) {
    final angle = 2 * math.pi * phase;
    return Offset(
      size.width * (0.5 + 0.36 * math.sin(angle)),
      size.height * (0.5 + 0.22 * math.sin(2 * angle)),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final accent = found ? AppConstants.success : AppConstants.accent;

    // Floor grid.
    final grid = Paint()
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.12);
    for (var x = 0.0; x <= size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y <= size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // Fading trail behind the phone.
    for (var i = 1; i <= _trailSamples; i++) {
      final a = _pointAt(size, t - _trailSpan * (i - 1) / _trailSamples);
      final b = _pointAt(size, t - _trailSpan * i / _trailSamples);
      final fade = 1 - i / _trailSamples;
      canvas.drawLine(
        a,
        b,
        Paint()
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = accent.withValues(alpha: 0.7 * fade),
      );
    }

    // The phone, tilted slightly along its direction of travel.
    final pos = _pointAt(size, t);
    final ahead = _pointAt(size, t + 0.01);
    final heading = math.atan2(ahead.dy - pos.dy, ahead.dx - pos.dx);
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(heading + math.pi / 2);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 16, height: 26),
      const Radius.circular(4),
    );
    canvas.drawRRect(rect, Paint()..color = Colors.white.withValues(alpha: 0.95));
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppConstants.secondary,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FloorSweepPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.found != found;
}
