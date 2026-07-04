import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';

class SellerWeeklyBar extends StatelessWidget {
  final List<double> dailySales;
  final List<String> dayLabels;
  final int? todayIndex;

  const SellerWeeklyBar({
    super.key,
    required this.dailySales,
    required this.dayLabels,
    this.todayIndex,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 140),
      painter: _WeeklyBarPainter(
        values: dailySales,
        labels: dayLabels,
        todayIndex: todayIndex ?? DateTime.now().weekday - 1,
      ),
    );
  }
}

class _WeeklyBarPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final int todayIndex;

  _WeeklyBarPainter({
    required this.values,
    required this.labels,
    required this.todayIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final double max = values
        .reduce((a, b) => a > b ? a : b)
        .clamp(1, double.infinity);
    final double barWidth = (size.width - 40) / values.length - 8;
    final double stepX = (size.width - 40) / values.length;
    final double startX = 20.0;
    final double chartHeight = size.height - 30;

    // Horizontal guide lines
    final guidePaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 1; i <= 3; i++) {
      final y = chartHeight * (1 - i * 0.25);
      canvas.drawLine(
        Offset(startX, y),
        Offset(size.width - 20, y),
        guidePaint,
      );
    }

    // Bars
    for (int i = 0; i < values.length; i++) {
      final x = startX + i * stepX + (stepX - barWidth) / 2;
      final barHeight = (values[i] / max) * chartHeight;
      final y = chartHeight - barHeight;

      Color barColor;
      if (i == todayIndex) {
        barColor = AppConstants.accent;
      } else if (i < todayIndex) {
        barColor = AppConstants.primary;
      } else {
        barColor = AppConstants.sellerSurface;
      }

      final barPaint = Paint()..color = barColor;

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(3),
      );
      canvas.drawRRect(rrect, barPaint);

      // Day label
      final textPainter = TextPainter(
        text: TextSpan(
          text: labels.length > i ? labels[i] : '',
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 10,
            color: Colors.grey[500],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x + (barWidth - textPainter.width) / 2, chartHeight + 6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WeeklyBarPainter oldDelegate) =>
      oldDelegate.values != values;
}
