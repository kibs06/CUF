import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../services/voucher_service.dart';
import '../../widgets/sole_card.dart';
import '../../widgets/sole_primary_button.dart';

/// Seller-facing voucher (discount code) management — ANQUI checklist #5.
///
/// Two jobs, two tabs:
///   • Codes — create a code, see what it is worth and how much of it has
///     been claimed, and stop it early.
///   • Redemptions — who used what, on which order, for how much. This is
///     the reconciliation view (`funded_by` says whether the seller or the
///     platform absorbed the discount).
///
/// Every value shown here came from the server: the discount is computed at
/// checkout time by `public.voucher_evaluate`, never by this screen.
class VouchersScreen extends StatefulWidget {
  const VouchersScreen({super.key});

  @override
  State<VouchersScreen> createState() => _VouchersScreenState();
}

class _VouchersScreenState extends State<VouchersScreen> {
  final _service = VoucherService();

  String? _storeId;
  List<Map<String, dynamic>> _vouchers = const [];
  List<Map<String, dynamic>> _redemptions = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final storeId = await _service.myStoreId();
      final vouchers = await _service.listVouchers();
      final redemptions = await _service.listRedemptions();
      if (!mounted) return;
      setState(() {
        _storeId = storeId;
        _vouchers = vouchers;
        _redemptions = redemptions;
        _loading = false;
      });
    } on VoucherException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'We could not load your vouchers. Please try again.';
        _loading = false;
      });
    }
  }

  // ── Formatting helpers ──────────────────────────────────────────

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  static String _peso(double value) => '₱${value.toStringAsFixed(2)}';

  static String _describe(Map<String, dynamic> v) {
    final type = v['discount_type']?.toString() ?? 'fixed';
    final value = _num(v['discount_value']);
    if (type == 'percent') {
      final cap = _num(v['max_discount_amount']);
      final base = '${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}% off';
      return cap > 0 ? '$base (max ${_peso(cap)})' : base;
    }
    return '${_peso(value)} off';
  }

  static String _window(Map<String, dynamic> v) {
    final start = _date(v['starts_at']);
    final end = _date(v['ends_at']);
    if (start == null && end == null) return 'Always available';
    final buffer = StringBuffer();
    if (start != null) buffer.write('from ${_shortDate(start)} ');
    if (end != null) buffer.write('until ${_shortDate(end)}');
    return buffer.toString().trim();
  }

  static String _shortDate(DateTime d) {
    final local = d.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }

  /// Active / scheduled / stopped / fully claimed — derived, never stored.
  static (String, Color) _status(Map<String, dynamic> v) {
    final active = v['is_active'] != false;
    final end = _date(v['ends_at']);
    final start = _date(v['starts_at']);
    final maxUses = v['max_uses'] == null ? null : _num(v['max_uses']).toInt();
    final uses = _num(v['uses_count']).toInt();
    final now = DateTime.now();

    if (!active || (end != null && now.isAfter(end.toLocal()))) {
      return ('Stopped', AppConstants.secondary.withValues(alpha: 0.6));
    }
    if (start != null && now.isBefore(start.toLocal())) {
      return ('Scheduled', AppConstants.primary);
    }
    if (maxUses != null && uses >= maxUses) {
      return ('Fully claimed', AppConstants.secondary.withValues(alpha: 0.6));
    }
    return ('Active', AppConstants.success);
  }

  // ── Actions ─────────────────────────────────────────────────────

  Future<void> _openCreateSheet() async {
    final storeId = _storeId;
    if (storeId == null) {
      _snack('We could not find your store. Please finish setting it up first.');
      return;
    }
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VoucherFormSheet(service: _service, storeId: storeId),
    );
    if (created == true) await _load();
  }

  Future<void> _stop(Map<String, dynamic> voucher) async {
    final code = voucher['code']?.toString() ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop this voucher?'),
        content: Text(
          '$code will stop working immediately. Orders that already used it '
          'keep their discount, and the redemption history stays available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it running'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Stop voucher'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.deactivateVoucher(voucher['id'].toString());
      if (!mounted) return;
      _snack('$code has been stopped.');
      await _load();
    } on VoucherException catch (e) {
      if (!mounted) return;
      _snack(e.message);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppConstants.secondary),
    );
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppConstants.surfaceLight,
        appBar: AppBar(
          title: Text('Vouchers',
              style: AppConstants.headlineStyle(fontSize: 20)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          bottom: TabBar(
            labelColor: AppConstants.primary,
            unselectedLabelColor:
                AppConstants.secondary.withValues(alpha: 0.6),
            indicatorColor: AppConstants.primary,
            tabs: const [
              Tab(text: 'Codes'),
              Tab(text: 'Redemptions'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorView()
                : TabBarView(
                    children: [_codesTab(), _redemptionsTab()],
                  ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 40, color: AppConstants.error),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(color: AppConstants.secondary),
            ),
            const SizedBox(height: 16),
            SolePrimaryButton(label: 'Try again', onPressed: _load),
          ],
        ),
      ),
    );
  }

  Widget _codesTab() {
    if (_vouchers.isEmpty) {
      return _emptyState(
        icon: Icons.local_offer_outlined,
        title: 'No voucher codes yet',
        body:
            'Create a code like ANQUI10 and share it — customers enter it at '
            'checkout and the discount is applied to their order total.',
        action: 'Create a voucher',
        onAction: _openCreateSheet,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          for (final voucher in _vouchers) ...[
            _voucherCard(voucher),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _voucherCard(Map<String, dynamic> voucher) {
    final (label, color) = _status(voucher);
    final code = voucher['code']?.toString() ?? '';
    final uses = _num(voucher['uses_count']).toInt();
    final maxUses =
        voucher['max_uses'] == null ? null : _num(voucher['max_uses']).toInt();
    final perUser = _num(voucher['per_user_limit']).toInt();
    final minOrder = _num(voucher['min_order_amount']);
    final platformFunded = voucher['funded_by']?.toString() == 'platform';
    final stopped = !(voucher['is_active'] != false);

    return SoleCard(
      color: AppConstants.sellerCardBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  code,
                  style: AppConstants.monoStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.primary,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_describe(voucher),
              style: AppConstants.bodyStyle(
                  fontSize: 13, color: AppConstants.secondary)),
          const SizedBox(height: 4),
          Text(
            '${maxUses == null ? '$uses used' : '$uses of $maxUses used'}  •  '
            '${perUser > 1 ? 'up to $perUser per customer' : '1 per customer'}',
            style: AppConstants.bodyStyle(
              fontSize: 11,
              color: AppConstants.secondary.withValues(alpha: 0.6),
            ),
          ),
          if (minOrder > 0) ...[
            const SizedBox(height: 2),
            Text('Minimum order ${_peso(minOrder)}',
                style: AppConstants.bodyStyle(
                  fontSize: 11,
                  color: AppConstants.secondary.withValues(alpha: 0.6),
                )),
          ],
          const SizedBox(height: 2),
          Text(_window(voucher),
              style: AppConstants.bodyStyle(
                fontSize: 11,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              )),
          if (platformFunded) ...[
            const SizedBox(height: 4),
            Text('Funded by CUFMAI — you still receive the full order total.',
                style: AppConstants.bodyStyle(
                    fontSize: 11, color: AppConstants.success)),
          ],
          if (!stopped) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _stop(voucher),
                child: const Text('Stop voucher'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _redemptionsTab() {
    if (_redemptions.isEmpty) {
      return _emptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No redemptions yet',
        body:
            'When a customer checks out with one of your codes, the order and '
            'the discount it took appear here.',
      );
    }

    final total = _redemptions.fold<double>(
        0, (sum, r) => sum + _num(r['discount_amount']));
    final storeFunded = _redemptions
        .where((r) => r['funded_by']?.toString() != 'platform')
        .fold<double>(0, (sum, r) => sum + _num(r['discount_amount']));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          SoleCard(
            color: AppConstants.sellerCardBg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total discounted',
                    style: AppConstants.bodyStyle(
                        fontSize: 12, color: AppConstants.secondary)),
                const SizedBox(height: 4),
                Text(_peso(total),
                    style: AppConstants.headlineStyle(fontSize: 22)),
                const SizedBox(height: 4),
                Text('${_redemptions.length} redemption(s)',
                    style: AppConstants.bodyStyle(
                        fontSize: 11,
                        color: AppConstants.secondary.withValues(alpha: 0.6))),
                if (storeFunded != total) ...[
                  const SizedBox(height: 6),
                  Text(
                    'You absorb ${_peso(storeFunded)}; CUFMAI covers '
                    '${_peso(total - storeFunded)}.',
                    style: AppConstants.bodyStyle(
                        fontSize: 11, color: AppConstants.success),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final redemption in _redemptions) ...[
            _redemptionTile(redemption),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _redemptionTile(Map<String, dynamic> redemption) {
    final code = redemption['code']?.toString() ?? '';
    final profile = redemption['profiles'];
    final customerName = profile is Map
        ? (profile['full_name']?.toString() ?? 'Customer')
        : 'Customer';
    final orderId = redemption['order_id']?.toString() ?? '';
    final shortOrder = orderId.length > 8 ? orderId.substring(0, 8) : orderId;
    final when = _date(redemption['created_at']);

    return SoleCard(
      color: AppConstants.sellerCardBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.local_offer_outlined,
              size: 18, color: AppConstants.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(code,
                          style: AppConstants.monoStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.primary,
                          )),
                    ),
                    Text('−${_peso(_num(redemption['discount_amount']))}',
                        style: AppConstants.bodyStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.success,
                        )),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$customerName  •  order #$shortOrder'
                  '${when != null ? '  •  ${_shortDate(when)}' : ''}',
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String body,
    String? action,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppConstants.borderGray),
            const SizedBox(height: 14),
            Text(title, style: AppConstants.headlineStyle(fontSize: 17)),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                  fontSize: 13, color: AppConstants.secondary),
            ),
            if (action != null && onAction != null) ...[
              const SizedBox(height: 20),
              SolePrimaryButton(label: action, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

/// Create-a-code sheet. Money terms are write-once (the server freezes them
/// after the first redemption), so this is create-only — editing is limited
/// to the caps and window from the card actions.
class _VoucherFormSheet extends StatefulWidget {
  final VoucherService service;
  final String storeId;

  const _VoucherFormSheet({required this.service, required this.storeId});

  @override
  State<_VoucherFormSheet> createState() => _VoucherFormSheetState();
}

class _VoucherFormSheetState extends State<_VoucherFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _valueController = TextEditingController(text: '10');
  final _minOrderController = TextEditingController(text: '0');
  final _maxUsesController = TextEditingController();
  final _perUserController = TextEditingController(text: '1');

  String _type = 'percent';
  DateTime? _endsAt;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _valueController.dispose();
    _minOrderController.dispose();
    _maxUsesController.dispose();
    _perUserController.dispose();
    super.dispose();
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endsAt ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      // End of the chosen day, local time.
      setState(() => _endsAt =
          DateTime(picked.year, picked.month, picked.day, 23, 59, 59));
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.createVoucher(
        storeId: widget.storeId,
        code: _codeController.text,
        discountType: _type,
        discountValue: double.parse(_valueController.text.trim()),
        minOrderAmount:
            double.tryParse(_minOrderController.text.trim()) ?? 0,
        maxUses: int.tryParse(_maxUsesController.text.trim()),
        perUserLimit: int.tryParse(_perUserController.text.trim()) ?? 1,
        endsAt: _endsAt,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on VoucherException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'We could not save that code. Please try again.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppConstants.surfaceLight,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('New voucher',
                    style: AppConstants.headlineStyle(fontSize: 18)),
                const SizedBox(height: 16),
                _field(
                  controller: _codeController,
                  label: 'Code',
                  hint: 'ANQUI10',
                  validator: (value) {
                    final code = (value ?? '').trim();
                    if (code.length < 3) {
                      return 'Use at least 3 characters';
                    }
                    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(code)) {
                      return 'Letters, numbers, - and _ only';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                Text('Discount',
                    style: AppConstants.bodyStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'percent', label: Text('% off')),
                          ButtonSegment(
                              value: 'fixed', label: Text('₱ off')),
                        ],
                        selected: {_type},
                        onSelectionChanged: (selection) =>
                            setState(() => _type = selection.first),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _field(
                  controller: _valueController,
                  label: _type == 'percent' ? 'Percent off' : 'Amount off (₱)',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    final parsed = double.tryParse((value ?? '').trim());
                    if (parsed == null || parsed <= 0) {
                      return 'Enter a value greater than zero';
                    }
                    if (_type == 'percent' && parsed > 100) {
                      return 'A percentage cannot exceed 100';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                _field(
                  controller: _minOrderController,
                  label: 'Minimum order (₱)',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 14),
                _field(
                  controller: _maxUsesController,
                  label: 'Maximum uses (blank = unlimited)',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 14),
                _field(
                  controller: _perUserController,
                  label: 'Uses per customer',
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final parsed = int.tryParse((value ?? '').trim());
                    if (parsed == null || parsed < 1) return 'At least 1';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: _pickEndDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Ends',
                      filled: true,
                      fillColor: AppConstants.sellerCardBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppConstants.borderGray.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    child: Text(
                      _endsAt == null
                          ? 'No end date'
                          : VouchersScreenDate.format(_endsAt!),
                      style: AppConstants.bodyStyle(
                          fontSize: 14, color: AppConstants.secondary),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: AppConstants.bodyStyle(
                          fontSize: 12, color: AppConstants.error)),
                ],
                const SizedBox(height: 20),
                SolePrimaryButton(
                  label: _saving ? 'Saving…' : 'Create voucher',
                  onPressed: _saving ? null : _save,
                ),
                const SizedBox(height: 8),
                Text(
                  'Codes cannot be edited once someone has used them — create '
                  'a new code instead. You can always stop a running code.',
                  style: AppConstants.bodyStyle(
                    fontSize: 11,
                    color: AppConstants.secondary.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      textCapitalization: label == 'Code'
          ? TextCapitalization.characters
          : TextCapitalization.none,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: AppConstants.sellerCardBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppConstants.borderGray.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

/// Shared short-date formatting for the sheet (kept tiny on purpose).
class VouchersScreenDate {
  const VouchersScreenDate._();

  static String format(DateTime date) {
    final local = date.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }
}
