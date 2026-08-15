import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../screens/shared/terms_privacy_screen.dart';
import 'signup_scaffold.dart';

/// Checkbox row for the Terms & Privacy consent — the shared tile used by
/// BOTH the customer registration and the seller application flows (they
/// used to each carry a private copy of this row). The tile is role-aware:
/// it consents to the [CUFMAITermsPolicy] passed in and opens the matching
/// document in read-and-agree mode.
///
/// To mark the checkbox the user must READ the policy first: tapping the row
/// (or the "Terms & Privacy Policy" link) opens [TermsPrivacyScreen] in
/// `readAndAgree` mode, where the agree button is disabled until they scroll
/// to the very bottom. Agreeing there checks the box; backing out leaves it
/// unchecked. Once checked, tapping again unchecks directly (no re-read).
class TermsPolicyTile extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Which Terms & Privacy document this tile consents to — the customer
  /// document at registration, the seller document in the seller flow.
  final CUFMAITermsPolicy policy;

  const TermsPolicyTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.policy = CUFMAITermsPolicy.customer,
  });

  @override
  State<TermsPolicyTile> createState() => _TermsPolicyTileState();
}

class _TermsPolicyTileState extends State<TermsPolicyTile> {
  /// Owned here (not created in build) so the recognizer is disposed and
  /// never leaks a listener across rebuilds.
  late final TapGestureRecognizer _policyLink;

  @override
  void initState() {
    super.initState();
    _policyLink = TapGestureRecognizer()..onTap = _openReadAndAgree;
  }

  /// Opens the policy in read-and-agree mode. The user must scroll to the
  /// very bottom before the screen's agree button enables; when they agree
  /// the screen pops `true` and the checkbox is checked here.
  Future<void> _openReadAndAgree() async {
    final agreed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            TermsPrivacyScreen(readAndAgree: true, policy: widget.policy),
      ),
    );
    if (agreed == true && mounted) {
      widget.onChanged(true);
    }
  }

  @override
  void dispose() {
    _policyLink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = AppConstants.bodyStyle(
      fontSize: 13,
      color: AppConstants.secondary.withValues(alpha: 0.75),
      height: 1.4,
    );
    final linkStyle = baseStyle.copyWith(
      color: AppConstants.primary,
      fontWeight: FontWeight.bold,
      decoration: TextDecoration.underline,
      decorationColor: AppConstants.primary,
    );

    // The tile is only ever given a single-document policy, but handle
    // `all` (admin combined view) defensively by omitting the role prefix.
    final prefix = switch (widget.policy) {
      CUFMAITermsPolicy.seller => 'Seller ',
      CUFMAITermsPolicy.customer => 'Customer ',
      CUFMAITermsPolicy.all => '',
    };
    final consentLabel =
        'I agree to the ${prefix}Terms & Privacy Policy of CUFMAI.';

    return Semantics(
      // The checkbox is a custom-drawn box (AnimatedContainer + icon), so it
      // has no built-in semantics. Announce the whole row as a checkbox with
      // its current state so screen-reader users can discover the toggle.
      container: true,
      checked: widget.value,
      label: consentLabel,
      child: InkWell(
        onTap: () {
          if (widget.value) {
            // Already agreed — unchecking is always allowed directly.
            widget.onChanged(false);
          } else {
            // Not agreed yet — the user must read the policy first.
            _openReadAndAgree();
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AuthSpacing.s4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: widget.value ? AppConstants.primary : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: widget.value
                      ? AppConstants.primary
                      : AppConstants.borderGray,
                  width: 1.5,
                ),
              ),
              child: widget.value
                  ? const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: AuthSpacing.s12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: baseStyle,
                    children: [
                      const TextSpan(text: 'I agree to the '),
                      TextSpan(
                        text: '${prefix}Terms & Privacy Policy',
                        style: linkStyle,
                        // Deeper than the row's InkWell, so a tap on the
                        // link opens the policy and does NOT toggle the
                        // checkbox.
                        recognizer: _policyLink,
                      ),
                      const TextSpan(text: ' of CUFMAI.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
