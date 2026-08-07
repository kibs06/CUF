import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../models/foot_measurement.dart';
import '../../providers/auth_provider.dart';
import '../../providers/foot_measurement_provider.dart';
import '../../utils/foot_measurement_utils.dart';

/// Results screen displaying foot measurements and size recommendations.
///
/// Shows:
/// - Measured length + width for each foot (in mm and cm)
/// - Recommended EU size (primary), with US/UK equivalents
/// - Confidence indicator (High / Medium / Low) for live AR scans
/// - Sized-to-larger-foot disclaimer
/// - Manual half-size adjustment option
/// - Save to Profile / Retake actions
///
/// Supports both single-foot (paper scan) and dual-foot (AR scan) results.
class FootResultsScreen extends StatefulWidget {
  final String footSide; // 'left', 'right', or 'both'
  final double footLengthMm;
  final double footWidthMm;
  final double? footLengthRightMm; // Non-null when footSide == 'both'
  final double? footWidthRightMm;
  final String? euSize;
  final String? usSize;
  final String? ukSize;
  final String paperSize; // 'ar', 'a4', or 'letter'
  final String footCondition;
  final double paperConfidence;
  final double lightingQuality;

  // Live AR confidence (§7 of the implementation prompt)
  final String? confidenceLevel; // 'high', 'medium', 'low'
  final double? confidenceScore; // 0.0–1.0
  final int? leftSampleCount;
  final int? rightSampleCount;

  /// True when the measurement came from the MANUAL tap-to-measure flow
  /// (MANUAL_MEASUREMENT_PIVOT_PROMPT). No automatic confidence scoring
  /// exists in that flow — instead of a confidence card, the results screen
  /// shows an honesty/trust framing: the values are based on where the user
  /// placed the points, and they can redo any that don't look right (§2.6).
  final bool manualMode;

  const FootResultsScreen({
    super.key,
    required this.footSide,
    required this.footLengthMm,
    required this.footWidthMm,
    this.footLengthRightMm,
    this.footWidthRightMm,
    this.euSize,
    this.usSize,
    this.ukSize,
    required this.paperSize,
    required this.footCondition,
    required this.paperConfidence,
    required this.lightingQuality,
    this.confidenceLevel,
    this.confidenceScore,
    this.leftSampleCount,
    this.rightSampleCount,
    this.manualMode = false,
  });

  @override
  State<FootResultsScreen> createState() => _FootResultsScreenState();
}

class _FootResultsScreenState extends State<FootResultsScreen> {
  String? _selectedEuSize;
  bool _isSaving = false;
  bool _hasAdjusted = false;

  bool get _isArScan => widget.paperSize == 'ar';
  bool get _isDualFoot => widget.footSide == 'both';

  @override
  void initState() {
    super.initState();
    _selectedEuSize = widget.euSize;
  }

  /// Available EU sizes for the adjustment picker (half-size steps).
  List<String> get _availableSizes {
    const double start = 35;
    const double end = 48;
    final sizes = <String>[];
    for (double s = start; s <= end; s += 0.5) {
      sizes.add(s == s.roundToDouble() ? '${s.round()}' : s.toStringAsFixed(1));
    }
    return sizes;
  }

  Future<void> _saveToProfile() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final measurementProvider = Provider.of<FootMeasurementProvider>(context, listen: false);
    final userId = auth.currentUser?['id']?.toString();
    if (userId == null) return;

    setState(() => _isSaving = true);

    final measurement = FootMeasurement(
      userId: userId,
      footLengthLeftMm: _isDualFoot ? widget.footLengthMm : (widget.footSide == 'left' ? widget.footLengthMm : null),
      footWidthLeftMm: _isDualFoot ? widget.footWidthMm : (widget.footSide == 'left' ? widget.footWidthMm : null),
      footLengthRightMm: _isDualFoot ? widget.footLengthRightMm : (widget.footSide == 'right' ? widget.footLengthMm : null),
      footWidthRightMm: _isDualFoot ? widget.footWidthRightMm : (widget.footSide == 'right' ? widget.footWidthMm : null),
      recommendedEuSize: widget.euSize,
      recommendedUsSize: widget.usSize,
      recommendedUkSize: widget.ukSize,
      paperSizeUsed: widget.paperSize,
      footCondition: widget.footCondition,
      userAdjustedEuSize: _hasAdjusted ? _selectedEuSize : null,
      paperDetectionConfidence: widget.paperConfidence,
      lightingQuality: widget.lightingQuality,
      lengthConfidenceLeft: widget.leftSampleCount != null ? widget.confidenceScore : null,
      lengthConfidenceRight: widget.rightSampleCount != null ? widget.confidenceScore : null,
      overallConfidenceScore: widget.confidenceScore,
      confidenceLevel: widget.confidenceLevel,
      rawSampleCount: widget.leftSampleCount != null
          ? (widget.leftSampleCount ?? 0) + (widget.rightSampleCount ?? 0)
          : null,
      finalSampleCount: widget.leftSampleCount != null
          ? (widget.leftSampleCount ?? 0) + (widget.rightSampleCount ?? 0)
          : null,
      scanDate: DateTime.now(),
    );

    final saved = await measurementProvider.saveScan(measurement);

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (saved != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Foot size saved to your profile!'),
          backgroundColor: AppConstants.success,
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save — please try again.'),
          backgroundColor: AppConstants.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Your Foot Size',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppConstants.secondary,
          ),
        ),
        backgroundColor: AppConstants.surfaceLight,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppConstants.secondary),
          onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Size Recommendation Card ──
                _buildSizeCard(),
                const SizedBox(height: 24),

                // ── Manual-mode honesty note (§2.6 of the pivot brief) ──
                // Manual tap-to-measure has no statistical confidence score;
                // instead we tell the user the measurements are based on
                // where THEY placed the points and invite a redo if any look
                // wrong — trust through transparency.
                if (widget.manualMode) ...[
                  _buildManualNote(),
                  const SizedBox(height: 24),
                ],

                // ── Confidence Indicator (AR scans only) ──
                if (_isArScan && widget.confidenceLevel != null) ...[
                  _buildConfidenceCard(),
                  const SizedBox(height: 24),
                ],

                // ── Measurement Details ──
                _buildSectionTitle('Measurement Details'),
                const SizedBox(height: 12),
                if (_isDualFoot) ...[
                  _buildFootMeasurements('Left Foot', widget.footLengthMm, widget.footWidthMm),
                  const SizedBox(height: 8),
                  _buildFootMeasurements('Right Foot', widget.footLengthRightMm ?? 0, widget.footWidthRightMm ?? 0),
                  const SizedBox(height: 8),
                  _buildMeasurementRow(
                    label: 'Larger Foot Used',
                    value: widget.footLengthMm >= (widget.footLengthRightMm ?? 0) ? 'Left' : 'Right',
                    subValue: '',
                  ),
                ] else ...[
                  _buildMeasurementRow(
                    label: '${widget.footSide == 'left' ? 'Left' : 'Right'} Foot Length',
                    value: FootMeasurement.formatMm(widget.footLengthMm),
                    subValue: FootMeasurement.formatCm(widget.footLengthMm),
                  ),
                  _buildMeasurementRow(
                    label: '${widget.footSide == 'left' ? 'Left' : 'Right'} Foot Width',
                    value: FootMeasurement.formatMm(widget.footWidthMm),
                    subValue: FootMeasurement.formatCm(widget.footWidthMm),
                  ),
                ],
                const SizedBox(height: 16),

                // ── Size Adjustment ──
                _buildSectionTitle('Adjust Size (Optional)'),
                const SizedBox(height: 4),
                Text(
                  'If you disagree with the recommendation, select a different size.',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 12),
                _buildSizeAdjuster(),
                const SizedBox(height: 24),

                // ── Scan Quality (paper scans) / Sample Info (AR scans) ──
                if (!_isArScan) ...[
                  _buildSectionTitle('Scan Quality'),
                  const SizedBox(height: 12),
                  _buildQualityIndicator('Paper Detection', widget.paperConfidence),
                  _buildQualityIndicator('Lighting', widget.lightingQuality),
                  const SizedBox(height: 24),
                ] else if (widget.leftSampleCount != null) ...[
                  _buildSectionTitle('Scan Details'),
                  const SizedBox(height: 12),
                  _buildMeasurementRow(
                    label: 'Left Foot Samples',
                    value: '${widget.leftSampleCount}',
                    subValue: '',
                  ),
                  _buildMeasurementRow(
                    label: 'Right Foot Samples',
                    value: '${widget.rightSampleCount}',
                    subValue: '',
                  ),
                  _buildMeasurementRow(
                    label: 'Scan Method',
                    value: 'Live AR',
                    subValue: 'ARCore + MediaPipe',
                  ),
                  const SizedBox(height: 24),
                ],

                // ── Disclaimer ──
                _buildDisclaimer(),
              ],
            ),
          ),

          // ── Action Buttons (pinned bottom) ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: AppConstants.surfaceLight,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Row(
                children: [
                  // Retake
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppConstants.primary),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppConstants.buttonRadius,
                        ),
                      ),
                      child: Text(
                        'Retake',
                        style: AppConstants.bodyStyle(
                          fontWeight: FontWeight.bold,
                          color: AppConstants.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Save
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _isSaving ? null : _saveToProfile,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppConstants.primary,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppConstants.buttonRadius,
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Save to Profile',
                              style: AppConstants.bodyStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSizeCard() {
    final displayEu = _selectedEuSize ?? widget.euSize ?? '—';
    final displayUs = _hasAdjusted && _selectedEuSize != null
        ? euToUs(_selectedEuSize!)
        : widget.usSize;
    final displayUk = _hasAdjusted && _selectedEuSize != null
        ? euToUk(_selectedEuSize!)
        : widget.ukSize;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppConstants.accent,
            AppConstants.accent.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppConstants.cardRadius,
        boxShadow: [
          BoxShadow(
            color: AppConstants.accent.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'YOUR RECOMMENDED SIZE',
            style: AppConstants.bodyStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppConstants.secondary.withValues(alpha: 0.7),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'EU $displayEu',
            style: AppConstants.monoStyle(
              fontSize: 56,
              fontWeight: FontWeight.bold,
              color: AppConstants.secondary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (displayUs != null && displayUs.isNotEmpty) ...[
                _buildSizeChip('US $displayUs'),
                const SizedBox(width: 12),
              ],
              if (displayUk != null && displayUk.isNotEmpty) ...[
                _buildSizeChip('UK $displayUk'),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppConstants.secondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Sized to your larger foot for best fit',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppConstants.secondary.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Honesty/trust framing for manual-mode results (§2.6 of the pivot brief):
  /// measurements are directly user-placed, so no auto-confidence score is
  /// claimed — instead the user is reminded they can redo any point pair.
  Widget _buildManualNote() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.accent.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.touch_app_outlined, color: AppConstants.accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How this was measured',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.secondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'These measurements are based on where you placed the points '
                  'on your foot. If any look off, feel free to redo them — '
                  'tapping the points directly is the most accurate way to '
                  'measure your feet.',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary.withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceCard() {
    final level = widget.confidenceLevel ?? 'medium';
    final score = widget.confidenceScore ?? 0.5;

    Color color;
    IconData icon;
    String title;
    String description;

    switch (level) {
      case 'high':
        color = AppConstants.success;
        icon = Icons.verified;
        title = 'High Confidence';
        description = 'Tight measurement spread — this result is reliable.';
        break;
      case 'medium':
        color = AppConstants.statusPendingColor;
        icon = Icons.info_outline;
        title = 'Medium Confidence';
        description = 'Moderate spread in measurements. Compare against a known fitting shoe.';
        break;
      default:
        color = AppConstants.error;
        icon = Icons.warning_amber_rounded;
        title = 'Low Confidence';
        description = 'Consider rescanning in better lighting with steady movement.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary.withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                // Confidence bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: score,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(color),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFootMeasurements(String label, double lengthMm, double widthMm) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.borderGray.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppConstants.bodyStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppConstants.secondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMiniMeasurement('Length', FootMeasurement.formatMm(lengthMm), FootMeasurement.formatCm(lengthMm)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniMeasurement('Width', FootMeasurement.formatMm(widthMm), FootMeasurement.formatCm(widthMm)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMeasurement(String label, String value, String subValue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppConstants.bodyStyle(
            fontSize: 11,
            color: AppConstants.secondary.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Text(
              value,
              style: AppConstants.monoStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppConstants.primary,
              ),
            ),
            if (subValue.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                subValue,
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  color: AppConstants.secondary.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: AppConstants.bodyStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppConstants.secondary.withValues(alpha: 0.5),
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildMeasurementRow({
    required String label,
    required String value,
    required String subValue,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppConstants.borderGray.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 14,
                color: AppConstants.secondary,
              ),
            ),
            Row(
              children: [
                Text(
                  value,
                  style: AppConstants.monoStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.primary,
                  ),
                ),
                if (subValue.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    subValue,
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: AppConstants.secondary.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSizeAdjuster() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _hasAdjusted
              ? AppConstants.accent.withValues(alpha: 0.5)
              : AppConstants.borderGray.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EU Size',
            style: AppConstants.bodyStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppConstants.secondary,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _availableSizes.length,
              itemBuilder: (context, index) {
                final size = _availableSizes[index];
                final isSelected = _selectedEuSize == size;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedEuSize = size;
                      _hasAdjusted = (size != widget.euSize);
                    });
                  },
                  child: Container(
                    width: 44,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppConstants.primary : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? AppConstants.primary
                            : AppConstants.borderGray.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        size,
                        style: AppConstants.monoStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : AppConstants.secondary,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_hasAdjusted) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: AppConstants.accent),
                const SizedBox(width: 6),
                Text(
                  'Adjusted from EU ${widget.euSize} to EU $_selectedEuSize',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.accent,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQualityIndicator(String label, double value) {
    final percentage = (value * 100).round();
    final color = value >= 0.8
        ? AppConstants.success
        : value >= 0.5
            ? AppConstants.statusPendingColor
            : AppConstants.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: AppConstants.secondary.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: value,
                backgroundColor: AppConstants.borderGray.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 36,
            child: Text(
              '$percentage%',
              style: AppConstants.monoStyle(
                fontSize: 12,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.borderGray.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: AppConstants.secondary.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This size is a recommendation based on your ${_isArScan ? 'live AR scan' : 'scan'}. Fit varies by '
              'brand and shoe style. For best results, compare against a shoe '
              'you already own that fits well.',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.5),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSizeChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppConstants.secondary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: AppConstants.monoStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AppConstants.secondary,
        ),
      ),
    );
  }
}
