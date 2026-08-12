import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../services/verification_document_service.dart';

/// Resolves a private verification-document storage path to a short-lived
/// signed URL and opens it in a full-screen zoomable dialog (InteractiveViewer
/// — pinch/pan). Admin-only context: createSignedUrl succeeds because the
/// admin passes the storage object SELECT policy.
Future<void> showVerificationDocZoom(
  BuildContext context, {
  required String? storagePath,
  required String label,
}) async {
  if (storagePath == null || storagePath.isEmpty) return;

  final String url;
  try {
    url = await VerificationDocumentService.instance.signedUrl(storagePath);
  } catch (e) {
    debugPrint('[VerificationDoc] signed URL failed for $storagePath: $e');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not load this document right now.'),
        backgroundColor: AppConstants.error,
      ),
    );
    return;
  }
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              maxScale: 6,
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  },
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                iconSize: 26,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A tappable thumbnail for a private verification document. Resolves the
/// signed URL ONCE per storage path (cached in state — rebuilding the admin
/// list does not re-mint signed URLs on every frame) and shows a loader
/// while loading; tap opens the full-screen zoom. Hidden entirely when
/// [storagePath] is empty.
class VerificationDocThumb extends StatefulWidget {
  final String? storagePath;
  final String label;
  final double size;

  const VerificationDocThumb({
    super.key,
    required this.storagePath,
    required this.label,
    this.size = 64,
  });

  @override
  State<VerificationDocThumb> createState() => _VerificationDocThumbState();
}

class _VerificationDocThumbState extends State<VerificationDocThumb> {
  Future<String>? _urlFuture;

  @override
  void initState() {
    super.initState();
    _urlFuture = _resolve();
  }

  @override
  void didUpdateWidget(covariant VerificationDocThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storagePath != widget.storagePath) {
      _urlFuture = _resolve();
    }
  }

  Future<String>? _resolve() {
    final path = widget.storagePath;
    if (path == null || path.isEmpty) return null;
    return VerificationDocumentService.instance.signedUrl(path);
  }

  @override
  Widget build(BuildContext context) {
    final future = _urlFuture;
    if (future == null) return const SizedBox.shrink();

    return FutureBuilder<String>(
      future: future,
      builder: (context, snapshot) {
        final Widget content;
        if (snapshot.connectionState == ConnectionState.waiting) {
          content = _loadingPlaceholder();
        } else if (snapshot.hasError) {
          content = _errorPlaceholder();
        } else {
          content = Image.network(
            snapshot.data!,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : _loadingPlaceholder(),
            errorBuilder: (_, _, _) => _errorPlaceholder(),
          );
        }

        return Semantics(
          label: widget.label,
          button: true,
          child: InkWell(
            onTap: () => showVerificationDocZoom(
              context,
              storagePath: widget.storagePath,
              label: widget.label,
            ),
            borderRadius: BorderRadius.circular(10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _loadingPlaceholder() {
    return Container(
      color: AppConstants.surfaceLight,
      child: const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppConstants.primary,
          ),
        ),
      ),
    );
  }

  Widget _errorPlaceholder() {
    return Container(
      color: AppConstants.error.withValues(alpha: 0.08),
      child: const Icon(
        Icons.broken_image_outlined,
        size: 20,
        color: AppConstants.error,
      ),
    );
  }
}
