import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/app_constants.dart';
import 'login_screen.dart';

/// Three-slide onboarding shown on the very first app launch.
///
/// After completion, sets `has_seen_onboarding = true` in SharedPreferences
/// so it never shows again.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const int _totalPages = 3;

  // ─── Slide data ───────────────────────────────────────────────
  static const List<_SlideData> _slides = [
    _SlideData(
      svg: _welcomeSvg,
      headline: 'Welcome to CUFMAI',
      body:
          'Discover handcrafted footwear from the heart of Carcar City, Cebu.',
    ),
    _SlideData(
      svg: _storefrontSvg,
      headline: 'Explore Artisan Stores',
      body:
          'Browse unique footwear from local craftsmen. Filter by style, size, and price.',
    ),
    _SlideData(
      svg: _arSvg,
      headline: 'Try It On with AR',
      body:
          'Use our augmented reality feature to see how shoes look on your feet before you buy.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  void _skipToLast() {
    _pageController.animateToPage(
      _totalPages - 1,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) =>
            FadeTransition(opacity: animation, child: const LoginScreen()),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: Stack(
        children: [
          // Noise overlay
          AppConstants.noiseOverlay(opacity: 0.03),

          // Page content
          SafeArea(
            child: Column(
              children: [
                // ─── Skip button (top-right) ───────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedOpacity(
                    opacity: _currentPage < _totalPages - 1 ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: TextButton(
                      onPressed: _currentPage < _totalPages - 1
                          ? _skipToLast
                          : null,
                      child: Text(
                        'Skip',
                        style: AppConstants.bodyStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.primary,
                        ),
                      ),
                    ),
                  ),
                ),

                // ─── PageView with slides ──────────────────────
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _totalPages,
                    onPageChanged: (index) {
                      setState(() => _currentPage = index);
                    },
                    itemBuilder: (context, index) {
                      final slide = _slides[index];
                      return _SlideWidget(data: slide);
                    },
                  ),
                ),

                // ─── Dot indicators ────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _totalPages,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        width: _currentPage == index ? 28 : 10,
                        height: 10,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          color: _currentPage == index
                              ? AppConstants.primary
                              : const Color(0xFFD9D0C7),
                        ),
                      ),
                    ),
                  ),
                ),

                // ─── Action button ─────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: _currentPage == _totalPages - 1
                          ? _completeOnboarding
                          : _nextPage,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppConstants.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppConstants.buttonRadius,
                        ),
                      ),
                      child: Text(
                        _currentPage == _totalPages - 1
                            ? 'Get Started'
                            : 'Next',
                        style: AppConstants.headlineStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.surfaceLight,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Slide data model ─────────────────────────────────────────────
class _SlideData {
  final String svg;
  final String headline;
  final String body;

  const _SlideData({
    required this.svg,
    required this.headline,
    required this.body,
  });
}

// ─── Individual slide widget ──────────────────────────────────────
class _SlideWidget extends StatelessWidget {
  final _SlideData data;
  const _SlideWidget({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Illustration
          SizedBox(
            width: 220,
            height: 220,
            child: SvgPicture.string(
              data.svg,
              colorFilter: const ColorFilter.mode(
                AppConstants.primary,
                BlendMode.srcIn,
              ),
            ),
          ),
          const SizedBox(height: 40),

          // Headline
          Text(
            data.headline,
            textAlign: TextAlign.center,
            style: AppConstants.headlineStyle(
              fontSize: 32,
              color: AppConstants.secondary,
            ),
          ),
          const SizedBox(height: 16),

          // Body
          Text(
            data.body,
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(
              fontSize: 16,
              color: AppConstants.secondary.withValues(alpha: 0.70),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── SVG Illustrations ────────────────────────────────────────────

/// Slide 1: Shoe sole — large, detailed, centered
const String _welcomeSvg = '''
<svg viewBox="0 0 200 200" fill="none" xmlns="http://www.w3.org/2000/svg">
  <!-- Outer sole shape -->
  <path d="M100,20 C125,20 140,45 135,75 C130,105 138,145 130,170 C122,182 78,182 70,170 C62,145 70,105 65,75 C60,45 75,20 100,20 Z"
        stroke="currentColor" stroke-width="3" stroke-linecap="round" fill="none"/>
  <!-- Inner detail lines -->
  <path d="M82,35 Q100,30 118,35" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" fill="none"/>
  <path d="M78,50 Q100,44 122,50" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" fill="none"/>
  <path d="M76,65 Q100,58 124,65" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" fill="none"/>
  <path d="M75,80 Q100,73 125,80" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" fill="none"/>
  <!-- Tread pattern -->
  <path d="M78,100 L122,100" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-dasharray="6 4"/>
  <path d="M76,115 L124,115" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-dasharray="6 4"/>
  <path d="M78,130 L122,130" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-dasharray="6 4"/>
  <!-- Heel area -->
  <ellipse cx="100" cy="155" rx="22" ry="12" stroke="currentColor" stroke-width="2" fill="none"/>
  <path d="M88,155 L112,155" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
  <!-- Decorative stitching dots -->
  <circle cx="100" cy="92" r="2" fill="currentColor"/>
  <circle cx="90" cy="92" r="1.5" fill="currentColor"/>
  <circle cx="110" cy="92" r="1.5" fill="currentColor"/>
</svg>
''';

/// Slide 2: Storefront with shoes on display
const String _storefrontSvg = '''
<svg viewBox="0 0 200 200" fill="none" xmlns="http://www.w3.org/2000/svg">
  <!-- Storefront frame -->
  <rect x="30" y="50" width="140" height="110" rx="6" stroke="currentColor" stroke-width="2.5" fill="none"/>
  <!-- Roof / awning -->
  <path d="M25,50 L100,25 L175,50" stroke="currentColor" stroke-width="3" stroke-linecap="round" fill="none"/>
  <path d="M35,50 L100,30 L165,50" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-dasharray="4 3" fill="none"/>
  <!-- Door -->
  <rect x="82" y="115" width="36" height="45" rx="3" stroke="currentColor" stroke-width="2" fill="none"/>
  <circle cx="112" cy="140" r="2.5" fill="currentColor"/>
  <!-- Window left -->
  <rect x="40" y="62" width="35" height="40" rx="3" stroke="currentColor" stroke-width="2" fill="none"/>
  <!-- Shoe in left window -->
  <path d="M48,90 C52,82 58,80 65,84 L68,90 L48,90 Z" stroke="currentColor" stroke-width="1.5" fill="none"/>
  <!-- Window right -->
  <rect x="125" y="62" width="35" height="40" rx="3" stroke="currentColor" stroke-width="2" fill="none"/>
  <!-- Shoe in right window -->
  <path d="M133,90 C137,82 143,80 150,84 L153,90 L133,90 Z" stroke="currentColor" stroke-width="1.5" fill="none"/>
  <!-- Sign -->
  <rect x="75" y="58" width="50" height="18" rx="3" stroke="currentColor" stroke-width="1.5" fill="none"/>
  <path d="M85,67 L115,67" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <!-- Stars/sparkles -->
  <circle cx="45" cy="40" r="2" fill="currentColor"/>
  <circle cx="155" cy="35" r="1.5" fill="currentColor"/>
  <circle cx="170" cy="45" r="2" fill="currentColor"/>
  <!-- Ground line -->
  <path d="M20,160 L180,160" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
</svg>
''';

/// Slide 3: AR shoe fitting — abstract foot with shoe overlay
const String _arSvg = '''
<svg viewBox="0 0 200 200" fill="none" xmlns="http://www.w3.org/2000/svg">
  <!-- Phone frame -->
  <rect x="50" y="20" width="100" height="170" rx="14" stroke="currentColor" stroke-width="2.5" fill="none"/>
  <rect x="58" y="32" width="84" height="140" rx="4" stroke="currentColor" stroke-width="1" fill="none"/>
  <!-- Camera dot -->
  <circle cx="100" cy="26" r="2" fill="currentColor"/>
  <!-- Home button indicator -->
  <path d="M90,178 L110,178" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
  <!-- Foot outline inside screen -->
  <path d="M85,150 C82,142 80,130 82,118 C84,106 83,98 88,92 C93,86 97,88 100,92 C103,88 107,86 110,88 C113,90 112,95 110,98 C112,102 115,110 114,120 C113,135 110,145 108,150 Z"
        stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>
  <!-- Shoe overlay (AR projection) -->
  <path d="M78,145 C80,132 84,125 92,122 C100,119 110,122 116,128 C120,132 122,140 120,148 L78,148 Z"
        stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-dasharray="5 3" fill="none"/>
  <!-- AR scan lines -->
  <path d="M62,55 L72,55 L72,45" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" fill="none"/>
  <path d="M138,55 L128,55 L128,45" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" fill="none"/>
  <path d="M62,155 L72,155 L72,165" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" fill="none"/>
  <path d="M138,155 L128,155 L128,165" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" fill="none"/>
  <!-- AR sparkle dots -->
  <circle cx="75" cy="75" r="2" fill="currentColor" opacity="0.6"/>
  <circle cx="125" cy="80" r="2" fill="currentColor" opacity="0.6"/>
  <circle cx="90" cy="60" r="1.5" fill="currentColor" opacity="0.4"/>
  <circle cx="115" cy="65" r="1.5" fill="currentColor" opacity="0.4"/>
</svg>
''';
