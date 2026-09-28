import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../exceptions/shoe_model_upload_exception.dart';
import '../services/shoe_model_request_service.dart';
import '../services/shoe_model_upload_service.dart';
import '../utils/shoe_model_request.dart';
import '../utils/shoe_model_upload.dart';
import 'shoe_model_report_card.dart';

/// The admin's side of the model request flow (roadmap V2.11, P2 of V2.10):
/// **fetch a `.glb`, publish it against the requested product, and close the
/// ask** — one sheet, because those three steps are one act of work.
///
/// **Why this exists at all.** The seller asked because they cannot produce a
/// contract-compliant `.glb` (that is the whole premise of V2.10). The queue's
/// other action, *Close as done*, can only point at a model that already exists
/// — so without this sheet the ask could be answered only by someone with a
/// terminal, a handover link and `tool/prepare_shoe_model.dart`. The pipeline
/// would have a door the person holding the request could not open.
///
/// **It reuses the seller's write path deliberately, and adds no second one.**
/// [ShoeModelUploadService.publish] is still the only writer: storage first,
/// then a `draft` row, then `validate-shoe-model` decides whether it may be
/// live. The interesting consequence is that **nothing here writes
/// `status='active'`** — the sheet is a caller of the same gate, not a way
/// around it, which is also why the database trigger from V2.4 does not need a
/// hole cut in it for admins.
///
/// **The one new rule is the length.** The seller measured the outside of the
/// pair; the model is scaled to the figure the modeller *declares*. So the
/// seller's measurement is prefilled — it is the same quantity, already measured
/// by the person holding the shoe — and a declaration that drifts more than the
/// contract's ±5 mm from it earns a note rather than a refusal
/// ([shoeModelDeclaredLengthAgreement]): the admin may know the seller measured
/// the wrong pair, and a wrong-looking note should not block a right model.
///
/// **Publish and close are two writes, and the sheet reports both** — including
/// the state in between ([ShoeModelRequestModellingEnding.liveButOpen]), because
/// a model that is live while the seller still reads "waiting" is exactly the
/// outcome this feature must not quietly produce.
///
/// The switch is [AppConstants.adminModelUploadAllowed] — this surface's own
/// switch **and** the pipeline's write switch — and off means the sheet renders
/// nothing at all.
class ShoeModelRequestUploadSheet extends StatefulWidget {
  const ShoeModelRequestUploadSheet({
    super.key,
    required this.request,
    this.requestService,
    this.uploadService,
    this.enabled = AppConstants.adminModelUploadAllowed,
  });

  /// The ask being answered: it carries the product, the store the object path
  /// must name, and the seller's own measurement.
  final ShoeModelRequestRecord request;

  /// Injected by tests. The default is the production wiring.
  final ShoeModelRequestService? requestService;
  final ShoeModelUploadService? uploadService;

  final bool enabled;

  @override
  State<ShoeModelRequestUploadSheet> createState() =>
      _ShoeModelRequestUploadSheetState();
}

class _ShoeModelRequestUploadSheetState
    extends State<ShoeModelRequestUploadSheet> {
  late final ShoeModelRequestService _requests =
      widget.requestService ?? ShoeModelRequestService.createDefault();
  late final ShoeModelUploadService _upload =
      widget.uploadService ?? ShoeModelUploadService.createDefault();

  late final TextEditingController _link;
  late final TextEditingController _length;
  late final TextEditingController _size;
  late final TextEditingController _note;

  /// The file that was fetched and checked, held for the publish step.
  ShoeModelAsset? _asset;

  bool _checking = false;
  bool _publishing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _link = TextEditingController();
    // Prefilled from the seller's ask — see the class doc. Not `_note`: there is
    // nothing to prefill it with, and a note the admin did not write is worse
    // than an empty box (the seller reads it as the team's words).
    final prefill = shoeModelRequestModellingPrefill(
      externalLengthMm: widget.request.externalLengthMm,
      measuredSizeEu: widget.request.measuredSizeEu,
    );
    _length = TextEditingController(text: prefill.externalLengthMm);
    _size = TextEditingController(text: prefill.authoredSizeEu);
    _note = TextEditingController();
  }

  @override
  void dispose() {
    _link.dispose();
    _length.dispose();
    _size.dispose();
    _note.dispose();
    super.dispose();
  }

  /// The declaration read off the two fields — the same parser the seller's form
  /// uses, so a centimetre figure is refused in the same words on both surfaces.
  ShoeModelDeclarationResult get _declaration =>
      ShoeModelDeclarationResult.fromFields(
        externalLengthMm: _length.text,
        authoredSizeEu: _size.text,
      );

  ShoeModelUploadGate get _gate => shoeModelUploadGate(
        productId: widget.request.productId,
        asset: _asset,
        declaration: _declaration,
      );

  /// The declared length against the seller's measurement. A note, never a gate.
  ({bool disagrees, String? message}) get _agreement =>
      shoeModelDeclaredLengthAgreement(
        measuredMm: widget.request.externalLengthMm,
        declaredMm: _declaration.externalLengthMm,
      );

  Future<void> _check() async {
    final url = _link.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Paste the link to the exported .glb first.');
      return;
    }

    final declaration = _declaration;
    if (declaration.isError) {
      setState(() => _error = declaration.error);
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
      // The previous file is dropped now rather than kept beside the spinner: a
      // stale report next to a new link is how the wrong model gets published
      // (the seller's form learned this first).
      _asset = null;
    });

    try {
      final asset = await _upload.fetchAndValidate(
        url: url,
        declaredExternalLengthMm: declaration.externalLengthMm,
        authoredSizeEu: declaration.authoredSizeEu,
        label: 'request-${widget.request.id}',
      );
      if (!mounted) return;
      setState(() => _asset = asset);
    } on ShoeModelUploadException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _error = 'Could not check that file. Check the connection and try again.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _publish() async {
    final asset = _asset;
    if (asset == null) return;

    final gate = _gate;
    if (!gate.ready) {
      setState(() => _error = gate.message);
      return;
    }

    setState(() {
      _publishing = true;
      _error = null;
    });

    ShoeModelPublishOutcome outcome;
    try {
      outcome = await _upload.publish(
        storeId: widget.request.storeId,
        productId: widget.request.productId,
        asset: asset,
      );
    } on ShoeModelUploadException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _publishing = false;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'The upload could not be sent. Check the connection and try '
            'again — nothing was published.';
        _publishing = false;
      });
      return;
    }

    final live = outcome.status == 'active';
    final modelId = shoeModelRowId(outcome.row['id']);

    // Only a live model can close an ask — the RPC requires it — so the close
    // is attempted only when there is something to point at.
    var fulfilled = false;
    if (live && modelId != null) {
      final note = _note.text.trim();
      final close = await _requests.fulfil(
        requestId: widget.request.id,
        modelId: modelId,
        note: note.isEmpty ? null : note,
      );
      fulfilled = close.success;
    }

    final result = shoeModelRequestModellingResult(
      modelIsLive: live,
      fulfilled: fulfilled,
      modelId: modelId,
      refusal: outcome.serverVerdict?.sellerMessage,
    );

    if (!mounted) return;

    // Nothing went live: stay open, because the admin still has the report and
    // the fields in front of them and the fix is usually one of the two. The
    // other endings have nothing left to do in here.
    if (result.ending == ShoeModelRequestModellingEnding.notLive) {
      setState(() {
        _error = result.message;
        _publishing = false;
      });
      return;
    }

    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();

    final declaration = _declaration;
    final agreement = _agreement;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
            Text('Upload the model', style: AppConstants.headlineStyle(fontSize: 18)),
            const SizedBox(height: 6),
            Text(
              'Paste a link to the finished .glb for '
              '${widget.request.productName ?? 'this product'}. Publishing it '
              'makes it live for customers and closes the seller\'s request in '
              'the same step.',
              style: AppConstants.bodyStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _link,
              style: AppConstants.bodyStyle(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Link to the .glb',
                labelStyle: AppConstants.bodyStyle(fontSize: 13),
                hintText: 'https://…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _length,
              onChanged: (_) => setState(() {}),
              style: AppConstants.bodyStyle(fontSize: 14),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Declared length (mm, outside)',
                labelStyle: AppConstants.bodyStyle(fontSize: 13),
                hintText: '270',
                helperText: widget.request.externalLengthMm == null
                    ? null
                    : 'The seller measured '
                        '${widget.request.externalLengthMm!.round()} mm outside',
                helperStyle: AppConstants.bodyStyle(
                  fontSize: 11,
                  color: AppConstants.secondary.withValues(alpha: 0.6),
                ),
                errorText: declaration.messageFor(ShoeModelField.externalLengthMm),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            // ⚠️ The one rule this surface adds: the mesh is scaled to the
            // DECLARED length, so a declaration that drifts from the seller's own
            // measurement is worth reading before it is published. A note, not an
            // error — the admin may know the seller measured the wrong pair.
            if (agreement.message != null) ...[
              const SizedBox(height: 10),
              _notice(agreement.message!, color: Colors.amber.shade800),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _size,
              onChanged: (_) => setState(() {}),
              style: AppConstants.bodyStyle(fontSize: 14),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Authored at (EU size, optional)',
                labelStyle: AppConstants.bodyStyle(fontSize: 13),
                hintText: '42',
                errorText: declaration.messageFor(ShoeModelField.authoredSizeEu),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _checking ? null : _check,
                icon: _checking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download_outlined, size: 16),
                label: Text(_checking ? 'Checking…' : 'Check the file'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppConstants.primary,
                  side: BorderSide(
                    color: AppConstants.primary.withValues(alpha: 0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppConstants.buttonRadius,
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _notice(_error!, color: AppConstants.error),
            ],
            if (_asset != null) ...[
              const SizedBox(height: 14),
              ShoeModelReportCard(asset: _asset!),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLines: 2,
                style: AppConstants.bodyStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Note for the seller (optional)',
                  labelStyle: AppConstants.bodyStyle(fontSize: 13),
                  hintText: 'e.g. modelled from the studio capture',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _gate.ready
                        ? AppConstants.success
                        : Colors.grey.shade300,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed:
                      (_publishing || !_gate.ready) ? null : _publish,
                  child: Text(
                    _publishing ? 'Publishing…' : 'Publish and close the request',
                    style: AppConstants.bodyStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'The server checks the stored bytes before the model goes live '
                '(the same contract this report ran), so a refusal leaves it '
                'hidden and the request open.',
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  color: AppConstants.secondary.withValues(alpha: 0.55),
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _notice(String message, {required Color color}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppConstants.bodyStyle(
                fontSize: 12,
                color: AppConstants.secondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
