import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../services/shoe_model_request_service.dart';
import '../utils/shoe_model_request.dart';

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
/// The switch is [AppConstants.shoeModelRequestEnabled], **off** until the
/// migration is applied and verified, and off means the row is not there at all.
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
          '3D model',
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
        await showModalBottomSheet<void>(
          context: context,
          backgroundColor: AppConstants.surfaceLight,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => const _RequestReadySheet(),
        );
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
  late final TextEditingController _size;
  late final TextEditingController _note;

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
    _size = TextEditingController(text: prefill.measuredSizeEu);
    _note = TextEditingController();
  }

  @override
  void dispose() {
    _length.dispose();
    _width.dispose();
    _heel.dispose();
    _size.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final result = ShoeModelRequestFormResult.fromFields(
      externalLengthMm: _length.text,
      externalWidthMm: _width.text,
      heelHeightMm: _heel.text,
      measuredSizeEu: _size.text,
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
                'Ask for a 3D model',
                style: AppConstants.headlineStyle(fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                'The CUFMAI team will build the 3D model for this product, so '
                'customers can try it on. Measure a pair — outside the shoe, '
                'heel to toe — and put the numbers in below. Millimetres, like '
                '270.',
                style: AppConstants.bodyStyle(fontSize: 13),
              ),
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
              _field(
                controller: _length,
                label: 'Outside length (mm) — required',
                hint: '270',
                field: ShoeModelRequestField.externalLengthMm,
              ),
              _field(
                controller: _width,
                label: 'Outside width (mm)',
                hint: '105',
                field: ShoeModelRequestField.externalWidthMm,
              ),
              _field(
                controller: _heel,
                label: 'Heel height (mm)',
                hint: '25',
                field: ShoeModelRequestField.heelHeightMm,
              ),
              _field(
                controller: _size,
                label: 'Size you measured (EU)',
                hint: '42',
                field: ShoeModelRequestField.measuredSizeEu,
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
          errorText: message,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
            Text('3D model requested',
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
              _sentLine('Size measured', r.measuredSizeEu),
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

  Widget _sentLine(String label, double? value) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '$label: ${value == null ? '—' : '${value.round()} mm'}',
          style: AppConstants.bodyStyle(fontSize: 13),
        ),
      );
}

class _RequestReadySheet extends StatelessWidget {
  const _RequestReadySheet();

  @override
  Widget build(BuildContext context) {
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
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: AppConstants.success),
                const SizedBox(width: 8),
                Text('3D model ready',
                    style: AppConstants.headlineStyle(fontSize: 18)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'This product has a model, so customers can try it on. Change it '
              'any time from the product form.',
              style: AppConstants.bodyStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
