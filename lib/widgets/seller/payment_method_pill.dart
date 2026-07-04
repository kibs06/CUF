import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';

class PaymentMethodPill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isDisabled;
  final String? disabledTooltip;
  final VoidCallback? onTap;

  const PaymentMethodPill({
    super.key,
    required this.label,
    required this.isSelected,
    this.isDisabled = false,
    this.disabledTooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final button = Expanded(
      child: GestureDetector(
        onTap: isDisabled ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppConstants.primary : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isSelected ? AppConstants.primary : AppConstants.borderGray,
            ),
            boxShadow: isSelected ? AppConstants.sellerShadow : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : AppConstants.secondary,
            ),
          ),
        ),
      ),
    );

    if (isDisabled && disabledTooltip != null) {
      return Tooltip(message: disabledTooltip, child: button);
    }

    return button;
  }
}
