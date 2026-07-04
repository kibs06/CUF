import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

  // Minimal shoe sole SVG logo (Crafted Ground concept)
  static const String _shoeSoleSvg = '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M50,12 C62,12 68,26 64,40 C60,54 66,74 62,84 C58,89 42,89 38,84 C34,74 40,54 36,40 C32,26 38,12 50,12 Z" stroke="currentColor" stroke-width="4" stroke-linecap="round"/>
  <line x1="43" y1="24" x2="57" y2="24" stroke="currentColor" stroke-width="4" stroke-linecap="round"/>
  <line x1="41" y1="34" x2="59" y2="34" stroke="currentColor" stroke-width="4" stroke-linecap="round"/>
  <line x1="42" y1="44" x2="58" y2="44" stroke="currentColor" stroke-width="4" stroke-linecap="round"/>
  <line x1="43" y1="54" x2="57" y2="54" stroke="currentColor" stroke-width="4" stroke-linecap="round"/>
  <line x1="45" y1="70" x2="55" y2="70" stroke="currentColor" stroke-width="4" stroke-linecap="round"/>
  <line x1="46" y1="78" x2="54" y2="78" stroke="currentColor" stroke-width="4" stroke-linecap="round"/>
</svg>
''';

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
                  // Centered Shoe Sole SVG Logo
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: SvgPicture.string(
                      _shoeSoleSvg,
                      colorFilter: const ColorFilter.mode(
                        AppConstants.primary,
                        BlendMode.srcIn,
                      ),
                    ),
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
