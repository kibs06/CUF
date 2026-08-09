import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'upload_service.dart';

/// Result of creating a gateway-free GCash checkout
/// (server function `create_gcash_checkout`).
class GcashCheckoutResult {
  final String orderId;
  final String storeId;
  final double totalAmount;
  final DateTime? deadline;
  final String storeName;
  final String? gcashQrUrl;
  final String? gcashNumber;
  final String? gcashAccountName;

  const GcashCheckoutResult({
    required this.orderId,
    required this.storeId,
    required this.totalAmount,
    this.deadline,
    this.storeName = '',
    this.gcashQrUrl,
    this.gcashNumber,
    this.gcashAccountName,
  });

  factory GcashCheckoutResult.fromJson(Map<String, dynamic> json) {
    return GcashCheckoutResult(
      orderId: json['order_id']?.toString() ?? '',
      storeId: json['store_id']?.toString() ?? '',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      deadline: json['payment_confirmation_deadline'] != null
          ? DateTime.tryParse(
              json['payment_confirmation_deadline'].toString(),
            )
          : null,
      storeName: json['store_name']?.toString() ?? '',
      gcashQrUrl: json['gcash_qr_url']?.toString(),
      gcashNumber: json['gcash_number']?.toString(),
      gcashAccountName: json['gcash_account_name']?.toString(),
    );
  }
}

/// A single line item of the customer's pending GCash order, already
/// enriched with the product name + first image so UI layers never need
/// to re-query the products table.
class PendingGcashItem {
  final String productId;
  final String productName;
  final String? imageUrl;
  final String size;
  final int quantity;
  final double unitPrice;

  const PendingGcashItem({
    required this.productId,
    required this.productName,
    this.imageUrl,
    this.size = '',
    this.quantity = 1,
    this.unitPrice = 0,
  });

  /// Line total for this item (unit price × quantity).
  double get lineTotal => unitPrice * quantity;

  /// Parses a nested `order_items` row that carries `products(name,
  /// product_images(image_url, display_order))` — the first image by
  /// `display_order` wins, mirroring `OrderService.fetchMyOrders`.
  factory PendingGcashItem.fromJson(Map<String, dynamic> json) {
    String? imageUrl;
    var productName = '';
    final product = json['products'];
    if (product is Map) {
      final p = Map<String, dynamic>.from(product);
      productName = p['name']?.toString() ?? '';
      final images = p['product_images'];
      if (images is List && images.isNotEmpty) {
        final sorted = List<Map<String, dynamic>>.from(
          images.map((e) => Map<String, dynamic>.from(e as Map)),
        )..sort(
            (a, b) =>
                ((a['display_order'] as num?)?.toInt() ?? 0).compareTo(
                    (b['display_order'] as num?)?.toInt() ?? 0),
          );
        final first = sorted.first['image_url']?.toString() ?? '';
        if (first.isNotEmpty) imageUrl = first;
      }
    }
    return PendingGcashItem(
      productId: json['product_id']?.toString() ?? '',
      productName: productName,
      imageUrl: imageUrl,
      size: json['size']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// The customer's currently-open `awaiting_payment_confirmation` GCash
/// order — the object the resolution sheet renders (items, total,
/// deadline) and the Complete/Cancel actions act on.
class PendingGcashOrder {
  final String id;
  final String storeId;
  final double totalAmount;
  final DateTime? deadline;
  final DateTime? createdAt;
  final bool proofSubmitted;
  final List<PendingGcashItem> items;

  const PendingGcashOrder({
    required this.id,
    required this.storeId,
    this.totalAmount = 0,
    this.deadline,
    this.createdAt,
    this.proofSubmitted = false,
    this.items = const [],
  });

  /// Total number of physical items across all lines (qty summed).
  int get itemCount =>
      items.fold(0, (sum, item) => sum + item.quantity);

  factory PendingGcashOrder.fromJson(
    Map<String, dynamic> json, {
    required bool proofSubmitted,
  }) {
    final rawItems = json['order_items'];
    return PendingGcashOrder(
      id: json['id']?.toString() ?? '',
      storeId: json['store_id']?.toString() ?? '',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      deadline: json['payment_confirmation_deadline'] != null
          ? DateTime.tryParse(
              json['payment_confirmation_deadline'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      proofSubmitted: proofSubmitted,
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((e) =>
                  PendingGcashItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

/// Thrown when a GCash RPC rejects the request. [message] is the friendly
/// message raised server-side (or a safe fallback); [code] carries the
/// PostgREST error code ('23505', 'P0001', '42501', …) when available so
/// callers can branch on the failure kind (e.g. the pending-checkout cap).
class DirectGcashException implements Exception {
  final String message;
  final String? code;

  const DirectGcashException(this.message, {this.code});

  @override
  String toString() => message;
}

/// Flutter client for the gateway-free (no-PayMongo) GCash flow.
///
/// Every state transition is a Postgres RPC (SECURITY DEFINER) — this
/// service NEVER writes payment status to the orders table directly.
/// The server is the only source of truth; the seller's confirmation tap
/// (confirm_gcash_payment) is the security control.
class DirectGcashService {
  final SupabaseClient _client;

  DirectGcashService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  /// Step 1 (customer): create the order (awaiting_payment_confirmation,
  /// stock reserved server-side) and return the store's GCash payment
  /// details. The server recomputes prices/stock — the client only sends
  /// product/size/quantity.
  Future<GcashCheckoutResult> createCheckout({
    required List<Map<String, dynamic>> items,
    String? deliveryAddress,
    Map<String, dynamic>? shippingAddress,
  }) async {
    try {
      final data = await _client.rpc('create_gcash_checkout', params: {
        'p_items': items,
        'p_delivery_address': deliveryAddress,
        'p_shipping_address': shippingAddress,
      });
      final map = data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
      return GcashCheckoutResult.fromJson(map);
    } catch (e) {
      throw _toException(
        e,
        fallback:
            'We could not start the GCash checkout. Please try again.',
      );
    }
  }

  /// Step 2 (customer): submit the proof of payment — reference number +
  /// screenshot (already uploaded to the private bucket; [screenshotPath]
  /// is the storage path `{order_id}/{file}`).
  Future<void> submitProof({
    required String orderId,
    required String referenceNumber,
    required String screenshotPath,
  }) async {
    try {
      await _client.rpc('submit_gcash_proof', params: {
        'p_order_id': orderId,
        'p_reference_number': referenceNumber,
        'p_screenshot_url': screenshotPath,
      });
    } catch (e) {
      throw _toException(
        e,
        fallback: 'We could not submit your proof. Please try again.',
      );
    }
  }

  /// Step 3 (seller): confirm receipt → order enters the normal pipeline.
  Future<void> confirmPayment(String orderId) async {
    try {
      await _client.rpc('confirm_gcash_payment', params: {
        'p_order_id': orderId,
      });
    } catch (e) {
      throw _toException(
        e,
        fallback: 'We could not confirm this payment. Please try again.',
      );
    }
  }

  /// Step 3 (seller): reject receipt → order cancelled, stock released.
  Future<void> rejectPayment(String orderId, String reason) async {
    try {
      await _client.rpc('reject_gcash_payment', params: {
        'p_order_id': orderId,
        'p_reason': reason,
      });
    } catch (e) {
      throw _toException(
        e,
        fallback: 'We could not reject this payment. Please try again.',
      );
    }
  }

  /// Customer cancels their OWN pending GCash checkout (allowed only while
  /// no proof has been submitted — server-enforced). Releases the reserved
  /// stock and frees the one-open-order cap so they can check out again.
  /// Returns true if the order was actually cancelled; false if it had
  /// already resolved (paid/rejected/expired) by the time the call landed.
  Future<bool> cancelPendingCheckout(String orderId) async {
    try {
      final data = await _client.rpc('cancel_my_pending_gcash_checkout',
          params: {'p_order_id': orderId});
      return data == true;
    } catch (e) {
      throw _toException(
        e,
        fallback: 'We could not cancel the pending order. Please try again.',
      );
    }
  }

  /// Fetch the customer's currently-open awaiting-payment GCash order (if
  /// any) — used to offer resume/cancel when a new checkout hits the
  /// one-open-order cap (23505). Returns the order WITH its line items
  /// (product name + first image) so the resolution sheet can show exactly
  /// what the customer is paying for, and reports whether proof was already
  /// submitted: a proof-submitted order is not cancellable, only trackable.
  ///
  /// Returns `null` ONLY when there is genuinely no pending order — a
  /// failed fetch throws, so callers can tell "nothing pending" apart from
  /// "couldn't check" (showing a misleading 'was resolved' message on a
  /// network blip is worse than an error).
  Future<PendingGcashOrder?> fetchPendingCheckout() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await _client
          .from('orders')
          .select(
            'id, store_id, total_amount, '
            'payment_confirmation_deadline, created_at, status, '
            'order_items(id, product_id, size, quantity, unit_price, '
            'products(name, product_images(image_url, display_order)))',
          )
          .eq('customer_id', uid)
          .eq('status', 'awaiting_payment_confirmation')
          .maybeSingle();
      if (row == null) return null;
      final order = Map<String, dynamic>.from(row);
      final proof = await _client
          .from('gcash_payment_proofs')
          .select('id')
          .eq('order_id', order['id'])
          .maybeSingle();
      return PendingGcashOrder.fromJson(
        order,
        proofSubmitted: proof != null,
      );
    } catch (e) {
      debugPrint('[GCASH] fetch pending checkout failed: $e');
      rethrow;
    }
  }

  /// Opportunistic expiry sweep — idempotent; safe to call from any screen.
  /// Fire-and-forget (never blocks the UI).
  Future<void> expireOverdue() async {
    try {
      await _client.rpc('expire_overdue_gcash_orders');
    } catch (e) {
      debugPrint('[GCASH] expiry sweep failed (non-fatal): $e');
    }
  }

  /// Upload the proof screenshot to the PRIVATE 'payment-proofs' bucket
  /// under `{order_id}/{uuid}.jpg` and return the storage PATH (not a
  /// public URL — the bucket is not public).
  Future<String> uploadProofScreenshot({
    required String orderId,
    required String filePath,
  }) async {
    final path = await UploadService().uploadFile(
      bucket: 'payment-proofs',
      folder: orderId,
      filePath: filePath,
      publicBucket: false,
    );
    return path;
  }

  /// Short-lived signed URL for displaying a proof screenshot (the bucket
  /// is private — only the order's customer and its store's seller can
  /// read these objects, enforced by storage policies).
  Future<String?> proofScreenshotUrl(String storagePath) async {
    try {
      final url = await _client.storage
          .from('payment-proofs')
          .createSignedUrl(storagePath, 3600);
      return url;
    } catch (e) {
      debugPrint('[GCASH] signed URL failed: $e');
      return null;
    }
  }

  /// Build a [DirectGcashException] from a PostgREST error, mapping the
  /// code to a friendly message and keeping the code for callers. RPCs
  /// RAISE with ERRCODE P0001 → the raised message is the copy we wrote
  /// server-side.
  DirectGcashException _toException(Object e, {required String fallback}) {
    String? code;
    String message = fallback;
    if (e is PostgrestException) {
      code = e.code;
      final msg = e.message.trim();
      if (code == 'P0001' && msg.isNotEmpty) {
        message = msg;
        // The create RPC catches the one-open-order unique violation and
        // re-raises it as a plain RAISE EXCEPTION (→ P0001, no ERRCODE).
        // Normalize it back so the checkout screen can branch on the cap
        // and offer the Complete/Cancel resolution dialog instead of a
        // dead-end snack bar. (The DB-level error is 23505 either way.)
        if (msg.contains('awaiting confirmation')) {
          code = '23505';
        }
      } else if (code == '23505') {
        message =
            'You already have a GCash checkout awaiting confirmation. Complete or cancel it first.';
      } else if (code == '42501') {
        message = 'You are not allowed to do that.';
      }
    }
    return DirectGcashException(message, code: code);
  }
}
