import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';

/// A segmented one-time-code input: [length] individual single-character
/// boxes in a horizontal row, with the caret position shown by an
/// accent-coloured border instead of a blinking text cursor.
///
/// Three states, all carried by border weight/colour plus fill — never by
/// opacity: empty (hairline, no fill), holding a digit (stronger neutral edge
/// + light fill), and focused (accent edge). Each box is its own [TextField]
/// with its own controller and focus node, which is what makes the row six
/// separate targets rather than one widget that merely looks divided.
///
/// Every colour below is an `AppConstants` token: the app ships a single light
/// theme (`main.dart` pins both color schemes to `Brightness.light`), so there
/// is no dark variant to branch on — and none is invented here.
///
/// Why separate boxes rather than one masked field: the position of the next
/// digit is legible at a glance, which is the whole point of a code screen —
/// the old single field needed a decorative `letterSpacing` to fake the same
/// information.
///
/// Behaviour it owns:
///  * digits only, auto-advancing focus as each box fills;
///  * backspace in an EMPTY box steps back and clears the previous one
///    (an empty field emits no `onChanged`, so that case has to be caught as
///    a key event — see [_OtpCodeFieldState._onKey]);
///  * pasting a whole code into any box redistributes it across the row;
///  * [onCompleted] fires once the last digit lands, so the caller can
///    auto-submit;
///  * each box announces its position to screen readers
///    ("Digit 2 of 6").
///
/// Purely presentational: it never validates, submits or knows what the code
/// is for. The caller reads [OtpCodeFieldState.code] or listens to
/// [onChanged]/[onCompleted].
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    this.length = 6,
    this.onChanged,
    this.onCompleted,
    this.enabled = true,
    this.hasError = false,
    this.autofocus = true,
    this.semanticLabelPrefix = 'Digit',
  });

  /// How many boxes to render. The screen's `EmailOtpPolicy.codeLength` is the
  /// source of truth for the real value; this default is only a convenience.
  final int length;

  /// Fires on every edit with the digits entered so far (missing boxes are
  /// omitted, so the value is a prefix of the full code, not padded).
  final ValueChanged<String>? onChanged;

  /// Fires once, when every box holds a digit.
  final ValueChanged<String>? onCompleted;

  final bool enabled;

  /// Paints every box in the error colour — set while a rejection is on
  /// screen so the row itself shows what the message is about.
  final bool hasError;

  /// Focus the first box on mount.
  final bool autofocus;

  /// Leading word for each box's screen-reader label.
  final String semanticLabelPrefix;

  @override
  State<OtpCodeField> createState() => OtpCodeFieldState();
}

class OtpCodeFieldState extends State<OtpCodeField> {
  /// Box geometry.
  ///
  /// Six 48px boxes plus five 8px gaps is 328px, which is exactly what a
  /// 360dp phone has left inside the page's 16px gutters — so on a normal
  /// phone every box reaches the intended 48x56, and the width stays a
  /// *ceiling* rather than a fixed size: [build] measures the row and shrinks
  /// the boxes instead of painting an overflow stripe on a narrow one (the
  /// 320dp floor still yields ~41px boxes). Height is fixed at 56 so the tap
  /// target — and the digit — survives the squeeze: this is a deliberate
  /// primary target, not a compact form field.
  static const double _maxBoxWidth = 48;
  static const double _minBoxWidth = 32;
  static const double _boxHeight = 56;
  static const double _gap = 8;
  static const double _radius = 12;

  /// 1.5px hairlines. The box has NO fill until it holds a digit, so state is
  /// carried by border weight/colour + fill rather than by opacity.
  static const double _borderWidth = 1.5;

  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;

  /// Set while WE rewrite a controller, so the resulting listener callback
  /// does not re-enter the redistribution logic and fight user input.
  bool _rewriting = false;

  @override
  void initState() {
    super.initState();
    _createBoxes();
  }

  @override
  void dispose() {
    _disposeBoxes();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OtpCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The row length is structural — rebuild the boxes rather than leaving
    // stray controllers behind.
    if (oldWidget.length != widget.length) {
      _disposeBoxes();
      _createBoxes();
    }
  }

  void _createBoxes() {
    _controllers =
        List<TextEditingController>.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List<FocusNode>.generate(widget.length, (_) => FocusNode());
  }

  void _disposeBoxes() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
  }

  /// The digits entered so far. Never padded — `'12'` means two digits are in,
  /// not that four boxes are blank mid-code.
  String get code => _controllers.map((c) => c.text.trim()).join();

  /// True once every box holds a digit.
  bool get isComplete => code.length == widget.length;

  /// Empties the row and returns the caret to the first box. Used after a
  /// resend, and after a rejected code so the user can re-key immediately.
  void clear({bool focusFirst = true}) {
    _rewriting = true;
    for (final controller in _controllers) {
      controller.clear();
    }
    _rewriting = false;
    if (!mounted) return;
    if (focusFirst && _focusNodes.isNotEmpty) {
      _focusNodes.first.requestFocus();
    }
    setState(() {});
  }

  void _notify() {
    final value = code;
    widget.onChanged?.call(value);
    if (value.length == widget.length) widget.onCompleted?.call(value);
  }

  void _setBox(int index, String value) {
    _rewriting = true;
    _controllers[index].value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _rewriting = false;
  }

  void _focusAt(int index) {
    if (index < 0 || index >= widget.length) return;
    _focusNodes[index].requestFocus();
  }

  /// Digits only, in entry order. A single box can legitimately receive more
  /// than one digit when the user pastes the whole code.
  static String _digitsOnly(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');

  void _onBoxChanged(int index, String raw) {
    if (_rewriting) return;
    final digits = _digitsOnly(raw);

    // A paste (or a fast keyboard) drops the whole code into one box, so
    // spread it from here rather than trying to limit the field length —
    // a length formatter would truncate the paste and lose the code.
    if (digits.length > 1) {
      var cursor = index;
      for (final digit in digits.split('')) {
        if (cursor >= widget.length) break;
        _setBox(cursor, digit);
        cursor++;
      }
      _focusAt(cursor < widget.length ? cursor : widget.length - 1);
      setState(() {});
      _notify();
      return;
    }

    if (digits.isEmpty) {
      setState(() {});
      _notify();
      return;
    }

    _setBox(index, digits);
    if (index < widget.length - 1) _focusAt(index + 1);
    setState(() {});
    _notify();
  }

  /// Backspace inside an EMPTY box is the only signal that the user wants to
  /// walk backwards: an empty field produces no `onChanged`, so it has to be
  /// caught as a key event. A non-empty box returns [KeyEventResult.ignored]
  /// and lets the field delete its own digit normally.
  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    if (_controllers[index].text.isNotEmpty) return KeyEventResult.ignored;
    if (index == 0) return KeyEventResult.ignored;

    _setBox(index - 1, '');
    _focusAt(index - 1);
    setState(() {});
    _notify();
    return KeyEventResult.handled;
  }

  /// Empty and unfocused: the app's default border token, no fill.
  BorderSide get _idleSide => BorderSide(
        color: widget.hasError
            ? AppConstants.error
            : AppConstants.borderGray,
        width: _borderWidth,
      );

  /// Holds a digit: a slightly stronger neutral edge (plus the fill below), so
  /// a settled digit reads as settled at a glance.
  BorderSide get _filledSide => BorderSide(
        color: widget.hasError
            ? AppConstants.error
            : AppConstants.secondary.withValues(alpha: 0.20),
        width: _borderWidth,
      );

  /// The box currently accepting input. Accent, so the active box is legible
  /// without relying on the blinking caret alone.
  BorderSide get _focusSide => BorderSide(
        color: widget.hasError ? AppConstants.error : AppConstants.primary,
        width: _borderWidth,
      );

  OutlineInputBorder _borderWith(BorderSide side) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: side,
      );

  Widget _box(int index, double width) {
    // Drives the "settled" state. Safe to read in build: every mutation of a
    // controller ends in setState (single digit, paste, backspace, [clear]).
    final hasDigit = _controllers[index].text.isNotEmpty;
    return Semantics(
      label: '${widget.semanticLabelPrefix} ${index + 1} of ${widget.length}',
      child: Focus(
        // This node must NOT take focus (the TextField owns it), but key
        // events still bubble up through it from the focused field.
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) => _onKey(index, event),
        child: SizedBox(
          width: width,
          height: _boxHeight,
          child: TextField(
            key: ValueKey<String>('otp-box-$index'),
            controller: _controllers[index],
            focusNode: _focusNodes[index],
            enabled: widget.enabled,
            autofocus: widget.autofocus && index == 0,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            cursorColor: AppConstants.primary,
            // No maxLength: it would clip a pasted code before we can
            // redistribute it.
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: AppConstants.bodyStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              counterText: '',
              isDense: true,
              contentPadding: EdgeInsets.zero,
              // Fill marks a SETTLED digit, not a rendered field: an empty box
              // is a bare outline (see [_idleSide]).
              filled: hasDigit,
              fillColor: AppConstants.surfaceSubtle,
              border: _borderWith(_idleSide),
              enabledBorder: _borderWith(hasDigit ? _filledSide : _idleSide),
              disabledBorder: _borderWith(_idleSide),
              focusedBorder: _borderWith(_focusSide),
            ),
            onChanged: (value) => _onBoxChanged(index, value),
            onSubmitted: (_) {
              if (isComplete) widget.onCompleted?.call(code);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Shrink the boxes rather than overflow: the row must fit whatever
        // width the page gives it (see [_maxBoxWidth]).
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _maxBoxWidth * widget.length + _gap * (widget.length - 1);
        final gaps = _gap * (widget.length - 1);
        final perBox = (available - gaps) / widget.length;
        final boxWidth = perBox.clamp(_minBoxWidth, _maxBoxWidth).toDouble();

        final children = <Widget>[];
        for (var i = 0; i < widget.length; i++) {
          if (i > 0) children.add(const SizedBox(width: _gap));
          children.add(_box(i, boxWidth));
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: children,
        );
      },
    );
  }
}
