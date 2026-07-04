import 'dart:math';
import 'package:flutter/material.dart';

/// Draws diagonal dashed lines across the canvas to evoke leather stitching.
/// Used as a subtle texture overlay on store cards and headers.
///
/// Usage:
///   CustomPaint(
///     painter: StitchPainter(),
///     child: yourCardContent,
///   )
class StitchPainter extends CustomPainter {
  final Color color;
  final double dashLength;
  final double gapLength;
  final double lineSpacing;
  final double strokeWidth;

  const StitchPainter({
    this.color = const Color(0x0DFFFFFF), // white at ~5% opacity
    this.dashLength = 8.0,
    this.gapLength = 6.0,
    this.lineSpacing = 24.0,
    this.strokeWidth = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // 45-degree diagonal lines from top-left to bottom-right
    final totalDiagonal = size.width + size.height;
    final lineCount = (totalDiagonal / lineSpacing).ceil();

    for (int i = -lineCount; i <= lineCount; i++) {
      final offset = i * lineSpacing;

      // Line start and end across the diagonal
      final startX = offset;
      final startY = 0.0;
      final endX = offset - size.height;
      final endY = size.height;

      // Draw dashed line along this diagonal
      _drawDashedLine(canvas, paint, startX, startY, endX, endY, size);
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Paint paint,
    double x1,
    double y1,
    double x2,
    double y2,
    Size clipSize,
  ) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final length = sqrt(dx * dx + dy * dy);
    if (length == 0) return;

    final unitX = dx / length;
    final unitY = dy / length;

    double drawn = 0;
    bool isDash = true;

    while (drawn < length) {
      final segLength = isDash ? dashLength : gapLength;
      final segEnd = (drawn + segLength).clamp(0.0, length);

      if (isDash) {
        final sx = x1 + unitX * drawn;
        final sy = y1 + unitY * drawn;
        final ex = x1 + unitX * segEnd;
        final ey = y1 + unitY * segEnd;

        // Only draw if within clip bounds
        if (_isVisible(sx, sy, ex, ey, clipSize)) {
          canvas.drawLine(Offset(sx, sy), Offset(ex, ey), paint);
        }
      }

      drawn = segEnd;
      isDash = !isDash;
    }
  }

  bool _isVisible(double x1, double y1, double x2, double y2, Size size) {
    // Quick bounds check — at least one endpoint should be near the canvas
    return (x1 >= -50 && x1 <= size.width + 50 && y1 >= -50 && y1 <= size.height + 50) ||
        (x2 >= -50 && x2 <= size.width + 50 && y2 >= -50 && y2 <= size.height + 50);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
