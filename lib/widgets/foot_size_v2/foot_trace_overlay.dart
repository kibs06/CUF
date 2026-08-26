import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import 'scan_instruction_overlay.dart' show footOutlinePath;

/// Live "scanning" overlay shown during a capture pass.
///
/// A stylized foot outline draws itself progressively as clean samples are
/// recorded ([progress] = samples / ideal), with a glowing scan line sweeping
/// across it — a premium visual confirmation that the pipeline is collecting
/// real data. Purely decorative: it shows the capture filling up, not the
/// user's actual foot geometry.
class FootTraceOverlay extends StatefulWidget {
  /// 0.0–1.0 — fraction of the ideal sample count recorded this pass.
  final double progress;

  /// Whether a capture is running (drives the sweeping line).
  final bool active;

  const FootTraceOverlay({
    super.key,
    required this.progress,
    required this.active,
  });

  @override
  State<FootTraceOverlay> createState() => _FootTraceOverlayState();
}

class _FootTraceOverlayState extends State<FootTraceOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.active) _sweep.repeat();
  }

  @override
  void didUpdateWidget(FootTraceOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!widget.active) {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The parent rebuilds us on every controller notification, so progress
    // changes repaint without their own listenable; only the sweep needs one.
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _sweep,
        builder: (context, _) => CustomPaint(
          painter: _FootTracePainter(
            progress: widget.progress.clamp(0.0, 1.0),
            sweepT: _sweep.value,
            active: widget.active,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// Draws the progressive foot outline + sweeping scan line + soft glow fill.
class _FootTracePainter extends CustomPainter {
  final double progress;
  final double sweepT; // 0..1 sweep-line phase
  final bool active;

  _FootTracePainter({
    required this.progress,
    required this.sweepT,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Centered footprint occupying most of the overlay box, nudged up so it
    // clears the coach card at the bottom.
    final area = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.shortestSide * 0.62,
      height: size.shortestSide * 1.05,
    ).shift(Offset(0, -size.height * 0.06));

    final path = footOutlinePath(area);

    // Soft accent fill that deepens with progress.
    if (progress > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color =
              AppConstants.accent.withValues(alpha: 0.10 + 0.10 * progress),
      );
    }

    // Faint full-outline ghost so the target shape is visible from t=0.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.16),
    );

    // Progressive outline draw via path metrics.
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (sum, m) => sum + m.length);
    var drawnBudget = total * progress;
    final traced = Path();
    for (final m in metrics) {
      if (drawnBudget <= 0) break;
      traced.addPath(
          m.extractPath(0, math.min(m.length, drawnBudget)), Offset.zero);
      drawnBudget -= m.length;
    }

    // Glow underlay behind the drawn portion, then the crisp stroke.
    canvas.drawPath(
      traced,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..color = AppConstants.accent.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawPath(
      traced,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.92),
    );

    // Sweeping scan line while capturing, with intersection sparkles where
    // it crosses the outline.
    if (!active) return;
    final bounce = 0.5 - 0.5 * math.cos(sweepT * 2 * math.pi);
    final y = area.top + area.height * bounce;

    canvas.drawLine(
      Offset(area.left - 14, y),
      Offset(area.right + 14, y),
      Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(colors: [
          AppConstants.accent.withValues(alpha: 0.0),
          AppConstants.accent.withValues(alpha: 0.9),
          AppConstants.accent.withValues(alpha: 0.0),
        ]).createShader(
            Rect.fromLTWH(area.left - 14, y - 1, area.width + 28, 2)),
    );

    for (final m in metrics) {
      for (final p in _samplePointsAlong(m)) {
        if ((p.dy - y).abs() < 4) {
          canvas.drawCircle(
            p,
            3.5,
            Paint()..color = Colors.white.withValues(alpha: 0.95),
          );
        }
      }
    }
  }

  static Iterable<Offset> _samplePointsAlong(PathMetric metric) sync* {
    const n = 24;
    for (var i = 0; i <= n; i++) {
      yield metric.getTangentForOffset(metric.length * i / n)?.position ??
          Offset.zero;
    }
  }

  @override
  bool shouldRepaint(covariant _FootTracePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.sweepT != sweepT ||
      oldDelegate.active != active;
}
