import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../widgets/foot_size_v2/glass_card.dart';
import '../../providers/v2/scan_phase.dart';

/// A looping, GIF-style "how to scan" demo for the current capture step —
/// drawn entirely with CustomPaint (no assets).
///
/// Shown automatically when a new capture step becomes ready; dismissed by
/// the user ("Got it") or automatically when capture starts. The parent
/// controls visibility; this widget only renders the looping animation.
class ScanInstructionOverlay extends StatefulWidget {
  final CaptureStep step;
  final VoidCallback onDismiss;

  const ScanInstructionOverlay({
    super.key,
    required this.step,
    required this.onDismiss,
  });

  @override
  State<ScanInstructionOverlay> createState() => _ScanInstructionOverlayState();
}

class _ScanInstructionOverlayState extends State<ScanInstructionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop;

  bool get _isTop => widget.step.captureAngle == 'front';

  String get _title => _isTop
      ? 'Scan the top of your ${widget.step.footSide} foot'
      : 'Now the side of your ${widget.step.footSide} foot';

  String get _body => _isTop
      ? 'Hold your phone about 30 cm above your foot, pointing straight '
          'down. Keep the whole foot inside the frame.'
      : 'Lower the phone to floor level and aim at the side of your foot. '
          'Move slowly — the floor must stay in view.';

  @override
  void initState() {
    super.initState();
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.62),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassCard(
                  borderRadius: BorderRadius.circular(24),
                  padding:
                      const EdgeInsets.fromLTRB(24, 22, 24, 18),
                  child: Column(
                    children: [
                      Text(
                        _title,
                        textAlign: TextAlign.center,
                        style: AppConstants.headlineStyle(
                          fontSize: 17,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 230,
                        height: 190,
                        child: AnimatedBuilder(
                          animation: _loop,
                          builder: (context, _) => CustomPaint(
                            painter: _InstructionDemoPainter(
                              t: _loop.value,
                              isTop: _isTop,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _body,
                        textAlign: TextAlign.center,
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.85),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: widget.onDismiss,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppConstants.accent,
                    foregroundColor: AppConstants.secondary,
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppConstants.stadiumRadius,
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: Text(
                    'Got it',
                    style: AppConstants.bodyStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One continuous stylized sole outline, toes pointing up, mapped into
/// [area] from a normalized 0..1 space. Shared by the instruction demo and
/// the live foot-trace overlay so the whole scan flow uses one foot glyph.
Path footOutlinePath(Rect area) {
  final w = area.width, h = area.height;
  Offset pt(double x, double y) =>
      Offset(area.left + x * w, area.top + y * h);

  // cubicTo takes 6 doubles: cp1x, cp1y, cp2x, cp2y, ex, ey
  final path = Path()..moveTo(pt(0.50, 0.97).dx, pt(0.50, 0.97).dy);

  Offset p(double x, double y) => pt(x, y);

  void c(Offset cp1, Offset cp2, Offset e) {
    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, e.dx, e.dy);
  }

  c(p(0.30, 0.94), p(0.25, 0.84), p(0.27, 0.76)); // heel left
  c(p(0.29, 0.64), p(0.31, 0.58), p(0.29, 0.48)); // arch
  c(p(0.26, 0.38), p(0.24, 0.30), p(0.30, 0.20)); // ball L
  c(p(0.36, 0.08), p(0.46, 0.02), p(0.54, 0.04)); // big toe
  c(p(0.64, 0.06), p(0.72, 0.14), p(0.74, 0.26)); // toes → ball R
  c(p(0.76, 0.36), p(0.70, 0.42), p(0.68, 0.52)); // arch R
  c(p(0.66, 0.62), p(0.72, 0.72), p(0.73, 0.80)); // heel R
  c(p(0.74, 0.90), p(0.64, 0.98), p(0.50, 0.97)); // close
  return path;
}

/// The looping demo itself.
///
/// TOP view: a phone glyph descends from the upper-left tilt into a straight
/// overhead pose above the guide box while the footprint pulses inside.
///
/// SIDE view: the footprint stays put and the phone orbits from overhead
/// down to floor level at the side, leaving an arc trail with an arrowhead.
class _InstructionDemoPainter extends CustomPainter {
  final double t; // 0..1 loop phase
  final bool isTop;

  _InstructionDemoPainter({required this.t, required this.isTop});

  static const _accent = AppConstants.accent;

  // One smooth ease in/out per half-loop: descend (0→0.45), hold (0.45→0.8),
  // fade-reset (0.8→1).
  double get _descend {
    if (t < 0.45) return Curves.easeOutCubic.transform(t / 0.45);
    if (t < 0.8) return 1;
    return 1 - Curves.easeIn.transform((t - 0.8) / 0.2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final box = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.60),
      width: size.width * 0.56,
      height: size.height * 0.52,
    );

    _drawGuideBox(canvas, box);
    drawFootprint(
      canvas,
      Rect.fromCenter(
        center: box.center,
        width: box.width * 0.78,
        height: box.height * 0.86,
      ),
      alpha: (0.55 + 0.3 * _pulse).clamp(0.0, 1.0),
    );

    if (isTop) {
      _drawTopDemo(canvas, size, box);
    } else {
      _drawSideDemo(canvas, size, box);
    }
  }

  double get _pulse => (0.5 - 0.5 * math.sin(t * 2 * math.pi)).abs();

  // ── TOP view: phone descends to overhead ──

  void _drawTopDemo(Canvas canvas, Size size, Rect box) {
    final p = _descend;
    // Start: up-left of the box, tilted like the user is holding it loosely.
    final start = Offset(box.left - 10, box.top - 64);
    final end = Offset(box.center.dx + 34, box.top - 26);
    final pos = Offset.lerp(start, end, p)!;
    final tilt = (1 - p) * -0.5; // radians, eases to level

    _drawPhone(canvas, pos, size * 0.30, tilt);

    if (p > 0.15 && p < 1) {
      _drawDownArrow(canvas, Offset(box.center.dx - 44, box.top - 40 + 6 * p),
          alpha: ((p - 0.15) / 0.3).clamp(0.0, 1.0));
    }
  }

  // ── SIDE view: phone orbits down to the side ──

  void _drawSideDemo(Canvas canvas, Size size, Rect box) {
    final p = _descend;
    // Orbit around the footprint's center, from overhead (−90°) to side (−8°).
    final center = box.center;
    final radius = box.width * 0.95;
    final angle = -3.141592653589793 / 2 + p * (3.141592653589793 / 2 - 0.14);

    // Trail arc behind the phone.
    if (p > 0.05 && p < 1) {
      final trail = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = _accent.withValues(alpha: 0.75 * p.clamp(0.0, 1.0));
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -3.141592653589793 / 2,
        p * (3.141592653589793 / 2 - 0.14),
        false,
        trail,
      );
      // Arrowhead at the arc's leading edge.
      final tip = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      final tangent = angle + 3.141592653589793 / 2;
      final arrow = Paint()
        ..color = _accent
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(tip, tip + Offset(math.cos(tangent - 2.6), math.sin(tangent - 2.6)) * 9, arrow);
      canvas.drawLine(tip, tip + Offset(math.cos(tangent + 2.6), math.sin(tangent + 2.6)) * 9, arrow);
    }

    _drawPhone(
      canvas,
      Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      ),
      size * 0.30,
      // Phone points at the foot as it travels.
      -angle - 3.141592653589793 / 2,
    );
  }

  // ── Shared primitives ──

  void _drawGuideBox(Canvas canvas, Rect box) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.white.withValues(alpha: 0.85);

    // Dashed border via small segments on each edge.
    const dash = 7.0, gap = 5.0;
    void dashedLine(Offset a, Offset b) {
      final dist = (b - a).distance;
      if (dist == 0) return;
      var d = 0.0;
      while (d < dist) {
        final next = (d + dash).clamp(0.0, dist);
        canvas.drawLine(
          Offset.lerp(a, b, d / dist)!,
          Offset.lerp(a, b, next / dist)!,
          paint,
        );
        d = next + gap;
      }
    }

    dashedLine(box.topLeft, box.topRight);
    dashedLine(box.topRight, box.bottomRight);
    dashedLine(box.bottomRight, box.bottomLeft);
    dashedLine(box.bottomLeft, box.topLeft);
  }

  void _drawPhone(Canvas canvas, Offset center, Size rawSize, double rotation) {
    final size = Size(rawSize.width.clamp(22.0, 40.0),
        rawSize.height.clamp(38.0, 66.0));
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);

    final rect = Rect.fromCenter(
        center: Offset.zero, width: size.width, height: size.height);
    final rrect = RRect.fromRectAndRadius(
        rect.deflate(1), const Radius.circular(6));

    canvas.drawRRect(
        rrect, Paint()..color = Colors.white.withValues(alpha: 0.95));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppConstants.secondary,
    );
    // Camera dot at the top edge — communicates "lens faces the foot".
    canvas.drawCircle(
      Offset(0, -size.height / 2 + 7),
      2.6,
      Paint()..color = AppConstants.secondary,
    );
    canvas.restore();
  }

  void _drawDownArrow(Canvas canvas, Offset tip, {required double alpha}) {
    final paint = Paint()
      ..color = _accent.withValues(alpha: alpha)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(tip, tip + const Offset(0, 26), paint);
    canvas.drawLine(tip + const Offset(0, 26), tip + const Offset(-6, 18), paint);
    canvas.drawLine(tip + const Offset(0, 26), tip + const Offset(6, 18), paint);
  }

  /// Stylized sole outline (continuous path), toes pointing up.
  static void drawFootprint(Canvas canvas, Rect area, {double alpha = 1}) {
    final path = footOutlinePath(area);

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = _accent.withValues(alpha: 0.28 * alpha),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.9 * alpha),
    );
  }

  @override
  bool shouldRepaint(covariant _InstructionDemoPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.isTop != isTop;
}
