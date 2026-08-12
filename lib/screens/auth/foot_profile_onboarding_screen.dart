import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../utils/customer_profile_fields.dart';
import '../../widgets/auth/signup_scaffold.dart';
import '../../widgets/sole_primary_button.dart';
import '../customer/foot_instructions_screen.dart';

/// The post-signup foot-profile onboarding step — shown ONCE, immediately
/// after a successful customer sign-up and before the user lands in
/// `CustomerShell`. It is never a hard gate: all three paths lead to the
/// shell, and account creation already succeeded before this screen exists.
///
/// Three paths, deliberately unequal in visual weight:
///  1. **Primary — Scan your feet with AR** (accent-filled card, larger,
///     "RECOMMENDED" badge). Launches the existing AR scan flow
///     (`FootInstructionsScreen`); on completion the results screen saves
///     the full measurement to `foot_measurements` AND stamps the profile
///     snapshot with `foot_profile_source = 'ar_scan'`.
///  2. **Secondary — Enter size manually** (outline card, inline pickers).
///     A lightweight EU size + width picker; persists
///     `foot_profile_source = 'manual'`.
///  3. **Tertiary — Skip for now** (plain text). Persists
///     `foot_profile_source = 'skipped'` (best-effort — never blocks) so
///     the reminder banner elsewhere in the app knows to invite them back.
///
/// Scan failure / permission denial never dead-ends the user: the scan flow
/// is pushed ON TOP of this screen, so backing out lands exactly here, with
/// the manual option in plain sight.
///
/// The persistence and navigation hooks are overridable for widget tests;
/// production callers use the defaults.
class FootProfileOnboardingScreen extends StatefulWidget {
  /// Overrides the AR-scan launch (default: push [FootInstructionsScreen]).
  final VoidCallback? onLaunchScan;

  /// Overrides persistence (default: `AuthProvider.saveFootProfile`).
  final Future<bool> Function({
    double? sizeEu,
    String? widthLabel,
    required String source,
  })? onPersist;

  /// Overrides the completion navigation (default: pop to the first route,
  /// where AuthGate has already swapped in `CustomerShell`).
  final VoidCallback? onFinished;

  const FootProfileOnboardingScreen({
    super.key,
    this.onLaunchScan,
    this.onPersist,
    this.onFinished,
  });

  @override
  State<FootProfileOnboardingScreen> createState() =>
      _FootProfileOnboardingScreenState();
}

class _FootProfileOnboardingScreenState
    extends State<FootProfileOnboardingScreen> {
  // Manual-entry state.
  String? _selectedEuSize;
  String _selectedWidth = 'Regular';
  bool _isSaving = false;
  String? _saveError;

  Future<bool> _persist({
    double? sizeEu,
    String? widthLabel,
    required String source,
  }) {
    final custom = widget.onPersist;
    if (custom != null) {
      return custom(sizeEu: sizeEu, widthLabel: widthLabel, source: source);
    }
    return context
        .read<AuthProvider>()
        .saveFootProfile(sizeEu: sizeEu, widthLabel: widthLabel, source: source);
  }

  void _finish() {
    if (widget.onFinished != null) {
      widget.onFinished!();
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _launchArScan() {
    if (widget.onLaunchScan != null) {
      widget.onLaunchScan!();
      return;
    }
    // Pushed ON TOP of this screen, so an abandoned/denied scan lands back
    // here with the manual option visible — never a dead end.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FootInstructionsScreen()),
    );
  }

  Future<void> _saveManual() async {
    if (_selectedEuSize == null) {
      setState(() => _saveError = 'Please pick your shoe size first.');
      return;
    }
    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    final ok = await _persist(
      sizeEu: double.tryParse(_selectedEuSize!),
      widthLabel: _selectedWidth,
      source: AppConstants.footProfileManual,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (ok) {
      final messenger = ScaffoldMessenger.of(context);
      _finish();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Foot size saved to your profile!'),
          backgroundColor: AppConstants.success,
        ),
      );
    } else {
      setState(() => _saveError = 'Couldn\'t save right now — please try again.');
    }
  }

  void _skip() {
    // Best-effort: persist 'skipped' so the reminder banner knows, but
    // NEVER block account access on this write — fire-and-forget. Awaited,
    // this could stall the user out of the app for the full 15s network
    // timeout on a flaky connection; skipping must always be instant.
    _persist(source: AppConstants.footProfileSkipped).ignore();
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    return SignupScaffold(
      eyebrow: 'ONE LAST THING',
      title: 'Find your perfect fit',
      subtitle:
          'Most people wear the wrong shoe size without realizing it. '
          'A 30-second scan means your SoleVision recommendations are built '
          'on your real foot — not a guess.',
      showBackButton: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildArCard(),
          const SizedBox(height: AuthSpacing.s16),
          _buildManualCard(),
          const SizedBox(height: AuthSpacing.s8),
          _buildSkipButton(),
        ],
      ),
    );
  }

  // ── PRIMARY — AR scan card ──────────────────────────────────────
  // Deliberately the dominant element: filled accent background, larger
  // touch target, a "RECOMMENDED" badge — the goal is to genuinely draw
  // people toward scanning, not present both options as neutral equals.
  Widget _buildArCard() {
    return Material(
      color: AppConstants.accent,
      borderRadius: AppConstants.cardRadius,
      child: InkWell(
        onTap: _launchArScan,
        borderRadius: AppConstants.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(AuthSpacing.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppConstants.secondary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'RECOMMENDED',
                      style: AppConstants.monoStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.surfaceLight,
                        // .copyWith: monoStyle returns a new TextStyle.
                      ).copyWith(letterSpacing: 1.2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AuthSpacing.s16),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppConstants.secondary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.view_in_ar,
                  size: 30,
                  color: AppConstants.secondary,
                ),
              ),
              const SizedBox(height: AuthSpacing.s16),
              Text(
                'Scan your feet with AR',
                style: AppConstants.headlineStyle(
                  fontSize: 22,
                  color: AppConstants.secondary,
                ),
              ),
              const SizedBox(height: AuthSpacing.s8),
              Text(
                'Point your camera at your feet, tap a few points, and get '
                'your real size in under a minute — the same tool professionals '
                'use to fit you properly.',
                style: AppConstants.bodyStyle(
                  fontSize: 14,
                  color: AppConstants.secondary.withValues(alpha: 0.85),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AuthSpacing.s20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: _launchArScan,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Start scan'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppConstants.surfaceLight,
                    foregroundColor: AppConstants.secondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppConstants.buttonRadius,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── SECONDARY — manual entry card ───────────────────────────────
  // Outline style, lighter visual weight than the AR card.
  Widget _buildManualCard() {
    return Container(
      padding: const EdgeInsets.all(AuthSpacing.s20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.cardRadius,
        border: Border.all(
          color: AppConstants.borderGray.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.straighten_outlined,
                size: 20,
                color: AppConstants.primary,
              ),
              const SizedBox(width: AuthSpacing.s12),
              Text(
                'Enter your size manually',
                style: AppConstants.bodyStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AuthSpacing.s4),
          Text(
            'If you already know your shoe size, just tell us.',
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AuthSpacing.s16),
          Text(
            'EU SIZE',
            style: AppConstants.bodyStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppConstants.secondary.withValues(alpha: 0.5),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AuthSpacing.s8),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: customerEuSizes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final size = customerEuSizes[index];
                final isSelected = _selectedEuSize == size;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedEuSize = size;
                    _saveError = null;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? AppConstants.primary : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppConstants.primary
                            : AppConstants.borderGray.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      size,
                      style: AppConstants.monoStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color:
                            isSelected ? Colors.white : AppConstants.secondary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AuthSpacing.s16),
          Text(
            'WIDTH',
            style: AppConstants.bodyStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppConstants.secondary.withValues(alpha: 0.5),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AuthSpacing.s8),
          Row(
            children: customerFootWidths.map((width) {
              final isSelected = _selectedWidth == width;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: width == customerFootWidths.last ? 0 : 8,
                  ),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedWidth = width),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color:
                            isSelected ? AppConstants.primary : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? AppConstants.primary
                              : AppConstants.borderGray.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        width,
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? Colors.white
                              : AppConstants.secondary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (_saveError != null) ...[
            const SizedBox(height: AuthSpacing.s12),
            Text(
              _saveError!,
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.error,
              ),
            ),
          ],
          const SizedBox(height: AuthSpacing.s16),
          SolePrimaryButton(
            label: 'Save my size',
            backgroundColor: AppConstants.secondary,
            isLoading: _isSaving,
            onPressed: _isSaving ? null : _saveManual,
          ),
        ],
      ),
    );
  }

  // ── TERTIARY — skip ─────────────────────────────────────────────
  // Least visual weight of the three; skipping must never block access.
  Widget _buildSkipButton() {
    return TextButton(
      onPressed: _isSaving ? null : _skip,
      child: Text(
        'Skip for now — I\'ll do this later',
        style: AppConstants.bodyStyle(
          fontSize: 14,
          color: AppConstants.secondary.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
