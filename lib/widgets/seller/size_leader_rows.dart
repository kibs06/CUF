import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../services/reservation_service.dart';
import '../../utils/bulk_reservation_export.dart';

/// The requested sizes as an aligned list, one per line:
///
/// ```
/// EU: 35 ------- 9
/// EU: 36 ------- 9
/// EU: 39 ------ 10
/// ```
///
/// A comma-joined sentence makes the reader parse; a column of sizes lets them
/// run their eye down the numbers and the quantities separately, which is how
/// a reseller reads a buy sheet out to a supplier. The label is mono so the
/// `EU: 35` blocks line up, and the quantity is right-aligned for the same
/// reason.
class SizeLeaderRows extends StatelessWidget {
  final BulkReservation reservation;

  const SizeLeaderRows({super.key, required this.reservation});

  @override
  Widget build(BuildContext context) {
    final rows = sizeLeaderRows(reservation);
    if (rows.isEmpty) {
      return Text(
        'Not specified',
        style: AppConstants.bodyStyle(
          fontSize: 11.5,
          color: SellerTheme.textMuted,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Row(
              children: [
                Text(
                  row.label,
                  style: AppConstants.monoStyle(
                    fontSize: 11,
                    color: AppConstants.secondary,
                  ),
                ),
                const SizedBox(width: 6),
                // The leader is decorative: it carries no data, it just keeps
                // the eye on the same line between the size and its count.
                Expanded(
                  child: CustomPaint(
                    painter: _DashLeaderPainter(
                      color: AppConstants.secondary.withValues(alpha: 0.28),
                    ),
                    child: const SizedBox(height: 11),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  row.quantity,
                  style: AppConstants.monoStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.secondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Evenly spaced short dashes on a hairline — a printed-list leader.
class _DashLeaderPainter extends CustomPainter {
  final Color color;
  const _DashLeaderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    const dash = 2.5;
    const gap = 2.5;
    var x = 0.0;
    while (x + dash <= size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashLeaderPainter oldDelegate) =>
      oldDelegate.color != color;
}
