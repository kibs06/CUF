import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'upload_service.dart';

/// A reseller bulk reservation: the customer asks to hold [quantity] units
/// of a product for resale; the seller approves with a deadline and the
/// units are physically moved out of `inventory` into the hold until the
/// customer cancels, the seller fulfills it, or it expires.
///
/// Server logic lives in the SECURITY DEFINER RPCs from
/// `supabase/migrations/20260913140000_add_bulk_reservation_deposits.sql`.
class BulkReservation {
  final String id;
  final String customerId;
  final String storeId;
  final String productId;
  final int quantity;
  final int reservedStock;
  final List<Map<String, dynamic>> requestedSizes;
  final String? note;
  /// 'pending' | 'awaiting_deposit' | 'approved' | 'rejected' | 'cancelled'
  /// | 'expired' | 'fulfilled'
  final String status;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final String? rejectionReason;
  // Deposit gate (20260913140000_add_bulk_reservation_deposits.sql).
  /// Resolved peso amount owed — 20% of the estimated value at approval,
  /// rounded up to a whole peso; null before approval.
  final double? depositAmount;
  /// 'not_required' | 'unpaid' | 'paid' | 'forfeited' | 'refunded'
  final String depositStatus;
  final DateTime? depositDeadline;
  final DateTime? depositPaidAt;
  // Joined display fields (customer-side: product; seller-side: profile).
  final String productName;
  final String? productImage;
  final String? customerName;
  final String storeName;

  const BulkReservation({
    required this.id,
    required this.customerId,
    required this.storeId,
    required this.productId,
    required this.quantity,
    this.reservedStock = 0,
    this.requestedSizes = const [],
    this.note,
    required this.status,
    this.depositAmount,
    this.depositStatus = 'not_required',
    this.depositDeadline,
    this.depositPaidAt,
    this.expiresAt,
    this.createdAt,
    this.rejectionReason,
    this.productName = '',
    this.productImage,
    this.customerName,
    this.storeName = '',
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isTerminal =>
      status == 'rejected' ||
      status == 'cancelled' ||
      status == 'expired' ||
      status == 'fulfilled';

  /// Seller approved and is waiting for the customer's deposit payment
  /// (proof submitted → store owner verifies in their GCash app).
  bool get isAwaitingDeposit => status == 'awaiting_deposit';

  /// True while the deposit window is still open (awaiting_deposit and
  /// the deadline has not passed). The 24h sweep expires it otherwise.
  bool get needsDeposit =>
      isAwaitingDeposit && depositStatus == 'unpaid';

  /// The 24h deposit window has lapsed (the opportunistic sweep expires
  /// the row server-side; this drives the customer-facing countdown).
  bool get depositExpired =>
      isAwaitingDeposit &&
      depositDeadline != null &&
      depositDeadline!.isBefore(DateTime.now());

  /// Human label for the status chip.
  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'Awaiting approval';
      case 'awaiting_deposit':
        return 'Deposit needed';
      case 'approved':
        return 'Reserved';
      case 'rejected':
        return 'Declined';
      case 'cancelled':
        return 'Cancelled';
      case 'expired':
        return 'Expired';
      case 'fulfilled':
        return 'Fulfilled';
    }
    return status;
  }

  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  /// Parses a row fetched with the nested joins used by the fetch methods:
  /// `products(name, product_images(image_url, display_order), stores(name))`
  /// or `profiles(name)`.
  factory BulkReservation.fromJson(Map<String, dynamic> json) {
    String productName = '';
    String? image;
    String storeName = '';
    final product = json['products'];
    if (product is Map) {
      final p = Map<String, dynamic>.from(product);
      productName = p['name']?.toString() ?? '';
      final store = p['stores'];
      if (store is Map) {
        storeName = Map<String, dynamic>.from(store)['name']?.toString() ?? '';
      }
      final images = p['product_images'];
      if (images is List && images.isNotEmpty) {
        final sorted = List<Map<String, dynamic>>.from(
          images.map((e) => Map<String, dynamic>.from(e as Map)),
        )..sort((a, b) => ((a['display_order'] as num?)?.toInt() ?? 0)
            .compareTo((b['display_order'] as num?)?.toInt() ?? 0));
        final first = sorted.first['image_url']?.toString() ?? '';
        if (first.isNotEmpty) image = first;
      }
    }
    String? customerName;
    final profile = json['profiles'];
    if (profile is Map) {
      customerName =
          Map<String, dynamic>.from(profile)['name']?.toString() ?? '';
    }
    return BulkReservation(
      id: json['id']?.toString() ?? '',
      customerId: json['customer_id']?.toString() ?? '',
      storeId: json['store_id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      reservedStock: (json['reserved_stock'] as num?)?.toInt() ?? 0,
      requestedSizes: json['requested_sizes'] is List
          ? List<Map<String, dynamic>>.from(
              (json['requested_sizes'] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e)))
          : const [],
      note: json['note']?.toString(),
      status: json['status']?.toString() ?? 'pending',
      expiresAt: _parseDate(json['expires_at']),
      createdAt: _parseDate(json['created_at']),
      rejectionReason: json['rejection_reason']?.toString(),
      depositAmount: (json['deposit_amount'] as num?)?.toDouble(),
      depositStatus: json['deposit_status']?.toString() ?? 'not_required',
      depositDeadline: _parseDate(json['deposit_deadline']),
      depositPaidAt: _parseDate(json['deposit_paid_at']),
      productName: productName,
      productImage: image,
      customerName: customerName,
      storeName: storeName,
    );
  }
}

/// Friendly message for a PostgREST error raised by the reservation RPCs
/// (they RAISE EXCEPTION with stable short codes).
String friendlyReservationError(Object error) {
  final msg = error.toString();
  String code = msg;
  final match = RegExp(r'"([A-Z_]+)[^"]*"').firstMatch(msg);
  if (match != null) code = match.group(1)!;
  if (code.startsWith('INSUFFICIENT_STOCK')) {
    return 'Not enough stock is available right now — try a smaller quantity.';
  }
  switch (code) {
    case 'RESERVATION_ALREADY_EXISTS':
      return 'You already have an open reservation for this product.';
    case 'PRODUCT_NOT_FOUND':
      return 'This product is no longer available.';
    case 'INVALID_QUANTITY':
      return 'Enter a quantity of at least 1.';
    case 'INVALID_DEADLINE':
      return 'Choose a reservation period of at least 1 day.';
    case 'DEPOSIT_DEADLINE_PASSED':
      return 'The 24-hour deposit window for this reservation has closed.';
    case 'DEPOSIT_PROOF_REQUIRED':
      return 'Submit your GCash payment proof first — then the store can confirm it.';
    case 'DEPOSIT_ALREADY_SUBMITTED':
      return 'A payment proof was already submitted for this reservation.';
    case 'INVALID_PROOF_REFERENCE':
      return 'Enter a valid GCash reference number (12–13 digits).';
    case 'INVALID_PROOF_SCREENSHOT':
      return 'Attach a screenshot of your GCash payment.';
    case 'REFERENCE_ALREADY_USED':
      return 'That GCash reference number has already been used for another payment.';
    case 'ALREADY_DECIDED':
    case 'ALREADY_RESOLVED':
      return 'This reservation was already resolved.';
    case 'FORBIDDEN':
      return 'You do not have permission for this action.';
    case 'NOT_FOUND':
      return 'Reservation not found.';
    case 'NOT_AUTHENTICATED':
      return 'Please sign in and try again.';
  }
  debugPrint('reservation error: $msg');
  return 'Something went wrong. Please try again.';
}

/// Data access for bulk (reseller) reservations. Thin RPC/CRUD wrapper —
/// all stock movement and state rules are enforced server-side.
class ReservationService {
  static final ReservationService instance = ReservationService._();

  ReservationService._() : _client = Supabase.instance.client;

  ReservationService.forClient(this._client);

  final SupabaseClient _client;

  /// Customer: request a hold on [quantity] units. Returns the new id.
  /// [requestedSizes] is an optional size breakdown for the seller,
  /// e.g. `[{size: 40, quantity: 20}]`.
  ///
  /// The RPC inserts the seller's in-app notification row; this method
  /// additionally fires an FCM push to the store owner's device so the
  /// request reaches them even with the app backgrounded (same
  /// fire-and-forget pattern as custom-order requests).
  Future<String> requestReservation({
    required String productId,
    required String storeId,
    required int quantity,
    List<Map<String, dynamic>> requestedSizes = const [],
    String? note,
  }) async {
    final data = await _client.rpc('request_bulk_reservation', params: {
      'p_product_id': productId,
      'p_store_id': storeId,
      'p_quantity': quantity,
      'p_requested_sizes': requestedSizes,
      'p_note': note,
    });
    final reservationId = data?.toString() ?? '';

    // Fire-and-forget: push failures must never fail the request itself.
    unawaited(_pushSellerNewRequest(
      reservationId: reservationId,
      storeId: storeId,
      productId: productId,
      quantity: quantity,
    ));

    return reservationId;
  }

  /// FCM push to the store owner about a new bulk reservation request.
  /// Resolves owner + product name client-side (both readable via RLS),
  /// then invokes the shared `send-notification-push` edge function.
  /// Mirrors the RPC's in-app message wording so both channels agree.
  Future<void> _pushSellerNewRequest({
    required String reservationId,
    required String storeId,
    required String productId,
    required int quantity,
  }) async {
    try {
      final store = await _client
          .from('stores')
          .select('owner_id')
          .eq('id', storeId)
          .maybeSingle();
      final ownerId = store?['owner_id']?.toString();
      if (ownerId == null || ownerId.isEmpty) return;

      final product = await _client
          .from('products')
          .select('name')
          .eq('id', productId)
          .maybeSingle();
      final productName = product?['name']?.toString() ?? 'a product';

      await _client.functions.invoke('send-notification-push', body: {
        'recipientUserId': ownerId,
        'title': 'New bulk reservation request',
        'body': 'A customer requested $quantity units of $productName for resale.',
        'type': 'bulk_reservation_request',
        if (reservationId.isNotEmpty) 'referenceId': reservationId,
        'screen': 'seller_reservations',
      });
    } catch (e) {
      debugPrint('[ReservationService] Push trigger failed: $e');
    }
  }

  /// Customer: my reservations, newest first.
  Future<List<BulkReservation>> fetchMyReservations() async {
    final rows = await _client
        .from('bulk_reservations')
        .select(
            '*, products(name, stores(name), product_images(image_url, display_order))')
        .order('created_at', ascending: false)
        .limit(50);
    return rows
        .map<BulkReservation>(
            (r) => BulkReservation.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Customer: cancel a pending/approved reservation (stock returns).
  /// Cancelling a PAID hold forfeits the deposit (server-enforced).
  Future<void> cancelReservation(String reservationId) async {
    await _client.rpc('cancel_bulk_reservation',
        params: {'p_reservation_id': reservationId});
  }

  /// Seller: all reservations for [storeId], newest first.
  Future<List<BulkReservation>> fetchStoreReservations(String storeId) async {
    final rows = await _client
        .from('bulk_reservations')
        .select('*, products(name), profiles(name)')
        .eq('store_id', storeId)
        .order('created_at', ascending: false)
        .limit(100);
    return rows
        .map<BulkReservation>(
            (r) => BulkReservation.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Seller: approve (with a [days]-long hold) or reject. Approval opens
  /// the customer's 24-hour deposit window — stock moves only after the
  /// store confirms the deposit proof.
  ///
  /// After a successful approval the customer additionally receives an
  /// FCM push (fire-and-forget) mirroring the RPC's in-app notification,
  /// so the deposit window is visible even with the app backgrounded.
  Future<void> decideReservation({
    required String reservationId,
    required bool approve,
    int? days,
    String? rejectionReason,
  }) async {
    await _client.rpc('decide_bulk_reservation', params: {
      'p_reservation_id': reservationId,
      'p_approve': approve,
      'p_days': days,
      'p_rejection_reason': rejectionReason,
    });

    if (approve) {
      // Fire-and-forget: push failures must never fail the approval.
      unawaited(_pushCustomerApproved(reservationId: reservationId));
    }
  }

  /// FCM push to the customer that the seller approved their bulk
  /// reservation and a 24-hour GCash deposit window is now open. Reads
  /// the resolved deposit amount + deadline straight from the row the
  /// RPC just updated (the approving seller can SELECT it via RLS), so
  /// the push matches the in-app message exactly.
  Future<void> _pushCustomerApproved({
    required String reservationId,
  }) async {
    try {
      final row = await _client
          .from('bulk_reservations')
          .select('customer_id, quantity, deposit_amount, deposit_deadline')
          .eq('id', reservationId)
          .maybeSingle();
      final customerId = row?['customer_id']?.toString();
      if (customerId == null || customerId.isEmpty) return;

      final quantity = (row?['quantity'] as num?)?.toInt() ?? 0;
      final deposit = (row?['deposit_amount'] as num?)?.toInt() ?? 0;
      final deadline = row?['deposit_deadline'] == null
          ? null
          : DateTime.tryParse(row!['deposit_deadline'].toString());

      await _client.functions.invoke('send-notification-push', body: {
        'recipientUserId': customerId,
        'title': 'Bulk reservation approved — deposit required',
        'body': 'Your reservation of $quantity units was approved. '
            'Pay the ₱$deposit GCash deposit (20% of the estimated value) by '
            '${_formatUtcDeadline(deadline)} to hold the stock. '
            'The deposit is NON-REFUNDABLE once paid.',
        'type': 'bulk_reservation_approved',
        'referenceId': reservationId,
        'screen': 'my_reservations',
      });
    } catch (e) {
      debugPrint('[ReservationService] Push trigger failed: $e');
    }
  }

  /// Formats a deposit deadline like the RPC's to_char output
  /// ("Sep 14, 14:30 UTC"); falls back to a generic phrase when the
  /// deadline is unexpectedly missing. Supabase returns timestamptz
  /// values in UTC, so the parsed wall-clock is already UTC.
  String _formatUtcDeadline(DateTime? deadlineUtc) {
    if (deadlineUtc == null) return 'the deadline';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    String two(int n) => n.toString().padLeft(2, '0');
    return '${months[deadlineUtc.month - 1]} ${deadlineUtc.day}, '
        '${two(deadlineUtc.hour)}:${two(deadlineUtc.minute)} UTC';
  }

  /// Seller: mark an approved (deposit-paid) reservation as picked up.
  Future<void> fulfillReservation(String reservationId) async {
    await _client.rpc('fulfill_bulk_reservation',
        params: {'p_reservation_id': reservationId});
  }

  /// Seller: confirm the deposit proof → stock is drawn into the hold
  /// (the relocated stock-draw), deposit flips to 'paid'.
  Future<void> confirmDeposit(String reservationId) async {
    await _client.rpc('confirm_bulk_reservation_deposit',
        params: {'p_reservation_id': reservationId});
  }

  /// Seller: reject the deposit payment — terminal, nothing was drawn.
  Future<void> rejectDeposit(String reservationId,
      {String? rejectionReason}) async {
    await _client.rpc('reject_bulk_reservation_deposit', params: {
      'p_reservation_id': reservationId,
      'p_reason': rejectionReason,
    });
  }

  /// Customer: submit the GCash deposit proof (reference + screenshot
  /// already uploaded to the private 'payment-proofs' bucket under
  /// `{reservationId}/{file}`). The store owner then verifies and
  /// confirms — only THAT draws stock.
  Future<void> submitDepositProof({
    required String reservationId,
    required String referenceNumber,
    required String screenshotPath,
  }) async {
    await _client.rpc('submit_bulk_reservation_deposit_proof', params: {
      'p_reservation_id': reservationId,
      'p_reference_number': referenceNumber,
      'p_screenshot_url': screenshotPath,
    });
  }

  /// Customer: upload the deposit proof screenshot to the PRIVATE
  /// 'payment-proofs' bucket under `{reservationId}/{uuid}.jpg`; returns
  /// the storage path (same convention as order proofs).
  Future<String> uploadDepositProofScreenshot({
    required String reservationId,
    required String filePath,
  }) async {
    return UploadService().uploadFile(
      bucket: 'payment-proofs',
      folder: reservationId,
      filePath: filePath,
      publicBucket: false,
    );
  }

  /// Seller: count of actionable reservations for a store — pending
  /// (undecided) requests PLUS awaiting_deposit rows whose proof needs
  /// verification — powers the dashboard metric without pulling rows.
  Future<int> fetchPendingCount(String storeId) async {
    final rows = await _client
        .from('bulk_reservations')
        .select('id')
        .eq('store_id', storeId)
        .inFilter('status', ['pending', 'awaiting_deposit']);
    return (rows as List).length;
  }

  /// Opportunistic expiry sweep — call on app load / dashboard load.
  /// Returns how many reservations expired (best-effort; failures are
  /// non-fatal since the sweep is also the client's own trigger).
  Future<int> expireStaleReservations() async {
    try {
      final n = await _client.rpc('expire_bulk_reservations');
      return (n as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('expire_bulk_reservations sweep failed: $e');
      return 0;
    }
  }
}
