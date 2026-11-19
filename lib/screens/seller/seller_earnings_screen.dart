import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_constants.dart';
import '../../constants/seller_theme_constants.dart';
import '../../utils/payout_account.dart';
import '../../widgets/gcash_flow_kit.dart';
import '../../widgets/sole_text_field.dart';

/// What the platform owes this store, and what it has already paid.
///
/// Money model: every online GCash payment lands in the PLATFORM account, so
/// the seller never holds the customer's cash. Each paid day is batched into
/// one payout (gross − ₱100 delivery − commission) once an admin has confirmed
/// the funds in the statement. The seller reads that debt here and may *ask*
/// for it early (request_my_payout), but only an admin's transfer settles it.
class SellerEarningsScreen extends StatefulWidget {
  const SellerEarningsScreen({super.key});

  @override
  State<SellerEarningsScreen> createState() => _SellerEarningsScreenState();
}

class _SellerEarningsScreenState extends State<SellerEarningsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _payouts = [];
  double _pendingNet = 0;
  int _pendingOrders = 0;
  String? _storeId;
  bool _requesting = false;

  /// Where the money goes, read from the same profile columns the admin
  /// portal prints on a payout batch (`payout_method` / `payout_details`).
  PayoutAccount? _payoutAccount;
  String _payoutMethod = 'gcash';

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
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;

      // The payout destination is a profile column, not a store one — the
      // admin reads these same two fields when preparing the transfer.
      final profile = uid == null
          ? null
          : await client
              .from('profiles')
              .select('payout_method, payout_details')
              .eq('id', uid)
              .maybeSingle();
      final payoutAccount = parsePayoutAccount(
        profile?['payout_method']?.toString(),
        profile?['payout_details']?.toString(),
      );
      final method = profile?['payout_method']?.toString().trim().toLowerCase();
      final payoutMethod =
          (method == null || method.isEmpty) ? 'gcash' : method;

      final store = await client
          .from('stores')
          .select('id')
          .eq('owner_id', client.auth.currentUser?.id ?? '')
          .maybeSingle();

      if (store == null) {
        setState(() {
          _loading = false;
          _payouts = [];
          _storeId = null;
          _payoutAccount = payoutAccount;
          _payoutMethod = payoutMethod;
        });
        return;
      }

      _storeId = store['id']?.toString();

      final payouts = await client
          .from('v_seller_payout_summary')
          .select('id, period_date, gross_amount, delivery_fees, platform_fee, '
              'net_amount, status, paid_at, paid_reference, order_count')
          .eq('store_id', store['id'])
          .order('period_date', ascending: false)
          .limit(30);

      final payable = await client
          .from('v_seller_payables')
          .select('net_amount, order_count')
          .eq('store_id', store['id'])
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _payouts = (payouts as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _pendingNet = (payable?['net_amount'] as num?)?.toDouble() ?? 0;
        _pendingOrders = (payable?['order_count'] as num?)?.toInt() ?? 0;
        _payoutAccount = payoutAccount;
        _payoutMethod = payoutMethod;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[EARNINGS] load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your earnings. Pull to retry.';
      });
    }
  }

  /// Ask the platform to pay this store now instead of waiting for the nightly
  /// batch. The RPC only ever batches orders an admin has already reconciled,
  /// and it never marks the payout paid — the transfer stays manual.
  Future<void> _requestPayout() async {
    if (_storeId == null || _requesting) return;
    setState(() => _requesting = true);
    try {
      final result = await Supabase.instance.client.rpc('request_my_payout');
      final map = result is Map
          ? Map<String, dynamic>.from(result)
          : <String, dynamic>{};
      final net = (map['net_amount'] as num?)?.toDouble() ?? 0;
      final added = (map['orders_added'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      setState(() => _requesting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added == 0 && net == 0
                ? 'Nothing to request yet — only orders whose money the admin '
                    'has already confirmed can be paid out.'
                : 'Payout requested — ₱${net.toStringAsFixed(2)} is waiting for '
                    'the admin\'s transfer.',
          ),
        ),
      );
      await _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _requesting = false);
      // The RPC ships with a migration that is applied by paste. Until it is,
      // PostgREST reports a missing function (PGRST202) or Postgres says 42883;
      // a raw "function does not exist" is not something a seller can act on.
      final notEnabled = e.code == 'PGRST202' ||
          e.code == '42883' ||
          e.message.contains('request_my_payout');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            notEnabled
                ? 'Payout requests are not switched on yet. Your earnings are '
                    'safe — ask the CUFMAI team to enable them.'
                : e.message,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[EARNINGS] request failed: $e');
      if (!mounted) return;
      setState(() => _requesting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not request a payout. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Earnings & Payouts',
          style: AppConstants.headlineStyle(fontSize: 19),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: RefreshIndicator(
        color: SellerTheme.rust,
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: SellerTheme.rust,
        ),
      );
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(fontSize: 13),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
      children: [
        GcashRiseIn(
          child: GcashFlowHeader(
            eyebrow: 'Payouts',
            title: 'Earnings',
            description:
                'Online GCash payments land in the platform account. Each day '
                'is batched into one payout once the admin confirms the money.',
          ),
        ),
        const SizedBox(height: 16),
        GcashRiseIn(order: 1, child: _awaitingPanel()),
        const SizedBox(height: 12),
        GcashRiseIn(
          order: 2,
          // A slide, not a tap: asking the platform to send money is the one
          // action here that should not be one stray thumb away.
          child: GcashSlideToConfirm(
            label: 'Slide to request payout',
            busyLabel: 'Requesting…',
            disabledLabel: 'Nothing to request yet',
            icon: Icons.send_rounded,
            enabled: _pendingOrders > 0,
            busy: _requesting,
            onConfirm: _requestPayout,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _pendingOrders == 0
              ? 'A payout can only cover orders whose money the admin has '
                  'already confirmed in the platform account.'
              : 'Ask any time instead of waiting for the nightly batch. The '
                  'admin still sends the GCash transfer and records the '
                  'reference.',
          textAlign: TextAlign.center,
          style: AppConstants.bodyStyle(
            fontSize: 11,
            height: 1.4,
            color: AppConstants.secondary.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 16),
        GcashRiseIn(order: 3, child: _payoutAccountCard()),
        const SizedBox(height: 20),
        GcashRiseIn(
          order: 4,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'PAYOUT HISTORY',
                  style: AppConstants.monoStyle(
                    fontSize: 9.5,
                    color: AppConstants.secondary.withValues(alpha: 0.55),
                  ).copyWith(letterSpacing: 1.8),
                ),
              ),
              if (_payouts.isNotEmpty)
                GcashStatusPill(
                  label: '${_payouts.length} batches',
                  color: AppConstants.secondary.withValues(alpha: 0.6),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (_payouts.isEmpty)
          GcashRiseIn(
            order: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: AppConstants.primary.withValues(alpha: 0.12),
                ),
                color: AppConstants.primary.withValues(alpha: 0.03),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 24,
                    color: AppConstants.secondary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No payouts yet',
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your first one is generated at the end of the day, after '
                    'the admin reconciles the GCash statement.',
                    textAlign: TextAlign.center,
                    style: AppConstants.bodyStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: AppConstants.secondary.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...List.generate(_payouts.length, (index) {
            final payout = _payouts[index];
            return GcashRiseIn(
              key: ValueKey(payout['id']),
              order: index > 5 ? 6 : index + 3,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _payoutCard(payout),
              ),
            );
          }),
        const SizedBox(height: 14),
        Text(
          'Commission is charged on goods value only. The ₱100 delivery fee '
          'stays with the platform to pay the courier.',
          textAlign: TextAlign.center,
          style: AppConstants.bodyStyle(
            fontSize: 11,
            height: 1.4,
            color: AppConstants.secondary.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _awaitingPanel() {
    return GcashPanel(
      dark: true,
      eyebrow: 'Awaiting payout',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '₱${_pendingNet.toStringAsFixed(2)}',
            style: AppConstants.monoStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: kGcashReceiptInk,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _pendingOrders == 0
                ? 'Nothing waiting. Verified payments appear here once an '
                    'admin confirms the money in the platform account.'
                : '$_pendingOrders verified order(s) already reconciled. They '
                    'are batched into a payout at the end of the day, or as soon '
                    'as you request one.',
            style: AppConstants.bodyStyle(
              fontSize: 11.5,
              height: 1.4,
              color: kGcashReceiptMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// The one place a seller can say where the money goes. It sits above the
  /// history because a batch cannot be sent without it: the admin's Payouts
  /// row reads the same two columns and shows "No payout details on file"
  /// until this is filled in.
  Widget _payoutAccountCard() {
    final account = _payoutAccount;
    final isSet = account?.isSet ?? false;
    return GcashPanel(
      eyebrow: 'PAYOUT ACCOUNT',
      trailing: GcashStatusPill(
        label: isSet ? 'On file' : 'Missing',
        color: isSet ? AppConstants.success : SellerTheme.amber,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            payoutDestinationLabel(account, method: _payoutMethod),
            style: AppConstants.monoStyle(
              fontSize: isSet ? 18 : 13,
              fontWeight: FontWeight.w700,
              color: isSet
                  ? AppConstants.primary
                  : AppConstants.secondary.withValues(alpha: 0.55),
            ),
          ),
          if (isSet && account!.name.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              account.name,
              style: AppConstants.bodyStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            isSet
                ? 'CUFMAI transfers your earnings to this account. Keep the '
                    'number and the name exactly as GCash shows them.'
                : 'A payout can only be sent once a GCash number is on file — '
                    'until then the admin has nowhere to send your earnings.',
            style: AppConstants.bodyStyle(
              fontSize: 11.5,
              height: 1.4,
              color: AppConstants.secondary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          GcashPrimaryButton(
            label: isSet ? 'Edit payout account' : 'Add payout account',
            icon: Icons.edit_outlined,
            showIcon: false,
            onPressed: _editPayoutAccount,
          ),
        ],
      ),
    );
  }

  /// Writes `profiles.payout_method` / `profiles.payout_details` — the seller
  /// owns this row, so the update goes through the ordinary own-profile policy
  /// (the column guard only protects role and suspension fields).
  Future<void> _editPayoutAccount() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;

    final saved = await showModalBottomSheet<PayoutAccount>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PayoutAccountSheet(
        initial: _payoutAccount,
        onSave: (number, holder) async {
          await client.from('profiles').update({
            'payout_method': 'gcash',
            'payout_details': encodePayoutDetails(number: number, name: holder),
          }).eq('id', uid);
        },
      ),
    );

    // Everything here runs only after the sheet has closed and handed back a
    // saved account, so this State is never updated while its route is being
    // torn down.
    if (!mounted || saved == null) return;
    setState(() {
      _payoutAccount = saved;
      _payoutMethod = 'gcash';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Payout account saved — the next batch is sent here.'),
      ),
    );
  }

  Widget _payoutCard(Map<String, dynamic> p) {
    final status = p['status']?.toString() ?? 'draft';
    final net = (p['net_amount'] as num?)?.toDouble() ?? 0;
    final gross = (p['gross_amount'] as num?)?.toDouble() ?? 0;
    final delivery = (p['delivery_fees'] as num?)?.toDouble() ?? 0;
    final fee = (p['platform_fee'] as num?)?.toDouble() ?? 0;
    final orders = (p['order_count'] as num?)?.toInt() ?? 0;
    final date = p['period_date']?.toString() ?? '';

    final paid = status == 'paid';
    final colour = paid
        ? AppConstants.success
        : (status == 'void' ? AppConstants.secondary : SellerTheme.amber);

    return GcashPanel(
      eyebrow: date,
      trailing: GcashStatusPill(
        label: paid ? 'Paid' : (status == 'void' ? 'Void' : 'Scheduled'),
        color: colour,
        icon: paid ? Icons.check : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '₱${net.toStringAsFixed(2)}',
            style: AppConstants.monoStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppConstants.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'net for $orders order(s)',
            style: AppConstants.bodyStyle(
              fontSize: 11.5,
              color: AppConstants.secondary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          GcashInsetTile(
            child: Column(
              children: [
                GcashFactRow(
                  label: 'Gross',
                  value: '₱${gross.toStringAsFixed(2)}',
                ),
                GcashFactRow(
                  label: 'Delivery',
                  value: '− ₱${delivery.toStringAsFixed(2)}',
                ),
                GcashFactRow(
                  label: 'Commission',
                  value: '− ₱${fee.toStringAsFixed(2)}',
                ),
                if ((p['paid_reference']?.toString().isNotEmpty ?? false))
                  GcashFactRow(
                    label: 'Transfer ref',
                    value: p['paid_reference'].toString(),
                  ),
              ],
            ),
          ),
          if ((p['paid_at']?.toString().isNotEmpty ?? false)) ...[
            const SizedBox(height: 8),
            Text(
              'Paid ${_formatWhen(p['paid_at'].toString())}',
              style: AppConstants.bodyStyle(
                fontSize: 11,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatWhen(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    final h =
        local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.month}/${local.day} $h:${local.minute.toString().padLeft(2, '0')} $ampm';
  }
}

/// The payout-account form.
///
/// This is a StatefulWidget rather than a `StatefulBuilder` on purpose: it owns
/// the text controllers and its own saving flag, so both live exactly as long
/// as the sheet does. The previous version disposed the controllers the moment
/// `pop()` returned, while the sheet route was still animating out with its
/// mounted `Form` and text fields — that teardown is what threw
/// `Failed assertion: '_dependents.isEmpty'` and left the seller on a red error
/// screen after saving. It pops with the saved [PayoutAccount], or null when
/// the seller cancels.
class _PayoutAccountSheet extends StatefulWidget {
  const _PayoutAccountSheet({required this.initial, required this.onSave});

  final PayoutAccount? initial;
  final Future<void> Function(String number, String holder) onSave;

  @override
  State<_PayoutAccountSheet> createState() => _PayoutAccountSheetState();
}

class _PayoutAccountSheetState extends State<_PayoutAccountSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _numberCtrl;
  late final TextEditingController _nameCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _numberCtrl = TextEditingController(text: widget.initial?.number ?? '');
    _nameCtrl = TextEditingController(text: widget.initial?.name ?? '');
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final number = normalizeGcashNumber(_numberCtrl.text);
    final holder = _nameCtrl.text.trim();
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(number, holder);
      if (!mounted) return;
      Navigator.of(context).pop(PayoutAccount(number: number, name: holder));
    } catch (e) {
      // Says which side failed: a Postgrest error is the server refusing,
      // anything else is the connection. Either way the seller must know the
      // account was NOT saved, so the message stays on the sheet next to the
      // fields that need fixing instead of vanishing with a snackbar.
      debugPrint('[EARNINGS] payout account save failed: $e');
      if (!mounted) return;
      final detail =
          e is PostgrestException ? e.message : 'check your connection';
      setState(() {
        _saving = false;
        _error = 'Could not save the payout account — $detail';
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
        decoration: BoxDecoration(
          color: AppConstants.surfaceLight,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).viewPadding.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Payout account',
                  style: AppConstants.bodyStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'CUFMAI transfers your earnings to this GCash '
                  'account. Both the number and the name must match '
                  'your wallet — a wrong number sends the money to a '
                  'stranger and it cannot be recalled.',
                  style: AppConstants.bodyStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: AppConstants.secondary.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 16),
                SoleTextField(
                  labelText: 'GCash number',
                  hintText: '09XXXXXXXXX',
                  controller: _numberCtrl,
                  keyboardType: TextInputType.phone,
                  prefixIcon: Icons.phone_iphone,
                  validator: gcashNumberError,
                ),
                const SizedBox(height: 14),
                SoleTextField(
                  labelText: 'Account name',
                  hintText: 'Name shown in your GCash app',
                  controller: _nameCtrl,
                  validator: payoutAccountNameError,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: AppConstants.bodyStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: AppConstants.error,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                GcashPrimaryButton(
                  label: 'Save payout account',
                  showIcon: false,
                  loading: _saving,
                  onPressed: _saving ? null : _save,
                ),
                TextButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
