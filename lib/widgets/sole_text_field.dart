import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class SoleTextField extends StatelessWidget {
  final String labelText;
  final String? hintText;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType keyboardType;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final bool readOnly;
  final VoidCallback? onTap;
  final int maxLines;
  final Iterable<String>? autofillHints;

  const SoleTextField({
    super.key,
    required this.labelText,
    this.hintText,
    this.controller,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.prefixIcon,
    this.suffixIcon,
    this.validator,
    this.readOnly = false,
    this.onTap,
    this.maxLines = 1,
    this.autofillHints,
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
            color: AppConstants.secondary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          readOnly: readOnly,
          onTap: onTap,
          maxLines: maxLines,
          autofillHints: autofillHints,
          style: AppConstants.bodyStyle(fontSize: 15, color: AppConstants.secondary),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: AppConstants.bodyStyle(fontSize: 14, color: AppConstants.secondary.withValues(alpha: 0.5)),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: AppConstants.primary, size: 20) : null,
            suffixIcon: suffixIcon,
            border: OutlineInputBorder(
              borderRadius: AppConstants.buttonRadius,
              borderSide: BorderSide(color: AppConstants.borderGray.withValues(alpha: 0.5), width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppConstants.buttonRadius,
              borderSide: BorderSide(color: AppConstants.borderGray.withValues(alpha: 0.5), width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppConstants.buttonRadius,
              borderSide: const BorderSide(color: AppConstants.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: AppConstants.buttonRadius,
              borderSide: const BorderSide(color: AppConstants.error, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: AppConstants.buttonRadius,
              borderSide: const BorderSide(color: AppConstants.error, width: 1.5),
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }
}
