import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of creating a GCash payment intent (edge function
/// `create-gcash-payment-intent`).
class GcashIntentResult {
  /// The server-created order id (awaiting_payment). Empty if unusable.
  final String orderId;

  /// PayMongo redirect URL the customer must open to authorize in GCash.
  final String checkoutUrl;

  final String? paymentIntentId;

  /// Scoped to this payment intent only — safe for the client to hold.
  final String? clientKey;

  final double amount;

  final DateTime? expiresAt;

  /// True when the server returned an already-pending intent instead of
  /// creating a new one (double-tap / retry / resume).
  final bool alreadyExists;

  const GcashIntentResult({
    required this.orderId,
    required this.checkoutUrl,
    this.paymentIntentId,
    this.clientKey,
    this.amount = 0,
    this.expiresAt,
    this.alreadyExists = false,
  });
}

/// Current authoritative order + payment state (edge function
/// `get-payment-status`).
class GcashStatusResult {
  final String orderId;

  /// orders.status: awaiting_payment | pending | cancelled | payment_conflict | …
  final String status;

  /// orders.payment_status: pending | paid | failed | unpaid
  final String paymentStatus;

  final bool paid;

  final double totalAmount;

  /// payment_intents.status: pending | succeeded | failed | expired | cancelled
  final String? intentStatus;

  const GcashStatusResult({
    required this.orderId,
    required this.status,
    required this.paymentStatus,
    required this.paid,
    required this.totalAmount,
    this.intentStatus,
  });
}

/// Thrown when an edge function rejects the request. [message] is
/// user-friendly; [statusCode] is the HTTP status (may be null).
class GcashPaymentException implements Exception {
  final String message;
  final int? statusCode;

  const GcashPaymentException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Flutter client for the online GCash payment edge functions.
///
/// The app NEVER marks a payment paid — it only creates the intent and
/// then polls this service for the authoritative status, which the
/// server-side webhook (signature-verified) controls.
class GcashPaymentService {
  final SupabaseClient _client;

  GcashPaymentService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  /// Step 1: create the order (awaiting_payment) + PayMongo intent and
  /// return the redirect URL. The server recomputes prices/stock, so the
  /// client only supplies product/size/quantity.
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
          // The edge function tolerates null/empty address fields.
          'delivery_address': deliveryAddress,
          'shipping_address': shippingAddress,
        },
      );
      final data = _asMap(res.data);
      return GcashIntentResult(
        orderId: data['order_id']?.toString() ?? '',
        checkoutUrl: data['checkout_url']?.toString() ?? '',
        paymentIntentId: data['payment_intent_id']?.toString(),
        clientKey: data['client_key']?.toString(),
        amount: (data['amount'] as num?)?.toDouble() ?? 0,
        expiresAt: data['expires_at'] != null
            ? DateTime.tryParse(data['expires_at'].toString())
            : null,
        alreadyExists: data['already_exists'] == true,
      );
    } on FunctionException catch (e) {
      // Non-2xx from the edge function — its JSON body lands in [details].
      throw GcashPaymentException(
        _errorMessage(e, fallback: 'We could not start the GCash payment. Please try again.'),
        statusCode: e.status,
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
          ? _asMap(data['payment'])
          : <String, dynamic>{};
      return GcashStatusResult(
        orderId: data['order_id']?.toString() ?? orderId,
        status: data['status']?.toString() ?? '',
        paymentStatus: data['payment_status']?.toString() ?? '',
        paid: data['paid'] == true,
        totalAmount: (data['total_amount'] as num?)?.toDouble() ?? 0,
        intentStatus: payment['status']?.toString(),
      );
    } on FunctionException catch (e) {
      throw GcashPaymentException(
        _errorMessage(e, fallback: 'We could not check your payment status.'),
        statusCode: e.status,
      );
    }
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  String _errorMessage(FunctionException e, {required String fallback}) {
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
        return 'A checkout is already in progress. Please complete or cancel it first.';
      case 502:
        return 'The payment provider is temporarily unavailable. Please try again in a moment.';
      default:
        return fallback;
    }
  }
}
