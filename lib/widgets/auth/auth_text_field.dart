import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import 'signup_scaffold.dart';

/// Premium text field for the signup flows.
///
/// Extends the app's existing SoleTextField visual language (bold 14 label,
/// filled white, 12px radius, 1px gray border) with the things the design
/// spec calls for on the auth screens:
///
///  * **Inline validation icons** — as the user types, the suffix shows a
///    green check once the input is valid or a red error icon while it
///    isn't (not just red text after submit).
///  * **Animated error text** — the FormField error is displayed with an
///    icon and animated in with AnimatedSwitcher.
///  * **Password show/hide toggle** with a screen-reader label.
///
/// Autocorrect + suggestions are OFF by default: auth forms collect
/// structured data (names, emails, passwords, IDs) that autocorrect would
/// fight, and the keyboard's per-word spell-check underline under that text
/// reads as a stray yellow underline. Pass `autocorrect`/`enableSuggestions`
/// explicitly to re-enable on genuinely prose fields.
///
/// Drop it inside a `Form` like any `TextFormField` — `Form.validate()`
/// still drives the submit-time error text.
class AuthTextField extends StatefulWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final bool obscureText;
  final bool passwordField;
  final TextInputType keyboardType;
  final IconData? prefixIcon;
  final String? Function(String?)? validator;
  final bool readOnly;
  final VoidCallback? onTap;
  final int maxLines;
  final Iterable<String>? autofillHints;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFieldSubmitted;
  final bool autocorrect;
  final bool enableSuggestions;

  const AuthTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.obscureText = false,
    this.passwordField = false,
    this.keyboardType = TextInputType.text,
    this.prefixIcon,
    this.validator,
    this.readOnly = false,
    this.onTap,
    this.maxLines = 1,
    this.autofillHints,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.onFieldSubmitted,
    // See the class doc: auth fields are structured data entry, and the
    // keyboard's per-word spell-check underline must not appear here.
    this.autocorrect = false,
    this.enableSuggestions = false,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  late final bool _ownsController;
  late final TextEditingController _controller;
  bool _obscure = true;

  /// Live validation error computed as the user types, so the suffix icon
  /// (and inline error) react immediately instead of only on submit.
  String? _liveError;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_onTextChanged);
    if (widget.obscureText && widget.passwordField) _obscure = widget.obscureText;
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final error = widget.validator?.call(_controller.text);
    if (error != _liveError) {
      setState(() => _liveError = error);
    }
    widget.onChanged?.call(_controller.text);
  }

  Widget? _buildSuffix() {
    if (widget.passwordField) {
      final show = !_obscure;
      return IconButton(
        onPressed: () => setState(() => _obscure = !_obscure),
        tooltip: show ? 'Hide password' : 'Show password',
        icon: Icon(
          show ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: 20,
          color: AppConstants.primary,
        ),
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      );
    }

    final text = _controller.text;
    if (text.isEmpty) return null;
    final hasError = _liveError != null;
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: Icon(
          hasError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
          key: ValueKey(hasError),
          size: 18,
          color: hasError ? AppConstants.error : AppConstants.success,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: AppConstants.borderGray.withValues(alpha: 0.6),
        width: 1,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: AppConstants.bodyStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppConstants.secondary,
          ),
        ),
        const SizedBox(height: AuthSpacing.s8),
        TextFormField(
          controller: _controller,
          obscureText: widget.obscureText && (widget.passwordField ? _obscure : true),
          keyboardType: widget.keyboardType,
          readOnly: widget.readOnly,
          onTap: widget.onTap,
          maxLines: widget.maxLines,
          autofillHints: widget.autofillHints,
          textInputAction: widget.textInputAction,
          onFieldSubmitted: (_) => widget.onFieldSubmitted?.call(),
          autocorrect: widget.autocorrect,
          enableSuggestions: widget.enableSuggestions,
          style: AppConstants.bodyStyle(
            fontSize: 15,
            color: AppConstants.secondary,
          ),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: AppConstants.bodyStyle(
              fontSize: 14,
              color: AppConstants.secondary.withValues(alpha: 0.45),
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            prefixIcon: widget.prefixIcon != null
                ? Icon(
                    widget.prefixIcon,
                    color: AppConstants.primary,
                    size: 20,
                  )
                : null,
            suffixIcon: _buildSuffix(),
            border: border,
            enabledBorder: border,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppConstants.primary,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppConstants.error,
                width: 1.5,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppConstants.error,
                width: 1.5,
              ),
            ),
            errorStyle: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.error,
            ),
            errorMaxLines: 2,
          ),
          validator: widget.validator,
        ),
      ],
    );
  }
}
