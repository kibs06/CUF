import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_constants.dart';
import '../../models/update_info.dart';
import '../../providers/update_provider.dart';
import '../../services/apk_installer_service.dart';
import '../../services/update_checker.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/error_retry_widget.dart';
import '../../widgets/release_note_card.dart';
import '../../widgets/shimmer_box.dart';
import '../../widgets/sole_badge.dart';
import '../../widgets/sole_primary_button.dart';

/// "What's New" — shows the current installed version, a prominent update
/// banner if a newer release exists, and a reverse-chronological changelog.
///
/// The primary Download action streams the APK inside the app (progress +
/// resume) and hands it to Android's system installer; the original browser
/// download remains available as a secondary link.
///
/// Pushed from the Profile → Settings card via `MaterialPageRoute`, matching
/// the app's other settings sub-screens (FAQ, Help & Support, etc.).
class WhatsNewScreen extends StatefulWidget {
  const WhatsNewScreen({super.key});

  @override
  State<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends State<WhatsNewScreen> {
  final UpdateCheckerService _service = UpdateCheckerService.instance;
  final ApkInstallerService _installer = ApkInstallerService.instance;

  late Future<List<UpdateInfo>> _changelogFuture;
  bool _hasChecked = false;

  @override
  void initState() {
    super.initState();
    // The update banner reads from [UpdateProvider] (single source of truth,
    // already fetched at startup) — only the changelog is fetched here.
    _changelogFuture = _service.fetchChangelog();
    _hasChecked = true;
  }

  Future<void> _reload() async {
    // Re-run the provider check (refresh banner) and force-refetch the
    // changelog (bypass the local cache). Awaiting the check keeps the
    // pull-to-refresh spinner in sync.
    await context.read<UpdateProvider>().checkForUpdate();
    if (!mounted) return;
    setState(() {
      _changelogFuture = _service.fetchChangelog(forceRefresh: true);
      _hasChecked = true;
    });
  }

  /// Fallback path: opens the APK URL in an external browser/app so Android's
  /// download-and-install flow takes over. Kept alongside the in-app updater
  /// for users whose device/CDN combination misbehaves with the streaming
  /// download. On iOS this isn't possible — see the banner.
  Future<void> _downloadApkViaBrowser(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          launched
              ? 'Download started — install the APK when it finishes.'
              : 'Could not open the download link.',
        ),
        backgroundColor: launched ? AppConstants.success : AppConstants.error,
      ),
    );
  }

  /// In-app path: stream the APK (progress in the banner) then trigger the
  /// system installer. When the APK is already fully downloaded (Install tap
  /// after completion, or a previous session), the download is skipped.
  /// Failures fall back to the browser flow with a toast.
  Future<void> _downloadInApp(UpdateInfo update) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Download is skipped by the service when this version's APK exists.
      await _installer.downloadAndInstall(update.apkUrl, update.version);
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('In-app download failed — opening the browser instead.'),
          backgroundColor: AppConstants.error,
        ),
      );
      await _downloadApkViaBrowser(update.apkUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Marking as viewed when the screen opens clears the Settings badge dot.
    // Done in a post-frame callback so the provider notification doesn't
    // rebuild this screen mid-build.
    if (_hasChecked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<UpdateProvider>().markUpdateViewed();
      });
      _hasChecked = false;
    }

    final updateProvider = context.watch<UpdateProvider>();
    final installed = updateProvider.installedVersion;

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        backgroundColor: AppConstants.secondary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFF5EDE4), size: 24),
        title: Text(
          "What's New",
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFF5EDE4),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        color: AppConstants.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            // ── Installed version header ────────────────────────
            _InstalledVersionHeader(installedVersion: installed),
            const SizedBox(height: 16),

            // ── Update available banner (reads provider state) ──
            if (updateProvider.isChecking)
              const _LoadingBanner()
            else if (updateProvider.checkFailed)
              SizedBox(
                width: double.infinity,
                child: ErrorRetryWidget(
                  message:
                      "We couldn't check for updates right now. Check your connection and try again.",
                  onRetry: () => context.read<UpdateProvider>().checkForUpdate(),
                ),
              )
            else if (updateProvider.latestUpdate != null)
              _UpdateBanner(
                update: updateProvider.latestUpdate!,
                // Emulators: show the release info but never push the APK
                // download — dev builds are updated via `flutter run`.
                showDownload: !updateProvider.isEmulator,
                installer: _installer,
                onDownloadInApp: () =>
                    _downloadInApp(updateProvider.latestUpdate!),
                onDownloadViaBrowser: () => _downloadApkViaBrowser(
                    updateProvider.latestUpdate!.apkUrl),
                onCancelDownload: () => _installer.cancelDownload(),
              )
            else
              const _UpToDateCard(),
            const SizedBox(height: 24),

            // ── Section header ──────────────────────────────────
            Text(
              'Release Notes',
              style: AppConstants.bodyStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppConstants.secondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'What changed in recent versions',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 12),

            // ── Changelog list ──────────────────────────────────
            FutureBuilder<List<UpdateInfo>>(
              future: _changelogFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _ChangelogSkeleton();
                }
                if (snapshot.hasError || snapshot.data == null) {
                  return SizedBox(
                    width: double.infinity,
                    child: ErrorRetryWidget(
                      message:
                          "We couldn't load the release notes. Check your connection and try again.",
                      onRetry: _reload,
                    ),
                  );
                }
                final releases = snapshot.data!;
                if (releases.isEmpty) {
                  return const SizedBox(
                    width: double.infinity,
                    child: EmptyStateWidget(
                      icon: Icons.history_rounded,
                      title: 'No release notes yet',
                      subtitle:
                          'Once releases are published, the changelog will appear here.',
                    ),
                  );
                }
                return Column(
                  children: [
                    for (var i = 0; i < releases.length; i++) ...[
                      ReleaseNoteCard(
                        release: releases[i],
                        isLatest: i == 0,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Header card showing the currently installed version.
class _InstalledVersionHeader extends StatelessWidget {
  const _InstalledVersionHeader({required this.installedVersion});

  final String? installedVersion;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.surfaceLight,
        borderRadius: AppConstants.cardRadius,
        boxShadow: AppConstants.warmShadow,
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppConstants.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.system_update_alt_rounded,
              color: AppConstants.primary,
              size: 26,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'CUFMAI',
            style: AppConstants.headlineStyle(fontSize: 20),
          ),
          const SizedBox(height: 4),
          Text(
            installedVersion != null
                ? 'You\'re on version v$installedVersion'
                : 'Checking your version…',
            style: AppConstants.bodyStyle(
              fontSize: 13,
              color: AppConstants.secondary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prominent card shown when a newer version is available. The primary
/// button drives the in-app download (with live progress); a secondary
/// link keeps the classic browser download available.
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({
    required this.update,
    required this.onDownloadInApp,
    required this.onDownloadViaBrowser,
    required this.onCancelDownload,
    required this.installer,
    this.showDownload = true,
  });

  final UpdateInfo update;
  final VoidCallback onDownloadInApp;
  final VoidCallback onDownloadViaBrowser;
  final VoidCallback onCancelDownload;
  final ApkInstallerService installer;

  /// False on emulators: the release info stays visible, but the download
  /// CTA is replaced by a passive note (dev builds update via `flutter run`).
  final bool showDownload;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppConstants.primary, Color(0xFF6B4423)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppConstants.cardRadius,
        boxShadow: [
          BoxShadow(
            color: AppConstants.primary.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SoleBadge(
            label: 'UPDATE AVAILABLE',
            backgroundColor: AppConstants.accent,
            textColor: Colors.white,
          ),
          const SizedBox(height: 12),
          Text(
            'Version v${update.version} is ready',
            style: AppConstants.headlineStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: const Color(0xFFF5EDE4),
            ),
          ),
          if (update.releasedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Released ${_formatDate(update.releasedAt!)}',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: const Color(0xFFF5EDE4).withValues(alpha: 0.75),
              ),
            ),
          ],
          if (update.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              update.notes.take(3).join('\n• ').replaceFirst(RegExp(r'^'), '• '),
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: const Color(0xFFF5EDE4).withValues(alpha: 0.85),
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (Platform.isIOS)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: AppConstants.buttonRadius,
              ),
              child: Text(
                'Updates are installed from the App Store on iOS.',
                textAlign: TextAlign.center,
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: const Color(0xFFF5EDE4),
                ),
              ),
            )
          else if (!showDownload)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: AppConstants.buttonRadius,
              ),
              child: Text(
                'Emulator detected — update via flutter run. No download needed.',
                textAlign: TextAlign.center,
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: const Color(0xFFF5EDE4),
                ),
              ),
            )
          else
            AnimatedBuilder(
              animation: installer,
              builder: (context, _) {
                final state = installer.state;
                final downloading =
                    state?.phase == ApkDownloadPhase.downloading;
                final done = state?.phase == ApkDownloadPhase.done;

                if (downloading) {
                  return _ProgressSection(
                    state: state!,
                    onCancel: onCancelDownload,
                  );
                }
                if (done && state?.filePath != null) {
                  return _InstallReadySection(
                    onInstall: onDownloadInApp,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SolePrimaryButton(
                      label: 'Download v${update.version}',
                      backgroundColor: AppConstants.accent,
                      textColor: AppConstants.secondary,
                      icon: Icon(Icons.download_rounded,
                          size: 18, color: AppConstants.secondary),
                      onPressed: onDownloadInApp,
                    ),
                    const SizedBox(height: 10),
                    // Fallback kept from the original flow: browser download.
                    Center(
                      child: TextButton(
                        onPressed: onDownloadViaBrowser,
                        child: Text(
                          'Download via browser instead',
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            color:
                                const Color(0xFFF5EDE4).withValues(alpha: 0.8),
                          ).copyWith(decoration: TextDecoration.underline),
                        ),
                      ),
                    ),
                  ],
                );
              },
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
class _ProgressSection extends StatelessWidget {
  const _ProgressSection({required this.state, required this.onCancel});

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
            backgroundColor: Colors.white.withValues(alpha: 0.2),
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
                  color: const Color(0xFFF5EDE4),
                ),
              ),
            ),
            TextButton(
              onPressed: onCancel,
              child: Text(
                'Cancel',
                style: AppConstants.bodyStyle(
                  fontSize: 12,
                  color: const Color(0xFFF5EDE4).withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shown once the APK is fully downloaded — one tap to install.
class _InstallReadySection extends StatelessWidget {
  const _InstallReadySection({required this.onInstall});

  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    return SolePrimaryButton(
      label: 'Install update',
      backgroundColor: AppConstants.success,
      textColor: Colors.white,
      icon: const Icon(Icons.install_mobile_rounded,
          size: 18, color: Colors.white),
      onPressed: onInstall,
    );
  }
}

/// Quiet card shown when the app is already up to date.
class _UpToDateCard extends StatelessWidget {
  const _UpToDateCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.success.withValues(alpha: 0.08),
        borderRadius: AppConstants.cardRadius,
        border: Border.all(color: AppConstants.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppConstants.success, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "You're up to date!",
              style: AppConstants.bodyStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppConstants.success,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shimmer skeleton for the update banner while the manifest loads.
class _LoadingBanner extends StatelessWidget {
  const _LoadingBanner();

  @override
  Widget build(BuildContext context) {
    return const ShimmerBox(width: double.infinity, height: 150, borderRadius: 16);
  }
}

/// Shimmer skeleton for the changelog list while it loads.
class _ChangelogSkeleton extends StatelessWidget {
  const _ChangelogSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 3; i++) ...[
          const ShimmerBox(width: double.infinity, height: 120, borderRadius: 16),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
