import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../constants/app_constants.dart';
import 'signup_scaffold.dart';

/// Upload lifecycle for one verification document (ID photo, selfie,
/// barangay proof, DTI cert, …). Driven by the screens' controllers — this
/// widget renders whatever state it's given.
enum DocumentUploadStatus {
  /// No image picked yet.
  empty,

  /// Image picked locally; upload happens with the form submit.
  picked,

  /// Upload in flight.
  uploading,

  /// Uploaded to the private bucket; [storagePath] available.
  uploaded,

  /// Upload failed; [errorMessage] explains and Retry re-runs it.
  error,
}

/// Bottom-sheet chooser for picking a verification photo from the gallery
/// or the camera. Returns null when dismissed.
Future<ImageSource?> showVerificationImageSourceSheet(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AuthSpacing.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Add photo',
              style: AppConstants.headlineStyle(fontSize: 18),
            ),
            const SizedBox(height: AuthSpacing.s16),
            Row(
              children: [
                Expanded(
                  child: _SourceOption(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: AuthSpacing.s12),
                Expanded(
                  child: _SourceOption(
                    icon: Icons.photo_camera_outlined,
                    label: 'Camera',
                    onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AuthSpacing.s8),
          ],
        ),
      ),
    ),
  );
}

/// Renders one verification-document upload slot with a designed state for
/// every lifecycle stage — empty (dashed drop target), picked, uploading
/// (indeterminate progress), uploaded (green check) and error (retry).
class DocumentUploadTile extends StatelessWidget {
  final String title;
  final String description;
  final DocumentUploadStatus status;
  final String? imagePath;
  final String? errorMessage;
  final bool required;

  /// Opens the source chooser (gallery/camera).
  final VoidCallback onPick;

  /// Clears the picked image so the user can start over.
  final VoidCallback? onRemove;

  /// Retries the failed upload.
  final VoidCallback? onRetry;

  const DocumentUploadTile({
    super.key,
    required this.title,
    required this.description,
    required this.status,
    required this.onPick,
    this.imagePath,
    this.errorMessage,
    this.required = true,
    this.onRemove,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = switch (status) {
      DocumentUploadStatus.error => AppConstants.error,
      DocumentUploadStatus.uploaded => AppConstants.success,
      _ => AppConstants.borderGray,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AuthSpacing.s12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor.withValues(alpha: 0.7), width: 1),
      ),
      child: status == DocumentUploadStatus.empty
          ? _buildEmpty(context)
          : _buildContent(context),
    );
  }

  // ── Empty (dashed drop target) ────────────────────────────────
  Widget _buildEmpty(BuildContext context) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AuthSpacing.s16),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppConstants.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_a_photo_outlined,
                color: AppConstants.primary,
                size: 24,
              ),
            ),
            const SizedBox(height: AuthSpacing.s12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AuthSpacing.s4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.55),
                height: 1.4,
              ),
            ),
            const SizedBox(height: AuthSpacing.s12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: AppConstants.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.add_rounded,
                    size: 16,
                    color: AppConstants.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    required ? 'Add photo' : 'Optional',
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.primary,
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

  // ── Picked / uploading / uploaded / error ─────────────────────
  Widget _buildContent(BuildContext context) {
    final uploading = status == DocumentUploadStatus.uploading;
    final hasImage = imagePath != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Thumbnail
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 64,
            height: 64,
            child: hasImage
                ? Image.file(
                    File(imagePath!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _thumbnailPlaceholder(),
                  )
                : _thumbnailPlaceholder(),
          ),
        ),
        const SizedBox(width: AuthSpacing.s12),
        // Copy + status
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppConstants.bodyStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AuthSpacing.s4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _statusLine(key: ValueKey(status)),
              ),
              if (uploading) ...[
                const SizedBox(height: AuthSpacing.s8),
                const LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: AppConstants.borderGray,
                  color: AppConstants.primary,
                ),
              ],
              if (status == DocumentUploadStatus.error &&
                  errorMessage != null) ...[
                const SizedBox(height: AuthSpacing.s8),
                Text(
                  errorMessage!,
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.error,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AuthSpacing.s8),
        _buildAction(),
      ],
    );
  }

  Widget _statusLine({required Key key}) {
    final (color, text) = switch (status) {
      DocumentUploadStatus.picked => (
          AppConstants.primary,
          'Ready to submit with your application'
        ),
      DocumentUploadStatus.uploading => (
          AppConstants.primary,
          'Uploading securely…'
        ),
      DocumentUploadStatus.uploaded => (
          AppConstants.success,
          'Uploaded securely'
        ),
      DocumentUploadStatus.error => (
          AppConstants.error,
          'Upload failed'
        ),
      DocumentUploadStatus.empty => (
          AppConstants.secondary,
          ''
        ),
    };

    return Row(
      key: key,
      children: [
        if (status == DocumentUploadStatus.uploaded) ...[
          const Icon(
            Icons.verified_rounded,
            size: 15,
            color: AppConstants.success,
          ),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            text,
            style: AppConstants.bodyStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAction() {
    switch (status) {
      case DocumentUploadStatus.uploaded:
      case DocumentUploadStatus.picked:
        // Local copies: public final fields aren't promotable, so capture
        // into locals before the null checks.
        final remove = onRemove;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _iconAction(
              icon: Icons.refresh_rounded,
              tooltip: 'Replace photo',
              onTap: onPick,
            ),
            const SizedBox(width: 4),
            if (remove != null)
              _iconAction(
                icon: Icons.close_rounded,
                tooltip: 'Remove photo',
                onTap: remove,
              ),
          ],
        );
      case DocumentUploadStatus.error:
        final retry = onRetry;
        return _iconAction(
          icon: Icons.refresh_rounded,
          tooltip: 'Retry upload',
          onTap: retry ?? onPick,
        );
      case DocumentUploadStatus.uploading:
        return const SizedBox.shrink();
      case DocumentUploadStatus.empty:
        return const SizedBox.shrink();
    }
  }

  Widget _iconAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: tooltip,
      button: true,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppConstants.surfaceLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppConstants.borderGray.withValues(alpha: 0.5),
              ),
            ),
            child: Icon(icon, size: 18, color: AppConstants.secondary),
          ),
        ),
      ),
    );
  }

  Widget _thumbnailPlaceholder() {
    return Container(
      color: AppConstants.surfaceLight,
      child: const Icon(
        Icons.image_outlined,
        size: 26,
        color: AppConstants.borderGray,
      ),
    );
  }
}

class _SourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SourceOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 92,
        decoration: BoxDecoration(
          color: AppConstants.surfaceLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppConstants.borderGray.withValues(alpha: 0.6),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppConstants.primary, size: 26),
            const SizedBox(height: AuthSpacing.s8),
            Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
