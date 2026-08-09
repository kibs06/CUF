import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class ARViewPlaceholder extends StatefulWidget {
  final Widget? arView;

  const ARViewPlaceholder({
    super.key,
    this.arView,
  });

  @override
  State<ARViewPlaceholder> createState() => _ARViewPlaceholderState();
}

class _ARViewPlaceholderState extends State<ARViewPlaceholder> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.arView != null) {
      return widget.arView!;
    }

    return Container(
      color: AppConstants.surfaceDark,
      child: Stack(
        children: [
          // Background guidelines / simulated target
          Center(
            child: Container(
              width: 220,
              height: 320,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppConstants.accent.withValues(alpha: 0.3),
                  width: 2,
                  style: BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Stack(
                children: [
                  // Corner brackets
                  _buildCorner(Alignment.topLeft),
                  _buildCorner(Alignment.topRight),
                  _buildCorner(Alignment.bottomLeft),
                  _buildCorner(Alignment.bottomRight),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.fit_screen_outlined,
                          color: AppConstants.accent.withValues(alpha: 0.5),
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Place Foot Inside Box',
                          style: AppConstants.bodyStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.surfaceLight.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Animated Scan Line
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Positioned(
                top: MediaQuery.of(context).size.height * 0.2 +
                    (MediaQuery.of(context).size.height * 0.5 * _animation.value),
                left: 20,
                right: 20,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppConstants.accent,
                    boxShadow: [
                      BoxShadow(
                        color: AppConstants.accent.withValues(alpha: 0.8),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          
          // Outer overlay hints
          Positioned(
            bottom: 240,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Simulating AR Foundation Camera Feed...',
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  color: AppConstants.surfaceLight.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCorner(Alignment alignment) {
    const double size = 20;
    const double thickness = 4;
    final double top = (alignment == Alignment.topLeft || alignment == Alignment.topRight) ? 0 : double.nan;
    final double bottom = (alignment == Alignment.bottomLeft || alignment == Alignment.bottomRight) ? 0 : double.nan;
    final double left = (alignment == Alignment.topLeft || alignment == Alignment.bottomLeft) ? 0 : double.nan;
    final double right = (alignment == Alignment.topRight || alignment == Alignment.bottomRight) ? 0 : double.nan;

    return Positioned(
      top: top.isNaN ? null : top,
      bottom: bottom.isNaN ? null : bottom,
      left: left.isNaN ? null : left,
      right: right.isNaN ? null : right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: Border(
            top: (top == 0)
                ? const BorderSide(color: AppConstants.accent, width: thickness)
                : BorderSide.none,
            bottom: (bottom == 0)
                ? const BorderSide(color: AppConstants.accent, width: thickness)
                : BorderSide.none,
            left: (left == 0)
                ? const BorderSide(color: AppConstants.accent, width: thickness)
                : BorderSide.none,
            right: (right == 0)
                ? const BorderSide(color: AppConstants.accent, width: thickness)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
