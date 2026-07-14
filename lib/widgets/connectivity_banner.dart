import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../services/connectivity_service.dart';

/// Non-blocking banner that appears at the top of the screen when
/// connectivity is lost mid-session. Auto-dismisses with a brief
/// "Back online" confirmation when restored.
class ConnectivityBanner extends StatefulWidget {
  final Widget child;

  const ConnectivityBanner({super.key, required this.child});

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  StreamSubscription? _sub;

  /// Current banner state: null = hidden, false = offline, true = back online
  bool? _bannerState;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    // Start listening to connectivity changes
    final service = ConnectivityService.instance;
    _sub = service.isOnlineStream.listen(_onConnectivityChanged);

    // Set initial state
    if (!service.isOnline) {
      _bannerState = false;
      _controller.value = 1.0;
    }
  }

  void _onConnectivityChanged(bool isOnline) {
    if (!mounted) return;

    if (!isOnline) {
      // Connection lost — show offline banner
      _dismissTimer?.cancel();
      setState(() => _bannerState = false);
      _controller.forward();
    } else {
      // Connection restored — briefly show "Back online", then dismiss
      setState(() => _bannerState = true);
      _controller.forward();
      _dismissTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          _controller.reverse().then((_) {
            if (mounted) setState(() => _bannerState = null);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _sub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_bannerState != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, -60 * (1 - _animation.value)),
                  child: Opacity(
                    opacity: _animation.value,
                    child: child,
                  ),
                );
              },
              child: _buildBanner(),
            ),
          ),
      ],
    );
  }

  Widget _buildBanner() {
    final isOffline = _bannerState == false;

    return SafeArea(
      bottom: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isOffline
              ? AppConstants.statusPendingColor.withValues(alpha: 0.95)
              : AppConstants.okStockColor.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              isOffline ? Icons.wifi_off_rounded : Icons.check_circle_outline,
              size: 18,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isOffline ? 'No internet connection' : 'Back online',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
