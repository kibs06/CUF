import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../constants/app_constants.dart';

/// **DeepAR Web shoe spike (5.3.0 pinned).**
///
/// Loads the portal's `/deepar-shoe?product=<id>` page (DeepAR Web SDK with
/// foot tracking) inside a WebView with camera access. This is the fallback
/// now that the native SDKs dropped feet — same Luna effect, rear camera.
class DeepArWebTryOnScreen extends StatefulWidget {
  const DeepArWebTryOnScreen({super.key, required this.productId});

  final String productId;

  @override
  State<DeepArWebTryOnScreen> createState() => _DeepArWebTryOnScreenState();
}

class _DeepArWebTryOnScreenState extends State<DeepArWebTryOnScreen> {
  late final WebViewController _controller;
  bool _failed = false;

  String get _url =>
      '${AppConstants.customerPortalUrl}/deepar-shoe?product=${Uri.encodeComponent(widget.productId)}';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (_) {
            if (mounted) setState(() => _failed = true);
          },
        ),
      )
      ..loadRequest(Uri.parse(_url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Try on in AR (DeepAR Web)'),
      ),
      body: _failed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not open the web try-on. Check connection and try again.',
                  textAlign: TextAlign.center,
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          : WebViewWidget(controller: _controller),
    );
  }
}
