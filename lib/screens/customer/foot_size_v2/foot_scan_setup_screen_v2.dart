import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../constants/app_constants.dart';
import '../foot_capture_screen.dart';
import '../foot_manual_measure_screen.dart';

/// Entry screen for "Get Your Foot Size 2.0" — the clean-rewrite flow.
///
/// Modern single-purpose setup flow (deliberately NOT v1's option-wall):
/// - Hero header with a time estimate
/// - Staggered "what to expect" preview of the beats
/// - Two segmented chip groups (shopping category, foot condition)
/// - One stadium CTA that doubles as camera-permission pre-flight:
///   if permission is missing it becomes "Allow camera access".
///
/// Card scan and tap — the AR camera scan was removed (inaccurate).
/// Both remaining modes measure both feet themselves.
class FootScanSetupScreenV2 extends StatefulWidget {
  /// When true, renders only the setup CONTENT — no Scaffold, no AppBar — so
  /// the screen can be embedded as a panel (see `SizeYourFootScreen`, whose
  /// landing panel this is). The parent then owns the chrome and the
  /// swipeable panels; the setup flow itself is unchanged.
  final bool embedded;

  const FootScanSetupScreenV2({super.key, this.embedded = false});

  @override
  State<FootScanSetupScreenV2> createState() => _FootScanSetupScreenV2State();
}

class _FootScanSetupScreenV2State extends State<FootScanSetupScreenV2> {
  /// Shopping preference: men's / women's / kids' sizing.
  String _shoeCategory = 'men';

  /// 'card' (card-referenced capture — camera only) or
  /// 'tap' (place the points by hand).
  String _measureMode = 'card';

  /// 'bare' or 'socks' — sock thickness affects compensation.
  String _footCondition = 'bare';

  /// Whether camera permission is already granted (drives CTA label).
  bool _cameraGranted = false;

  @override
  void initState() {
    super.initState();
    Permission.camera.status.then((status) {
      if (mounted) setState(() => _cameraGranted = status.isGranted);
    });
  }

  IconData get _ctaIcon {
    if (_measureMode == 'tap' && _cameraGranted) {
      return Icons.touch_app_rounded;
    }
    return _cameraGranted
        ? Icons.credit_card_outlined
        : Icons.photo_camera_outlined;
  }

  String get _ctaLabel {
    if (!_cameraGranted) return 'Allow camera access';
    return _measureMode == 'tap' ? 'Start tapping' : 'Start card scan';
  }

  Future<void> _onCtaPressed() async {
    if (!_cameraGranted) {
      final status = await Permission.camera.request();
      if (!mounted) return;
      setState(() => _cameraGranted = status.isGranted);
      if (!status.isGranted) {
        // Permanently denied → send to system settings; otherwise stay put
        // (the CTA will re-read on next tap).
        if (status.isPermanentlyDenied && mounted) {
          await openAppSettings();
        }
        return;
      }
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _measureMode == 'tap'
            ? FootManualMeasureScreen(
                footCondition: _footCondition,
                shoeCategory: _shoeCategory,
              )
            : FootCaptureScreen(
                paperSize: 'card',
                footCondition: _footCondition,
                shoeCategory: _shoeCategory,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHero(),
                        const SizedBox(height: 28),
                        _buildMeasureModeSection(),
                        const SizedBox(height: 28),
                        _measureMode == 'card'
                            ? _buildCardExpect()
                            : _buildTapExpect(),
                        const SizedBox(height: 28),
                        _buildChipSection(
                          title: 'Shopping size',
                          subtitle: 'Which sizing system are you shopping in?',
                          options: const [
                            ('men', "Men's"),
                            ('women', "Women's"),
                            ('kids', "Kids'"),
                          ],
                          selected: _shoeCategory,
                          onSelect: (v) => setState(() => _shoeCategory = v),
                        ),
                        const SizedBox(height: 24),
                        _buildChipSection(
                          title: 'Foot condition',
                          subtitle: 'Sock thickness affects measurements.',
                          options: const [
                            ('bare', 'Bare feet'),
                            ('socks', 'With socks'),
                          ],
                          selected: _footCondition,
                          onSelect: (v) => setState(() => _footCondition = v),
                        ),
                        const SizedBox(height: 16),
                        _buildDisclaimer(),
                      ],
                    ),
                  ),
                ),

                // ── Pinned stadium CTA ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _onCtaPressed,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppConstants.accent,
                        foregroundColor: AppConstants.secondary,
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppConstants.stadiumRadius,
                        ),
                      ),
                      icon: Icon(_ctaIcon),
                      label: Text(
                        _ctaLabel,
                        style: AppConstants.bodyStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.secondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
    );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        backgroundColor: AppConstants.surfaceLight,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Foot Size 2.0',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppConstants.secondary,
          ),
        ),
        centerTitle: true,
      ),
      body: body,
    );
  }

  /// Chooses how the foot is measured: card-referenced camera capture, or
  /// the customer taps the points themselves.
  Widget _buildMeasureModeSection() {
    return _buildChipSection(
      title: 'How to measure',
      subtitle: 'Card uses a bank card as a scale reference. Tap lets you '
          'place the points yourself.',
      options: const [
        ('card', 'Card scan'),
        ('tap', 'Tap to measure'),
      ],
      selected: _measureMode,
      onSelect: (v) => setState(() => _measureMode = v),
    );
  }

  /// What the tap flow asks of the customer, in place of the scan steps.
  Widget _buildTapExpect() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('What to expect'),
        const SizedBox(height: 12),
        _expectRow(
          icon: Icons.touch_app_rounded,
          title: 'Tap the widest points',
          description:
              'Tap the inside and then the outside of your foot at its widest point.',
          delay: 0,
        ),
        _expectRow(
          icon: Icons.straighten_rounded,
          title: 'Tap heel and toe',
          description: 'Then tap your heel and the tip of your longest toe.',
          delay: 80,
        ),
        _expectRow(
          icon: Icons.compare_arrows_rounded,
          title: 'Both feet',
          description: 'The guide walks you through each foot in turn.',
          delay: 160,
        ),
      ],
    );
  }

  /// What the card flow asks of the customer, in place of the scan steps.
  Widget _buildCardExpect() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('What to expect'),
        const SizedBox(height: 12),
        _expectRow(
          icon: Icons.credit_card_outlined,
          title: 'Place a card flat beside your foot',
          description:
              'Any bank card works — fully visible, same surface as your foot.',
          delay: 0,
        ),
        _expectRow(
          icon: Icons.timer_outlined,
          title: 'Hold still for a second',
          description:
              'Keep the card in frame; the burst captures automatically.',
          delay: 80,
        ),
        _expectRow(
          icon: Icons.compare_arrows_rounded,
          title: 'Both feet',
          description:
              'Left foot first, then right — the larger foot sizes you.',
          delay: 160,
        ),
      ],
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppConstants.accent.withValues(alpha: 0.14),
            AppConstants.primary.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: AppConstants.premiumCardRadius,
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.straighten_rounded,
              size: 32,
              color: AppConstants.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Get your foot size',
            style: AppConstants.headlineStyle(
              fontSize: 24,
              color: AppConstants.secondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Point your camera at your feet — we do the rest.\nAbout 90 seconds.',
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(
              fontSize: 14,
              color: AppConstants.secondary.withValues(alpha: 0.65),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _expectRow({
    required IconData icon,
    required String title,
    required String description,
    required int delay,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 450 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - t)),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppConstants.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppConstants.accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppConstants.bodyStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.secondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: AppConstants.secondary.withValues(alpha: 0.6),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChipSection({
    required String title,
    required String subtitle,
    required List<(String, String)> options,
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(title),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: AppConstants.bodyStyle(
            fontSize: 13,
            color: AppConstants.secondary.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: _chip(options[i], selected == options[i].$1, onSelect)),
            ],
          ],
        ),
      ],
    );
  }

  Widget _chip(
    (String, String) option,
    bool isSelected,
    ValueChanged<String> onSelect,
  ) {
    final (value, label) = option;
    return GestureDetector(
      onTap: () => onSelect(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? AppConstants.accent : Colors.white,
          borderRadius: AppConstants.stadiumRadius,
          border: Border.all(
            color: isSelected ? AppConstants.accent : AppConstants.borderGray,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: AppConstants.bodyStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color:
                isSelected ? AppConstants.secondary : AppConstants.secondary.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: AppConstants.bodyStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppConstants.secondary.withValues(alpha: 0.5),
          letterSpacing: 0.8,
        ),
      );

  Widget _buildDisclaimer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: AppConstants.buttonRadius,
        border: Border.all(color: AppConstants.borderGray.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 18, color: AppConstants.secondary.withValues(alpha: 0.5)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Stand on a flat, well-lit floor with visible texture '
              '(not glossy tile). Fit also depends on brand and last shape.',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.55),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
