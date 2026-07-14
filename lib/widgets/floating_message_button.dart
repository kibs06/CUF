import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../providers/message_provider.dart';
import 'messages_quick_preview_sheet.dart';

/// A draggable floating chat button that lives on the CustomerHomeScreen.
///
/// - Freely draggable anywhere on screen via pan gesture
/// - Snaps to nearest horizontal edge on release
/// - Persists position across app sessions via SharedPreferences
/// - Shows unread badge when conversations have unread messages
/// - Tapping opens a quick-preview bottom sheet
///
/// Computes safe bounds internally using [MediaQuery] — no external params needed.
class FloatingMessageButton extends StatefulWidget {
  const FloatingMessageButton({super.key});

  @override
  State<FloatingMessageButton> createState() => _FloatingMessageButtonState();
}

class _FloatingMessageButtonState extends State<FloatingMessageButton>
    with TickerProviderStateMixin {
  // ── Position state ──────────────────────────────────────────────
  double _x = 0;
  double _y = 0;
  bool _initialized = false;

  // ── Drag state ──────────────────────────────────────────────────
  bool _isDragging = false;
  double _dragStartX = 0;
  double _dragStartY = 0;
  double _buttonStartX = 0;
  double _buttonStartY = 0;
  static const _dragThreshold = 8.0; // px movement before treated as drag

  // ── Animation ───────────────────────────────────────────────────
  late AnimationController _snapAnimController;
  Animation<double>? _snapXAnim;
  Animation<double>? _snapYAnim;

  // ── Badge state ─────────────────────────────────────────────────
  int _unreadCount = 0;
  late AnimationController _badgePulseController;

  // ── Layout constants ────────────────────────────────────────────
  static const double _buttonSize = 50;
  static const double _badgeSize = 18;
  static const double _edgePadding = 12;
  static const double _appBarHeight = kToolbarHeight; // 56dp
  static const String _prefsKey = 'floating_chat_button_position';

  @override
  void initState() {
    super.initState();

    // Snap animation
    _snapAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (_snapXAnim != null && _snapYAnim != null && mounted) {
          setState(() {
            _x = _snapXAnim!.value;
            _y = _snapYAnim!.value;
          });
        }
      });

    // Badge pulse animation
    _badgePulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      lowerBound: 0.0,
      upperBound: 1.0,
    );

    // Compute default position synchronously so the button is visible immediately.
    // Uses MediaQueryData.fromView since MediaQuery.of(context) isn't available in initState.
    _setDefaultPosition();

    // Load saved position in a post-frame callback (async SharedPreferences)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPosition();
    });
  }

  @override
  void dispose() {
    _snapAnimController.dispose();
    _badgePulseController.dispose();
    super.dispose();
  }

  // ── Body bounds helpers ────────────────────────────────────────

  /// Screen size (full device screen).
  Size get _screenSize => MediaQuery.of(context).size;

  /// Safe-area padding (status bar inset).
  double get _statusBarHeight => MediaQuery.of(context).padding.top;

  /// Bottom nav height (NavigationBar default is ~80dp).
  double get _bottomNavHeight => 80;

  /// Body height = screen height minus status bar, AppBar, and bottom nav.
  double get _bodyHeight =>
      _screenSize.height - _statusBarHeight - _appBarHeight - _bottomNavHeight;

  /// Body width = screen width (full width).
  double get _bodyWidth => _screenSize.width;

  // ── Position persistence ──────────────────────────────────────

  /// Set default position immediately (synchronous, no await).
  /// Bottom-right, leaving room for the bottom nav bar.
  void _setDefaultPosition() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final screen = MediaQueryData.fromView(view).size;
    final bodyH = screen.height - _appBarHeight - _bottomNavHeight;
    setState(() {
      _x = screen.width - _buttonSize - _edgePadding;
      _y = bodyH - _buttonSize - 100;
      _initialized = true;
    });
  }

  Future<void> _loadPosition() async {
    if (!mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_prefsKey);
      if (data != null && mounted) {
        final parts = data.split(',');
        if (parts.length == 3) {
          final edge = parts[0]; // 'left' or 'right'
          final y = double.tryParse(parts[1]);
          final screenW = double.tryParse(parts[2]);
          if (y != null && screenW != null) {
            setState(() {
              _x = edge == 'left'
                  ? _edgePadding
                  : screenW - _buttonSize - _edgePadding;
              _y = y;
            });
            // Re-clamp in case screen size changed
            _clampAndUpdate();
            return;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _savePosition() async {
    if (!mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final edge = _x < (_bodyWidth / 2) ? 'left' : 'right';
      await prefs.setString(_prefsKey, '$edge,$_y,$_bodyWidth');
    } catch (_) {}
  }



  // ── Clamp to safe bounds ──────────────────────────────────────

  /// Clamp position to the body area.
  /// minY = 0 (top of body, already below AppBar).
  /// maxY = bodyHeight - buttonSize - small padding (above bottom nav).
  Offset _clampPosition(double rawX, double rawY) {
    final maxX = _bodyWidth - _buttonSize - _edgePadding;
    final maxY = _bodyHeight - _buttonSize - _edgePadding;
    final minX = _edgePadding;
    const minY = 0.0; // Stack is already below the AppBar

    return Offset(
      rawX.clamp(minX, maxX),
      rawY.clamp(minY, maxY),
    );
  }

  /// Re-clamp current position after layout changes (e.g., screen rotation).
  void _clampAndUpdate() {
    final clamped = _clampPosition(_x, _y);
    if (clamped.dx != _x || clamped.dy != _y) {
      setState(() {
        _x = clamped.dx;
        _y = clamped.dy;
      });
    }
  }

  // ── Snap to nearest edge ──────────────────────────────────────

  void _snapToEdge() {
    final minX = _edgePadding;
    final maxX = _bodyWidth - _buttonSize - _edgePadding;
    final snapLeft = _x + (_buttonSize / 2) < (_bodyWidth / 2);
    final targetX = snapLeft ? minX : maxX;
    final targetY = _y; // keep vertical position

    _snapXAnim = Tween<double>(begin: _x, end: targetX).animate(
      CurvedAnimation(parent: _snapAnimController, curve: Curves.easeOutBack),
    );
    _snapYAnim = Tween<double>(begin: _y, end: targetY).animate(
      CurvedAnimation(parent: _snapAnimController, curve: Curves.easeOutBack),
    );
    _snapAnimController.forward(from: 0.0).then((_) {
      _savePosition();
    });
  }

  // ── Gesture handling ──────────────────────────────────────────

  void _onPanStart(DragStartDetails details) {
    _snapAnimController.stop();
    _dragStartX = details.localPosition.dx;
    _dragStartY = details.localPosition.dy;
    _buttonStartX = _x;
    _buttonStartY = _y;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final dx = details.localPosition.dx - _dragStartX;
    final dy = details.localPosition.dy - _dragStartY;

    if (!_isDragging) {
      if (dx.abs() > _dragThreshold || dy.abs() > _dragThreshold) {
        _isDragging = true;
      } else {
        return;
      }
    }

    final clamped = _clampPosition(
      _buttonStartX + dx,
      _buttonStartY + dy,
    );

    setState(() {
      _x = clamped.dx;
      _y = clamped.dy;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isDragging) {
      _isDragging = false;
      _snapToEdge();
    }
    // If not dragging, it was a tap — handled by GestureDetector.onTap
  }

  void _onTap() {
    if (_isDragging) return;
    _showQuickPreview();
  }

  // ── Quick preview sheet ───────────────────────────────────────

  void _showQuickPreview() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const MessagesQuickPreviewSheet(),
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return const SizedBox.shrink();

    // Single source of truth for unread count — use provider's total.
    final provider = context.watch<MessageProvider>();
    final total = provider.totalUnreadCount;
    // Trigger pulse when count increases (new messages arrived)
    if (total > _unreadCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _badgePulseController.forward(from: 0.0);
      });
    }
    _unreadCount = total;

    return Positioned(
      left: _x,
      top: _y,
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onTap: _onTap,
        child: Semantics(
          label: 'Messages',
          button: true,
          child: AnimatedScale(
            scale: _isDragging ? 1.1 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: _buildButton(),
          ),
        ),
      ),
    );
  }

  Widget _buildButton() {
    return Container(
      width: _buttonSize,
      height: _buttonSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppConstants.primary,
        boxShadow: [
          BoxShadow(
            color: AppConstants.primary.withValues(alpha: 0.30),
            blurRadius: 14,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Chat icon
          const Center(
            child: Icon(
              Icons.chat_bubble_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          // Unread badge
          if (_unreadCount > 0)
            Positioned(
              top: -4,
              right: -4,
              child: AnimatedBuilder(
                animation: _badgePulseController,
                builder: (context, child) {
                  final scale = 1.0 + (_badgePulseController.value * 0.25);
                  return Transform.scale(
                    scale: scale,
                    child: child,
                  );
                },
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: _badgeSize,
                    minHeight: _badgeSize,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: AppConstants.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      _unreadCount > 9 ? '9+' : '$_unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
