import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wheel_picker/wheel_picker.dart';

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

/// Manual foot-size entry as a 2-step wizard panel.
///
/// Step 1 (scale) offers two animated cards — Men's and Women's. Step 2
/// (size) offers the EU/US/UK unit switch, a horizontal size wheel, the
/// width row and the save CTA.
///
/// The panel owns only the selection UI: it reports the choice through
/// [onSave] and never persists anything, so the foot-profile write path stays
/// in one place (`AuthProvider.saveFootProfile`). It renders no Scaffold, so
/// it can sit inside a swipeable panel (`SizeYourFootScreen`).
///
/// The adult band is 35 → 48 for both scales; the legacy Kids' band (22 → 35)
/// is still honoured for a profile saved with it, but new picks are
/// men/women only (kids' shoppers use the camera scan flow, which keeps the
/// children's band).
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
  /// 0 = scale cards, 1 = size wheel.
  late int _step;

  /// The canonical EU size — the single truth behind every unit shown.
  double? _sizeEu;

  /// The unit the size wheel is labelled in. Display-only.
  String _unit = kSizeUnits.first;
  String? _category;
  late String _width;

  /// Briefly holds the tapped card so its confirmation fill is visible
  /// before the wizard advances.
  String? _confirming;

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
    // A known scale opens straight on the size step — including a legacy
    // kids' save, which keeps its children's band there. Anything else
    // starts on the scale cards.
    _step = _category == null ? 0 : 1;
  }

  /// EU sizes the active band offers: the adult band for Men's/Women's (and
  /// for an unpicked scale), the children's band for a legacy Kids' save.
  List<String> get _euOptions => customerEuSizesFor(_category);

  /// Units the active scale can be labelled in. The legacy kids' band has no
  /// US/UK chart, so the selector hides and EU is the only label.
  List<String> get _units =>
      _category == 'kids' ? const ['EU'] : sizeUnitsForCategory(_category);

  /// A wheel entry's label for an EU option, in the active unit: `'42'` in
  /// EU, `'9'` in US for a man, `'10.5'` in US for a woman.
  String _labelFor(String eu) => _unit == kSizeUnits.first
      ? eu
      : formatSizeNumber(convertSizeNumber(double.parse(eu), 'EU', _unit,
          category: _category));

  /// Index of [eu] in the active band, or null when the band has no such
  /// size (e.g. a kids' size after switching to an adult scale).
  int? _indexOf(double? eu) {
    if (eu == null) return null;
    final index = _euOptions.indexWhere((option) => double.parse(option) == eu);
    return index < 0 ? null : index;
  }

  /// Pick a shopping scale from a card: confirm briefly, then advance to the
  /// size step. A pick that no longer exists in the new band is dropped — an
  /// unseen selection must never sit armed behind an enabled Save.
  void _pickScale(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      _category = key;
      _confirming = key;
      if (!sizeUnitsForCategory(key).contains(_unit)) {
        _unit = kSizeUnits.first;
      }
      if (_indexOf(_sizeEu) == null) {
        _sizeEu = null;
      }
    });
    void advance() {
      if (!mounted) return;
      setState(() {
        _confirming = null;
        _step = 1;
      });
    }
    if (MediaQuery.of(context).disableAnimations) {
      advance();
    } else {
      Future.delayed(const Duration(milliseconds: 200), advance);
    }
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.12, 0), end: Offset.zero)
                .animate(animation),
            child: child,
          ),
        ),
        child: _step == 0
            ? _ScaleStep(
                key: const ValueKey('scale-step'),
                category: _category,
                confirming: _confirming,
                onPick: _pickScale,
              )
            : _SizeStep(
                key: ValueKey(
                    'size-step-${_category == 'kids' ? 'kids' : 'adult'}'),
                euOptions: _euOptions,
                units: _units,
                unit: _unit,
                sizeEu: _sizeEu,
                width: _width,
                category: _category,
                isSaving: widget.isSaving,
                labelFor: _labelFor,
                onUnit: (unit) => setState(() => _unit = unit),
                onSize: (eu) => setState(() => _sizeEu = eu),
                onWidth: (width) => setState(() => _width = width),
                onBack: () => setState(() => _step = 0),
                onSave: _save,
              ),
      ),
    );
  }
}

/// Step 1: the shopping-scale cards.
///
/// Two large cards — Men's and Women's — each naming its EU band. A legacy
/// Kids' save is honoured by the size step, but new picks are men/women
/// only: kids' shoppers use the camera scan flow.
class _ScaleStep extends StatelessWidget {
  final String? category;
  final String? confirming;
  final ValueChanged<String> onPick;

  const _ScaleStep({
    super.key,
    required this.category,
    required this.confirming,
    required this.onPick,
  });

  static const _cards = [
    ('men', "Men's", Icons.male_rounded, 'EU 35 – 48'),
    ('women', "Women's", Icons.female_rounded, 'EU 35 – 48'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('scale-step-body'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Who are you shopping for?',
          style: AppConstants.headlineStyle(
            fontSize: 20,
            color: AppConstants.secondary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Men and women share EU sizes, but the US and UK charts differ — '
          'picking the right scale keeps the label honest. Kids’ sizes live '
          'in the camera scan flow.',
          style: AppConstants.bodyStyle(
            fontSize: 13,
            color: AppConstants.secondary.withValues(alpha: 0.6),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            for (final (key, label, icon, hint) in _cards)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: key == _cards.last.$1 ? 0 : 12,
                  ),
                  child: _ScaleCard(
                    label: label,
                    icon: icon,
                    hint: hint,
                    selected: category == key || confirming == key,
                    onTap: () => onPick(key),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// One scale card: icon, label and band hint with a confirmation fill on
/// selection. At least a 44px touch target, the platform minimum.
class _ScaleCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  const _ScaleCard({
    required this.label,
    required this.icon,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: const BoxConstraints(minHeight: 132),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppConstants.primary : AppConstants.sellerCardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppConstants.primary
                : AppConstants.borderGray.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 32,
                color: selected
                    ? AppConstants.inkInverse
                    : AppConstants.secondary,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: AppConstants.bodyStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected
                      ? AppConstants.inkInverse
                      : AppConstants.secondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hint,
                style: AppConstants.monoStyle(
                  fontSize: 11,
                  color: selected
                      ? AppConstants.inkInverse.withValues(alpha: 0.8)
                      : AppConstants.secondary.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Step 2: unit switch, size wheel, width row, summary and save.
///
/// The wheel commits on every user change (tap/drag/scroll); programmatic
/// shifts never commit, so mounting the wheel on a saved size — or
/// repositioning it after a scale switch — cannot arm a size the customer
/// did not choose.
class _SizeStep extends StatelessWidget {
  final List<String> euOptions;
  final List<String> units;
  final String unit;
  final double? sizeEu;
  final String width;
  final String? category;
  final bool isSaving;
  final String Function(String eu) labelFor;
  final ValueChanged<String> onUnit;
  final ValueChanged<double> onSize;
  final ValueChanged<String> onWidth;
  final VoidCallback onBack;
  final VoidCallback onSave;

  const _SizeStep({
    super.key,
    required this.euOptions,
    required this.units,
    required this.unit,
    required this.sizeEu,
    required this.width,
    required this.category,
    required this.isSaving,
    required this.labelFor,
    required this.onUnit,
    required this.onSize,
    required this.onWidth,
    required this.onBack,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final size = sizeEu;
    final savedIndex = size == null
        ? euOptions.length ~/ 2
        : euOptions.indexWhere((eu) => double.parse(eu) == size);
    // Scrollable so the step fits small screens (the wheel alone is 200
    // tall, and the parent panel already scrolls for anything beyond that).
    return SingleChildScrollView(
      key: const ValueKey('size-step-body'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onBack();
              },
              child: Semantics(
                button: true,
                label: 'Back to scale',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.arrow_back_ios,
                        size: 14,
                        color:
                            AppConstants.secondary.withValues(alpha: 0.7),
                      ),
                      Text(
                        'Back',
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          color:
                              AppConstants.secondary.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Spacer(),
            if (category != null)
              Text(
                footSizeCategoryLabel(category) ?? category!,
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.secondary.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (category == 'kids')
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Your saved scale is Kids’. New picks are Men’s or Women’s — '
              'go back to switch scale, or keep editing this size.',
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _StepLabel('SIZE'),
            const Spacer(),
            if (units.length > 1)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in units)
                    Padding(
                      padding: EdgeInsets.only(
                        left: entry == units.first ? 0 : 6,
                      ),
                      child: _UnitChip(
                        label: entry,
                        selected: unit == entry,
                        onTap: () => onUnit(entry),
                      ),
                    ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 4),
        // The live readout: the committed size in the active unit, or an
        // invitation until the wheel has been touched.
        Center(
          child: Text(
            size == null
                ? 'Spin the wheel to your size'
                : labelFor(formatSizeNumber(size)),
            style: size == null
                ? AppConstants.bodyStyle(
                    fontSize: 14,
                    color: AppConstants.secondary.withValues(alpha: 0.55),
                  )
                : AppConstants.monoStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.secondary,
                  ),
          ),
        ),
        // Vertical is the wheel's native axis. The package renders
        // horizontal by painting rotated content outside its layout box,
        // where taps can never land (ancestors bounds-check hit tests),
        // so horizontal neighbours are dead to touch on a real phone.
        SizedBox(
          height: 200,
          child: WheelPicker(
            itemCount: euOptions.length,
            initialIndex:
                savedIndex < 0 ? euOptions.length ~/ 2 : savedIndex,
            looping: false,
            scrollDirection: Axis.vertical,
            enableTap: true,
            selectedIndexColor: AppConstants.primary,
            onIndexChanged: (index, interactionType) {
              if (interactionType == WheelPickerInteractionType.control ||
                  interactionType == WheelPickerInteractionType.mount) {
                return;
              }
              final eu = double.parse(euOptions[index]);
              if (eu != size) {
                HapticFeedback.selectionClick();
                onSize(eu);
              }
            },
            style: WheelPickerStyle(
              itemExtent: 64,
              diameterRatio: 1.6,
              squeeze: 1.0,
              surroundingOpacity: 0.3,
              magnification: 1.15,
            ),
            builder: (context, index) {
              final eu = euOptions[index];
              final committed =
                  size != null && double.parse(eu) == size;
              return Center(
                child: Semantics(                      button: true,
                      selected: committed,
                      // Routed through formatSize: the repo guards against
                      // hardcoded 'EU ' label literals (size_key_test).
                      label: formatSize(eu),
                  child: Text(
                    labelFor(eu),
                    style: AppConstants.monoStyle(
                      fontSize: 20,
                      fontWeight:
                          committed ? FontWeight.bold : FontWeight.normal,
                      color: AppConstants.secondary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _StepLabel('WIDTH'),
        Row(
          children: [
            for (final option in customerFootWidths)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: option == customerFootWidths.last ? 0 : 8,
                  ),
                  child: _WidthChip(
                    label: option,
                    selected: width == option,
                    onTap: () => onWidth(option),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 28),
        _summaryOrHint(size),
        SolePrimaryButton(
          label: 'Save my size',
          // Disabled until BOTH a size and a shopping scale are picked: a
          // width or a size alone cannot be labelled honestly, and a
          // guessed scale is exactly the mistake this field exists to stop.
          isLoading: isSaving,
          onPressed: size == null || category == null ? null : onSave,
        ),
        ],
      ),
    );
  }

  /// Confirms what will be saved once both a size and a scale are picked,
  /// and says what is still missing until then, so the disabled button is
  /// never a mystery.
  Widget _summaryOrHint(double? size) {
    if (size == null || category == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          'Choose a size to continue.',
          style: AppConstants.bodyStyle(
            fontSize: 12,
            color: AppConstants.secondary.withValues(alpha: 0.55),
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppConstants.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.success.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppConstants.success,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${formatSize(formatSizeNumber(size))} · $width · '
              '${footSizeCategoryLabel(category) ?? category}',
              style: AppConstants.bodyStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppConstants.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepLabel extends StatelessWidget {
  final String text;

  const _StepLabel(this.text);

  @override
  Widget build(BuildContext context) {
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
}

class _UnitChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _UnitChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
        child: Semantics(
          button: true,
          selected: selected,
          child: Text(
            label,
            style: AppConstants.bodyStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color:
                  selected ? AppConstants.inkInverse : AppConstants.secondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _WidthChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _WidthChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        // At least a 44px touch target, the platform minimum.
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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
        child: Semantics(
          button: true,
          selected: selected,
          child: Text(
            label,
            style: AppConstants.bodyStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color:
                  selected ? AppConstants.inkInverse : AppConstants.secondary,
            ),
          ),
        ),
      ),
    );
  }
}
