import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';

class SellerSparkline extends StatelessWidget {
  final List<double> values;
  final Color color;

  /// When true, fills the area under the line with a gradient fading from
  /// [color] at 35% opacity to transparent (hero-card treatment).
  final bool showFill;

  final double strokeWidth;
  final double height;

  const SellerSparkline({
    super.key,
    required this.values,
    this.color = AppConstants.accent,
    this.showFill = false,
    this.strokeWidth = 2.5,
    this.height = 28,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: _SparklinePainter(
        values: values,
        color: color,
        showFill: showFill,
        strokeWidth: strokeWidth,
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final bool showFill;
  final double strokeWidth;

  _SparklinePainter({
    required this.values,
    required this.color,
    required this.showFill,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final double min = values.reduce((a, b) => a < b ? a : b);
    final double max = values.reduce((a, b) => a > b ? a : b);
    final range = (max - min).clamp(1.0, double.infinity);

    final double stepX = size.width / (values.length - 1);
    final path = Path();

    for (int i = 0; i < values.length; i++) {
      final double x = i * stepX;
      final double y = size.height - ((values[i] - min) / range) * (size.height - 4) - 2;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Gradient area fill under the line (rust at 35% fading to 0%).
    if (showFill) {
      final area = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      final fill = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.35),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size);
      canvas.drawPath(area, fill);
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.showFill != showFill ||
      oldDelegate.strokeWidth != strokeWidth;
}
