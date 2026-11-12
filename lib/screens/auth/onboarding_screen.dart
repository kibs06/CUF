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
                            width: 178,
                            height: 178,
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

/// Slide 1: hand-stitched leather sandal, side profile.
///
/// The footbed wash, welt stitching and needle-and-thread arc are the craft
/// story; the shared kit (ground shadow, sparkles, 3 / 2 / 1.25 weights)
/// keeps all three slides one visual family (Material: visual continuity).
const String _welcomeSvg = '''
<svg viewBox="0 0 200 200" fill="none" xmlns="http://www.w3.org/2000/svg">
  <!-- Ground shadow -->
  <ellipse cx="100" cy="172" rx="48" ry="6" fill="currentColor" opacity="0.12"/>
  <!-- Footbed wash -->
  <path d="M52,146 C66,152 134,152 152,142 L150,132 C130,140 70,140 54,134 Z"
        fill="currentColor" opacity="0.10"/>
  <!-- Outsole slab -->
  <path d="M46,142 C62,152 138,152 156,140 L154,130 C138,140 64,140 48,132 Z"
        stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
  <!-- Welt stitching along the sole -->
  <path d="M54,137 C70,144 132,144 148,135"
        stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-dasharray="4 3" opacity="0.6" fill="none"/>
  <!-- Back strap -->
  <path d="M76,136 C79,112 90,98 104,96"
        stroke="currentColor" stroke-width="2.5" stroke-linecap="round" fill="none"/>
  <path d="M82,132 C85,114 93,103 103,101"
        stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-dasharray="3.5 3" opacity="0.55" fill="none"/>
  <!-- Front strap -->
  <path d="M108,138 C112,116 124,104 140,104"
        stroke="currentColor" stroke-width="2.5" stroke-linecap="round" fill="none"/>
  <path d="M114,134 C118,118 127,109 139,109"
        stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-dasharray="3.5 3" opacity="0.55" fill="none"/>
  <!-- Buckle on the front strap -->
  <rect x="122" y="112" width="12" height="10" rx="3"
        stroke="currentColor" stroke-width="2" fill="none"/>
  <circle cx="128" cy="117" r="1.6" fill="currentColor"/>
  <!-- Heel pad -->
  <ellipse cx="62" cy="136" rx="7" ry="4"
        stroke="currentColor" stroke-width="1.5" opacity="0.6" fill="none"/>
  <!-- Needle and thread arc — the making of the pair -->
  <path d="M36,116 Q56,88 94,84"
        stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-dasharray="5 4" opacity="0.7" fill="none"/>
  <path d="M94,84 L106,76" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
  <circle cx="107" cy="75" r="1.8" fill="currentColor"/>
  <!-- Sparkles -->
  <path d="M158,52 v10 M153,57 h10" stroke="currentColor" stroke-width="1.75" stroke-linecap="round"/>
  <circle cx="140" cy="44" r="1.8" fill="currentColor" opacity="0.7"/>
  <circle cx="172" cy="70" r="1.5" fill="currentColor" opacity="0.5"/>
</svg>
''';

/// Slide 2: artisan boutique — striped awning, hanging sign, shoes on stands
/// in both windows, planters flanking the door.
const String _storefrontSvg = '''
<svg viewBox="0 0 200 200" fill="none" xmlns="http://www.w3.org/2000/svg">
  <!-- Ground shadow + line -->
  <ellipse cx="100" cy="170" rx="62" ry="6" fill="currentColor" opacity="0.12"/>
  <path d="M26,170 L174,170" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
  <!-- Facade -->
  <rect x="46" y="62" width="108" height="108" rx="5"
        stroke="currentColor" stroke-width="2.5" fill="none"/>
  <!-- Cornice -->
  <rect x="40" y="52" width="120" height="10" rx="3.5"
        stroke="currentColor" stroke-width="2.5" fill="none"/>
  <!-- Striped awning with scallops -->
  <path d="M52,74 L148,74 L144,92 Q138,98 132,92 Q126,98 120,92 Q114,98 108,92 Q102,98 96,92 Q90,98 84,92 Q78,98 72,92 Q66,98 60,92 Q55,97 52,92 Z"
        stroke="currentColor" stroke-width="2" stroke-linejoin="round" fill="currentColor" fill-opacity="0.10"/>
  <path d="M76,74 L74,93 M100,74 L100,94 M124,74 L126,93"
        stroke="currentColor" stroke-width="1.25" stroke-linecap="round" opacity="0.55"/>
  <!-- Hanging sign with a mini sole -->
  <path d="M92,74 v6 M108,74 v6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <rect x="80" y="80" width="40" height="17" rx="8.5"
        stroke="currentColor" stroke-width="1.75" fill="none"/>
  <path d="M90,88.5 C93,86 97,86 99,88.5 M101,88.5 C103,86 107,86 110,88.5"
        stroke="currentColor" stroke-width="1.25" stroke-linecap="round" fill="none"/>
  <!-- Door -->
  <rect x="88" y="118" width="24" height="52" rx="2.5"
        stroke="currentColor" stroke-width="2.25" fill="none"/>
  <path d="M92,124 L92,164 M108,124 L108,164" stroke="currentColor" stroke-width="1.25" opacity="0.5"/>
  <circle cx="106" cy="146" r="2" fill="currentColor"/>
  <!-- Lantern dots flanking the sign -->
  <circle cx="66" cy="88" r="2" fill="currentColor" opacity="0.7"/>
  <circle cx="134" cy="88" r="2" fill="currentColor" opacity="0.7"/>
  <!-- Left window + shoe on a stand -->
  <rect x="54" y="118" width="26" height="32" rx="3"
        stroke="currentColor" stroke-width="2" fill="none"/>
  <path d="M58,142 C60,136 64,134 68,136 L73,140 L58,140 Z"
        stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" fill="none"/>
  <path d="M62,140 v4 M70,140 v4" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" opacity="0.6"/>
  <!-- Right window + shoe on a stand -->
  <rect x="120" y="118" width="26" height="32" rx="3"
        stroke="currentColor" stroke-width="2" fill="none"/>
  <path d="M124,142 C126,136 130,134 134,136 L139,140 L124,140 Z"
        stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" fill="none"/>
  <path d="M128,140 v4 M136,140 v4" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" opacity="0.6"/>
  <!-- Planters -->
  <path d="M34,158 L44,158 L42,170 L36,170 Z"
        stroke="currentColor" stroke-width="1.75" stroke-linejoin="round" fill="none"/>
  <path d="M39,158 C37,150 33,147 29,146 M39,158 C39,150 41,145 45,143 M39,158 v-10"
        stroke="currentColor" stroke-width="1.5" stroke-linecap="round" fill="none"/>
  <path d="M156,158 L166,158 L164,170 L158,170 Z"
        stroke="currentColor" stroke-width="1.75" stroke-linejoin="round" fill="none"/>
  <path d="M161,158 C159,150 155,147 151,146 M161,158 C161,150 163,145 167,143 M161,158 v-10"
        stroke="currentColor" stroke-width="1.5" stroke-linecap="round" fill="none"/>
  <!-- Sparkles -->
  <path d="M164,30 v9 M159.5,34.5 h9" stroke="currentColor" stroke-width="1.75" stroke-linecap="round"/>
  <circle cx="34" cy="38" r="1.8" fill="currentColor" opacity="0.7"/>
  <circle cx="48" cy="28" r="1.4" fill="currentColor" opacity="0.5"/>
</svg>
''';

/// Slide 3: camera try-on — a phone framing a foot with a laced sneaker
/// settling onto it, a scan beam, focus corners and a fitted check badge.
const String _arSvg = '''
<svg viewBox="0 0 200 200" fill="none" xmlns="http://www.w3.org/2000/svg">
  <!-- Ground shadow -->
  <ellipse cx="100" cy="184" rx="42" ry="5" fill="currentColor" opacity="0.12"/>
  <!-- Focus corners around the phone -->
  <path d="M36,62 L36,46 L52,46" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>
  <path d="M164,62 L164,46 L148,46" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>
  <path d="M36,142 L36,158 L52,158" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>
  <path d="M164,142 L164,158 L148,158" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>
  <!-- Phone frame -->
  <rect x="58" y="22" width="84" height="158" rx="16"
        stroke="currentColor" stroke-width="3" fill="none"/>
  <rect x="66" y="36" width="68" height="130" rx="6"
        stroke="currentColor" stroke-width="1" opacity="0.5" fill="none"/>
  <circle cx="100" cy="29" r="2" fill="currentColor"/>
  <!-- Foot inside the screen -->
  <path d="M88,148 C86,140 84,130 86,120 C87,112 87,104 91,99 C94,95 98,96 100,99 C102,96 106,95 108,97 C111,99 110,103 109,106 C111,112 113,122 112,134 C111,142 110,146 109,148"
        stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>
  <!-- Scan beam -->
  <rect x="72" y="112" width="56" height="14" rx="7"
        fill="currentColor" opacity="0.08"/>
  <path d="M72,119 L128,119" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
  <path d="M72,113 v-4 M128,113 v-4 M72,125 v-4 M128,125 v-4"
        stroke="currentColor" stroke-width="1.5" stroke-linecap="round" opacity="0.7"/>
  <!-- Sneaker settling onto the foot -->
  <path d="M74,140 C88,146 116,146 130,139 L132,131 C118,137 88,137 76,131 Z"
        stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
  <path d="M80,131 C82,120 90,113 101,111 L117,112 C124,113 128,119 129,127"
        stroke="currentColor" stroke-width="2.25" stroke-linecap="round" fill="none"/>
  <path d="M94,121 l7,-3 M92,127 l7,-3 M90,133 l7,-3"
        stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <path d="M108,116 C114,118 118,122 119,128"
        stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-dasharray="3 2.5" opacity="0.6" fill="none"/>
  <!-- Placement motion arc -->
  <path d="M136,108 C142,116 143,128 139,138"
        stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-dasharray="4 3.5" opacity="0.55" fill="none"/>
  <!-- Fitted check badge -->
  <circle cx="148" cy="150" r="13" fill="currentColor" opacity="0.12"/>
  <circle cx="148" cy="150" r="13" stroke="currentColor" stroke-width="2" fill="none"/>
  <path d="M142.5,150 l4,4 l7,-8" stroke="currentColor" stroke-width="2.25" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
  <!-- Sparkles -->
  <path d="M44,96 v8 M40,100 h8" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <circle cx="158" cy="92" r="1.8" fill="currentColor" opacity="0.7"/>
  <circle cx="46" cy="120" r="1.4" fill="currentColor" opacity="0.5"/>
</svg>
''';
