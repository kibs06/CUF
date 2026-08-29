import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_constants.dart';
import '../models/update_info.dart';

/// A full-screen overlay that appears when a newer app version is available.
///
/// Shows a premium modal card with version info, release notes, and a
/// download button. Designed to feel like a first-class product moment —
/// not a nag screen.
///
/// Usage: call [UpdateOverlay.show] from any context that has access to
/// the root [NavigatorState]. The overlay dismisses itself on download
/// or "Maybe Later".
class UpdateOverlay {
  UpdateOverlay._();

  /// Shows the update overlay. Returns a [Future] that completes when
  /// the overlay is dismissed (download tapped or "Later" tapped).
  static Future<void> show(
    BuildContext context, {
    required UpdateInfo update,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Update available',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 400),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, _) => _UpdateOverlayDialog(update: update),
    );
  }
}

class _UpdateOverlayDialog extends StatefulWidget {
  const _UpdateOverlayDialog({required this.update});

  final UpdateInfo update;

  @override
  State<_UpdateOverlayDialog> createState() => _UpdateOverlayDialogState();
}

class _UpdateOverlayDialogState extends State<_UpdateOverlayDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
    _shimmerAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final update = widget.update;
    final isAndroid = !Platform.isIOS;
    final screenSize = MediaQuery.of(context).size;

    return PopScope(
      canPop: true,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 400,
            maxHeight: screenSize.height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppConstants.surfaceLight,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppConstants.primary.withValues(alpha: 0.2),
                      blurRadius: 40,
                      offset: const Offset(0, 20),
                      spreadRadius: -4,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildHeader(update),
                        _buildVersionBadge(update),
                        if (update.notes.isNotEmpty) _buildReleaseNotes(update),
                        _buildActions(update, isAndroid),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(UpdateInfo update) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppConstants.primary, Color(0xFF6B4423)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          // App icon with glow
          AnimatedBuilder(
            animation: _shimmerAnimation,
            builder: (context, child) {
              return Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.15),
                  boxShadow: [
                    BoxShadow(
                      color: AppConstants.accent.withValues(
                        alpha: 0.2 + (_shimmerAnimation.value * 0.15),
                      ),
                      blurRadius: 20 + (_shimmerAnimation.value * 8),
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: const Icon(
              Icons.directions_run_rounded,
              size: 36,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'New Update Available',
            style: AppConstants.headlineStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: const Color(0xFFF5EDE4),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Version ${update.version}',
            style: AppConstants.monoStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppConstants.accent,
            ),
          ),
          if (update.releasedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Released ${_formatDate(update.releasedAt!)}',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: const Color(0xFFF5EDE4).withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVersionBadge(UpdateInfo update) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        children: [
          // "What's new" label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppConstants.accent.withValues(alpha: 0.12),
              borderRadius: AppConstants.stadiumRadius,
            ),
            child: Text(
              "What's New",
              style: AppConstants.bodyStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppConstants.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReleaseNotes(UpdateInfo update) {
    // Filter out redundant version number lines and category headers
    final notes = update.notes.where((note) {
      final trimmed = note.trim();
      if (trimmed.isEmpty) return false;
      // Skip lines that are just the version number (e.g. "v1.0.15")
      if (RegExp(r'^v?\d+\.\d+\.\d+$').hasMatch(trimmed)) return false;
      // Skip category headers like "Fixed:", "New:", "Changed:"
      if (RegExp(r'^(Fixed|New|Changed|Added|Removed|Improved):?\s*$')
          .hasMatch(trimmed)) {
        return false;
      }
      return true;
    }).toList();

    if (notes.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Column(
        children: notes.map((note) {
          final isHeader = note.endsWith(':');
          final isBullet = note.startsWith('- ') || note.startsWith('• ');
          final text = isBullet ? note.substring(2).trim() : note.trim();

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isBullet) ...[
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(top: 7, right: 10),
                    decoration: const BoxDecoration(
                      color: AppConstants.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ] else ...[
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(top: 7, right: 10),
                    decoration: BoxDecoration(
                      color: AppConstants.primary.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
                Expanded(
                  child: Text(
                    text,
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      fontWeight:
                          isHeader ? FontWeight.w600 : FontWeight.normal,
                      color: AppConstants.secondary.withValues(
                        alpha: isHeader ? 0.9 : 0.75,
                      ),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActions(UpdateInfo update, bool isAndroid) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        children: [
          // Download / Update button
          if (isAndroid)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () => _downloadApk(update.apkUrl),
                style: FilledButton.styleFrom(
                  backgroundColor: AppConstants.accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppConstants.buttonRadius,
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.download_rounded,
                      size: 20,
                      color: AppConstants.secondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Update Now',
                      style: AppConstants.headlineStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppConstants.primary.withValues(alpha: 0.08),
                borderRadius: AppConstants.buttonRadius,
              ),
              child: Text(
                'Open the App Store to update',
                textAlign: TextAlign.center,
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppConstants.primary,
                ),
              ),
            ),
          const SizedBox(height: 10),
          // Maybe Later button
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            child: Text(
              'Maybe Later',
              style: AppConstants.bodyStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadApk(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (launched) {
      Navigator.of(context).pop();
    }
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
