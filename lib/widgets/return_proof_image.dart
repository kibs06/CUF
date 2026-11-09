import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../services/order_service.dart';

/// Reads the return photo proofs off an order map: prefers the
/// `return_proof_paths` array, falling back to the legacy single
/// `return_proof_path` for requests filed before multi-photo support.
List<String> returnProofPathsOf(Map<String, dynamic> order) {
  final raw = order['return_proof_paths'];
  if (raw is List) {
    final paths = raw
        .map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
    if (paths.isNotEmpty) return paths;
  }
  final legacy = order['return_proof_path']?.toString() ?? '';
  return legacy.isEmpty ? const [] : [legacy];
}

/// Thumbnails of a return's photo proofs stored in the private
/// `return-proofs` bucket, resolved via signed URLs. Renders nothing when
/// [storagePaths] is empty (pre-proof-migration orders). A single photo
/// fills the width; several render as a thumbnail row. Tapping opens a
/// fullscreen swipeable viewer.
class ReturnProofImage extends StatefulWidget {
  final List<String> storagePaths;
  final double height;

  const ReturnProofImage({
    super.key,
    required this.storagePaths,
    this.height = 140,
  });

  @override
  State<ReturnProofImage> createState() => _ReturnProofImageState();
}

class _ReturnProofImageState extends State<ReturnProofImage> {
  late final Future<List<String>> _urlsFuture;

  @override
  void initState() {
    super.initState();
    _urlsFuture = _resolveUrls(widget.storagePaths);
  }

  Future<List<String>> _resolveUrls(List<String> paths) async {
    final service = OrderService();
    final urls = await Future.wait(paths.map(service.returnProofUrl));
    return urls.whereType<String>().where((u) => u.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.storagePaths.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<List<String>>(
      future: _urlsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: widget.height,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppConstants.borderGray.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final urls = snapshot.data ?? const <String>[];
        if (urls.isEmpty) {
          return Container(
            height: 64,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppConstants.borderGray.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.image_not_supported_outlined,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Photo proof unavailable',
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary,
                  ),
                ),
              ],
            ),
          );
        }
        if (urls.length == 1) {
          return GestureDetector(
            onTap: () => _openFullscreen(context, urls, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                urls.first,
                height: widget.height,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _brokenThumb(widget.height),
              ),
            ),
          );
        }
        return SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) => GestureDetector(
              onTap: () => _openFullscreen(context, urls, index),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  urls[index],
                  height: 96,
                  width: 96,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _brokenThumb(96, width: 96),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _brokenThumb(double height, {double? width}) {
    return Container(
      height: height,
      width: width ?? double.infinity,
      color: AppConstants.borderGray.withValues(alpha: 0.15),
      child: const Icon(Icons.image_not_supported_outlined),
    );
  }

  void _openFullscreen(
      BuildContext context, List<String> urls, int initialIndex) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: _FullscreenProofViewer(urls: urls, initialIndex: initialIndex),
      ),
    );
  }
}

class _FullscreenProofViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const _FullscreenProofViewer({required this.urls, required this.initialIndex});

  @override
  State<_FullscreenProofViewer> createState() => _FullscreenProofViewerState();
}

class _FullscreenProofViewerState extends State<_FullscreenProofViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: widget.urls.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) => InteractiveViewer(
            child: Image.network(
              widget.urls[i],
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: Colors.white70,
                  size: 48,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 4,
          top: 4,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        if (widget.urls.length > 1)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_index + 1} / ${widget.urls.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
