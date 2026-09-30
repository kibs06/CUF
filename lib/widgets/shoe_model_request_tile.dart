import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../constants/app_constants.dart';
import '../screens/shared/shoe_preview_screen.dart';
import '../services/shoe_model_request_service.dart';
import '../utils/shoe_model_request.dart';
import '../utils/size_key.dart';

/// The product action sheet's **3D model** row — the second door into the model
/// pipeline (roadmap V2.10).
///
/// It exists because the upload section in the product form assumes a seller
/// who can produce a contract-compliant `.glb`, and this market's sellers are
/// local artisans who cannot. So the row is a request: the seller measures the
/// pair with a ruler, the CUFMAI team does the modelling, and both sides read
/// the same state. The label carries that state, because a seller who cannot
/// tell "waiting" from "declined" will ask again and file a duplicate.
///
/// **Self-loading on purpose.** The screen this lives in renders a bottom sheet
/// synchronously, so a tile that needs a request's state cannot read it from the
/// parent's build. Loading it here keeps `manage_products_screen.dart`'s list
/// untouched — and it is one query for one product, only when the sheet opens.
///
/// The switch is [AppConstants.shoeModelRequestEnabled], **on** since the
/// migration behind it was applied and verified, and off — which now takes a
/// deliberate `--dart-define` — means the row is not there at all.
///
/// ⚠️ **The ready row shows the model (2026-10-01).** It used to open a sheet
/// that *described* the model, which put the seller's only evidence that their
/// pair was modelled on the word of the row itself. It now opens the 3D viewer
/// (`ShoePreviewScreen.forProduct`), which resolves the product's model on the
/// seller's device and draws it — or says plainly that there is nothing to draw.
class ShoeModelRequestTile extends StatefulWidget {
  const ShoeModelRequestTile({
    super.key,
    required this.productId,
    this.product,
    this.service,
    this.enabled = AppConstants.shoeModelRequestEnabled,
    this.onChanged,
  });

  final String productId;

  /// The product row, read for the prefill only (a heel height and a reference
  /// size are the same measurement on both sides; the length is not — see
  /// `shoeModelRequestPrefill`).
  final Map<String, dynamic>? product;

  /// Injected by tests, and by the sheet's own refresh.
  final ShoeModelRequestService? service;

  final bool enabled;

  /// Called after a change, so the screen can refresh whatever it shows.
  final VoidCallback? onChanged;

  @override
  State<ShoeModelRequestTile> createState() => _ShoeModelRequestTileState();
}

class _ShoeModelRequestTileState extends State<ShoeModelRequestTile> {
  late final ShoeModelRequestService _service =
      widget.service ?? ShoeModelRequestService.createDefault();

  ShoeModelRequestAvailability _availability = const ShoeModelRequestAvailability();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await _service.availability(widget.productId);
    if (!mounted) return;
    setState(() {
      _availability = result;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();

    if (_loading) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        title: Text(
          '3D fitting',
          style: AppConstants.bodyStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      );
    }

    final row = _availability.row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(_iconFor(row.action), color: AppConstants.primary),
          title: Text(
            row.label,
            style: AppConstants.bodyStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          subtitle: row.subtitle == null
              ? null
              : Text(
                  row.subtitle!,
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary,
                  ),
                ),
          onTap: () => _open(row.action),
        ),
      ],
    );
  }

  IconData _iconFor(ShoeModelRequestAction action) => switch (action) {
        ShoeModelRequestAction.ask => Icons.view_in_ar_outlined,
        ShoeModelRequestAction.progress => Icons.hourglass_top_outlined,
        ShoeModelRequestAction.ready => Icons.check_circle_outline,
        ShoeModelRequestAction.declined => Icons.info_outline,
      };

  Future<void> _open(ShoeModelRequestAction action) async {
    switch (action) {
      case ShoeModelRequestAction.ask:
      case ShoeModelRequestAction.declined:
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppConstants.surfaceLight,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => ShoeModelRequestFormSheet(
            productId: widget.productId,
            product: widget.product,
            service: _service,
            // A declined request is being re-asked, so the seller should see
            // what the team said before they type the numbers again.
            previous: action == ShoeModelRequestAction.declined
                ? _availability.request
                : null,
          ),
        );
        await _load();
        widget.onChanged?.call();
      case ShoeModelRequestAction.progress:
        await showModalBottomSheet<void>(
          context: context,
          backgroundColor: AppConstants.surfaceLight,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => _RequestProgressSheet(
            request: _availability.request,
            service: _service,
          ),
        );
        await _load();
        widget.onChanged?.call();
      case ShoeModelRequestAction.ready:
        // ⚠️ **A look, not a sentence about one.** This used to open a sheet that
        // *said* the product has a model. A seller reads "3D fitting ready" off a
        // row backed by a `product_models` record, and a record is not a shoe:
        // the model may be unrenderable, or those bytes may not be on any device
        // at all. Tapping now opens the model itself, which is the only thing
        // that answers the question the row just raised — and the viewer says so
        // honestly when there turns out to be nothing to draw.
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ShoePreviewScreen.forProduct(
              productId: widget.productId,
              product: widget.product ?? const <String, dynamic>{},
              note: 'Change it any time from the product form.',
            ),
          ),
        );
        await _load();
        widget.onChanged?.call();
    }
  }
}

/// The measurement form. Four numbers, one of which is required, and the
/// required one is the length the modeller scales everything from.
class ShoeModelRequestFormSheet extends StatefulWidget {
  const ShoeModelRequestFormSheet({
    super.key,
    required this.productId,
    required this.service,
    this.product,
    this.previous,
  });

  final String productId;
  final ShoeModelRequestService service;
  final Map<String, dynamic>? product;

  /// The declined request being re-asked, if this form was opened from one.
  final ShoeModelRequestRecord? previous;

  @override
  State<ShoeModelRequestFormSheet> createState() =>
      _ShoeModelRequestFormSheetState();
}

class _ShoeModelRequestFormSheetState extends State<ShoeModelRequestFormSheet> {
  late final TextEditingController _length;
  late final TextEditingController _width;
  late final TextEditingController _heel;
  late final TextEditingController _upper;
  late final TextEditingController _size;
  late final TextEditingController _note;

  /// Which unit the four millimetre boxes are read in. Storage is millimetres
  /// either way — see [ShoeModelRequestUnit].
  ShoeModelRequestUnit _unit = ShoeModelRequestUnit.mm;

  /// The sizes this shoe is made in, as picked. Empty means "not stated".
  final Set<double> _sizeRun = <double>{};

  ShoeModelRequestFormResult _result = const ShoeModelRequestFormResult.empty();
  bool _sending = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    // The heel and the size are the same quantities measured the same way, so
    // they are prefilled from the product's fit spec when it has one. The
    // LENGTH is never prefilled: `products.last_length_mm` is the internal
    // measurement and this field wants the outside of the shoe, 8–15 mm longer.
    final prefill = shoeModelRequestPrefill(widget.product);
    _length = TextEditingController();
    _width = TextEditingController();
    _heel = TextEditingController(text: prefill.heelHeightMm);
    _upper = TextEditingController();
    _size = TextEditingController(text: prefill.measuredSizeEu);
    _note = TextEditingController();
  }

  @override
  void dispose() {
    _length.dispose();
    _width.dispose();
    _heel.dispose();
    _upper.dispose();
    _size.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final result = ShoeModelRequestFormResult.fromFields(
      externalLengthMm: _length.text,
      externalWidthMm: _width.text,
      heelHeightMm: _heel.text,
      upperHeightMm: _upper.text,
      measuredSizeEu: _size.text,
      unit: _unit,
      sizesEu: _sizeRun.toList(),
    );

    setState(() {
      _result = result;
      _failure = null;
    });
    if (result.isError || result.measurements == null) return;

    setState(() => _sending = true);
    final outcome = await widget.service.request(
      productId: widget.productId,
      measurements: result.measurements!,
      note: _note.text,
    );
    if (!mounted) return;

    if (outcome.success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(outcome.message),
          backgroundColor: AppConstants.success,
        ),
      );
      return;
    }

    setState(() {
      _sending = false;
      _failure = outcome.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppConstants.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Ask for a 3D fitting',
                style: AppConstants.headlineStyle(fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                'The CUFMAI team will build the 3D model for this product, so '
                'customers can try it on. Measure the pair — not your foot — '
                'with a ruler or a tape, and type what you read.',
                style: AppConstants.bodyStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              const _MeasureGuide(),
              if (widget.previous?.adminNote != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppConstants.borderGray.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Last time the team said: ${widget.previous!.adminNote}',
                    style: AppConstants.bodyStyle(fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _unitToggle(),
              const SizedBox(height: 8),
              _field(
                controller: _length,
                label: 'Outside length (${_unit.label}) — required',
                hint: _hintFor(kSampleShoeLengthMm),
                field: ShoeModelRequestField.externalLengthMm,
              ),
              _field(
                controller: _width,
                label: 'Outside width (${_unit.label})',
                hint: _hintFor(kSampleShoeWidthMm),
                field: ShoeModelRequestField.externalWidthMm,
              ),
              _field(
                controller: _heel,
                label: 'Heel height (${_unit.label})',
                hint: _hintFor(kSampleShoeHeelMm),
                field: ShoeModelRequestField.heelHeightMm,
              ),
              _field(
                controller: _upper,
                label: 'Height of the shoe (${_unit.label})',
                hint: _hintFor(kSampleShoeUpperMm),
                field: ShoeModelRequestField.upperHeightMm,
              ),
              _pickerField(
                label: 'Size you measured (EU)',
                value: _size.text.isEmpty ? null : _size.text,
                helper: shoeModelRequestSampleHint(
                  ShoeModelRequestField.measuredSizeEu,
                ),
                onTap: _pickMeasuredSize,
              ),
              _pickerField(
                label: 'Sizes you make this shoe in (EU)',
                value: _sizeRun.isEmpty ? null : _sizeRunSentence(),
                helper: 'Optional, and it is not what the model is scaled to — '
                    'the team uses it to check the model against the sizes you '
                    'actually sell.',
                onTap: _pickSizeRun,
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _note,
                maxLines: 3,
                style: AppConstants.bodyStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Anything the team should know (optional)',
                  labelStyle: AppConstants.bodyStyle(fontSize: 13),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              if (_failure != null) ...[
                const SizedBox(height: 12),
                Text(
                  _failure!,
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    color: AppConstants.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppConstants.primary,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _sending ? null : _send,
                  child: Text(
                    _sending ? 'Sending…' : 'Send the request',
                    style: AppConstants.bodyStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required ShoeModelRequestField field,
  }) {
    // The inline error is the same sentence the save path would produce, read
    // off the same result — so the two cannot disagree about what is valid.
    final message = _result.messageFor(field);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: AppConstants.bodyStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: AppConstants.bodyStyle(fontSize: 13),
          // The anchor, not a default: it says what a real shoe measures, so a
          // number from the wrong unit looks wrong before it is sent. It steps
          // aside for the error, which is exactly the trade we want — an error
          // matters more than an example.
          helperText: shoeModelRequestSampleHint(field),
          helperMaxLines: 3,
          helperStyle: AppConstants.bodyStyle(
            fontSize: 11,
            color: AppConstants.secondary,
          ),
          errorText: message,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  /// The mm/cm choice, above the boxes it governs.
  ///
  /// ⚠️ Switching it does **not** convert what is already typed, deliberately:
  /// rewriting `270` into `27` under the seller's fingers would be the app
  /// guessing, and if they typed in the wrong unit the number is wrong in a way
  /// only they can fix. What does change is every label, every sample hint and
  /// the band in the error — so a figure left over from the other unit is told
  /// its range in the unit now selected, which is a sentence they can act on.
  Widget _unitToggle() => Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'I am typing in',
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary,
            ),
          ),
          for (final unit in ShoeModelRequestUnit.values)
            _choiceChip(
              label: unit.label,
              selected: _unit == unit,
              onTap: () => setState(() => _unit = unit),
            ),
        ],
      );

  /// A box's placeholder, in the unit the seller picked — `270` or `27` —
  /// derived from the same sample the hint sentence quotes, so the two can never
  /// disagree about what a normal shoe measures.
  String _hintFor(double sampleMm) =>
      formatSizeNumber(sampleMm / _unit.millimetresPerUnit);

  /// A box that opens a picker instead of a keyboard. Sizes are a list, not a
  /// number: a seller who does not know what `42.5` is spelled like can still
  /// tap it, and nothing in this field can produce a value the column refuses.
  Widget _pickerField({
    required String label,
    required String? value,
    required String helper,
    required Future<void> Function() onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              labelStyle: AppConstants.bodyStyle(fontSize: 13),
              helperText: helper,
              helperMaxLines: 3,
              helperStyle: AppConstants.bodyStyle(
                fontSize: 11,
                color: AppConstants.secondary,
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value ?? 'Tap to choose',
                    style: AppConstants.bodyStyle(
                      fontSize: 14,
                      color: value == null ? AppConstants.secondary : null,
                    ),
                  ),
                ),
                const Icon(Icons.unfold_more, size: 18),
              ],
            ),
          ),
        ),
      );

  Future<void> _pickMeasuredSize() async {
    final current = double.tryParse(_size.text);
    final picked = await _showSizePicker(
      title: 'Size you measured',
      subtitle: 'The size printed inside the pair on the bench.',
      multi: false,
      selected: {?current},
    );
    if (picked == null || !mounted) return;
    setState(() {
      _size.text = picked.isEmpty ? '' : formatSizeNumber(picked.first);
    });
  }

  Future<void> _pickSizeRun() async {
    final picked = await _showSizePicker(
      title: 'Sizes you make this shoe in',
      subtitle: 'Tap every size you sell. Leave it empty if you would rather '
          'not say — the request is complete without it.',
      multi: true,
      selected: _sizeRun,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _sizeRun
        ..clear()
        ..addAll(picked);
    });
  }

  Future<Set<double>?> _showSizePicker({
    required String title,
    required String subtitle,
    required bool multi,
    required Set<double> selected,
  }) =>
      showModalBottomSheet<Set<double>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppConstants.surfaceLight,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _SizePickerSheet(
          title: title,
          subtitle: subtitle,
          multi: multi,
          initial: selected,
        ),
      );

  /// The run as the seller picked it, in the queue's own words.
  String _sizeRunSentence() =>
      ShoeModelRequestMeasurements(
        externalLengthMm: 0,
        sizesEu: normaliseSizeRun(_sizeRun),
      ).sizeRunSentence;
}

/// The measuring guide: the drawing, then what each arrow on it means.
///
/// The SVG carries **no text** (flutter_svg does not render `<text>`, so a
/// numeral there would vanish on the device) — the dimensions are told apart by
/// colour, and this legend is what names them. The four colours below must match
/// the strokes in `assets/images/measure_shoe.svg`; `shoe_model_request_tile_test.dart`
/// reads the file and pins the pairing, because a legend that names the wrong
/// arrow is worse than no legend.
class _MeasureGuide extends StatelessWidget {
  const _MeasureGuide();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConstants.borderGray.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SvgPicture.asset(
            'assets/images/measure_shoe.svg',
            height: 150,
            fit: BoxFit.contain,
            semanticsLabel: 'Where to measure the pair: outside length, outside '
                'width, heel height and the height of the shoe',
          ),
          const SizedBox(height: 8),
          for (final entry in _measureGuideLegend)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 3, right: 8),
                    decoration: BoxDecoration(
                      color: entry.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.label,
                      style: AppConstants.bodyStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

}

/// One chip in a pick-one or pick-many set — the unit toggle and the size
/// picker both draw from this.
///
/// **Why the colours are named here instead of left to the theme.** Material 3
/// paints a *selected* chip with `colorScheme.secondaryContainer` and inks it
/// `onSecondaryContainer`. This app builds its `ColorScheme` by hand
/// (`app_theme.dart`) and sets neither role, so both fell back to Flutter's
/// baseline — which put the sheet's dark ink (the `labelStyle` below used to be
/// the only colour given) on a dark fill. The seller's selected unit rendered
/// as a black pill with black text in it, unreadable, and the same was true of
/// every selected size in the picker (2026-09-29).
///
/// So the pair is explicit, and it is the pair the rest of the app already
/// uses for a chosen chip (the POS size grid, the auth gender pickers): brand
/// clay fill, white ink, no checkmark, and an unchosen chip on the page surface
/// inside a hairline. Naming them once here is also why the next chip added to
/// this sheet cannot reintroduce the bug.
ChoiceChip _choiceChip({
  required String label,
  required bool selected,
  required VoidCallback onTap,
  TextStyle? labelStyle,
}) =>
    ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      // The tick would sit beside the label the fill and the ink already spell
      // out, and on a compact chip it is the thing that eats the width.
      showCheckmark: false,
      selectedColor: AppConstants.primary,
      backgroundColor: AppConstants.surfaceLight,
      side: BorderSide(
        color: selected
            ? Colors.transparent
            : AppConstants.borderGray.withValues(alpha: 0.5),
        width: 1,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: AppConstants.stadiumRadius,
      ),
      labelStyle: (labelStyle ?? AppConstants.bodyStyle(fontSize: 12)).copyWith(
        fontWeight: FontWeight.w600,
        color: selected ? Colors.white : AppConstants.secondary,
      ),
      visualDensity: VisualDensity.compact,
    );

/// One legend line: the arrow's colour, and the box it belongs to.
class _MeasureGuideEntry {
  const _MeasureGuideEntry(this.color, this.label);
  final Color color;
  final String label;
}

const Color kMeasureGuideLengthColor = Color(0xFF8B5A2B);
const Color kMeasureGuideWidthColor = Color(0xFF4ECDC4);
const Color kMeasureGuideHeelColor = Color(0xFFE8A020);
const Color kMeasureGuideUpperColor = Color(0xFF7E57C2);

const List<_MeasureGuideEntry> _measureGuideLegend = [
  _MeasureGuideEntry(
    kMeasureGuideLengthColor,
    'Outside length — heel to toe, along the outside of the pair. This is the '
        'one the model is scaled to, so it is the one to get right.',
  ),
  _MeasureGuideEntry(
    kMeasureGuideWidthColor,
    'Outside width — across the widest part, usually the ball of the foot.',
  ),
  _MeasureGuideEntry(
    kMeasureGuideHeelColor,
    'Heel height — the sole and stack under the heel, not the top of the shoe.',
  ),
  _MeasureGuideEntry(
    kMeasureGuideUpperColor,
    'Height of the shoe — the ground to the highest point, collar or strap.',
  ),
];

/// The size picker both size boxes open. Single-select pops on tap; multi-select
/// keeps a tap per size and finishes with Done, because a run is several taps by
/// nature and closing on the first one would be a bug the seller cannot undo.
class _SizePickerSheet extends StatefulWidget {
  const _SizePickerSheet({
    required this.title,
    required this.subtitle,
    required this.multi,
    required this.initial,
  });

  final String title;
  final String subtitle;
  final bool multi;
  final Set<double> initial;

  @override
  State<_SizePickerSheet> createState() => _SizePickerSheetState();
}

class _SizePickerSheetState extends State<_SizePickerSheet> {
  late final Set<double> _selected = {...widget.initial};

  void _tap(double size) {
    if (!widget.multi) {
      Navigator.of(context).pop(<double>{size});
      return;
    }
    setState(() {
      if (!_selected.remove(size)) _selected.add(size);
    });
  }

  @override
  Widget build(BuildContext context) {
    final chosen = normaliseSizeRun(_selected);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 3,
                decoration: BoxDecoration(
                  color: AppConstants.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(widget.title,
                style: AppConstants.headlineStyle(fontSize: 18)),
            const SizedBox(height: 6),
            Text(widget.subtitle,
                style: AppConstants.bodyStyle(fontSize: 12)),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final size in kRequestEuSizes)
                      _choiceChip(
                        label: formatSizeNumber(size),
                        selected: _selected.contains(size),
                        onTap: () => _tap(size),
                        labelStyle: AppConstants.monoStyle(fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
            if (widget.multi) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      chosen.isEmpty
                          ? 'No sizes picked'
                          : 'Picked: ${chosen.map(formatSizeNumber).join(', ')}',
                      style: AppConstants.bodyStyle(
                        fontSize: 12,
                        color: AppConstants.secondary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text('Clear'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppConstants.primary,
                    ),
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the seller sees while the team is on it — the numbers they sent, so
/// they can check them, and a way out.
class _RequestProgressSheet extends StatelessWidget {
  const _RequestProgressSheet({required this.request, required this.service});

  final ShoeModelRequestRecord? request;
  final ShoeModelRequestService service;

  @override
  Widget build(BuildContext context) {
    final r = request;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 3,
                decoration: BoxDecoration(
                  color: AppConstants.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('3D fitting requested',
                style: AppConstants.headlineStyle(fontSize: 18)),
            const SizedBox(height: 6),
            Text(
              r?.status?.sellerSentence ?? 'Waiting for the CUFMAI team',
              style: AppConstants.bodyStyle(fontSize: 13),
            ),
            if (r != null) ...[
              const SizedBox(height: 12),
              _sentLine('Outside length', r.externalLengthMm),
              _sentLine('Outside width', r.externalWidthMm),
              _sentLine('Heel height', r.heelHeightMm),
              _sentLine('Height of the shoe', r.upperHeightMm),
              _sentLine('Size measured', r.measuredSizeEu),
              // Only when there is one: "Sizes made: —" would read as a hole in
              // the request rather than as a question the seller skipped.
              if (r.sizesEu.isNotEmpty)
                _sentLine(
                  'Sizes made',
                  r.sizesEu.map(formatSizeNumber).join(', '),
                ),
              if (r.note != null && r.note!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('You wrote: ${r.note}',
                    style: AppConstants.bodyStyle(fontSize: 12)),
              ],
            ],
            const SizedBox(height: 16),
            if (r != null && r.isOpen && r.status == ShoeModelRequestStatus.requested)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppConstants.error,
                    side: BorderSide(color: AppConstants.error),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppConstants.surfaceLight,
                        title: Text('Withdraw this request?',
                            style: AppConstants.headlineStyle(fontSize: 18)),
                        content: Text(
                          'The team will stop working on this product. You can '
                          'ask again later.',
                          style: AppConstants.bodyStyle(),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text('Keep it',
                                style: AppConstants.bodyStyle(
                                    color: AppConstants.secondary)),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: AppConstants.error),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text('Withdraw',
                                style: AppConstants.bodyStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                    if (confirm != true || !context.mounted) return;

                    final outcome = await service.cancel(r.id);
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(outcome.message),
                        backgroundColor: outcome.success
                            ? AppConstants.success
                            : AppConstants.error,
                      ),
                    );
                  },
                  child: Text('Withdraw the request',
                      style: AppConstants.bodyStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// One line of "what you sent". A number is millimetres unless the caller has
  /// already formatted it, which is what the size run needs — a run is a list,
  /// and `40–44` is not a measurement to round.
  Widget _sentLine(String label, Object? value) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '$label: ${switch (value) {
            null => '—',
            num n => '${n.round()} mm',
            _ => value.toString(),
          }}',
          style: AppConstants.bodyStyle(fontSize: 13),
        ),
      );
}

