import 'package:flutter/material.dart';

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
/// local artisans who cannot. So the row is a request: the seller asks, the
/// CUFMAI team does the modelling, and both sides read
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

  /// The product row, passed to the ready-path's viewer. The ask itself reads
  /// nothing off it — the seller sends no measurements.
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

  ShoeModelRequestAvailability _availability =
      const ShoeModelRequestAvailability();
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
          style: AppConstants.bodyStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
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
            style: AppConstants.bodyStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
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
            service: _service,
            // A declined request is being re-asked, so the seller should see
            // what the team said before they ask again.
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

/// The ask form. No measurements — the fitting sizes itself to each
/// customer's foot, so there is nothing a ruler could add that the team
/// cannot see on the product. The seller sends a bare ask, tells the team
/// anything worth knowing in the note, and reads the wait up front.
class ShoeModelRequestFormSheet extends StatefulWidget {
  const ShoeModelRequestFormSheet({
    super.key,
    required this.productId,
    required this.service,
    this.previous,
  });

  final String productId;
  final ShoeModelRequestService service;

  /// The declined request being re-asked, if this form was opened from one.
  final ShoeModelRequestRecord? previous;

  @override
  State<ShoeModelRequestFormSheet> createState() =>
      _ShoeModelRequestFormSheetState();
}

class _ShoeModelRequestFormSheetState extends State<ShoeModelRequestFormSheet> {
  late final TextEditingController _note;

  bool _sending = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _failure = null);

    setState(() => _sending = true);
    final outcome = await widget.service.request(
      productId: widget.productId,
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
                'The CUFMAI team will build the 3D model for this product, '
                'so customers can try it on. No measuring needed.',
                style: AppConstants.bodyStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              // The wait, up front — a seller who knows it is 9 business
              // days does not open the sheet on day 8 to ask.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppConstants.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppConstants.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.schedule_outlined,
                      size: 16,
                      color: AppConstants.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        kShoeModelRequestTimelineMessage,
                        style: AppConstants.bodyStyle(
                          fontSize: 12,
                          color: AppConstants.secondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
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
              TextField(
                controller: _note,
                maxLines: 3,
                style: AppConstants.bodyStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Anything the team should know (optional)',
                  labelStyle: AppConstants.bodyStyle(fontSize: 13),
                  hintText: 'e.g. the pair in the photos is a size 42',
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
}

/// What the seller sees while the team is on it — what they sent (old asks
/// carry numbers), the wait, and a way out.
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
            Text(
              '3D fitting requested',
              style: AppConstants.headlineStyle(fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              r?.status?.sellerSentence ?? 'Waiting for the CUFMAI team',
              style: AppConstants.bodyStyle(fontSize: 13),
            ),
            if (r != null) ...[
              const SizedBox(height: 12),
              // Old asks show what was sent; bare asks show the wait instead —
              // a row of dashes would read as a hole in the request.
              if (r.hasMeasurements) ...[
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
              ] else
                Text(
                  kShoeModelRequestTimelineMessage,
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    color: AppConstants.secondary,
                    height: 1.4,
                  ),
                ),
              if (r.note != null && r.note!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'You wrote: ${r.note}',
                  style: AppConstants.bodyStyle(fontSize: 12),
                ),
              ],
            ],
            const SizedBox(height: 16),
            if (r != null &&
                r.isOpen &&
                r.status == ShoeModelRequestStatus.requested)
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
                        title: Text(
                          'Withdraw this request?',
                          style: AppConstants.headlineStyle(fontSize: 18),
                        ),
                        content: Text(
                          'The team will stop working on this product. You can '
                          'ask again later.',
                          style: AppConstants.bodyStyle(),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(
                              'Keep it',
                              style: AppConstants.bodyStyle(
                                color: AppConstants.secondary,
                              ),
                            ),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppConstants.error,
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(
                              'Withdraw',
                              style: AppConstants.bodyStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
                  child: Text(
                    'Withdraw the request',
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
