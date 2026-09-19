import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../utils/customer_profile_fields.dart';
import '../utils/size_key.dart';
import 'sole_primary_button.dart';

/// What the customer chose in [FootSizePickerPanel]: their usual EU size, the
/// width label that goes with it, and the shopping scale the size should be
/// labelled with.
typedef FootSizeSelection = ({
  double euSize,
  String widthLabel,
  String sizeCategory,
});

/// Manual foot-size entry — the EU size + width picker as an inline panel.
///
/// The panel owns only the selection UI: it reports the choice through
/// [onSave] and never persists anything, so the foot-profile write path stays
/// in one place (`AuthProvider.saveFootProfile`). It renders no Scaffold, so
/// it can sit inside a swipeable panel (`SizeYourFootScreen`).
///
/// The range follows the shopping scale ([customerEuSizesFor]): 35 → 48 for
/// Men's/Women's, 22 → 35 for Kids', which is the scan's own children's band.
///
/// The size can be entered in EU, US or UK ([sizeUnitsForCategory]) so a
/// customer who only knows "US 9" never has to translate: whatever unit is
/// on screen, the value that leaves this panel is the canonical EU size.
class FootSizePickerPanel extends StatefulWidget {
  /// The customer's saved EU size, preselected so "edit" opens on the truth.
  final double? initialEuSize;

  /// The saved width. An absent or unrecognised value falls back to the
  /// middle option — never to an arbitrary first entry that would silently
  /// mean 'Narrow'.
  final String? initialWidth;

  /// The saved shopping scale. Unlike the size and width this is NOT given a
  /// default: guessing a scale is how a woman gets a men's US label. The
  /// customer picks it (or it is carried over from what is already saved).
  final String? initialCategory;

  /// Called with the picked size, width and shopping scale.
  final ValueChanged<FootSizeSelection> onSave;

  /// Disables the CTA and shows a spinner while the caller persists.
  final bool isSaving;

  const FootSizePickerPanel({
    super.key,
    this.initialEuSize,
    this.initialWidth,
    this.initialCategory,
    required this.onSave,
    this.isSaving = false,
  });

  @override
  State<FootSizePickerPanel> createState() => _FootSizePickerPanelState();
}

class _FootSizePickerPanelState extends State<FootSizePickerPanel> {
  /// The canonical EU size — the single truth behind every unit shown.
  double? _sizeEu;

  /// The unit the size chips are labelled in. Display-only.
  String _unit = kSizeUnits.first;
  String? _category;
  late String _width;

  @override
  void initState() {
    super.initState();
    _sizeEu = widget.initialEuSize;
    final saved = widget.initialWidth;
    _width = (saved != null && customerFootWidths.contains(saved))
        ? saved
        : customerFootWidths[1];
    // Carry over a scale we already know; otherwise leave it unanswered so
    // the customer picks one rather than inheriting a wrong label.
    final category = widget.initialCategory;
    _category = footSizeCategoryLabel(category) == null ? null : category;
  }

  /// EU sizes this scale offers — the size chips are built from these, in
  /// whichever unit is active.
  List<String> get _euOptions => customerEuSizesFor(_category);

  /// Units this scale can be labelled in. One entry (Kids') means there is
  /// nothing to choose, so the selector is hidden.
  List<String> get _units => sizeUnitsForCategory(_category);

  /// A chip's label for an EU option, in the active unit: `'42'` in EU, `'9'`
  /// in US for a man, `'10.5'` in US for a woman.
  String _labelFor(String eu) => _unit == kSizeUnits.first
      ? eu
      : formatSizeNumber(convertSizeNumber(double.parse(eu), 'EU', _unit,
          category: _category));

  /// Switching scale changes the band and can change the available units, so a
  /// pick that no longer exists in the new list is dropped — an unseen
  /// selection must never sit armed behind an enabled Save.
  void _selectCategory(String key) {
    setState(() {
      _category = key;
      if (!sizeUnitsForCategory(key).contains(_unit)) {
        _unit = kSizeUnits.first;
      }
      final eu = _sizeEu;
      if (eu != null &&
          !customerEuSizesFor(key)
              .map(double.parse)
              .any((option) => option == eu)) {
        _sizeEu = null;
      }
    });
  }

  void _save() {
    final size = _sizeEu;
    final category = _category;
    if (size == null || category == null) return;
    widget.onSave((
      euSize: size,
      widthLabel: _width,
      sizeCategory: category,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final size = _sizeEu;
    final units = _units;
    final options = _euOptions;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter your size',
            style: AppConstants.headlineStyle(
              fontSize: 20,
              color: AppConstants.secondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Already know your size? Pick it here — we use it to show which '
            'products actually stock it. Choose the scale you shop in: it sets '
            'the size range, and enter your size in whichever unit you know — '
            'EU, US or UK.',
            style: AppConstants.bodyStyle(
              fontSize: 13,
              color: AppConstants.secondary.withValues(alpha: 0.6),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          _label('SHOPPING SIZE'),
          Row(
            children: [
              for (final (key, label) in customerFootSizeCategories)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: key == customerFootSizeCategories.last.$1 ? 0 : 8,
                    ),
                    child: _chip(
                      label: label,
                      selected: _category == key,
                      vertical: 11,
                      onTap: () => _selectCategory(key),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          // 'SIZE', not 'EU SIZE': the chips are whatever unit is selected,
          // and the switcher on this row is how a customer who knows only
          // their US or UK size enters it.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _label('SIZE'),
              const Spacer(),
              if (units.length > 1)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final unit in units)
                      Padding(
                        padding: EdgeInsets.only(
                          left: unit == units.first ? 0 : 6,
                        ),
                        child: _chip(
                          label: unit,
                          selected: _unit == unit,
                          vertical: 4,
                          horizontal: 10,
                          fontSize: 11,
                          onTap: () => setState(() => _unit = unit),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: options.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final eu = options[index];
                // The label moves with the unit; the selection stays pinned to
                // the EU value, so switching US → EU never changes the size.
                return _chip(
                  label: _labelFor(eu),
                  selected: size != null && size == double.parse(eu),
                  mono: true,
                  onTap: () => setState(() => _sizeEu = double.parse(eu)),
                );
              },
            ),
          ),
          const SizedBox(height: 22),
          _label('WIDTH'),
          Row(
            children: [
              for (final option in customerFootWidths)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: option == customerFootWidths.last ? 0 : 8,
                    ),
                    child: _chip(
                      label: option,
                      selected: _width == option,
                      vertical: 11,
                      onTap: () => setState(() => _width = option),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 28),
          SolePrimaryButton(
            label: 'Save my size',
            // Disabled until BOTH a size and a shopping scale are picked: a
            // width or a size alone cannot be labelled honestly, and a
            // guessed scale is exactly the mistake this field exists to stop.
            isLoading: widget.isSaving,
            onPressed: size == null || _category == null ? null : _save,
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: AppConstants.bodyStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppConstants.secondary.withValues(alpha: 0.5),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool mono = false,
    double vertical = 0,
    double horizontal = 14,
    double fontSize = 13,
  }) {
    final style = mono
        ? AppConstants.monoStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: selected ? AppConstants.inkInverse : AppConstants.secondary,
          )
        : AppConstants.bodyStyle(
            fontSize: fontSize,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? AppConstants.inkInverse : AppConstants.secondary,
          );

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppConstants.primary : AppConstants.sellerCardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppConstants.primary
                : AppConstants.borderGray.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Text(label, style: style),
      ),
    );
  }
}
