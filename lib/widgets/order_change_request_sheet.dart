import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import 'sole_primary_button.dart';

/// Result data returned from the change request flow.
class ChangeRequestResult {
  final String type; // 'size', 'color', 'address', 'quantity', 'other'
  final String? fromValue; // Current value (optional)
  final String toValue; // Requested new value

  const ChangeRequestResult({
    required this.type,
    this.fromValue,
    required this.toValue,
  });
}

/// Predefined change request types.
class ChangeRequestType {
  final String id;
  final String label;
  final IconData icon;
  final String hint;

  const ChangeRequestType({
    required this.id,
    required this.label,
    required this.icon,
    required this.hint,
  });
}

const changeRequestTypes = [
  ChangeRequestType(
    id: 'size',
    label: 'Change Size',
    icon: Icons.straighten,
    hint: 'e.g. EU 42 → EU 43',
  ),
  ChangeRequestType(
    id: 'color',
    label: 'Change Color/Variant',
    icon: Icons.palette_outlined,
    hint: 'e.g. Burnished Clay → Saddle Brown',
  ),
  ChangeRequestType(
    id: 'address',
    label: 'Change Delivery Address',
    icon: Icons.location_on_outlined,
    hint: 'New delivery address',
  ),
  ChangeRequestType(
    id: 'quantity',
    label: 'Change Quantity',
    icon: Icons.numbers,
    hint: 'e.g. 2 → 1',
  ),
  ChangeRequestType(
    id: 'other',
    label: 'Other Request',
    icon: Icons.edit_outlined,
    hint: 'Describe your request',
  ),
];

/// Bottom sheet for selecting a change request type and entering details.
Future<ChangeRequestResult?> showChangeRequestSheet(BuildContext context) {
  return showModalBottomSheet<ChangeRequestResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ChangeRequestSheet(),
  );
}

class _ChangeRequestSheet extends StatefulWidget {
  const _ChangeRequestSheet();

  @override
  State<_ChangeRequestSheet> createState() => _ChangeRequestSheetState();
}

class _ChangeRequestSheetState extends State<_ChangeRequestSheet> {
  ChangeRequestType? _selectedType;
  final _detailsController = TextEditingController();

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    return _selectedType != null && _detailsController.text.trim().isNotEmpty;
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop(
      ChangeRequestResult(
        type: _selectedType!.id,
        toValue: _detailsController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppConstants.surfaceLight,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppConstants.borderGray,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Request a Change',
                        style: AppConstants.headlineStyle(fontSize: 20),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Subtitle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Select what you\'d like to change. The seller will review your request.',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Type options
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: changeRequestTypes.length,
                  itemBuilder: (context, index) {
                    final type = changeRequestTypes[index];
                    final isSelected = _selectedType?.id == type.id;

                    return Column(
                      children: [
                        _TypeOption(
                          type: type,
                          isSelected: isSelected,
                          onTap: () {
                            setState(() {
                              _selectedType = type;
                              _detailsController.clear();
                            });
                          },
                        ),
                        // Show details field when type is selected
                        if (isSelected) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _detailsController,
                            maxLines: 3,
                            minLines: 2,
                            decoration: InputDecoration(
                              hintText: type.hint,
                              hintStyle: AppConstants.bodyStyle(
                                fontSize: 13,
                                color: AppConstants.secondary.withValues(alpha: 0.4),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.all(12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: AppConstants.borderGray.withValues(alpha: 0.5),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: AppConstants.borderGray.withValues(alpha: 0.5),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: AppConstants.primary,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 4),
                        ],
                        const SizedBox(height: 4),
                      ],
                    );
                  },
                ),
              ),

              // Submit button
              Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  12 + MediaQuery.of(context).padding.bottom,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SolePrimaryButton(
                  label: 'Send Request',
                  onPressed: _canSubmit ? _submit : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Single selectable type option.
class _TypeOption extends StatelessWidget {
  final ChangeRequestType type;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeOption({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppConstants.primary.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppConstants.primary.withValues(alpha: 0.3)
                : AppConstants.borderGray.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppConstants.primary.withValues(alpha: 0.12)
                    : AppConstants.surfaceLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                type.icon,
                size: 18,
                color: isSelected ? AppConstants.primary : AppConstants.secondary,
              ),
            ),
            const SizedBox(width: 12),
            // Label
            Expanded(
              child: Text(
                type.label,
                style: AppConstants.bodyStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: AppConstants.secondary,
                ),
              ),
            ),
            // Radio indicator
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppConstants.primary : AppConstants.borderGray,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppConstants.primary,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
