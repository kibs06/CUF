import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of the `create-gcash-payment-intent` edge function.
///
/// The server recomputes prices/stock and the Model B GCash fee; the
/// client only ever sends product/size/quantity. [amount] is what the
/// customer is actually charged = order total + GCash fee.
class GcashIntentResult {
  final String orderId;

  /// PayMongo hosted checkout URL — open it in the SYSTEM browser
  /// (never an in-app webview: the GCash handoff uses the gcash://
  /// custom scheme that WebViews do not intercept).
  final String checkoutUrl;

  /// Scoped to this checkout session only — safe for the client to hold.
  final String? clientKey;

  /// Amount charged to the customer (order total + Model B fee).
  final double amount;

  /// The Model B surcharge line shown to the customer.
  final double feeAmount;

  final DateTime? expiresAt;

  /// True when the server returned an already-pending checkout instead of
  /// creating a new one (double-tap / retry / resume).
  final bool alreadyExists;

  const GcashIntentResult({
    required this.orderId,
    required this.checkoutUrl,
    this.clientKey,
    this.amount = 0,
    this.feeAmount = 0,
    this.expiresAt,
    this.alreadyExists = false,
  });

  double get orderTotal => amount - feeAmount;

  factory GcashIntentResult.fromJson(Map<String, dynamic> json) {
    return GcashIntentResult(
      orderId: json['order_id']?.toString() ?? '',
      checkoutUrl: json['checkout_url']?.toString() ?? '',
      clientKey: json['client_key']?.toString(),
      amount: _toDouble(json['amount']) ?? 0,
      feeAmount: _toDouble(json['fee_amount']) ?? 0,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
      alreadyExists: json['already_exists'] == true,
    );
  }
}

/// Authoritative order + payment state (`get-payment-status` edge
/// function). The app NEVER infers payment success from a redirect — it
/// polls this (or the order row) instead.
class GcashStatusResult {
  final String orderId;

  /// orders.status: awaiting_payment | pending | cancelled | payment_conflict | …
  final String status;

  /// orders.payment_status: pending | paid | failed | unpaid
  final String paymentStatus;

  final bool paid;

  final double totalAmount;

  /// orders.cancellation_reason when the order was cancelled/conflicted.
  final String? cancellationReason;

  /// payment_intents.status: pending | succeeded | failed | expired | cancelled
  final String? intentStatus;

  final double? amount;
  final double? feeAmount;
  final DateTime? expiresAt;
  final String? checkoutUrl;

  const GcashStatusResult({
    required this.orderId,
    required this.status,
    required this.paymentStatus,
    required this.paid,
    required this.totalAmount,
    this.cancellationReason,
    this.intentStatus,
    this.amount,
    this.feeAmount,
    this.expiresAt,
    this.checkoutUrl,
  });
}

/// Model B fee breakdown from `get_gcash_fee` (checkout display only —
/// the authoritative fee is computed by the intent edge function).
class GcashFeeInfo {
  final double base;
  final int rateBps;
  final double feeAmount;
  final double totalCharged;

  const GcashFeeInfo({
    required this.base,
    required this.rateBps,
    required this.feeAmount,
    required this.totalCharged,
  });

  factory GcashFeeInfo.fromJson(Map<String, dynamic> json) {
    return GcashFeeInfo(
      base: _toDouble(json['base']) ?? 0,
      rateBps: (json['rate_bps'] as num?)?.toInt() ?? 0,
      feeAmount: _toDouble(json['fee_amount']) ?? 0,
      totalCharged: _toDouble(json['total_charged']) ?? 0,
    );
  }
}

/// Thrown when an edge function or RPC rejects the request.
/// [message] is user-friendly; [statusCode] is the HTTP status of edge
/// function errors (409 = a checkout is already in progress); [code] is
/// the PostgREST error code for RPC errors (P0001 / 23505 / 42501).
class GcashPaymentException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;

  const GcashPaymentException(this.message, {this.statusCode, this.code});

  @override
  String toString() => message;
}

/// Flutter client for the online GCash payment flow (PayMongo Checkout
/// Sessions). The app NEVER writes payment status — it only creates the
/// checkout and then polls for the authoritative state, which the
/// server-side signature-verified webhook controls.
class GcashPaymentService {
  final SupabaseClient _client;

  GcashPaymentService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  /// Step 1: create the order (`awaiting_payment`, no stock touched) +
  /// the PayMongo checkout session, and return the hosted checkout URL.
  /// [idempotencyKey] is a client UUID that makes double-taps/retries
  /// idempotent server-side.
  Future<GcashIntentResult> createIntent({
    required String idempotencyKey,
    required List<Map<String, dynamic>> items,
    String? deliveryAddress,
    Map<String, dynamic>? shippingAddress,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'create-gcash-payment-intent',
        body: {
          'idempotency_key': idempotencyKey,
          'items': items,
          'delivery_address': deliveryAddress,
          'shipping_address': shippingAddress,
        },
      );
      final data = _asMap(res.data);
      return GcashIntentResult.fromJson(data);
    } on FunctionException catch (e) {
      throw GcashPaymentException(
        _edgeMessage(e, fallback: 'We could not start the GCash payment. Please try again.'),
        statusCode: e.status,
      );
    } catch (e) {
      debugPrint('[GCASH] createIntent failed: $e');
      throw GcashPaymentException(
        'We could not start the GCash payment. Please check your connection and try again.',
      );
    }
  }

  /// Step 2: fetch the authoritative order + payment status. Poll this
  /// after the customer returns from GCash — never trust the redirect.
  Future<GcashStatusResult> getStatus(String orderId) async {
    try {
      final res = await _client.functions.invoke(
        'get-payment-status',
        body: {'order_id': orderId},
      );
      final data = _asMap(res.data);
      final payment = data['payment'] is Map
          ? _asMap(data['payment'] as Map)
          : <String, dynamic>{};
      return GcashStatusResult(
        orderId: data['order_id']?.toString() ?? orderId,
        status: data['status']?.toString() ?? '',
        paymentStatus: data['payment_status']?.toString() ?? '',
        paid: data['paid'] == true,
        totalAmount: _toDouble(data['total_amount']) ?? 0,
        cancellationReason: data['cancellation_reason']?.toString(),
        intentStatus: payment['status']?.toString(),
        amount: _toDouble(payment['amount']),
        feeAmount: _toDouble(payment['fee_amount']),
        expiresAt: payment['expires_at'] != null
            ? DateTime.tryParse(payment['expires_at'].toString())
            : null,
        checkoutUrl: payment['checkout_url']?.toString(),
      );
    } on FunctionException catch (e) {
      throw GcashPaymentException(
        _edgeMessage(e, fallback: 'We could not check your payment status.'),
        statusCode: e.status,
      );
    } catch (e) {
      debugPrint('[GCASH] getStatus failed: $e');
      throw GcashPaymentException('We could not check your payment status.');
    }
  }

  /// Customer self-service: cancel their own still-pending checkout
  /// (safe — no money captured, no stock held while awaiting_payment).
  /// Returns true if cancelled; false if it had already resolved.
  Future<bool> cancelPending(String orderId) async {
    try {
      final data = await _client.rpc(
        'cancel_my_pending_payment_intent',
        params: {'p_order_id': orderId},
      );
      return data == true;
    } on PostgrestException catch (e) {
      throw GcashPaymentException(
        _pgMessage(e, fallback: 'We could not cancel this checkout. Please try again.'),
        code: e.code,
      );
    } catch (e) {
      debugPrint('[GCASH] cancelPending failed: $e');
      throw GcashPaymentException('We could not cancel this checkout.');
    }
  }

  /// Model B fee breakdown for a subtotal — shown at checkout BEFORE the
  /// customer submits. Display only (the intent function recomputes
  /// authoritatively). Returns null when the fee isn't configured yet.
  Future<GcashFeeInfo?> fetchFee(double subtotal) async {
    try {
      final data = await _client.rpc(
        'get_gcash_fee',
        params: {'p_subtotal': subtotal},
      );
      return GcashFeeInfo.fromJson(_asMap(data));
    } catch (e) {
      debugPrint('[GCASH] fetchFee failed: $e');
      return null;
    }
  }

  /// The customer's currently-open pending checkout (if any) — used to
  /// resume a checkout that hit the one-pending cap (409) or to handle a
  /// cold-start deep link. RLS limits reads to the caller's own intents.
  Future<GcashIntentResult?> fetchPendingIntent() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await _client
          .from('payment_intents')
          .select('order_id, checkout_url, client_key, amount, fee_amount, expires_at, status')
          .eq('customer_id', uid)
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) return null;
      // Confirm the order is still awaiting payment (not already paid /
      // cancelled — e.g. the webhook won a race with our poll).
      final order = await _client
          .from('orders')
          .select('status')
          .eq('id', row['order_id'])
          .maybeSingle();
      if (order == null || order['status'] != 'awaiting_payment') return null;
      return GcashIntentResult.fromJson({
        ...Map<String, dynamic>.from(row),
        'already_exists': true,
      });
    } catch (e) {
      debugPrint('[GCASH] fetchPendingIntent failed: $e');
      return null;
    }
  }

  /// The pending checkout for a SPECIFIC order (tracking screen resume).
  Future<GcashIntentResult?> fetchIntentForOrder(String orderId) async {
    try {
      final row = await _client
          .from('payment_intents')
          .select('order_id, checkout_url, client_key, amount, fee_amount, expires_at, status')
          .eq('order_id', orderId)
          .eq('status', 'pending')
          .maybeSingle();
      if (row == null) return null;
      return GcashIntentResult.fromJson({
        ...Map<String, dynamic>.from(row),
        'already_exists': true,
      });
    } catch (e) {
      debugPrint('[GCASH] fetchIntentForOrder failed: $e');
      return null;
    }
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  String _edgeMessage(FunctionException e, {required String fallback}) {
    if (e.details is Map) {
      final msg = (e.details as Map)['error'];
      if (msg is String && msg.isNotEmpty) return msg;
    }
    switch (e.status) {
      case 400:
        return 'Invalid request. Please review your checkout details.';
      case 401:
        return 'Your session has expired. Please sign in again.';
      case 403:
        return 'You are not allowed to perform this action.';
      case 409:
        return 'You have an unfinished GCash checkout. Complete or cancel it first.';
      case 502:
        return 'The payment provider is temporarily unavailable. Please try again in a moment.';
      case 503:
        return 'GCash payments are temporarily unavailable. Please try again later.';
      default:
        return fallback;
    }
  }

  String _pgMessage(PostgrestException e, {required String fallback}) {
    final msg = e.message.trim();
    if (msg.isNotEmpty && e.code == 'P0001') return msg;
    if (e.code == '23505') {
      return 'A checkout is already in progress for this order.';
    }
    if (e.code == '42501') return 'You are not allowed to do that.';
    return fallback;
  }
}

/// Shared numeric coercion used by the payment result models.
double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}
