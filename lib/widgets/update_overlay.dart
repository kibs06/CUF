import 'dart:io';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/update_info.dart';
import '../services/apk_installer_service.dart';
import '../utils/in_app_update_eligibility.dart';
import 'update_restart_prompt.dart';

/// A full-screen overlay that appears when a newer app version is available.
///
/// Shows a premium modal card with version info, release notes, and a
/// download button. Designed to feel like a first-class product moment —
/// not a nag screen.
///
/// Usage: call [UpdateOverlay.show] from any context that has access to
/// the root [NavigatorState]. The overlay dismisses itself on "Maybe
/// Later" — an in-flight download keeps running in the background (see
/// [ApkInstallerService]) and is announced from the notification shade.
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

  /// Starts the in-app download outside the build pass: the service is a
  /// singleton, so the download survives this dialog being dismissed.
  /// Failures surface as the service's error state (with a Retry button),
  /// never as a browser handoff.
  Future<void> _startInAppDownload(UpdateInfo update) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Skipped by the service when this version's APK already sits on
      // disk — the second call short-circuits to the Install tap.
      final existing = await _existingCompletedApk(update.version);
      if (existing == null) {
        await ApkInstallerService.instance.downloadApk(
          update.apkUrl,
          update.version,
        );
      }
      if (!mounted) return;
      final path = ApkInstallerService.instance.state?.filePath ?? existing;
      if (path == null) return;
      final message = await ApkInstallerService.instance.installApk(path);
      if (!mounted) return;
      if (message.isEmpty) {
        // The system installer is now in front: offer the restart choice
        // for when the user comes back.
        await showUpdateRestartPrompt(context, version: update.version);
      } else {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } on DownloadIncompleteException catch (e) {
      // The .part file is still on disk — tapping Update Now resumes it
      // instead of restarting the whole ~220 MB.
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Download stopped early (${e.receivedBytes ~/ (1024 * 1024)} of '
            '${e.expectedBytes ~/ (1024 * 1024)} MB) — tap Update Now to resume.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Download failed — check your connection and retry.'),
        ),
      );
    }
  }

  /// Null unless this version's APK already finished downloading earlier
  /// (this session or a previous one — the service checks the file on disk).
  Future<String?> _existingCompletedApk(String version) {
    final state = ApkInstallerService.instance.state;
    if (state?.phase == ApkDownloadPhase.done && state?.filePath != null) {
      return Future.value(state!.filePath);
    }
    return ApkInstallerService.instance.existingCompletedApk(version);
  }

  Widget _buildActions(UpdateInfo update, bool isAndroid) {
    // The only reason that can apply here is a development build:
    // `UpdateProvider.shouldShowUpdateOverlay` already withholds this overlay
    // on emulators, so there is no emulator to report.
    final blocker = inAppUpdateBlocker(isEmulator: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        children: [
          // Download / Update button — or, when no download this app could
          // hand over would install, the reason instead of a dead end.
          if (!isAndroid)
            const _PassiveNote('Open the App Store to update')
          else if (blocker != null)
            // Deliberately no button AND no browser link: both fetch the same
            // signed APK, and neither can be installed over this copy.
            _PassiveNote(inAppUpdateBlockerMessage(blocker))
          else
            AnimatedBuilder(
              animation: ApkInstallerService.instance,
              builder: (context, _) {
                final state = ApkInstallerService.instance.state;
                final downloading =
                    state?.phase == ApkDownloadPhase.downloading;
                final done = state?.phase == ApkDownloadPhase.done;
                final failed = state?.phase == ApkDownloadPhase.error;

                if (downloading && state != null) {
                  return _DownloadProgressSection(
                    state: state,
                    onCancel: () => ApkInstallerService.instance
                        .cancelDownload(),
                  );
                }
                return Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: () => _startInAppDownload(update),
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
                            Icon(
                              done
                                  ? Icons.install_mobile_rounded
                                  : Icons.download_rounded,
                              size: 20,
                              color: AppConstants.secondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              done ? 'Install Update' : 'Update Now',
                              style: AppConstants.headlineStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppConstants.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (failed && state?.message != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        state!.message!,
                        textAlign: TextAlign.center,
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          color: AppConstants.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Downloads inside the app — you can leave this screen, '
                      'it continues in the background.',
                      textAlign: TextAlign.center,
                      style: AppConstants.bodyStyle(
                        fontSize: 11,
                        color: AppConstants.secondary.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                );
              },
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

  static String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

/// Live progress (percent + MB) with a Cancel action while the APK streams.
/// Dismissing the dialog does not stop the download — the shade
/// notification keeps reporting it.
class _DownloadProgressSection extends StatelessWidget {
  const _DownloadProgressSection({required this.state, required this.onCancel});

  final ApkDownloadState state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final pct = (state.progress * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: state.progress,
            minHeight: 10,
            backgroundColor: AppConstants.secondary.withValues(alpha: 0.12),
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppConstants.accent),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                state.totalMb > 0
                    ? 'Downloading — $pct% (${state.receivedMb}/${state.totalMb} MB)'
                    : 'Downloading…',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary.withValues(alpha: 0.7),
                ),
              ),
            ),
            TextButton(
              onPressed: onCancel,
              child: Text(
                'Cancel',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: AppConstants.secondary.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A passive stand-in for the primary action: the same shape and placement as
/// the button it replaces, so the card does not jump, but nothing tappable.
///
/// Both of its cases are "there is no download this app is allowed to offer":
/// iOS installs from the App Store, and a development build is signed with a key
/// no release APK carries. Its text is the whole message, so it wraps.
class _PassiveNote extends StatelessWidget {
  const _PassiveNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppConstants.primary.withValues(alpha: 0.08),
        borderRadius: AppConstants.buttonRadius,
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: AppConstants.bodyStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          height: 1.4,
          color: AppConstants.primary,
        ),
      ),
    );
  }
}
