import 'package:deepar_flutter_plus/deepar_flutter_plus.dart';
import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../services/deepar_try_on.dart';

/// **DeepAR shoe spike screen (Step 2).**
///
/// Opens the native DeepAR camera and loads the bundled `.deepar` effect for
/// [productId] (Luna Loafers first). Keys come from `--dart-define` so the
/// repo never pins them; a missing key or missing effect draws the honest
/// sentence from [deepArUnavailableMessage] instead of a black camera.
class DeepArTryOnScreen extends StatefulWidget {
  const DeepArTryOnScreen({super.key, required this.productId});

  final String productId;

  @override
  State<DeepArTryOnScreen> createState() => _DeepArTryOnScreenState();
}

class _DeepArTryOnScreenState extends State<DeepArTryOnScreen> {
  final DeepArControllerPlus _controller = DeepArControllerPlus();
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  String? _effect;
  String? _loadNote;

  Future<void> _init() async {
    final effect = deepArEffectForProduct(widget.productId);
    if (!deepArConfigured) {
      setState(() => _error = deepArUnavailableMessage(configured: false));
      return;
    }
    if (effect == null) {
      setState(() => _error = deepArUnavailableMessage(configured: true));
      return;
    }
    _effect = effect;
    final result = await _controller.initialize(
      androidLicenseKey: kDeepArAndroidKey,
      iosLicenseKey: kDeepArIosKey,
    );
    if (!mounted) return;
    if (!result.success) {
      setState(() => _error = 'DeepAR could not start: ${result.message}');
      return;
    }
    // Shoe try-on needs the rear camera (feet on the floor). The plugin
    // defaults to front, so flip once right after init — before the preview
    // draws — so the customer never sees their face.
    try {
      await _controller.flipCamera();
    } catch (_) {
      // Non-fatal: front camera still previews, user can flip manually.
    }
    if (!mounted) return;
    setState(() => _initialized = true);
    // Load after the native preview exists. The first call can race the
    // texture (foot tracking is lazy-loaded), so wait a beat then load.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      await _loadEffect();
    });
  }

  Future<void> _loadEffect() async {
    final effect = _effect;
    if (effect == null) return;
    try {
      final answer = await _controller.switchEffect(effect);
      if (!mounted) return;
      setState(() => _loadNote = 'effect: $answer');
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load shoe: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Try on in AR (DeepAR)'),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          : _initialized
              ? Stack(
                  children: [
                    DeepArPreviewPlus(_controller),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 24,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_loadNote != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                _loadNote!,
                                textAlign: TextAlign.center,
                                style: AppConstants.bodyStyle(
                                  fontSize: 11,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton(
                                onPressed: _loadEffect,
                                child: const Text('Reload shoe'),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: () async {
                                  try {
                                    await _controller.flipCamera();
                                  } catch (_) {}
                                },
                                child: const Text('Flip camera'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Point rear camera at feet, ~1m back, ankle + toes in frame.',
                            textAlign: TextAlign.center,
                            style: AppConstants.bodyStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
    );
  }
}
