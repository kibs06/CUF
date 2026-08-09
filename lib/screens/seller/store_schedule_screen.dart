import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../services/store_service.dart';
import '../../widgets/sole_primary_button.dart';

/// Seller-facing store schedule configuration screen.
///
/// Allows configuring auto-schedule (open/close times) with a visual
/// 24h timeline bar showing the open window.
class StoreScheduleScreen extends StatefulWidget {
  final Map<String, dynamic> store;

  const StoreScheduleScreen({super.key, required this.store});

  @override
  State<StoreScheduleScreen> createState() => _StoreScheduleScreenState();
}

class _StoreScheduleScreenState extends State<StoreScheduleScreen> {
  final _storeService = StoreService.instance;
  bool _autoScheduleEnabled = false;
  TimeOfDay _openTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _closeTime = const TimeOfDay(hour: 21, minute: 0);
  bool _isSaving = false;
  Map<String, dynamic>? _store;

  @override
  void initState() {
    super.initState();
    _store = widget.store;
    _loadCurrentSchedule();
  }

  void _loadCurrentSchedule() {
    if (_store == null) return;
    _autoScheduleEnabled = _store!['auto_schedule_enabled'] ?? false;
    if (_store!['open_time'] != null) {
      _openTime = _parseTime(_store!['open_time']);
    }
    if (_store!['close_time'] != null) {
      _closeTime = _parseTime(_store!['close_time']);
    }
  }

  TimeOfDay _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: parts.length > 1 ? int.parse(parts[1]) : 0,
    );
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _timeToString(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
  }

  /// Compute time in minutes since midnight for the timeline bar.
  int _timeToMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  bool get _isOvernight =>
      _timeToMinutes(_closeTime) < _timeToMinutes(_openTime);

  /// Current live status line
  String get _liveStatus {
    if (!_autoScheduleEnabled) return 'Schedule disabled';
    final now = TimeOfDay.now();
    final nowMinutes = _timeToMinutes(now);
    final openMinutes = _timeToMinutes(_openTime);
    final closeMinutes = _timeToMinutes(_closeTime);

    final isWithinSchedule = _isOvernight
        ? (nowMinutes >= openMinutes || nowMinutes < closeMinutes)
        : (nowMinutes >= openMinutes && nowMinutes < closeMinutes);

    final isManualOverride = _store?['manual_override'] ?? false;

    if (isManualOverride) {
      final isOpen = _store?['is_open'] ?? true;
      return isOpen
          ? 'Manually opened — schedule resumes at ${_formatTime(_closeTime)}'
          : 'Manually closed — reopens automatically at ${_formatTime(_openTime)}';
    }

    if (isWithinSchedule) {
      return 'Auto · Open · Closes at ${_formatTime(_closeTime)}';
    } else {
      return 'Auto · Closed · Opens at ${_formatTime(_openTime)}';
    }
  }

  Color get _statusColor {
    if (!_autoScheduleEnabled) return Colors.grey;
    final now = TimeOfDay.now();
    final nowMinutes = _timeToMinutes(now);
    final openMinutes = _timeToMinutes(_openTime);
    final closeMinutes = _timeToMinutes(_closeTime);

    final isWithinSchedule = _isOvernight
        ? (nowMinutes >= openMinutes || nowMinutes < closeMinutes)
        : (nowMinutes >= openMinutes && nowMinutes < closeMinutes);

    return isWithinSchedule ? AppConstants.success : AppConstants.error;
  }

  Future<void> _pickTime({required bool isOpen}) async {
    final initial = isOpen ? _openTime : _closeTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppConstants.primary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isOpen) {
          _openTime = picked;
        } else {
          _closeTime = picked;
        }
      });
    }
  }

  Future<void> _saveSchedule() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);
    try {
      final storeId = _store!['id'].toString();
      await _storeService.updateStoreSchedule(
        storeId: storeId,
        autoScheduleEnabled: _autoScheduleEnabled,
        openTime: _autoScheduleEnabled ? _timeToString(_openTime) : null,
        closeTime: _autoScheduleEnabled ? _timeToString(_closeTime) : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_autoScheduleEnabled
                ? 'Schedule saved — store will open/close automatically'
                : 'Auto-schedule disabled'),
            backgroundColor: AppConstants.success,
          ),
        );
        Navigator.of(context).pop(true); // Return true to refresh parent
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppConstants.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.sellerSurface,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        title: Text(
          'Store Hours',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Live Status Line
            _buildLiveStatus(),
            const SizedBox(height: 20),

            // Auto Schedule Toggle
            _buildAutoScheduleToggle(),
            const SizedBox(height: 24),

            // Time Pickers
            _buildTimePickers(),
            const SizedBox(height: 24),

            // 24h Timeline Bar
            _buildTimelineBar(),
            const SizedBox(height: 16),

            // Overnight notice
            if (_isOvernight)
              _buildOvernightNotice(),
            const SizedBox(height: 32),

            // Save Button
            SolePrimaryButton(
              label: 'Save Schedule',
              onPressed: (_autoScheduleEnabled && _isSaving) ? null : _saveSchedule,
              isLoading: _isSaving,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveStatus() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _statusColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _statusColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _liveStatus,
              style: AppConstants.bodyStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoScheduleToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
        boxShadow: AppConstants.warmShadow,
      ),
      child: Row(
        children: [
          Icon(
            Icons.schedule_outlined,
            color: _autoScheduleEnabled
                ? AppConstants.primary
                : Colors.grey.shade400,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto Schedule',
                  style: AppConstants.bodyStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Automatically open/close at set times',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _autoScheduleEnabled,
            onChanged: (value) {
              setState(() => _autoScheduleEnabled = value);
            },
            activeThumbColor: AppConstants.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildTimePickers() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: _autoScheduleEnabled ? 1.0 : 0.4,
      child: IgnorePointer(
        ignoring: !_autoScheduleEnabled,
        child: Row(
          children: [
            // Open Time
            Expanded(
              child: _buildTimeCard(
                label: 'Opens At',
                time: _openTime,
                icon: Icons.wb_sunny_outlined,
                onTap: () => _pickTime(isOpen: true),
              ),
            ),
            const SizedBox(width: 12),
            // Close Time
            Expanded(
              child: _buildTimeCard(
                label: 'Closes At',
                time: _closeTime,
                icon: Icons.nightlight_outlined,
                onTap: () => _pickTime(isOpen: false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeCard({
    required String label,
    required TimeOfDay time,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppConstants.cardRadius,
          boxShadow: AppConstants.warmShadow,
          border: Border.all(
            color: _autoScheduleEnabled
                ? AppConstants.primary.withValues(alpha: 0.3)
                : Colors.grey.shade200,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppConstants.primary, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(time),
              style: AppConstants.monoStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _autoScheduleEnabled
                    ? AppConstants.secondary
                    : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineBar() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: _autoScheduleEnabled ? 1.0 : 0.4,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppConstants.cardRadius,
          boxShadow: AppConstants.warmShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '24-HOUR TIMELINE',
              style: AppConstants.bodyStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 12),
            // Timeline bar
            SizedBox(
              height: 32,
              child: CustomPaint(
                size: const Size(double.infinity, 32),
                painter: _TimelinePainter(
                  openMinutes: _timeToMinutes(_openTime),
                  closeMinutes: _timeToMinutes(_closeTime),
                  isOvernight: _isOvernight,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Time labels
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatTime(_openTime),
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.success,
                  ),
                ),
                Text(
                  _formatTime(_closeTime),
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'OPEN',
                  style: AppConstants.bodyStyle(
                    fontSize: 9,
                    color: Colors.grey.shade400,
                  ),
                ),
                Text(
                  'CLOSE',
                  style: AppConstants.bodyStyle(
                    fontSize: 9,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOvernightNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.amber, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Overnight schedule: store stays open past midnight and closes the next day.',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: Colors.amber.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for the 24h timeline bar.
class _TimelinePainter extends CustomPainter {
  final int openMinutes;
  final int closeMinutes;
  final bool isOvernight;

  _TimelinePainter({
    required this.openMinutes,
    required this.closeMinutes,
    required this.isOvernight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = const Color(0xFFF3F4F6)
      ..style = PaintingStyle.fill;

    final openPaint = Paint()
      ..color = AppConstants.success
      ..style = PaintingStyle.fill;

    final closedPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.fill;

    final radius = Radius.circular(8);

    // Draw background
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), radius),
      bgPaint,
    );

    if (isOvernight) {
      // Overnight: open from openMinutes to 1440 (midnight), then 0 to closeMinutes
      final openStartFrac = openMinutes / 1440;
      final openEndFrac = 1.0; // midnight
      final closeStartFrac = 0.0;
      final closeEndFrac = closeMinutes / 1440;

      // Open segment: from open to end
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            openStartFrac * size.width,
            0,
            (openEndFrac - openStartFrac) * size.width,
            size.height,
          ),
          const Radius.circular(0),
        ),
        openPaint,
      );

      // Open segment: from start to close
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            closeStartFrac * size.width,
            0,
            (closeEndFrac - closeStartFrac) * size.width,
            size.height,
          ),
          const Radius.circular(0),
        ),
        openPaint,
      );

      // Closed segment: from close to open
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            closeEndFrac * size.width,
            0,
            (openStartFrac - closeEndFrac) * size.width,
            size.height,
          ),
          const Radius.circular(0),
        ),
        closedPaint,
      );
    } else {
      // Normal: open from openMinutes to closeMinutes
      final openStartFrac = openMinutes / 1440;
      final openEndFrac = closeMinutes / 1440;

      // Closed before open
      if (openStartFrac > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, openStartFrac * size.width, size.height),
            radius,
          ),
          closedPaint,
        );
      }

      // Open window
      canvas.drawRect(
        Rect.fromLTWH(
          openStartFrac * size.width,
          0,
          (openEndFrac - openStartFrac) * size.width,
          size.height,
        ),
        openPaint,
      );

      // Closed after close
      if (openEndFrac < 1) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              openEndFrac * size.width,
              0,
              (1 - openEndFrac) * size.width,
              size.height,
            ),
            radius,
          ),
          closedPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) =>
      openMinutes != oldDelegate.openMinutes ||
      closeMinutes != oldDelegate.closeMinutes ||
      isOvernight != oldDelegate.isOvernight;
}
