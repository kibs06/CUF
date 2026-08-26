import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../constants/app_constants.dart';
import '../../../models/foot_measurement.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/foot_measurement_provider.dart';
import '../../../providers/v2/scan_session_controller.dart';
import '../../../utils/foot_measurement_utils.dart' show euToUs, euToUk;

/// Foot Size 2.0 results — the premium end of the scan flow.
///
/// Sections stagger in over a single entrance controller; every number
/// counts up; the confidence ring sweeps to the scan's actual score with a
/// per-factor "why this score" breakdown (sample volume, consistency,
/// measured-vs-estimated width, both feet, sock compensation).
///
/// The user can nudge the recommended EU size in half steps if the fit
/// doesn't feel right — US/UK re-derive instantly and the adjustment is
/// recorded in the saved measurement's reason.
///
/// E8 guarantee honored end-to-end: every mm value shown here is the SAME
/// compensated number the sizing math consumed.
class FootScanResultsScreenV2 extends StatefulWidget {
  final ScanResultsPayloadV2 payload;

  const FootScanResultsScreenV2({super.key, required this.payload});

  @override
  State<FootScanResultsScreenV2> createState() =>
      _FootScanResultsScreenV2State();
}

class _FootScanResultsScreenV2State extends State<FootScanResultsScreenV2>
    with SingleTickerProviderStateMixin {
  /// Drives the staggered entrance of every section.
  late final AnimationController _entrance;

  /// User's manual size adjustment (absolute EU value), null = untouched.
  double? _adjustedEu;
  bool _isSaving = false;

  ScanResultsPayloadV2 get p => widget.payload;

  // ── Size adjustment math ──────────────────────────────────────────

  static const double _stepEu = 0.5;
  static const double _maxAdjust = 2.0;

  double? get _baseEu => p.euSize != null ? double.tryParse(p.euSize!) : null;

  String _fmtEu(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

  /// The EU size that will be displayed / saved.
  String get _displayEu {
    final adjusted = _adjustedEu;
    if (adjusted != null) return _fmtEu(adjusted);
    return p.euSize ?? '—';
  }

  String get _displayUs {
    if (_adjustedEu != null) {
      return euToUs(_displayEu, category: p.shoeCategory) ?? '—';
    }
    return p.usSize ?? '—';
  }

  String get _displayUk {
    if (_adjustedEu != null) {
      return euToUk(_displayEu) ?? '—';
    }
    return p.ukSize ?? '—';
  }

  void _adjust(int direction) {
    final base = _baseEu;
    if (base == null) return;
    final current = _adjustedEu ?? base;
    // Clamp to ±2 sizes of the recommendation and a sane absolute range.
    final next = (current + direction * _stepEu)
        .clamp(base - _maxAdjust, base + _maxAdjust)
        .clamp(30.0, 50.0)
        .toDouble();
    if (next == current) return;
    HapticFeedback.selectionClick();
    setState(() => _adjustedEu = next);
  }

  bool get _canDecrease {
    final base = _baseEu;
    if (base == null) return false;
    final next = (_adjustedEu ?? base) - _stepEu;
    return next >= base - _maxAdjust && next >= 30.0;
  }

  bool get _canIncrease {
    final base = _baseEu;
    if (base == null) return false;
    final next = (_adjustedEu ?? base) + _stepEu;
    return next <= base + _maxAdjust && next <= 50.0;
  }

  void _resetAdjustment() {
    if (_adjustedEu == null) return;
    HapticFeedback.selectionClick();
    setState(() => _adjustedEu = null);
  }

  // ── Lifecycle ─────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  // ── Save (adjusted sizes win; adjustment recorded in the reason) ──

  Future<void> _saveToProfile() async {
    final auth = context.read<AuthProvider>();
    final provider = context.read<FootMeasurementProvider>();
    final userId = auth.currentUser?['id']?.toString();
    if (userId == null) return;

    setState(() => _isSaving = true);

    final hasLeft = p.leftLengthMm != null;
    final hasRight = p.rightLengthMm != null;

    final adjusted = _adjustedEu != null;
    final reason = [
      if (p.sizeRecommendationReason != null) p.sizeRecommendationReason!,
      if (adjusted)
        'Manually adjusted from EU ${p.euSize} to $_displayEu by the user.',
    ].join(' · ');

    final measurement = FootMeasurement(
      userId: userId,
      // Compensated values everywhere (E8) — raw lengths live only as
      // provenance, never in the sizing columns.
      footLengthLeftMm: hasLeft ? p.leftRawLengthMm : null,
      footWidthLeftMm: null, // raw width not tracked per-foot in payload
      footLengthRightMm: hasRight ? p.rightRawLengthMm : null,
      footWidthRightMm: null,
      footLengthLeftCompensatedMm: p.leftLengthMm,
      footWidthLeftCompensatedMm: p.leftWidthMm,
      footLengthRightCompensatedMm: p.rightLengthMm,
      footWidthRightCompensatedMm: p.rightWidthMm,
      recommendedEuSize: _displayEu,
      recommendedUsSize: _displayUs,
      recommendedUkSize: _displayUk,
      sizingFootSide: p.sizingFootSide,
      recommendedWidthCategory: p.widthCategory,
      measurementSource: 'ar_auto_scan',
      // Provenance: this scan came from the rewritten v2 pipeline.
      algorithmVersion: 'v2.0',
      sizeRecommendationReason: reason.isEmpty ? null : reason,
      paperSizeUsed: 'ar',
      footCondition: p.footCondition,
      shoeCategory: p.shoeCategory,
      overallConfidenceScore: p.confidenceScore,
      confidenceLevel: p.confidenceLevel,
      lengthConfidenceLeft: hasLeft ? p.confidenceScore : null,
      lengthConfidenceRight: hasRight ? p.confidenceScore : null,
      rawSampleCount: p.leftSampleCount + p.rightSampleCount,
      finalSampleCount: p.leftSampleCount + p.rightSampleCount,
      scanDate: DateTime.now(),
    );

    final saved = await provider.saveScan(measurement);

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (saved != null) {
      // Stamp the cheap profile snapshot (same contract as v1's results).
      try {
        await auth.saveFootProfile(
          sizeEu: double.tryParse(saved.effectiveEuSize ?? ''),
          source: AppConstants.footProfileArScan,
        );
      } catch (e) {
        debugPrint('[FootResultsV2] Foot profile snapshot write failed: $e');
      }
      if (!mounted) return;
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
      setState(() => _isSaving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final confPct = (p.confidenceScore * 100).round();

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 130),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Stagger(controller: _entrance, index: 0, child: _buildHeader()),
                  const SizedBox(height: 20),
                  _Stagger(controller: _entrance, index: 1, child: _buildHeroSize()),
                  const SizedBox(height: 16),
                  if (_baseEu != null) ...[
                    _Stagger(
                        controller: _entrance, index: 2, child: _buildAdjustCard()),
                    const SizedBox(height: 16),
                  ],
                  _Stagger(controller: _entrance, index: 3, child: _buildFootCards()),
                  const SizedBox(height: 16),
                  _Stagger(
                      controller: _entrance,
                      index: 4,
                      child: _buildConfidenceCard(confPct)),
                  const SizedBox(height: 16),
                  _Stagger(controller: _entrance, index: 5, child: _buildWidthGauge()),
                  if (p.sizeRecommendationReason != null) ...[
                    const SizedBox(height: 16),
                    _Stagger(
                        controller: _entrance,
                        index: 6,
                        child: _buildReasonCard()),
                  ],
                ],
              ),
            ),
          ),

          // ── Sticky save bar ──
          Positioned(
            left: 24,
            right: 24,
            bottom: 24,
            child: _Stagger(
              controller: _entrance,
              index: 5,
              slideFrom: const Offset(0, 0.6),
              child: SizedBox(
                height: 56,
                child: FilledButton.icon(
                  key: const Key('save-to-profile'),
                  onPressed: _isSaving ? null : _saveToProfile,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppConstants.accent,
                    foregroundColor: AppConstants.secondary,
                    elevation: 6,
                    shadowColor: AppConstants.accent.withValues(alpha: 0.4),
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppConstants.stadiumRadius,
                    ),
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    'Save EU $_displayEu to my profile',
                    style: AppConstants.bodyStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.secondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sections ──────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          icon: const Icon(Icons.close_rounded),
        ),
        const SizedBox(width: 4),
        Text(
          'Your result',
          style: AppConstants.headlineStyle(fontSize: 20),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppConstants.secondary.withValues(alpha: 0.85),
            borderRadius: AppConstants.stadiumRadius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                p.footCondition == 'socks'
                    ? Icons.checkroom_outlined
                    : Icons.directions_walk_outlined,
                color: Colors.white,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                p.footCondition == 'socks' ? 'Socks' : 'Bare',
                style:
                    AppConstants.bodyStyle(fontSize: 12, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Hero: the recommended size, huge, with a soft brand glow.
  Widget _buildHeroSize() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppConstants.accent.withValues(alpha: 0.16),
            AppConstants.primary.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: AppConstants.premiumCardRadius,
        border:
            Border.all(color: AppConstants.accent.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppConstants.accent.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'RECOMMENDED EU SIZE',
            style: AppConstants.bodyStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
              color: AppConstants.secondary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: KeyedSubtree(
              key: ValueKey(_displayEu),
              child: Text(
                _displayEu,
                key: const Key('hero-eu'),
                style: AppConstants.monoStyle(
                  fontSize: 68,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.secondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _sizePill('US $_displayUs', key: const Key('hero-us')),
              const SizedBox(width: 10),
              _sizePill('UK $_displayUk', key: const Key('hero-uk')),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _adjustedEu != null
                ? Row(
                    key: const ValueKey('adjusted-caption'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune_rounded,
                          size: 14, color: AppConstants.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Adjusted by you from EU ${p.euSize}',
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.primary,
                        ),
                      ),
                    ],
                  )
                : Text(
                    'Based on your ${p.sizingFootSide} foot (the larger one)',
                    key: const ValueKey('plain-caption'),
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      color: AppConstants.secondary.withValues(alpha: 0.55),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sizePill(String label, {Key? key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: AppConstants.stadiumRadius,
      ),
      child: Text(
        label,
        style: AppConstants.monoStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// "Does this feel right?" — half-size stepper, US/UK re-derive live.
  Widget _buildAdjustCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
        border:
            Border.all(color: AppConstants.borderGray.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded,
                  size: 18, color: AppConstants.primary.withValues(alpha: 0.8)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Does this size feel right?',
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (_adjustedEu != null)
                GestureDetector(
                  key: const Key('adjust-reset'),
                  onTap: _resetAdjustment,
                  child: Text(
                    'Reset',
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Nudge it in half sizes — you know your feet best. '
            'US & UK update automatically.',
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.55),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _AdjustButton(
                key: const Key('adjust-minus'),
                icon: Icons.remove_rounded,
                enabled: _canDecrease,
                onTap: () => _adjust(-1),
              ),
              const SizedBox(width: 18),
              Column(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutBack,
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_displayEu),
                      child: Text(
                        _displayEu,
                        key: const Key('adjust-eu'),
                        style: AppConstants.monoStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.secondary,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    'EU',
                    style: AppConstants.bodyStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: AppConstants.secondary.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 18),
              _AdjustButton(
                key: const Key('adjust-plus'),
                icon: Icons.add_rounded,
                enabled: _canIncrease,
                onTap: () => _adjust(1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFootCards() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _FootCard(
            side: 'LEFT',
            lengthComp: p.leftLengthMm,
            widthComp: p.leftWidthMm,
            isSizingFoot: p.sizingFootSide == 'left',
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _FootCard(
            side: 'RIGHT',
            lengthComp: p.rightLengthMm,
            widthComp: p.rightWidthMm,
            isSizingFoot: p.sizingFootSide == 'right',
          ),
        ),
      ],
    );
  }

  /// Confidence: animated ring + percentage + the per-factor breakdown.
  Widget _buildConfidenceCard(int confPct) {
    final level = p.confidenceLevel;
    final color = level == 'high'
        ? AppConstants.success
        : level == 'medium'
            ? AppConstants.statusPendingColor
            : AppConstants.error;
    final levelLabel =
        level.substring(0, 1).toUpperCase() + level.substring(1);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
        border:
            Border.all(color: AppConstants.borderGray.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: p.confidenceScore),
                duration: const Duration(milliseconds: 1300),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => SizedBox(
                  width: 84,
                  height: 84,
                  child: CustomPaint(
                    painter: _ConfidenceRingPainter(
                      progress: value,
                      color: color,
                    ),
                    child: Center(
                      child: Text(
                        '${(value * 100).round()}%',
                        key: const Key('confidence-pct'),
                        style: AppConstants.monoStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.secondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$levelLabel confidence',
                      style: AppConstants.bodyStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${p.leftSampleCount + p.rightSampleCount} clean samples '
                      'across both feet${p.footCondition == 'socks' ? ' · sock thickness compensated' : ''}.',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.secondary.withValues(alpha: 0.55),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (p.confidenceFactors.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(
                height: 1,
                color: AppConstants.borderGray.withValues(alpha: 0.35)),
            const SizedBox(height: 12),
            Text(
              'WHY THIS SCORE',
              style: AppConstants.bodyStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppConstants.secondary.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 10),
            ...p.confidenceFactors.map(_factorRow),
          ],
        ],
      ),
    );
  }

  Widget _factorRow(ConfidenceFactorV2 f) {
    final color =
        f.positive ? AppConstants.success : AppConstants.statusPendingColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            f.positive
                ? Icons.check_circle_rounded
                : Icons.info_outline_rounded,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.title,
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (f.detail != null)
                  Text(
                    f.detail!,
                    style: AppConstants.bodyStyle(
                      fontSize: 11.5,
                      color: AppConstants.secondary.withValues(alpha: 0.55),
                      height: 1.35,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Width-fit gauge: narrow ↔ wide marker positioned by category.
  Widget _buildWidthGauge() {
    final positions = {'narrow': 0.15, 'standard': 0.5, 'wide': 0.85};
    final pos = positions[p.widthCategory] ?? 0.5;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
        border:
            Border.all(color: AppConstants.borderGray.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'WIDTH FIT',
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  color: AppConstants.secondary.withValues(alpha: 0.5),
                ),
              ),
              Text(
                switch (p.widthCategory) {
                  'narrow' => 'Narrow',
                  'wide' => 'Wide',
                  _ => 'Standard',
                },
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, constraints) {
            final w = constraints.maxWidth;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Track.
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      AppConstants.borderGray.withValues(alpha: 0.5),
                      AppConstants.primary.withValues(alpha: 0.35),
                      AppConstants.borderGray.withValues(alpha: 0.5),
                    ]),
                    borderRadius: AppConstants.stadiumRadius,
                  ),
                ),
                Positioned(
                  left: w * pos - 9,
                  top: -5,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border:
                          Border.all(color: AppConstants.accent, width: 3),
                      boxShadow: AppConstants.darkShadow,
                    ),
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Narrow', style: AppConstants.bodyStyle(fontSize: 11)),
              Text('Standard', style: AppConstants.bodyStyle(fontSize: 11)),
              Text('Wide', style: AppConstants.bodyStyle(fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReasonCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.primary.withValues(alpha: 0.05),
        borderRadius: AppConstants.cardRadius,
        border:
            Border.all(color: AppConstants.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline,
              size: 18, color: AppConstants.primary.withValues(alpha: 0.7)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              p.sizeRecommendationReason!,
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.7),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SUPPORTING WIDGETS
// ═══════════════════════════════════════════════════════════════════

/// Staggered entrance: fades + slides each section in, offset by [index].
class _Stagger extends StatelessWidget {
  final AnimationController controller;
  final int index;
  final Widget child;
  final Offset slideFrom;

  const _Stagger({
    required this.controller,
    required this.index,
    required this.child,
    this.slideFrom = const Offset(0, 0.35),
  });

  @override
  Widget build(BuildContext context) {
    final start = (index * 0.09).clamp(0.0, 0.85);
    final anim = CurvedAnimation(
      parent: controller,
      curve: Interval(start, (start + 0.4).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(
            slideFrom.dx * 24 * (1 - anim.value),
            slideFrom.dy * 40 * (1 - anim.value),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Round − / + stepper button for the size adjustment.
class _AdjustButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _AdjustButton({
    super.key,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled
          ? AppConstants.accent.withValues(alpha: 0.14)
          : AppConstants.borderGray.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            icon,
            size: 22,
            color: enabled ? AppConstants.secondary : AppConstants.borderGray,
          ),
        ),
      ),
    );
  }
}

/// L/R measurement card with count-up cm values.
class _FootCard extends StatelessWidget {
  final String side;
  final double? lengthComp;
  final double? widthComp;
  final bool isSizingFoot;

  const _FootCard({
    required this.side,
    required this.lengthComp,
    required this.widthComp,
    required this.isSizingFoot,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
        border: Border.all(
          color: isSizingFoot ? AppConstants.accent : AppConstants.borderGray,
          width: isSizingFoot ? 2 : 1,
        ),
        boxShadow: isSizingFoot
            ? [
                BoxShadow(
                  color: AppConstants.accent.withValues(alpha: 0.12),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                side,
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: AppConstants.secondary.withValues(alpha: 0.55),
                ),
              ),
              if (isSizingFoot) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppConstants.accent.withValues(alpha: 0.15),
                    borderRadius: AppConstants.stadiumRadius,
                  ),
                  child: Text(
                    'SIZING',
                    style: AppConstants.bodyStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (lengthComp != null)
            _CountUpText(
              end: lengthComp! / 10,
              decimals: 1,
              suffix: ' cm',
              key: Key('foot-length-$side'),
              style: AppConstants.monoStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            )
          else
            Text(
              '—',
              style: AppConstants.monoStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
          Text(
            lengthComp != null ? 'length (${lengthComp!.round()} mm)' : 'length',
            style: AppConstants.bodyStyle(
              fontSize: 11,
              color: AppConstants.secondary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widthComp != null
                ? 'width ${(widthComp! / 10).toStringAsFixed(1)} cm'
                : 'width —',
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

/// Counts a number up from zero on first build; re-animates when [end] changes.
class _CountUpText extends StatelessWidget {
  final double end;
  final int decimals;
  final String suffix;
  final TextStyle style;

  const _CountUpText({
    super.key,
    required this.end,
    required this.decimals,
    required this.suffix,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: end),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => Text(
        '${value.toStringAsFixed(decimals)}$suffix',
        style: style,
      ),
    );
  }
}

/// Circular gauge: track ring + rounded sweep arc with a soft glow.
class _ConfidenceRingPainter extends CustomPainter {
  final double progress; // 0.0–1.0
  final Color color;

  _ConfidenceRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 7;
    const stroke = 8.0;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Track.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = AppConstants.borderGray.withValues(alpha: 0.25),
    );

    if (progress <= 0) return;

    final sweep = 2 * 3.141592653589793 * progress.clamp(0.0, 1.0);

    // Glow underlay.
    canvas.drawArc(
      rect,
      -3.141592653589793 / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 4
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Main arc.
    canvas.drawArc(
      rect,
      -3.141592653589793 / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_ConfidenceRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
