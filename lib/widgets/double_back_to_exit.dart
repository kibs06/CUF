import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Double-press back to exit, for the customer and seller shells.
///
/// A root shell sits at the bottom of the navigator, so a single stray back
/// press would otherwise kill the app with no warning. The first press only
/// names what a second one will do; a second press inside [grace] exits via
/// [SystemNavigator.pop]. A press after the grace lapses starts over.
///
/// Pushed pages are untouched: this guards its own route, so a detail page on
/// top of the shell still pops normally on the first press.
class DoubleBackToExit extends StatefulWidget {
  const DoubleBackToExit({
    super.key,
    required this.child,
    this.message = 'Press back again to exit',
    this.grace = const Duration(seconds: 2),
  });

  final Widget child;

  /// What the first press says. Kept plain text on purpose — it is a
  /// transient hint, not a branded moment.
  final String message;

  /// How long the second press still counts as "again".
  final Duration grace;

  @override
  State<DoubleBackToExit> createState() => _DoubleBackToExitState();
}

class _DoubleBackToExitState extends State<DoubleBackToExit> {
  DateTime? _firstPressAt;

  void _onPopInvoked(bool didPop) {
    if (didPop) return;
    final now = DateTime.now();
    final first = _firstPressAt;
    if (first != null && now.difference(first) <= widget.grace) {
      SystemNavigator.pop();
      return;
    }
    _firstPressAt = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(widget.message),
          duration: widget.grace,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onPopInvoked(didPop),
      child: widget.child,
    );
  }
}
