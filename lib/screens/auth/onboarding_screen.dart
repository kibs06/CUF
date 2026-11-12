import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/app_brightness.dart';
import '../../constants/app_constants.dart';
import '../../constants/app_palette.dart';

/// Three-slide onboarding shown on the very first app launch.
///
/// After completion, sets `has_seen_onboarding = true` in SharedPreferences
/// so it never shows again.
///
/// **It does not navigate.** [onFinished] tells the host (AuthGate's
/// `_FirstTimeOrLoginRouter`) that the pref is written; the host is what swaps
/// itself for `AccountEntryScreen`.
///
/// This used to be `Navigator.pushReplacement(AccountEntryScreen)` — and since
/// this screen is a CHILD of AuthGate rather than a route of its own, that call
/// replaced the gate's own route and unmounted the gate. On a fresh install the
/// user therefore signed in with nothing left listening for the new session and
/// sat on the sign-in form until they force-closed the app. Reproduced
/// 2026-09-28 (see test/screens/onboarding_handoff_test.dart) and fixed by
/// handing the swap back to the gate.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  /// Called after `has_seen_onboarding` is persisted. The host decides what
  /// comes next — pushing a route from here would take the gate out of the
  /// navigation stack again.
  final VoidCallback onFinished;

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
      eyebrow: 'Handcrafted in Cebu',
      svg: _welcomeSvg,
      headline: 'Welcome to CUFMAI',
      body:
          'Handcrafted footwear from the heart of Carcar City, Cebu — sold by the makers themselves.',
      bullets: [
        _SlideBullet('handyman_outlined', 'Hand-stitched by Cebu craftsmen'),
        _SlideBullet('storefront_outlined', 'Sold by the makers themselves'),
        _SlideBullet('savings_outlined', 'Fair prices, no middlemen'),
      ],
      chips: ['Carcar · Cebu', 'Hand-stitched'],
    ),
    _SlideData(
      eyebrow: 'The marketplace',
      svg: _storefrontSvg,
      headline: 'Explore Artisan Stores',
      body: 'Browse unique footwear from local workshops across Cebu.',
      bullets: [
        _SlideBullet('style_outlined', 'Filter by style, size and price'),
        _SlideBullet(
          'local_shipping_outlined',
          'Track every order to your door',
        ),
        _SlideBullet('chat_bubble_outline', 'Message sellers directly'),
      ],
      chips: ['Local makers', 'Small batches'],
    ),
    _SlideData(
      eyebrow: 'True-to-size fit',
      svg: _arSvg,
      headline: 'See It On Your Feet',
      body:
          'Try pairs on through your camera and scan your feet once — so the size you order is the size that fits.',
      bullets: [
        _SlideBullet('view_in_ar_outlined', 'Camera try-on before you buy'),
        _SlideBullet('camera_alt_outlined', 'One scan remembers your size'),
        _SlideBullet('straighten_outlined', 'Size advice on every product'),
      ],
      chips: ['Camera try-on', 'Foot scan'],
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
    // The host owns the swap (see the class docs). Nothing is pushed here on
    // purpose — a route pushed from this widget's context sits ABOVE the gate.
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final bool isLast = _currentPage == _totalPages - 1;
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
                // ─── Progress + Skip (top bar) ───────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 8, 0),
                  child: Row(
                    children: [
                      // "1 / 3" counter + segmented progress, announced as
                      // one labelled unit; the bars themselves are decorative.
                      Expanded(
                        child: Semantics(
                          label:
                              'Page ${_currentPage + 1} of $_totalPages',
                          excludeSemantics: true,
                          child: Row(
                            children: [
                              Text(
                                '${_currentPage + 1} / $_totalPages',
                                style: AppConstants.monoStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppConstants.secondary
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ...List.generate(
                                _totalPages,
                                (index) => Expanded(
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 300),
                                    curve: Curves.easeOut,
                                    height: 4,
                                    margin: EdgeInsets.only(
                                      right: index < _totalPages - 1 ? 6 : 0,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(2),
                                      color: index <= _currentPage
                                          ? AppConstants.primary
                                          : AppConstants.secondary
                                              .withValues(alpha: 0.15),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedOpacity(
                        opacity: isLast ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 250),
                        child: TextButton(
                          onPressed: isLast ? null : _skipToLast,
                          // 44px minimum tap target (iOS) with room to spare.
                          style: TextButton.styleFrom(
                            minimumSize: const Size(72, 44),
                          ),
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
                    ],
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
                      return _SlideWidget(
                        data: _slides[index],
                        index: index,
                        pageController: _pageController,
                        currentPage: _currentPage,
                      );
                    },
                  ),
                ),

                // ─── Action button ─────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: isLast ? _completeOnboarding : _nextPage,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppConstants.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppConstants.buttonRadius,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isLast ? 'Get Started' : 'Next',
                            style: AppConstants.headlineStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              // Ink on the clay CTA — pinned light, not the
                              // page tone.
                              color: AppConstants.inkInverse,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 19,
                            color: AppConstants.inkInverse,
                          ),
                        ],
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
  final String eyebrow;
  final String svg;
  final String headline;
  final String body;
  final List<_SlideBullet> bullets;
  final List<String> chips;

  const _SlideData({
    required this.eyebrow,
    required this.svg,
    required this.headline,
    required this.body,
    required this.bullets,
    required this.chips,
  });
}

class _SlideBullet {
  final String icon;
  final String label;

  const _SlideBullet(this.icon, this.label);
}

// ─── Individual slide widget ──────────────────────────────────────
class _SlideWidget extends StatelessWidget {
  final _SlideData data;
  final int index;
  final PageController pageController;
  final int currentPage;

  const _SlideWidget({
    required this.data,
    required this.index,
    required this.pageController,
    required this.currentPage,
  });

  static const _bulletIcons = <String, IconData>{
    'handyman_outlined': Icons.handyman_outlined,
    'storefront_outlined': Icons.storefront_outlined,
    'savings_outlined': Icons.savings_outlined,
    'style_outlined': Icons.style_outlined,
    'local_shipping_outlined': Icons.local_shipping_outlined,
    'chat_bubble_outline': Icons.chat_bubble_outline,
    'view_in_ar_outlined': Icons.view_in_ar_outlined,
    'camera_alt_outlined': Icons.camera_alt_outlined,
    'straighten_outlined': Icons.straighten_outlined,
  };

  @override
  Widget build(BuildContext context) {
    // Clay ink that stays legible in both brightnesses: full clay on a
    // light page, the lightened clay on a dark one.
    final clayInk = AppPalette.of(AppBrightness.current).primaryInk;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Illustration medallion — the line art on a warm glow,
                  // ringed with a stitched circle (the craft motif) and two
                  // floating chips. Drifts against the swipe for depth;
                  // static when the OS asks for reduced motion.
                  _Parallax(
                    pageController: pageController,
                    index: index,
                    currentPage: currentPage,
                    child: SizedBox(
                      width: 248,
                      height: 248,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Warm glow
                          Container(
                            width: 248,
                            height: 248,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  AppConstants.primary
                                      .withValues(alpha: 0.22),
                                  AppConstants.primary
                                      .withValues(alpha: 0.0),
                                ],
                                stops: const [0.0, 0.72],
                              ),
                            ),
                          ),
                          // Stitched ring
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: CustomPaint(
                              size: const Size(228, 228),
                              painter: _StitchRingPainter(
                                AppConstants.primary
                                    .withValues(alpha: 0.45),
                              ),
                            ),
                          ),
                          // Line art
                          SizedBox(
                            width: 168,
                            height: 168,
                            child: SvgPicture.string(
                              data.svg,
                              colorFilter: ColorFilter.mode(
                                clayInk,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                          // Floating chips
                          Positioned(
                            top: 26,
                            right: 0,
                            child: _MedallionChip(label: data.chips[0]),
                          ),
                          Positioned(
                            bottom: 30,
                            left: 0,
                            child: _MedallionChip(label: data.chips[1]),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Eyebrow
                  Text(
                    data.eyebrow.toUpperCase(),
                    style: AppConstants.bodyStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.8,
                      color: clayInk,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Headline
                  Text(
                    data.headline,
                    textAlign: TextAlign.center,
                    style: AppConstants.headlineStyle(
                      fontSize: 30,
                      color: AppConstants.secondary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Body
                  Text(
                    data.body,
                    textAlign: TextAlign.center,
                    style: AppConstants.bodyStyle(
                      fontSize: 15,
                      color:
                          AppConstants.secondary.withValues(alpha: 0.65),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Proof bullets — one icon tile + one line each.
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < data.bullets.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        _BulletRow(
                          icon: _bulletIcons[data.bullets[i].icon] ??
                              Icons.check_circle_outline,
                          label: data.bullets[i].label,
                          clayInk: clayInk,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One proof bullet: a 32px clay-tinted icon tile (48px effective tap row,
/// though the row itself is not tappable) and a single line of body text.
class _BulletRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color clayInk;

  const _BulletRow({
    required this.icon,
    required this.label,
    required this.clayInk,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppConstants.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: clayInk),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            label,
            style: AppConstants.bodyStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppConstants.secondary.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small pill floating on the medallion: raised surface, hairline border,
/// clay dot + label. Purely illustrative — hidden from screen readers so it
/// is never announced twice (the bullets below carry the same meaning).
class _MedallionChip extends StatelessWidget {
  final String label;

  const _MedallionChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppConstants.surfaceRaised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppConstants.borderGray),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppConstants.primary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Translates + fades [child] against the page swipe: the illustration lags
/// the text by a few dozen pixels, which is what gives the swipe its depth.
/// Reads the controller's live page offset; before first layout (no
/// dimensions yet) it renders the resting state. Fully static when the OS
/// reports reduced motion.
class _Parallax extends StatelessWidget {
  final PageController pageController;
  final int index;
  final int currentPage;
  final Widget child;

  const _Parallax({
    required this.pageController,
    required this.index,
    required this.currentPage,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) return child;
    return AnimatedBuilder(
      animation: pageController,
      builder: (context, child) {
        double offset = 0;
        if (pageController.hasClients &&
            pageController.position.hasContentDimensions) {
          offset =
              (pageController.page ?? currentPage.toDouble()) - index;
        }
        final clamped = offset.clamp(-1.0, 1.0);
        return Opacity(
          opacity: (1.0 - clamped.abs() * 0.3).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(clamped * -30, 0),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// The stitched circle around the medallion — short clay dashes on the
/// circumference, the way a welt is stitched around a sole.
class _StitchRingPainter extends CustomPainter {
  final Color color;

  _StitchRingPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final radius = size.width / 2;
    final center = Offset(radius, radius);
    const dash = 7.0;
    const gap = 6.0;
    double angle = -math.pi / 2;
    while (angle < math.pi * 1.5) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        dash / radius,
        false,
        paint,
      );
      angle += (dash + gap) / radius;
    }
  }

  @override
  bool shouldRepaint(covariant _StitchRingPainter oldDelegate) =>
      oldDelegate.color != color;
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
