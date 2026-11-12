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
                          label: 'Page ${_currentPage + 1} of $_totalPages',
                          excludeSemantics: true,
                          child: Row(
                            children: [
                              Text(
                                '${_currentPage + 1} / $_totalPages',
                                style: AppConstants.monoStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppConstants.secondary.withValues(
                                    alpha: 0.55,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ...List.generate(
                                _totalPages,
                                (index) => Expanded(
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeOut,
                                    height: 4,
                                    margin: EdgeInsets.only(
                                      right: index < _totalPages - 1 ? 6 : 0,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(2),
                                      color: index <= _currentPage
                                          ? AppConstants.primary
                                          : AppConstants.secondary.withValues(
                                              alpha: 0.15,
                                            ),
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
                          // The sticker disc lives inside the SVG (opaque sand,
                          // flat craft colours); the stitched ring circles it
                          // like a welt. No tint filter any more — the art
                          // carries its own palette on both brightnesses.
                          // Stitched ring
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: CustomPaint(
                              size: const Size(228, 228),
                              painter: _StitchRingPainter(
                                AppConstants.primary.withValues(alpha: 0.45),
                              ),
                            ),
                          ),
                          // Line art
                          SizedBox(
                            width: 198,
                            height: 198,
                            child: SvgPicture.string(data.svg),
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
                      color: AppConstants.secondary.withValues(alpha: 0.65),
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
                          icon:
                              _bulletIcons[data.bullets[i].icon] ??
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
          offset = (pageController.page ?? currentPage.toDouble()) - index;
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

/// Slide 1: hand-stitched leather sandal, side profile — flat clipart:
/// espresso sole, tan footbed, clay straps with cream stitching, brass
/// buckle, needle-and-thread arc.
const String _welcomeSvg = '''
<svg viewBox="0 0 200 200" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="100" cy="100" r="78" fill="#F4E4C8"/>
  <circle cx="100" cy="100" r="78" stroke="#8B5A2B" stroke-width="2.5" fill="none"/>
  <!-- Ground shadow -->
  <ellipse cx="100" cy="158" rx="44" ry="6" fill="#3A2415" opacity="0.18"/>
  <!-- Outsole slab -->
  <path d="M48,140 C64,150 136,150 154,138 L152,128 C136,138 66,138 50,130 Z"
        fill="#3A2415"/>
  <path d="M50,135 C66,143 134,143 152,133"
        stroke="#FFF8EC" stroke-width="1.5" stroke-linecap="round" opacity="0.8" fill="none"/>
  <!-- Footbed -->
  <path d="M56,130 C70,136 130,136 146,128 L142,120 C126,126 74,126 60,122 Z"
        fill="#D9A45B"/>
  <!-- Back strap (clay band + cream stitch) -->
  <path d="M78,128 C80,106 90,92 102,90"
        stroke="#8B5A2B" stroke-width="11" stroke-linecap="round" fill="none"/>
  <path d="M78,128 C80,106 90,92 102,90"
        stroke="#FFF8EC" stroke-width="1.5" stroke-linecap="round" stroke-dasharray="3.5 3" fill="none"/>
  <!-- Front strap -->
  <path d="M110,128 C112,108 122,96 138,94"
        stroke="#8B5A2B" stroke-width="11" stroke-linecap="round" fill="none"/>
  <path d="M110,128 C112,108 122,96 138,94"
        stroke="#FFF8EC" stroke-width="1.5" stroke-linecap="round" stroke-dasharray="3.5 3" fill="none"/>
  <!-- Brass buckle -->
  <rect x="120" y="98" width="15" height="12" rx="3.5"
        fill="#B5622E" stroke="#3A2415" stroke-width="2"/>
  <circle cx="127.5" cy="104" r="1.8" fill="#FFF8EC"/>
  <!-- Needle and thread -->
  <path d="M36,106 Q54,80 88,76"
        stroke="#B5622E" stroke-width="2" stroke-linecap="round" fill="none"/>
  <path d="M88,76 L100,68" stroke="#3A2415" stroke-width="2.5" stroke-linecap="round"/>
  <circle cx="101" cy="67" r="1.8" fill="#3A2415"/>
  <!-- Sparkles -->
  <path d="M152,44 v10 M147,49 h10" stroke="#8B5A2B" stroke-width="2" stroke-linecap="round"/>
  <circle cx="134" cy="38" r="2" fill="#8B5A2B"/>
  <circle cx="164" cy="64" r="1.6" fill="#8B5A2B" opacity="0.6"/>
</svg>
''';

/// Slide 2: artisan boutique, flat clipart — cream facade, clay/cream
/// striped awning, espresso door, clay shoes on stands, sage planters.
const String _storefrontSvg = '''
<svg viewBox="0 0 200 200" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="100" cy="100" r="78" fill="#F4E4C8"/>
  <circle cx="100" cy="100" r="78" stroke="#8B5A2B" stroke-width="2.5" fill="none"/>
  <!-- Ground shadow + line -->
  <ellipse cx="100" cy="168" rx="58" ry="6" fill="#3A2415" opacity="0.18"/>
  <path d="M30,168 L170,168" stroke="#3A2415" stroke-width="2.5" stroke-linecap="round"/>
  <!-- Facade -->
  <rect x="48" y="60" width="104" height="108" rx="6"
        fill="#FFF8EC" stroke="#3A2415" stroke-width="3"/>
  <!-- Cornice -->
  <rect x="42" y="50" width="116" height="12" rx="4"
        fill="#8B5A2B" stroke="#3A2415" stroke-width="2.5"/>
  <!-- Striped awning with scallops -->
  <path d="M56,72 L144,72 L140,90 Q134,96 128,90 Q122,96 116,90 Q110,96 104,90 Q98,96 92,90 Q86,96 80,90 Q74,96 68,90 Q62,96 58,90 Z"
        fill="#FFF8EC" stroke="#3A2415" stroke-width="2.5" stroke-linejoin="round"/>
  <path d="M76,72 L74,90 M96,72 L95,91 M104,72 L105,91 M124,72 L126,90"
        stroke="#3A2415" stroke-width="1.5" stroke-linecap="round" opacity="0.45"/>
  <path d="M84,72 L83,90.5 M116,72 L117,90.5"
        stroke="#B5622E" stroke-width="7" opacity="0.75"/>
  <!-- Hanging sign -->
  <path d="M92,90 v6 M108,90 v6" stroke="#3A2415" stroke-width="2" stroke-linecap="round"/>
  <rect x="79" y="96" width="42" height="18" rx="9"
        fill="#8B5A2B" stroke="#3A2415" stroke-width="2"/>
  <path d="M89,105 C92,102.5 96,102.5 98,105 M100,105 C102,102.5 106,102.5 109,105"
        stroke="#FFF8EC" stroke-width="1.75" stroke-linecap="round" fill="none"/>
  <circle cx="113" cy="105" r="1.6" fill="#FFF8EC"/>
  <!-- Door -->
  <rect x="89" y="120" width="22" height="48" rx="2.5"
        fill="#3A2415"/>
  <rect x="93" y="124" width="14" height="18" rx="1.5"
        stroke="#FFF8EC" stroke-width="1.5" opacity="0.7" fill="none"/>
  <rect x="93" y="145" width="14" height="18" rx="1.5"
        stroke="#FFF8EC" stroke-width="1.5" opacity="0.7" fill="none"/>
  <circle cx="105" cy="144" r="2" fill="#C98A2C"/>
  <!-- Lanterns -->
  <circle cx="66" cy="104" r="3" fill="#C98A2C" stroke="#3A2415" stroke-width="1.5"/>
  <circle cx="134" cy="104" r="3" fill="#C98A2C" stroke="#3A2415" stroke-width="1.5"/>
  <!-- Left window: clay shoe on a stand -->
  <rect x="56" y="120" width="26" height="32" rx="3"
        fill="#E9DCC3" stroke="#3A2415" stroke-width="2.5"/>
  <path d="M60,142 C62,135 66,133 70,135 L75,139 L60,139 Z"
        fill="#8B5A2B"/>
  <path d="M64,139 v4 M71,139 v4" stroke="#3A2415" stroke-width="1.5" stroke-linecap="round"/>
  <!-- Right window: clay shoe on a stand -->
  <rect x="118" y="120" width="26" height="32" rx="3"
        fill="#E9DCC3" stroke="#3A2415" stroke-width="2.5"/>
  <path d="M122,142 C124,135 128,133 132,135 L137,139 L122,139 Z"
        fill="#8B5A2B"/>
  <path d="M126,139 v4 M133,139 v4" stroke="#3A2415" stroke-width="1.5" stroke-linecap="round"/>
  <!-- Planters -->
  <path d="M36,156 L46,156 L44,168 L38,168 Z"
        fill="#B5622E" stroke="#3A2415" stroke-width="2" stroke-linejoin="round"/>
  <path d="M41,156 C39,148 35,145 31,144 M41,156 C41,148 43,143 47,141 M41,156 v-10"
        stroke="#5B7A52" stroke-width="2" stroke-linecap="round" fill="none"/>
  <path d="M154,156 L164,156 L162,168 L160,168 Z"
        fill="#B5622E" stroke="#3A2415" stroke-width="2" stroke-linejoin="round"/>
  <path d="M159,156 C157,148 153,145 149,144 M159,156 C159,148 161,143 165,141 M159,156 v-10"
        stroke="#5B7A52" stroke-width="2" stroke-linecap="round" fill="none"/>
</svg>
''';

/// Slide 3: camera try-on, flat clipart — espresso phone with a cream
/// screen, tan foot, clay sneaker with cream sole and laces, rust scan
/// beam, clay focus corners, sage fitted badge.
const String _arSvg = '''
<svg viewBox="0 0 200 200" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="100" cy="100" r="78" fill="#F4E4C8"/>
  <circle cx="100" cy="100" r="78" stroke="#8B5A2B" stroke-width="2.5" fill="none"/>
  <!-- Ground shadow -->
  <ellipse cx="100" cy="180" rx="40" ry="5" fill="#3A2415" opacity="0.18"/>
  <!-- Focus corners -->
  <path d="M40,60 L40,46 L54,46" stroke="#8B5A2B" stroke-width="2.5" stroke-linecap="round" fill="none"/>
  <path d="M160,60 L160,46 L146,46" stroke="#8B5A2B" stroke-width="2.5" stroke-linecap="round" fill="none"/>
  <path d="M40,140 L40,154 L54,154" stroke="#8B5A2B" stroke-width="2.5" stroke-linecap="round" fill="none"/>
  <path d="M160,140 L160,154 L146,154" stroke="#8B5A2B" stroke-width="2.5" stroke-linecap="round" fill="none"/>
  <!-- Phone -->
  <rect x="62" y="28" width="76" height="148" rx="15"
        fill="#3A2415"/>
  <rect x="69" y="41" width="62" height="122" rx="5"
        fill="#FFF8EC"/>
  <circle cx="100" cy="34.5" r="2" fill="#FFF8EC" opacity="0.85"/>
  <!-- Foot -->
  <path d="M90,144 C88,136 86,126 88,116 C89,108 89,102 93,97 C96,93 100,94 102,98 C104,94 108,93 110,95 C113,97 112,101 111,104 C113,110 115,120 114,132 C113,140 112,143 111,144 Z"
        fill="#E8CF9F" stroke="#3A2415" stroke-width="2" stroke-linejoin="round"/>
  <!-- Scan beam -->
  <rect x="74" y="110" width="52" height="14" rx="7"
        fill="#B5622E" opacity="0.20"/>
  <path d="M74,117 L126,117" stroke="#B5622E" stroke-width="2.5" stroke-linecap="round"/>
  <!-- Sneaker upper -->
  <path d="M78,132 C80,120 88,112 100,110 L118,111 C125,112 129,117 130,126 L131,132 Z"
        fill="#8B5A2B" stroke="#3A2415" stroke-width="2.5" stroke-linejoin="round"/>
  <path d="M94,120 l8,-3 M92,126 l8,-3 M90,132 l8,-3"
        stroke="#FFF8EC" stroke-width="2" stroke-linecap="round"/>
  <!-- Sneaker sole -->
  <path d="M76,132 C90,138 114,138 130,132 L128,140 C112,145 90,145 78,140 Z"
        fill="#FFF8EC" stroke="#3A2415" stroke-width="2" stroke-linejoin="round"/>
  <!-- Placement motion arc -->
  <path d="M136,104 C142,112 143,124 139,134"
        stroke="#8B5A2B" stroke-width="2" stroke-linecap="round" stroke-dasharray="4 3.5" fill="none"/>
  <!-- Fitted check badge -->
  <circle cx="144" cy="152" r="13" fill="#5B7A52" stroke="#3A2415" stroke-width="2"/>
  <path d="M138.5,152 l4,4 l7,-8" stroke="#FFF8EC" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
  <!-- Sparkles -->
  <path d="M48,92 v8 M44,96 h8" stroke="#8B5A2B" stroke-width="2" stroke-linecap="round"/>
  <circle cx="154" cy="88" r="2" fill="#8B5A2B"/>
</svg>
''';
