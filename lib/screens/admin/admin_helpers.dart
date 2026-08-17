import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';

// ════════════════════════════════════════════════════════════════════
// Shared formatting + status helpers for the admin screens.
// Mirrors admin-portal/src/lib/constants.js (formatCurrency, formatDate,
// formatDateTime, shortId) so the app admin matches the web portal.
// ════════════════════════════════════════════════════════════════════

/// '₱1,234.56' with thousands separators, 2 decimals.
String adminCurrency(num? value) {
  final v = (value ?? 0).toDouble();
  final negative = v < 0;
  final abs = v.abs();
  final parts = abs.toStringAsFixed(2).split('.');
  final digits = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return '${negative ? '-' : ''}₱$buf.${parts[1]}';
}

/// Whole-number currency without decimals: '₱1,234'.
String adminCurrencyWhole(num? value) {
  final v = (value ?? 0).toDouble();
  final negative = v < 0;
  final digits = v.abs().round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return '${negative ? '-' : ''}₱$buf';
}

/// First 8 chars + ellipsis for long IDs (matches web `shortId`).
String adminShortId(String? id) {
  if (id == null || id.isEmpty) return '—';
  return id.length > 8 ? '${id.substring(0, 8)}…' : id;
}

/// 'Aug 17, 2026' style date.
String adminDate(DateTime? d) {
  if (d == null) return '—';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

/// 'Aug 17, 2026, 4:30 PM' style date+time.
String adminDateTime(DateTime? d) {
  if (d == null) return '—';
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  return '${adminDate(d)}, $hour12:$minute $ampm';
}

/// Parse a DB timestamp (ISO string or DateTime) — null-safe.
DateTime? adminParseTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}

/// Colors a status the way the web portal badges do.
/// Covers order statuses + payment intent statuses + report statuses.
Color adminStatusColor(String status) {
  switch (status) {
    case 'pending':
    case 'placed':
      return const Color(0xFFE8A020); // amber
    case 'confirmed':
    case 'preparing':
      return const Color(0xFF3B82F6); // blue
    case 'ready':
      return AppConstants.primary; // brown
    case 'shipped':
      return const Color(0xFF8B5CF6); // purple
    case 'received':
    case 'delivered':
    case 'succeeded':
    case 'processed':
      return const Color(0xFF4ECDC4); // teal
    case 'cancelled':
    case 'failed':
    case 'expired':
    case 'amount_mismatch':
    case 'stock_conflict':
    case 'rejected_signature':
    case 'dismissed':
      return AppConstants.error; // red
    case 'under_review':
    case 'resolved':
    case 'processing':
      return const Color(0xFF5C6BC0); // indigo
    default:
      return AppConstants.borderGray;
  }
}

/// Rounded status pill (matches the web Badge component).
class AdminStatusChip extends StatelessWidget {
  final String label;
  final String? status;

  const AdminStatusChip({super.key, required this.label, this.status});

  @override
  Widget build(BuildContext context) {
    final color = adminStatusColor(status ?? label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: color,
        ),
      ),
    );
  }
}

/// Card container matching the web portal's white rounded cards.
class AdminCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  const AdminCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppConstants.borderGray.withValues(alpha: 0.6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}
