import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../constants/app_constants.dart';
import 'foot_scan_session_screen_v2.dart';

/// Entry screen for "Get Your Foot Size 2.0" — the clean-rewrite auto scan.
///
/// Modern single-purpose setup flow (deliberately NOT v1's option-wall):
/// - Hero header with a time estimate
/// - Staggered "what to expect" preview of the three beats
/// - Two segmented chip groups (shopping category, foot condition)
/// - One stadium CTA that doubles as camera-permission pre-flight:
///   if permission is missing it becomes "Allow camera access".
///
/// Auto Scan only — Guided Tap / paper modes stay in v1.
class FootScanSetupScreenV2 extends StatefulWidget {
  const FootScanSetupScreenV2({super.key});

  @override
  State<FootScanSetupScreenV2> createState() => _FootScanSetupScreenV2State();
}

class _FootScanSetupScreenV2State extends State<FootScanSetupScreenV2> {
  /// Shopping preference: men's / women's / kids' sizing.
  String _shoeCategory = 'men';

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
        builder: (_) => FootScanSessionScreenV2(
          footCondition: _footCondition,
          shoeCategory: _shoeCategory,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
      body: Stack(
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
                        _buildWhatToExpect(),
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
                      icon: Icon(_cameraGranted
                          ? Icons.view_in_ar_rounded
                          : Icons.photo_camera_outlined),
                      label: Text(
                        _cameraGranted ? 'Start scanning' : 'Allow camera access',
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
      ),
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

  Widget _buildWhatToExpect() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('What to expect'),
        const SizedBox(height: 12),
        _expectRow(
          icon: Icons.crop_free_rounded,
          title: 'Frame your foot',
          description: 'Follow the guide — top view first, then side view.',
          delay: 0,
        ),
        _expectRow(
          icon: Icons.timer_outlined,
          title: 'Hold still for 4 seconds',
          description: 'We sample from many angles and keep only the best readings.',
          delay: 120,
        ),
        _expectRow(
          icon: Icons.check_circle_outline_rounded,
          title: 'Get your size',
          description: 'Both feet measured, converted to your shoe size.',
          delay: 240,
        ),
      ],
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
