import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';

class SellerSparkline extends StatelessWidget {
  final List<double> values;

  const SellerSparkline({super.key, required this.values});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 28),
      painter: _SparklinePainter(values: values, color: AppConstants.accent),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparklinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

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

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values;
}
