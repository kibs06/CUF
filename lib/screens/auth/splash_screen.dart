import 'dart:async';
import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
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
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _controller.forward();

    // Auto-navigates to AuthGate after 2 seconds
    Timer(const Duration(seconds: 2), () {
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
                    'SoleVision',
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
