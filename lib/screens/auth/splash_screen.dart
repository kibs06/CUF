import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/update_provider.dart';
import '../auth_gate.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    // Short brand flash only: the home feed paints from disk cache, so the
    // splash must never waste the fast path. 900ms is enough for the
    // wordmark to read; AuthGate (profile fetch) owns any further wait and
    // shows its own loading state instead of holding branding on screen.
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _controller.forward();

    // Silent, non-blocking update check — never shows a popup. If a newer
    // build exists, the Settings → "What's New" row shows a badge dot.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<UpdateProvider>().checkForUpdate();
      }
    });

    // Leaves for AuthGate after the brand flash — not a fixed 2s wait.
    Timer(const Duration(milliseconds: 900), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const AuthGate(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          children: [
            AppConstants.noiseOverlay(opacity: 0.03),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Centered Shoe Sole Icon (replaces SVG for reliability)
                  const Icon(
                    Icons.directions_run,
                    size: 100,
                    color: AppConstants.primary,
                  ),
                  const SizedBox(height: 24),
                  // Wordmark
                  Text(
                    'CUFMAI',
                    style: AppConstants.headlineStyle(
                      fontSize: 36,
                      color: AppConstants.secondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Tagline
                  Text(
                    'Crafted for your every step',
                    style: AppConstants.bodyStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      color: AppConstants.secondary.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
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
}
