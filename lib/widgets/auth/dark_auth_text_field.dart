import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';

/// Dark variant of the auth text field, built for the sign-in mode of the
/// merged account entry screen where fields float directly over the
/// full-bleed video background.
///
/// This is deliberately NOT `SoleTextField` re-theme'd — that widget is
/// built for a white card (`fillColor: white`, dark labels) and would have
/// no contrast over footage. Instead it uses a semi-opaque dark fill and a
/// light border, with warm-cream labels/icons and white text — the same
/// field skeleton (label above, prefix/suffix icons, validators, autofill,
/// autocorrect opt-out for credentials) so the sign-in contract is unchanged.
///
/// Contrast (measured against `video/locals.mp4` with ffmpeg): the fields
/// sit as high as ~33–55% of screen height on short devices, where the
/// scrims overlap weakest — the video reaches luma ≈ 130 there on the
/// brightest frames. The fill is therefore `black @ 0.35` (the design brief's
/// "0.28-ish" darkened to close the measured gap), which keeps the field
/// surface ≤ ≈0.17 luma on the worst frame: white text ≥ 4.9:1 and the cream
/// 14px-bold labels ≥ 4.6:1 — comfortably AA. The hint text is white @ 0.7 so
/// even the placeholder stays clearly readable (≥ 3.5:1 everywhere).
class DarkAuthTextField extends StatelessWidget {
  final String labelText;
  final String? hintText;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType keyboardType;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final Iterable<String>? autofillHints;
  final bool autocorrect;
  final bool enableSuggestions;

  const DarkAuthTextField({
    super.key,
    required this.labelText,
    this.hintText,
    this.controller,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.prefixIcon,
    this.suffixIcon,
    this.validator,
    this.autofillHints,
    // Same credential defaults as the login screen's fields: no
    // spell-check/suggestions so the keyboard's per-word yellow underlines
    // never appear and the address can't get mangled.
    this.autocorrect = false,
    this.enableSuggestions = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          style: AppConstants.bodyStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppConstants.surfaceLight,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          autofillHints: autofillHints,
          autocorrect: autocorrect,
          enableSuggestions: enableSuggestions,
          style: AppConstants.bodyStyle(
            fontSize: 15,
            color: Colors.white,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: AppConstants.bodyStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.7),
            ),
            filled: true,
            // Semi-opaque dark fill — the merged-screen treatment, deepened
            // to 0.35 (from the brief's 0.28) so white/cream text clears
            // AA even in the 40–60% height band on the video's brightest
            // frames (see the class doc for the measured numbers).
            fillColor: Colors.black.withValues(alpha: 0.35),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            prefixIcon: prefixIcon != null
                ? Icon(
                    prefixIcon,
                    color: AppConstants.surfaceLight.withValues(alpha: 0.85),
                    size: 20,
                  )
                : null,
            suffixIcon: suffixIcon,
            border: OutlineInputBorder(
              borderRadius: AppConstants.fieldRadius,
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.22),
                width: 1.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppConstants.fieldRadius,
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.22),
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppConstants.fieldRadius,
              borderSide: BorderSide(
                color: AppConstants.surfaceLight.withValues(alpha: 0.9),
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: AppConstants.fieldRadius,
              borderSide: const BorderSide(
                color: AppConstants.error,
                width: 1.5,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: AppConstants.fieldRadius,
              borderSide: const BorderSide(
                color: AppConstants.error,
                width: 1.5,
              ),
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }
}
