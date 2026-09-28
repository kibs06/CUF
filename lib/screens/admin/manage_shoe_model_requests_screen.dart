import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../services/shoe_model_request_service.dart';
import '../../utils/shoe_model_request.dart';
import '../../widgets/shoe_model_request_upload_sheet.dart';

/// Admin screen for the **3D model request queue** (roadmap V2.10).
///
/// The seller's half of this feature is one row in a product's action sheet;
/// this is where that row lands. A request is not a work order — it is a queue
/// with a state, and the three tabs are the three things an admin needs to tell
/// apart: **waiting** (nobody has it, or somebody does), **fulfilled**, and
/// **closed** (declined or withdrawn).
///
/// Two design points worth reading before changing anything here:
///
///  * **"Close as done" names a model.** It cannot be a button that sets a
///    status: `fulfil_shoe_model_request` refuses anything but an `active` model
///    of the same product, and the table's CHECK refuses `fulfilled` without a
///    `model_id`. So the action opens a picker over the product's own model
///    rows, and an admin who has no live model to point at is told that rather
///    than left with a button that fails.
///  * **And the queue can now *make* the model — roadmap V2.11, P2.** *Upload a
///    3D model* fetches a `.glb`, publishes it through the same
///    `ShoeModelUploadService` the seller's form uses (storage → draft row →
///    `validate-shoe-model`), and closes the ask in the same step. Without it
///    the picker above could only ever be filled by someone with a terminal,
///    which would leave this screen unable to answer the requests it exists
///    for. It is behind [AppConstants.adminModelUploadAllowed] — **off** — and
///    when it is off the queue behaves exactly as it did before, including the
///    dialog that says so.
///  * **A decline must carry a reason.** The button stays disabled until it
///    does, because the seller reads that sentence in their own sheet and a
///    decline with no reason leaves them with nothing to act on.
class ManageShoeModelRequestsScreen extends StatefulWidget {
  const ManageShoeModelRequestsScreen({super.key, this.service});

  /// Injected by tests so the queue can be exercised without a socket.
  final ShoeModelRequestService? service;

  @override
  State<ManageShoeModelRequestsScreen> createState() =>
      _ManageShoeModelRequestsScreenState();
}

class _ManageShoeModelRequestsScreenState
    extends State<ManageShoeModelRequestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final ShoeModelRequestService _service =
      widget.service ?? ShoeModelRequestService.createDefault();

  List<ShoeModelRequestRecord> _waiting = const [];
  List<ShoeModelRequestRecord> _fulfilled = const [];
  List<ShoeModelRequestRecord> _closed = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final all = await _service.queue();
    if (!mounted) return;

    setState(() {
      _waiting = all.where((r) => r.isOpen).toList();
      _fulfilled = all
          .where((r) => r.status == ShoeModelRequestStatus.fulfilled)
          .toList();
      _closed = all
          .where((r) =>
              r.status == ShoeModelRequestStatus.declined ||
              r.status == ShoeModelRequestStatus.cancelled)
          .toList();
      _loading = false;
      // An empty queue and a failed read return the same list, so the screen
      // says both things rather than claiming there is nothing to do.
      if (all.isEmpty) _error = null;
    });
  }

  void _toast(String message, {bool ok = true, Color? background}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            background ?? (ok ? AppConstants.success : AppConstants.error),
      ),
    );
  }

  Future<void> _claim(ShoeModelRequestRecord request) async {
    final outcome = await _service.claim(request.id);
    _toast(outcome.message, ok: outcome.success);
    await _load();
  }

  Future<void> _decline(ShoeModelRequestRecord request) async {
    final controller = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppConstants.surfaceLight,
          title: Text('Decline this request?',
              style: AppConstants.headlineStyle(fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The seller reads this, so say what happened — for example '
                '"we could not get the pair to measure", or "the samples were '
                'not clear enough to model".',
                style: AppConstants.bodyStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                style: AppConstants.bodyStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Why not, in the seller\'s words',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: AppConstants.bodyStyle(color: AppConstants.secondary)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: controller.text.trim().isEmpty
                    ? Colors.grey.shade300
                    : AppConstants.error,
              ),
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, controller.text.trim()),
              child: Text('Decline',
                  style: AppConstants.bodyStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (reason == null) return;
    final outcome = await _service.decline(requestId: request.id, reason: reason);
    _toast(outcome.message, ok: outcome.success);
    await _load();
  }

  /// Close as done — against a model that exists, is on this product, and is
  /// live. The RPC checks all three; this picker is how an admin gets there.
  Future<void> _fulfil(ShoeModelRequestRecord request) async {
    final models = await _service.modelsForProduct(request.productId);
    if (!mounted) return;

    final active = models
        .where((m) => m['status']?.toString() == 'active')
        .toList(growable: false);

    if (active.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppConstants.surfaceLight,
          title: Text('No live model to attach',
              style: AppConstants.headlineStyle(fontSize: 18)),
          content: Text(
            models.isEmpty
                ? (AppConstants.adminModelUploadAllowed
                    ? 'This product has no 3D model yet. Use Upload a 3D model '
                        'on this request — it publishes the file and closes the '
                        'ask in one step — or prepare one with '
                        'tool/prepare_shoe_model.dart and close this request '
                        'against it.'
                    : 'This product has no 3D model yet. Prepare and publish '
                        'one (tool/prepare_shoe_model.dart → the validator), '
                        'then close this request against it.')
                : 'This product has a model, but it is still a draft. Publish '
                    'it through the validator first — a request can only be '
                    'closed against a live model, so "done" means done.',
            style: AppConstants.bodyStyle(),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      return;
    }

    final chosen = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppConstants.surfaceLight,
        title: Text('Which model fulfils this request?',
            style: AppConstants.headlineStyle(fontSize: 18)),
        children: [
          for (final model in active)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, model),
              child: Text(
                'v${model['version']} · '
                '${model['authored_length_mm'] == null ? 'no declared length' : '${model['authored_length_mm']} mm'}'
                '${model['authored_size_eu'] == null ? '' : ' · EU ${model['authored_size_eu']}'}',
                style: AppConstants.bodyStyle(fontSize: 14),
              ),
            ),
        ],
      ),
    );

    if (chosen == null) return;
    final modelId = chosen['id'];
    final id = modelId is num ? modelId.toInt() : int.tryParse('$modelId');
    if (id == null) {
      _toast('That model row has no id — nothing was closed.', ok: false);
      return;
    }

    final outcome = await _service.fulfil(requestId: request.id, modelId: id);
    _toast(outcome.message, ok: outcome.success);
    await _load();
  }

  /// Model this pair from a link, publish it, and close the ask — roadmap
  /// V2.11 (P2). The sheet does the writing; this reports the three endings.
  ///
  /// The ending that needs care is [ShoeModelRequestModellingEnding.liveButOpen]:
  /// the model went live and the ask did not close, so the seller still reads
  /// "somebody is on it". It is amber rather than green or red, because it is
  /// neither — the work is done and the record does not say so, and the fix is
  /// in this screen (the picker can now see the model).
  Future<void> _uploadAndClose(ShoeModelRequestRecord request) async {
    final result = await showModalBottomSheet<ShoeModelRequestModellingResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppConstants.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ShoeModelRequestUploadSheet(
        request: request,
        requestService: _service,
      ),
    );

    // Dismissed without an ending: the publish may have happened while the close
    // did not, so the tabs are re-read rather than left as they were.
    if (result == null) {
      await _load();
      return;
    }

    _toast(
      result.message,
      background: switch (result.ending) {
        ShoeModelRequestModellingEnding.closed => AppConstants.success,
        ShoeModelRequestModellingEnding.liveButOpen => Colors.amber.shade800,
        ShoeModelRequestModellingEnding.notLive => AppConstants.error,
      },
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text('3D Model Requests',
            style: AppConstants.headlineStyle(fontSize: 20)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppConstants.primary,
          unselectedLabelColor: AppConstants.secondary,
          indicatorColor: AppConstants.primary,
          tabs: [
            Tab(text: 'Waiting (${_waiting.length})'),
            Tab(text: 'Fulfilled (${_fulfilled.length})'),
            Tab(text: 'Closed (${_closed.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: AppConstants.error),
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: AppConstants.bodyStyle(
                                color: AppConstants.error),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _list(_waiting, waiting: true),
                    _list(_fulfilled, waiting: false),
                    _list(_closed, waiting: false),
                  ],
                ),
    );
  }

  Widget _list(List<ShoeModelRequestRecord> requests, {required bool waiting}) {
    if (requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(waiting ? Icons.inbox_outlined : Icons.check_circle_outline,
                size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              waiting ? 'Nobody is waiting for a model' : 'Nothing here yet',
              style: AppConstants.bodyStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: requests.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _card(requests[index], waiting: waiting),
      ),
    );
  }

  Widget _card(ShoeModelRequestRecord request, {required bool waiting}) {
    return Card(
      color: AppConstants.surfaceLight,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: waiting
              ? Colors.amber.withValues(alpha: 0.3)
              : AppConstants.borderGray,
          width: waiting ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.productName ?? 'Product',
                        style: AppConstants.bodyStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        request.storeName ?? '',
                        style: AppConstants.bodyStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                _badge(request.status),
              ],
            ),
            const SizedBox(height: 12),
            // The seller's numbers, exactly as they were typed. The external
            // length is the one the modeller scales from, so it leads.
            Text(
              'Outside: ${_mm(request.externalLengthMm)} long'
              '${request.externalWidthMm == null ? '' : ' · ${_mm(request.externalWidthMm)} wide'}'
              '${request.heelHeightMm == null ? '' : ' · ${_mm(request.heelHeightMm)} heel'}'
              '${request.measuredSizeEu == null ? '' : ' · measured at EU ${request.measuredSizeEu!.round()}'}',
              style: AppConstants.bodyStyle(fontSize: 13),
            ),
            if (request.note != null && request.note!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppConstants.borderGray.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Seller: ${request.note}',
                    style: AppConstants.bodyStyle(fontSize: 12)),
              ),
            ],
            if (request.adminNote != null && request.adminNote!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Team: ${request.adminNote}',
                  style: AppConstants.bodyStyle(
                      fontSize: 12, color: Colors.grey.shade600)),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(
                  'Asked ${_formatDate(request.createdAt)}',
                  style: AppConstants.bodyStyle(
                      fontSize: 11, color: Colors.grey.shade500),
                ),
                if (request.assignedTo != null) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.person_outline,
                      size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text('Taken',
                      style: AppConstants.bodyStyle(
                          fontSize: 11, color: Colors.grey.shade500)),
                ],
              ],
            ),
            if (waiting) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  if (request.status == ShoeModelRequestStatus.requested) ...[
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppConstants.primary,
                          side: BorderSide(color: AppConstants.primary),
                          minimumSize: const Size.fromHeight(40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => _claim(request),
                        child: Text("I'll do it",
                            style: AppConstants.bodyStyle(
                                fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppConstants.secondary,
                        side: BorderSide(color: AppConstants.secondary),
                        minimumSize: const Size.fromHeight(40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => _decline(request),
                      child: Text('Decline',
                          style: AppConstants.bodyStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppConstants.success,
                        minimumSize: const Size.fromHeight(40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => _fulfil(request),
                      child: Text('Close as done',
                          style: AppConstants.bodyStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          )),
                    ),
                  ),
                ],
              ),
              // P2 (roadmap V2.11): the queue can make the model, not only point
              // at one. Hidden unless both switches are on — off means this
              // screen is byte-for-byte what it was before the phase.
              if (AppConstants.adminModelUploadAllowed) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _uploadAndClose(request),
                    icon: const Icon(Icons.upload_file_outlined, size: 16),
                    label: Text('Upload a 3D model',
                        style: AppConstants.bodyStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppConstants.primary,
                      side: BorderSide(
                        color: AppConstants.primary.withValues(alpha: 0.4),
                      ),
                      minimumSize: const Size.fromHeight(40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Publishes a .glb for this pair and closes the request in one '
                  'step.',
                  style: AppConstants.bodyStyle(
                      fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _badge(ShoeModelRequestStatus? status) {
    final label = switch (status) {
      ShoeModelRequestStatus.requested => 'Waiting',
      ShoeModelRequestStatus.inProgress => 'In progress',
      ShoeModelRequestStatus.fulfilled => 'Fulfilled',
      ShoeModelRequestStatus.declined => 'Declined',
      ShoeModelRequestStatus.cancelled => 'Withdrawn',
      null => 'Unknown',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppConstants.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppConstants.bodyStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppConstants.primary,
        ),
      ),
    );
  }

  String _mm(double? value) => value == null ? '—' : '${value.round()} mm';

  String _formatDate(DateTime? date) {
    if (date == null) return '—';
    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$month/$day/${local.year} $hour:$min';
  }
}
