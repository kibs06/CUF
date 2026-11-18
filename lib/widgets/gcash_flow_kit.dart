import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';

/// Shared visual primitives for the manual-GCash flow.
///
/// The buyer's pay screen, the seller's verification queue and the seller's
/// payout history are one workflow, so they share one surface language with
/// the admin portal's GCash screens: a mono eyebrow over a display title, a
/// double-bezel card (tray, then face), pill CTAs with the icon living in its
/// own circle, mono numerals for money, and a staggered fade-up on entry.
///
/// Every widget here paints from [AppConstants] so both brightnesses resolve
/// correctly. The espresso "money" surfaces use fixed brand tones on purpose:
/// they read as a receipt in light and dark alike, and white-on-espresso is
/// the one pairing whose contrast never moves.
const Curve kGcashEase = Cubic(0.32, 0.72, 0, 1);

/// Ink for anything painted on an espresso receipt surface. Public because a
/// screen sometimes needs to style a string-typed amount directly instead of
/// going through [GcashPanel]'s title slot.
const Color kGcashReceiptInk = Color(0xFFF5F0EB);
const Color kGcashReceiptMuted = Color(0xFFC4A882);
const Color kGcashReceiptWarn = Color(0xFFF2C14E);

const Color _espressoTray = Color(0xFF22150C);
const Color _espressoFace = Color(0xFF3A2415);
const Color _espressoInk = kGcashReceiptInk;
const Color _espressoMuted = kGcashReceiptMuted;

/// Mono eyebrow + display title + one specific line.
class GcashFlowHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? description;
  final Widget? trailing;

  const GcashFlowHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.description,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: AppConstants.monoStyle(
                  fontSize: 10,
                  color: AppConstants.secondary.withValues(alpha: 0.55),
                ).copyWith(letterSpacing: 2.2, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: AppConstants.headlineStyle(fontSize: 27)
                    .copyWith(height: 1.08),
              ),
              if (description != null) ...[
                const SizedBox(height: 8),
                Text(
                  description!,
                  style: AppConstants.bodyStyle(
                    fontSize: 12.5,
                    height: 1.42,
                    color: AppConstants.secondary.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

/// Double-bezel panel: an outer tray, then the machined face that holds ink.
///
/// [dark] paints the money surfaces (receipt amount, expected amount). It is
/// not a theme mode — it is the same espresso card in light and dark.
class GcashPanel extends StatelessWidget {
  final String? eyebrow;
  final String? title;
  final String? description;
  final Widget child;
  final Widget? trailing;
  final bool dark;
  final EdgeInsetsGeometry padding;
  final Color? faceColor;

  const GcashPanel({
    super.key,
    this.eyebrow,
    this.title,
    this.description,
    required this.child,
    this.trailing,
    this.dark = false,
    this.padding = const EdgeInsets.all(18),
    this.faceColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: dark
            ? _espressoTray
            : AppConstants.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.10)
              : AppConstants.primary.withValues(alpha: 0.07),
        ),
      ),
      padding: const EdgeInsets.all(6),
      child: Container(
        decoration: BoxDecoration(
          color: faceColor ?? (dark ? _espressoFace : AppConstants.surfaceLight),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: dark
                ? Colors.white.withValues(alpha: 0.12)
                : AppConstants.borderGray,
          ),
          boxShadow: dark
              ? const <BoxShadow>[]
              : AppConstants.warmShadow,
        ),
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow != null || title != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (eyebrow != null)
                          Text(
                            eyebrow!.toUpperCase(),
                            style: AppConstants.monoStyle(
                              fontSize: 9.5,
                              color: dark
                                  ? _espressoMuted
                                  : AppConstants.secondary
                                      .withValues(alpha: 0.55),
                            ).copyWith(letterSpacing: 1.9),
                          ),
                        if (title != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            title!,
                            style: AppConstants.headlineStyle(
                              fontSize: 19,
                              color: dark ? _espressoInk : null,
                            ).copyWith(height: 1.15),
                          ),
                        ],
                        if (description != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            description!,
                            style: AppConstants.bodyStyle(
                              fontSize: 11.5,
                              height: 1.38,
                              color: dark
                                  ? _espressoMuted
                                  : AppConstants.secondary
                                      .withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 10),
                    trailing!,
                  ],
                ],
              ),
              const SizedBox(height: 16),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Full pill CTA with the icon nested in its own circle inside the pill.
class GcashPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final Color? background;
  final bool expand;
  final bool loading;

  /// False drops the trailing icon circle and centres the label — for a pill
  /// whose action is the only thing on it ("Submit proof"), where an arrow
  /// promises a next step that is the same button.
  final bool showIcon;
  final String? semanticsLabel;

  const GcashPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward,
    this.background,
    this.expand = true,
    this.loading = false,
    this.showIcon = true,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final fill = background ?? AppConstants.primary;
    final enabled = onPressed != null && !loading;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: semanticsLabel ?? label,
      onTap: enabled ? onPressed : null,
      child: Material(
        color: enabled ? fill : fill.withValues(alpha: 0.45),
        borderRadius: AppConstants.stadiumRadius,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          excludeFromSemantics: true,
          borderRadius: AppConstants.stadiumRadius,
          child: Container(
            height: 52,
            width: expand ? double.infinity : null,
            padding: showIcon
                ? const EdgeInsets.only(left: 20, right: 6)
                : const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: showIcon
                  ? MainAxisAlignment.spaceBetween
                  : MainAxisAlignment.center,
              children: [
                Flexible(
                  child: loading
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppConstants.inkInverse,
                            ),
                          ),
                        )
                      : Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: showIcon
                              ? TextAlign.start
                              : TextAlign.center,
                          style: AppConstants.bodyStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppConstants.inkInverse,
                          ),
                        ),
                ),
                if (showIcon) ...[
                  const SizedBox(width: 10),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 17, color: AppConstants.inkInverse),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Slide-to-confirm pill: the thumb must reach the far edge before the action
/// fires, and letting go early settles it back to rest.
///
/// It exists for the decisions where a stray tap would cost money — the
/// seller's "pay me now" is the first — so the gesture is deliberate without
/// putting a dialog between the seller and one button. [onConfirm] is awaited:
/// while it runs the thumb holds at the end with a spinner, then settles back.
///
/// A slide is not something a screen reader can perform, so [Semantics.onTap]
/// exposes the same action as a plain activation.
class GcashSlideToConfirm extends StatefulWidget {
  final String label;
  final String? busyLabel;
  final String? disabledLabel;
  final IconData icon;
  final bool enabled;
  final bool busy;
  final Color? background;
  final String? semanticsLabel;
  final Future<void> Function() onConfirm;

  const GcashSlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirm,
    this.busyLabel,
    this.disabledLabel,
    this.icon = Icons.arrow_forward,
    this.enabled = true,
    this.busy = false,
    this.background,
    this.semanticsLabel,
  });

  @override
  State<GcashSlideToConfirm> createState() => _GcashSlideToConfirmState();
}

class _GcashSlideToConfirmState extends State<GcashSlideToConfirm>
    with SingleTickerProviderStateMixin {
  static const double _height = 52;
  static const double _inset = 6;
  static const double _thumb = 40;

  /// How far the thumb may travel, measured by [build]. The gesture reads it;
  /// nothing writes it back, so a rotation or a wider phone just re-measures.
  double _travel = 0;
  double _drag = 0;
  bool _firing = false;
  double _settleFrom = 0;

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(() {
      if (!mounted) return;
      setState(() => _drag = _settleFrom * (1 - _settle.value));
    });

  bool get _locked => !widget.enabled || widget.busy;

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _start(DragStartDetails _) {
    if (_locked) return;
    _settle.stop();
  }

  void _move(DragUpdateDetails details) {
    if (_locked) return;
    setState(() => _drag = (_drag + details.delta.dx).clamp(0.0, _travel));
  }

  void _end(DragEndDetails _) {
    if (_locked) return;
    // One pixel of slack: a thumb parked on the end must not need a second
    // push to fire.
    if (_travel > 0 && _drag >= _travel - 1) {
      _confirm();
    } else {
      _settleBack();
    }
  }

  void _settleBack() {
    if (_drag <= 0) return;
    _settleFrom = _drag;
    _settle.forward(from: 0);
  }

  Future<void> _confirm() async {
    if (_locked || _firing) return;
    _firing = true;
    HapticFeedback.mediumImpact();
    setState(() => _drag = _travel);
    try {
      await widget.onConfirm();
    } finally {
      _firing = false;
      if (mounted) _settleBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fill = widget.background ?? AppConstants.primary;
    final interactive = widget.enabled && !widget.busy;
    final hint = widget.busy
        ? (widget.busyLabel ?? 'Working…')
        : widget.enabled
        ? widget.label
        : (widget.disabledLabel ?? widget.label);
    return Semantics(
      container: true,
      button: true,
      enabled: interactive,
      label: widget.semanticsLabel ?? hint,
      onTap: interactive ? _confirm : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _travel = (constraints.maxWidth - (_inset * 2) - _thumb).clamp(
            0.0,
            double.infinity,
          );
          final position = _drag.clamp(0.0, _travel);
          final progress = _travel == 0 ? 0.0 : position / _travel;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onHorizontalDragStart: _start,
            onHorizontalDragUpdate: _move,
            onHorizontalDragEnd: _end,
            onHorizontalDragCancel: _settleBack,
            child: Container(
              height: _height,
              decoration: BoxDecoration(
                color: interactive ? fill : fill.withValues(alpha: 0.45),
                borderRadius: AppConstants.stadiumRadius,
              ),
              child: Stack(
                children: [
                  // The trail the thumb uncovers as it travels.
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: (_thumb + _inset + position).clamp(
                      0.0,
                      constraints.maxWidth,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: AppConstants.stadiumRadius,
                      ),
                    ),
                  ),
                  // The hint dims as the thumb closes on the far edge, so the
                  // last stretch reads as "almost there".
                  Positioned.fill(
                    child: Center(
                      child: Opacity(
                        opacity: (1 - progress * 0.85).clamp(0.0, 1.0),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: _thumb + 18,
                          ),
                          child: Text(
                            hint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: AppConstants.bodyStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: widget.enabled
                                  ? AppConstants.inkInverse
                                  : AppConstants.inkInverse.withValues(
                                      alpha: 0.7,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // The thumb.
                  Positioned(
                    left: _inset + position,
                    top: _inset,
                    child: Container(
                      width: _thumb,
                      height: _thumb,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: widget.busy
                          ? Center(
                              child: SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppConstants.inkInverse,
                                  ),
                                ),
                              ),
                            )
                          : Icon(
                              widget.icon,
                              size: 17,
                              color: AppConstants.inkInverse,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Outlined pill for the secondary decision (reject, cancel, retry).
class GcashGhostPill extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final bool expand;

  const GcashGhostPill({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final ink = color ?? AppConstants.secondary;
    final enabled = onPressed != null;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: label,
      onTap: onPressed,
      child: Material(
        color: Colors.transparent,
        borderRadius: AppConstants.stadiumRadius,
        child: InkWell(
          onTap: onPressed,
          excludeFromSemantics: true,
          borderRadius: AppConstants.stadiumRadius,
          child: Container(
            height: 52,
            width: expand ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              borderRadius: AppConstants.stadiumRadius,
              border: Border.all(color: ink.withValues(alpha: enabled ? 0.4 : 0.2)),
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: ink.withValues(alpha: 0.9)),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppConstants.bodyStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: ink.withValues(alpha: enabled ? 1 : 0.45),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small state chip (Active, Paid, Flagged, Closed).
class GcashStatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const GcashStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 11, color: color)
          else
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 5),
          Text(
            label.toUpperCase(),
            style: AppConstants.monoStyle(fontSize: 9.5, color: color)
                .copyWith(letterSpacing: 1.1, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Inset well for grouped facts, inside a [GcashPanel].
class GcashInsetTile extends StatelessWidget {
  final Widget child;
  final Color? color;

  const GcashInsetTile({super.key, required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color ?? AppConstants.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppConstants.primary.withValues(alpha: 0.10),
        ),
      ),
      child: child,
    );
  }
}

/// One label/value fact. The value wraps instead of overflowing, which is
/// what keeps a 13-digit reference readable on a 320 dp phone.
class GcashFactRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool mono;

  const GcashFactRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.mono = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label.toUpperCase(),
              style: AppConstants.monoStyle(
                fontSize: 9.5,
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ).copyWith(letterSpacing: 1.1),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              softWrap: true,
              style: mono
                  ? AppConstants.monoStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: valueColor ??
                          AppConstants.secondary.withValues(alpha: 0.9),
                    )
                  : AppConstants.bodyStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: valueColor ?? AppConstants.secondary,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Label above a mono value with a copy affordance in its own circle.
class GcashCopyRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onCopy;
  final String? semanticsLabel;

  const GcashCopyRow({
    super.key,
    required this.label,
    required this.value,
    this.onCopy,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: AppConstants.monoStyle(
                  fontSize: 9.5,
                  color: AppConstants.secondary.withValues(alpha: 0.5),
                ).copyWith(letterSpacing: 1.4),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                softWrap: true,
                style: AppConstants.bodyStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        if (onCopy != null) ...[
          const SizedBox(width: 8),
          Semantics(
            container: true,
            button: true,
            label: semanticsLabel ?? 'Copy $label',
            onTap: onCopy,
            child: Material(
              color: AppConstants.primary.withValues(alpha: 0.08),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onCopy,
                excludeFromSemantics: true,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.content_copy_rounded,
                    size: 17,
                    color: AppConstants.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Staggered fade-up on entry. Transform + opacity only, and it stands down
/// when the platform asks for reduced motion.
class GcashRiseIn extends StatefulWidget {
  final Widget child;
  final int order;
  final int stepMs;
  final Duration duration;

  const GcashRiseIn({
    super.key,
    required this.child,
    this.order = 0,
    this.stepMs = 60,
    this.duration = const Duration(milliseconds: 420),
  });

  @override
  State<GcashRiseIn> createState() => _GcashRiseInState();
}

class _GcashRiseInState extends State<GcashRiseIn> {
  bool _shown = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final reduce =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations;
    if (reduce) {
      _shown = true;
      return;
    }
    _timer = Timer(Duration(milliseconds: widget.order * widget.stepMs), () {
      if (!mounted) return;
      setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: widget.duration,
      curve: kGcashEase,
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(0, 0.05),
        duration: widget.duration,
        curve: kGcashEase,
        child: widget.child,
      ),
    );
  }
}

/// Inline banner for a rejection reason, an expired window or a mismatch.
class GcashBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const GcashBanner({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppConstants.bodyStyle(
                fontSize: 12,
                height: 1.35,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
