import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../utils/dev_mode.dart';
import '../../widgets/auth/signup_scaffold.dart';
import '../../widgets/auth/sole_primary_auth_button.dart';
import '../customer/customer_shell.dart';

/// Locked screen for seller applicants awaiting admin approval.
///
/// Shown right after the application is submitted (AuthGate routes here
/// while `seller_status == pending`). The design walks the applicant
/// through what happens next — application received → verification →
/// certified CUFMAI member — highlighting their actual current status from
/// `profiles.seller_status`, lists exactly what was received (tight,
/// divider-separated rows), and demotes the optional Tier 2 business
/// verification so it reads as low-priority info rather than a peer of the
/// core content.
class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen>
    with SingleTickerProviderStateMixin {
  /// Drives the gentle pulse of the hero's medallion halo while the
  /// application sits in review.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  late final Animation<double> _ring =
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = auth.profile ?? const <String, dynamic>{};

    // ⚠️ DEV MODE — REMOVE BEFORE RELEASE (docs/AI/DEV_MODE_ARCHITECTURE.md).
    // No account exists in dev mode, so there's no profile to check —
    // default every "received" row to checked so the dev previews the
    // screen as a real applicant would see it.
    final devPreview = DevMode.instance.isEnabled;
    final firstName = _firstName(auth.displayName);
    final hasId = devPreview || _notEmpty(profile['id_document_url']);
    final hasSelfie = devPreview || _notEmpty(profile['selfie_url']);
    final hasCommunity =
        devPreview ||
        _notEmpty(profile['cufmai_member_id']) ||
        _notEmpty(profile['barangay_proof_url']);
    final hasStore = devPreview || _notEmpty(profile['store_name']);
    final productPaths = profile['product_photo_urls'];
    final hasStorePhotos =
        devPreview ||
        _notEmpty(profile['store_front_url']) ||
        (productPaths is List && productPaths.isNotEmpty);

    // Timeline highlighting is driven by the applicant's REAL status (not
    // hardcoded): while pending, step 1 (received) is done, step 2
    // (verification) is in progress, step 3 (certified member) is next.
    final sellerStatus =
        profile['seller_status']?.toString() ?? AppConstants.statusPending;
    final steps = _timelineStepsFor(sellerStatus);

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AuthSpacing.s24,
                AuthSpacing.s24,
                AuthSpacing.s24,
                AuthSpacing.s40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ⚠️ DEV MODE — REMOVE BEFORE RELEASE: unmistakably a
                  // debug element (dark, monospace), never shown in a
                  // production build (DevMode defaults off).
                  if (devPreview) ...[
                    const _DevPreviewBanner(),
                    const SizedBox(height: AuthSpacing.s16),
                  ],

                  // ── Header card: badge + status + heading ────
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.92, end: 1),
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutBack,
                    builder: (context, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: _SubmissionHeader(ring: _ring),
                  ),
                  const SizedBox(height: AuthSpacing.s20),

                  // ── Intro paragraph (below the card) ──────────
                  Text.rich(
                    TextSpan(
                      style: AppConstants.bodyStyle(
                        fontSize: 14,
                        color: AppConstants.secondary.withValues(alpha: 0.7),
                        height: 1.5,
                      ),
                      children: [
                        TextSpan(
                          text:
                              'Thanks, $firstName! We’re verifying your '
                              'identity, store, and product photos. Once '
                              'approved, you’ll be a ',
                        ),
                        const TextSpan(
                          text: 'certified CUFMAI member',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(
                          text:
                              ' with your own seller dashboard.',
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AuthSpacing.s24),

                  // ── What happens next (single instance) ───────
                  const _SectionLabel('WHAT HAPPENS NEXT'),
                  const SizedBox(height: AuthSpacing.s8),
                  _TimelineCard(steps: steps),
                  const SizedBox(height: AuthSpacing.s20),

                  // ── What we received (tight divider rows) ─────
                  _ReceivedList(
                    children: [
                      _ReceivedRow(
                        icon: Icons.person_outline,
                        label: 'Full name & contact details',
                        done: true,
                      ),
                      _ReceivedRow(
                        icon: Icons.badge_outlined,
                        label: 'Government ID photo',
                        done: hasId,
                      ),
                      _ReceivedRow(
                        icon: Icons.face_outlined,
                        label: 'Liveness selfie',
                        done: hasSelfie,
                      ),
                      _ReceivedRow(
                        icon: Icons.groups_outlined,
                        label: 'CUFMAI membership / barangay proof',
                        done: hasCommunity,
                      ),
                      _ReceivedRow(
                        icon: Icons.storefront_outlined,
                        label: 'Store name & description',
                        done: hasStore,
                      ),
                      _ReceivedRow(
                        icon: Icons.store_mall_directory_outlined,
                        label: 'Store front & product photos',
                        done: hasStorePhotos,
                      ),
                    ],
                  ),
                  const SizedBox(height: AuthSpacing.s16),

                  // ── Optional Tier 2 (visually secondary) ──────
                  const _Tier2Card(),
                  const SizedBox(height: AuthSpacing.s24),

                  // ── Actions ───────────────────────────────────
                  SolePrimaryAuthButton(
                    label: 'Back to home',
                    onPressed: () {
                      final navigator = Navigator.of(context);
                      // Dev preview: this screen was pushed over the app's
                      // landing — "Back to home" pops back to it. Real
                      // pending state: this screen IS the root (AuthGate
                      // locks the app here), so push the customer home
                      // instead — the applicant can browse stores while
                      // their application is under review, and the back
                      // gesture returns them to this status screen.
                      if (navigator.canPop()) {
                        navigator.pop();
                      } else {
                        navigator.push(
                          MaterialPageRoute(
                            builder: (_) => const CustomerShell(),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _notEmpty(dynamic value) =>
      value != null && value.toString().trim().isNotEmpty;

  String _firstName(String fullName) {
    final first = fullName.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? 'there' : first;
  }
}

/// Maps an applicant's `seller_status` to the three timeline step states.
/// This screen only ever renders while `pending` (AuthGate locks the app
/// to it), but the mapping stays honest for every status so highlighting
/// is driven by state, never by a hardcoded build.
List<_TimelineStepState> _timelineStepsFor(String status) {
  switch (status) {
    case AppConstants.statusApproved:
      return const [
        _TimelineStepState.completed,
        _TimelineStepState.completed,
        _TimelineStepState.completed,
      ];
    case AppConstants.statusRejected:
      // The application was received but went no further — the applicant
      // re-applies via the flow, not this screen.
      return const [
        _TimelineStepState.completed,
        _TimelineStepState.upcoming,
        _TimelineStepState.upcoming,
      ];
    default:
      // pending (and any unknown value): received ✓ → verification in
      // progress → certified member next.
      return const [
        _TimelineStepState.completed,
        _TimelineStepState.current,
        _TimelineStepState.upcoming,
      ];
  }
}

enum _TimelineStepState { completed, current, upcoming }

/// ⚠️ DEV MODE — REMOVE BEFORE RELEASE. Deliberately styled outside the
/// app's design language (dark background, diagonal hazard stripes,
/// monospace gold text) so it can never be mistaken for product UI. Only
/// rendered while dev mode is enabled, which defaults to off in
/// production.
class _DevPreviewBanner extends StatelessWidget {
  const _DevPreviewBanner();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          // Diagonal hazard stripes
          Positioned.fill(
            child: CustomPaint(
              painter: _HazardStripesPainter(
                color: const Color(0xFF8B5A2B).withValues(alpha: 0.35),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: const Color(0xFF1D1813),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.bug_report_rounded,
                  size: 15,
                  color: Color(0xFFF59E0B),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'DEV PREVIEW · NO ACCOUNT CREATED',
                    textAlign: TextAlign.center,
                    style: AppConstants.monoStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFF59E0B),
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

/// Paints faint diagonal hazard stripes over the dev banner's background.
class _HazardStripesPainter extends CustomPainter {
  final Color color;

  _HazardStripesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 6;
    const spacing = 14.0;
    for (double x = -size.height; x < size.width + size.height; x += spacing) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HazardStripesPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The white header card: a large brown badge with a soft pulsing halo,
/// the "UNDER ADMIN REVIEW" eyebrow, and the serif "Application submitted"
/// heading all in one compact element (mockup: cufmai_status_redesign).
class _SubmissionHeader extends StatelessWidget {
  final Animation<double> ring;

  const _SubmissionHeader({required this.ring});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AuthSpacing.s24, vertical: AuthSpacing.s24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.premiumCardRadius,
        border: Border.all(
          color: AppConstants.borderGray.withValues(alpha: 0.5),
        ),
        boxShadow: AppConstants.premiumCardShadow,
      ),
      child: Column(
        children: [
          // Badge with soft pulsing halo
          SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: ring,
                  builder: (context, child) {
                    final t = ring.value;
                    return Transform.scale(
                      scale: 1 + t * 0.08,
                      child: Opacity(opacity: 1 - t * 0.4, child: child),
                    );
                  },
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppConstants.statusPendingColor.withValues(
                        alpha: 0.14,
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppConstants.primary,
                    boxShadow: [
                      BoxShadow(
                        color: AppConstants.primary.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.verified_user_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AuthSpacing.s16),
          Text(
            'UNDER ADMIN REVIEW',
            style: AppConstants.bodyStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: AppConstants.statusPendingColor,
            ),
          ),
          const SizedBox(height: AuthSpacing.s8),
          Text(
            'Application submitted',
            textAlign: TextAlign.center,
            style: AppConstants.headlineStyle(fontSize: 28),
          ),
        ],
      ),
    );
  }
}

/// Small uppercase section label used above the timeline and received
/// lists (e.g. "WHAT HAPPENS NEXT", "WHAT WE RECEIVED").
class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppConstants.bodyStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppConstants.secondary.withValues(alpha: 0.55),
      ),
    );
  }
}

/// The "What happens next" card — rendered exactly once, with each step
/// styled by its state (done / in progress / upcoming).
class _TimelineCard extends StatelessWidget {
  final List<_TimelineStepState> steps;

  const _TimelineCard({required this.steps});

  @override
  Widget build(BuildContext context) {
    final stepData = [
      (
        title: 'Application received',
        caption: 'Your ID, selfie, store photos, and community proof are in.',
      ),
      (
        title: 'Verification',
        caption:
            'We confirm you’re a real Carcar shoe artisan — usually within '
            'a few days.',
      ),
      (
        title: 'Certified CUFMAI member',
        caption:
            'Approved — your seller dashboard opens and you can start selling.',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(AuthSpacing.s16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppConstants.premiumCardRadius,
        boxShadow: AppConstants.premiumCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < stepData.length; i++)
            _TimelineStepRow(
              stepNumber: i + 1,
              title: stepData[i].title,
              caption: stepData[i].caption,
              state: steps.length > i ? steps[i] : _TimelineStepState.upcoming,
              isLast: i == stepData.length - 1,
            ),
        ],
      ),
    );
  }
}

/// One timeline row. Completed = green check; current = amber medallion +
/// "In progress" tag; upcoming = muted/grayed out.
class _TimelineStepRow extends StatelessWidget {
  final int stepNumber;
  final String title;
  final String caption;
  final _TimelineStepState state;
  final bool isLast;

  const _TimelineStepRow({
    required this.stepNumber,
    required this.title,
    required this.caption,
    required this.state,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final muted =
        state == _TimelineStepState.upcoming
            ? AppConstants.secondary.withValues(alpha: 0.4)
            : AppConstants.secondary;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Rail: state medallion + connector line
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: switch (state) {
                      _TimelineStepState.completed =>
                        AppConstants.success,
                      _TimelineStepState.current =>
                        AppConstants.primary,
                      _TimelineStepState.upcoming =>
                        AppConstants.borderGray.withValues(alpha: 0.5),
                    },
                    boxShadow: state == _TimelineStepState.current
                        ? [
                            BoxShadow(
                              color: AppConstants.primary.withValues(
                                alpha: 0.3,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: state == _TimelineStepState.completed
                        ? const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: Colors.white,
                          )
                        : Text(
                            '$stepNumber',
                            style: AppConstants.bodyStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: state == _TimelineStepState.upcoming
                                  ? AppConstants.secondary.withValues(
                                      alpha: 0.5,
                                    )
                                  : Colors.white,
                            ),
                          ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: state == _TimelineStepState.completed
                          ? AppConstants.success.withValues(alpha: 0.4)
                          : AppConstants.borderGray.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AuthSpacing.s12),
          // Copy
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AuthSpacing.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: AppConstants.bodyStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: muted,
                          ),
                        ),
                      ),
                      if (state == _TimelineStepState.current) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppConstants.statusPendingColor.withValues(
                              alpha: 0.16,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'IN PROGRESS',
                            style: AppConstants.bodyStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: const Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                      if (state == _TimelineStepState.completed) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 15,
                          color: AppConstants.success,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    style: AppConstants.bodyStyle(
                      fontSize: 12.5,
                      color: AppConstants.secondary.withValues(
                        alpha: state == _TimelineStepState.upcoming ? 0.35 : 0.7,
                      ),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "What we received" — a tight list of divider-separated rows instead of
/// a heavy bordered card, so it doesn't compete with the core content.
class _ReceivedList extends StatelessWidget {
  final List<Widget> children;

  const _ReceivedList({required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('WHAT WE RECEIVED'),
        const SizedBox(height: AuthSpacing.s8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AuthSpacing.s12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppConstants.borderGray.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1) const _DashedDivider(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A thin horizontal dashed divider (the mockup shows the received rows
/// separated by faint dashed lines).
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 1),
      painter: _DashedLinePainter(
        color: AppConstants.borderGray.withValues(alpha: 0.5),
      ),
    );
  }
}

/// Paints a single dashed horizontal line.
class _DashedLinePainter extends CustomPainter {
  final Color color;

  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const dashLength = 4.0;
    const gapLength = 3.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + dashLength, 0),
        paint,
      );
      x += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ReceivedRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool done;

  const _ReceivedRow({
    required this.icon,
    required this.label,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AuthSpacing.s12),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: done
                ? AppConstants.success
                : AppConstants.secondary.withValues(alpha: 0.35),
          ),
          const SizedBox(width: AuthSpacing.s12),
          Expanded(
            child: Text(
              label,
              style: AppConstants.bodyStyle(
                fontSize: 13,
                color: done
                    ? AppConstants.secondary
                    : AppConstants.secondary.withValues(alpha: 0.45),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: done
                ? const Icon(
                    Icons.check_circle_rounded,
                    key: ValueKey('done'),
                    size: 19,
                    color: AppConstants.success,
                  )
                : const Icon(
                    Icons.radio_button_unchecked_rounded,
                    key: ValueKey('pending'),
                    size: 19,
                    color: AppConstants.borderGray,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Optional Tier 2 business verification — visually secondary: dashed
/// border, no filled background, muted copy, so it reads as genuinely
/// optional rather than a peer of the core content.
class _Tier2Card extends StatelessWidget {
  const _Tier2Card();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: AppConstants.borderGray.withValues(alpha: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AuthSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Optional · Business verification (Tier 2)',
              style: AppConstants.bodyStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppConstants.secondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add your DTI certificate, BIR COR, or mayor’s/barangay permit '
              'later from Profile → Settings. Never required to sell.',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.55),
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimal dashed rounded-rectangle border (Flutter has no built-in dashed
/// border without a package).
class _DashedBorderPainter extends CustomPainter {
  final Color color;

  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const dashLength = 5.0;
    const gapLength = 4.0;
    const strokeWidth = 1.2;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(16),
        ),
      );

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashLength),
          paint,
        );
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
