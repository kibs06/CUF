import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_constants.dart';

/// A destructive-action button that enforces a 5-second cooldown before it
/// becomes tappable. The button fills left-to-right with the active color
/// over the cooldown period, then bounces to signal it's ready.
///
/// ```dart
/// CountdownDeleteButton(
///   onConfirm: () => _deleteOrder(orderId),
///   label: 'Delete',
///   duration: const Duration(seconds: 5),
/// )
/// ```
class CountdownDeleteButton extends StatefulWidget {
  /// Called when the user taps the button after the cooldown completes.
  final VoidCallback onConfirm;

  /// Button label. Defaults to `'Delete'`.
  final String label;

  /// Cooldown duration. Defaults to 5 seconds.
  final Duration duration;

  /// Fully saturated "ready" color. Defaults to [AppConstants.error].
  final Color activeColor;

  /// Muted / desaturated starting color before the cooldown completes.
  final Color inactiveColor;

  /// Background color behind the fill. Same as [inactiveColor] by default.
  final Color trackColor;

  const CountdownDeleteButton({
    super.key,
    required this.onConfirm,
    this.label = 'Delete',
    this.duration = const Duration(seconds: 5),
    this.activeColor = AppConstants.error,
    this.inactiveColor = const Color(0xFF9E7E7E),
    Color? trackColor,
  }) : trackColor = trackColor ?? inactiveColor;

  @override
  State<CountdownDeleteButton> createState() => _CountdownDeleteButtonState();
}

class _CountdownDeleteButtonState extends State<CountdownDeleteButton>
    with TickerProviderStateMixin {
  late final AnimationController _fillController;
  late final AnimationController _bounceController;
  late final Animation<double> _bounceScale;
  bool _ready = false;
  bool _reducedMotion = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();

    // ── Fill controller ────────────────────────────────────────────
    _fillController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _fillController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _ready = true);
        HapticFeedback.mediumImpact();
        if (!_reducedMotion) {
          _bounceController.forward(from: 0);
        }
      }
    });

    // ── Bounce controller (scale 1 → 1.03 → 1 on completion) ──────
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _bounceScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.03), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.03, end: 1.0), weight: 60),
    ]).animate(CurvedAnimation(
      parent: _bounceController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    _reducedMotion = MediaQuery.of(context).disableAnimations;

    if (_reducedMotion) {
      // Skip the fill animation — just wait 5 seconds then enable
      Future.delayed(widget.duration, () {
        if (mounted) {
          setState(() => _ready = true);
          HapticFeedback.mediumImpact();
        }
      });
    } else {
      _fillController.forward();
    }
  }

  @override
  void dispose() {
    _fillController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!_ready) return;
    HapticFeedback.mediumImpact();
    widget.onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_fillController, _bounceController]),
      builder: (context, child) {
        final progress = _reducedMotion ? 1.0 : _fillController.value;
        final isEnabled = _ready;

        return GestureDetector(
          onTap: _handleTap,
          child: AnimatedScale(
            scale: _reducedMotion ? 1.0 : _bounceScale.value,
            duration: const Duration(milliseconds: 100),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              height: 44,
              decoration: BoxDecoration(
                color: _ready ? widget.activeColor : widget.trackColor,
                borderRadius: BorderRadius.circular(22),
                boxShadow: _ready
                    ? [
                        BoxShadow(
                          color: widget.activeColor.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // ── Left-to-right fill overlay ────────────────────
                    if (!_reducedMotion)
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: progress,
                            child: Container(
                              decoration: BoxDecoration(
                                color: widget.activeColor,
                              ),
                            ),
                          ),
                        ),
                      ),

                    // ── Label ─────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        widget.label,
                        style: AppConstants.bodyStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),

                    // ── Subtle shimmer line during countdown ──────────
                    if (!isEnabled && !_reducedMotion)
                      Positioned.fill(
                        child: _ShimmerLine(progress: progress),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A thin bright line that sweeps across the button during the fill,
/// giving the button a "charging" feel instead of a flat color fade.
class _ShimmerLine extends StatelessWidget {
  final double progress;

  const _ShimmerLine({required this.progress});

  @override
  Widget build(BuildContext context) {
    // The shimmer sits at the leading edge of the fill
    final xPos = progress;
    return Align(
      alignment: Alignment(-1.0 + 2.0 * xPos, 0),
      child: Container(
        width: 3,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.0),
              Colors.white.withValues(alpha: 0.25),
              Colors.white.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}
