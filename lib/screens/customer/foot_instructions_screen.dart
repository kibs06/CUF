import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../widgets/sole_switch.dart';
import 'foot_capture_screen.dart';
import 'foot_manual_measure_screen.dart';

/// Instructions screen for the AR foot sizing feature.
///
/// Explains to the user how to set up for live AR scanning:
/// - Stand on a flat, well-lit, textured floor
/// - Point camera at your foot, move slowly in an arc
/// - ARCore tracks your phone's position in real-world space
///
/// Lets the user choose between:
/// - Live AR scan (ARCore world tracking — no paper needed)
/// - Paper-based scan (uses A4/Letter paper as scale reference)
class FootInstructionsScreen extends StatefulWidget {
  const FootInstructionsScreen({super.key});

  @override
  State<FootInstructionsScreen> createState() => _FootInstructionsScreenState();
}

class _FootInstructionsScreenState extends State<FootInstructionsScreen> {
  String _paperSize = 'a4'; // 'a4' or 'letter'
  String _footCondition = 'bare'; // 'bare' or 'socks'
  bool _useLiveAr = true; // true = live AR scan, false = paper-based

  /// Smart-assist toggle (§6): auto-suggested initial points in the manual AR
  /// flow. On by default; users who prefer full manual control can disable it.
  bool _smartAssistEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Foot Sizing',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppConstants.secondary,
          ),
        ),
        backgroundColor: AppConstants.surfaceLight,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppConstants.secondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header illustration ──
                _buildHeader(),
                const SizedBox(height: 28),

                // ── Step-by-step instructions ──
                _buildSectionTitle(_useLiveAr ? 'How Live AR Works' : 'How Paper Scan Works'),
                const SizedBox(height: 12),
                if (_useLiveAr) ...[
                  _buildStep(
                    number: 1,
                    icon: Icons.view_in_ar,
                    title: 'Stand on a flat floor',
                    description: 'Find a well-lit area with a textured floor (not glossy white tile). Point your camera at your feet.',
                  ),
                  _buildStep(
                    number: 2,
                    icon: Icons.touch_app_outlined,
                    title: 'Tap the widest points',
                    description: 'Front view: tap the widest point on each side of your foot. Like using a tape measure — but in AR.',
                  ),
                  _buildStep(
                    number: 3,
                    icon: Icons.open_with,
                    title: 'Tap heel and toe',
                    description: 'Side view: tap your heel, then the tip of your longest toe. Drag any point to fine-tune it.',
                  ),
                  _buildStep(
                    number: 4,
                    icon: Icons.check_circle_outline,
                    title: 'Both feet measured',
                    description: 'We measure left and right foot separately — feet can differ in size!',
                  ),
                ] else ...[
                  _buildStep(
                    number: 1,
                    icon: Icons.description_outlined,
                    title: 'Place paper on the floor',
                    description: 'Put a full sheet of paper on a flat surface, pushed against a wall.',
                  ),
                  _buildStep(
                    number: 2,
                    icon: Icons.directions_walk_outlined,
                    title: 'Stand on the paper',
                    description: 'Stand with your heel against the wall, socks or bare feet. Wear what you normally would when trying shoes.',
                  ),
                  _buildStep(
                    number: 3,
                    icon: Icons.phone_android_outlined,
                    title: 'Hold phone above',
                    description: 'Hold your phone directly above your foot, about 1 meter high. The camera will guide you.',
                  ),
                  _buildStep(
                    number: 4,
                    icon: Icons.camera_alt_outlined,
                    title: 'Capture both feet',
                    description: 'We\'ll scan your left foot, then your right foot separately — feet can differ in size!',
                  ),
                ],
                const SizedBox(height: 24),

                // ── Scan Mode Selection ──
                _buildSectionTitle('Scan Mode'),
                const SizedBox(height: 4),
                Text(
                  'Choose how you want to measure your feet.',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildScanModeOption(
                        key: true,
                        icon: Icons.view_in_ar,
                        label: 'Live AR Scan',
                        description: 'No paper needed — uses ARCore world tracking',
                        isSelected: _useLiveAr,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildScanModeOption(
                        key: false,
                        icon: Icons.description_outlined,
                        label: 'Paper Scan',
                        description: 'Uses A4/Letter paper as scale reference',
                        isSelected: !_useLiveAr,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── Paper Size Selection (only for paper mode) ──
                if (!_useLiveAr) ...[
                  _buildSectionTitle('Paper Size'),
                  const SizedBox(height: 4),
                  Text(
                    'Select the type of paper you\'re using — this is the scale reference for measurement.',
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: AppConstants.secondary.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildPaperOption(
                          key: 'a4',
                          label: 'A4',
                          dimensions: '210 × 297 mm',
                          isSelected: _paperSize == 'a4',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildPaperOption(
                          key: 'letter',
                          label: 'US Letter',
                          dimensions: '215.9 × 279.4 mm',
                          isSelected: _paperSize == 'letter',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                ],
                const SizedBox(height: 28),

                // ── Foot Condition Selection ──
                _buildSectionTitle('Foot Condition'),
                const SizedBox(height: 4),
                Text(
                  'Sock thickness affects measurements. Choose what you\'ll wear most often.',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildConditionOption(
                        key: 'bare',
                        icon: Icons.directions_walk_outlined,
                        label: 'Bare feet',
                        isSelected: _footCondition == 'bare',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildConditionOption(
                        key: 'socks',
                        icon: Icons.checkroom_outlined,
                        label: 'With socks',
                        isSelected: _footCondition == 'socks',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // ── Smart Assist Toggle (Live AR mode only) ──
                if (_useLiveAr) ...[
                  _buildSectionTitle('Smart Assist'),
                  const SizedBox(height: 12),
                  _buildSmartAssistToggle(),
                ],
                const SizedBox(height: 32),

                // ── Disclaimer ──
                _buildDisclaimer(),
                const SizedBox(height: 24),
              ],
            ),
          ),

          // ── CTA Button (pinned bottom) ──
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () {
                  if (_useLiveAr) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FootManualMeasureScreen(
                          footCondition: _footCondition,
                          smartAssistEnabled: _smartAssistEnabled,
                        ),
                      ),
                    );
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FootCaptureScreen(
                          paperSize: _paperSize,
                          footCondition: _footCondition,
                        ),
                      ),
                    );
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppConstants.accent,
                  foregroundColor: AppConstants.secondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppConstants.buttonRadius,
                  ),
                ),
                child: Text(
                  'Got it, start scanning',
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
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppConstants.accent.withValues(alpha: 0.08),
        borderRadius: AppConstants.cardRadius,
        border: Border.all(
          color: AppConstants.accent.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.straighten_outlined,
            size: 48,
            color: AppConstants.accent,
          ),
          const SizedBox(height: 12),
          Text(
            'Find Your Perfect Size',
            style: AppConstants.headlineStyle(
              fontSize: 20,
              color: AppConstants.secondary,
            ),
          ),
          const SizedBox(height: 8),                Text(
                  'Tap a few points on your foot to measure it — no special hardware needed.',
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(
              fontSize: 14,
              color: AppConstants.secondary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
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

  Widget _buildStep({
    required int number,
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppConstants.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                '$number',
                style: AppConstants.bodyStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.primary,
                ),
              ),
            ),
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
                const SizedBox(height: 4),
                Text(
                  description,
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
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

  Widget _buildPaperOption({
    required String key,
    required String label,
    required String dimensions,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => setState(() => _paperSize = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppConstants.accent.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppConstants.accent : AppConstants.borderGray.withValues(alpha: 0.5),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.description_outlined,
              color: isSelected ? AppConstants.accent : AppConstants.secondary.withValues(alpha: 0.4),
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isSelected ? AppConstants.accent : AppConstants.secondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              dimensions,
              style: AppConstants.bodyStyle(
                fontSize: 11,
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionOption({
    required String key,
    required IconData icon,
    required String label,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => setState(() => _footCondition = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppConstants.accent.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppConstants.accent : AppConstants.borderGray.withValues(alpha: 0.5),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? AppConstants.accent : AppConstants.secondary.withValues(alpha: 0.4),
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isSelected ? AppConstants.accent : AppConstants.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanModeOption({
    required bool key,
    required IconData icon,
    required String label,
    required String description,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => setState(() => _useLiveAr = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppConstants.accent.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppConstants.accent : AppConstants.borderGray.withValues(alpha: 0.5),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? AppConstants.accent : AppConstants.secondary.withValues(alpha: 0.4),
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isSelected ? AppConstants.accent : AppConstants.secondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                fontSize: 11,
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Smart-assist toggle card (Live AR only): auto-propose initial point
  /// positions from the segmentation detector. Users who prefer full manual
  /// control can turn this off.
  Widget _buildSmartAssistToggle() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.borderGray.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppConstants.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: AppConstants.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smart suggestions',
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.secondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'The app suggests where to place each point — you can still drag to adjust. Turn off for fully manual placement.',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary.withValues(alpha: 0.55),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SoleSwitch(
            value: _smartAssistEnabled,
            onChanged: (v) => setState(() => _smartAssistEnabled = v),
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
              'This scan produces a recommended size based on your foot measurements. '
              'Fit also depends on shoe brand and last shape. For best results, '
              'compare against a shoe you already own that fits well.',
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
}
