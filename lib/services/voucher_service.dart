import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The server's verdict on a voucher code plus the totals it implies.
///
/// This is a SERVER product: `validate_voucher` reprices the cart from
/// `public.products` (sale-aware) and applies the voucher rules, so the
/// numbers here are the numbers the order will get. The client renders
/// them and only ever sends the CODE back — never a discount amount.
@immutable
class VoucherQuote {
  final bool ok;
  final String reason;
  final String message;
  final String code;
  final String storeId;
  final double subtotal;
  final double deliveryFee;
  final double discountAmount;
  final double total;

  const VoucherQuote({
    required this.ok,
    required this.reason,
    required this.message,
    this.code = '',
    this.storeId = '',
    this.subtotal = 0,
    this.deliveryFee = 0,
    this.discountAmount = 0,
    this.total = 0,
  });

  /// True when a discount is actually being taken off this order.
  bool get hasDiscount => ok && discountAmount > 0;

  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  factory VoucherQuote.fromJson(Map<String, dynamic> json) {
    return VoucherQuote(
      ok: json['ok'] == true,
      reason: json['reason']?.toString() ?? VoucherReason.invalidCode,
      message: json['message']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      storeId: json['store_id']?.toString() ?? '',
      subtotal: _toDouble(json['subtotal']),
      deliveryFee: _toDouble(json['delivery_fee']),
      discountAmount: _toDouble(json['discount_amount']),
      total: _toDouble(json['total']),
    );
  }

  /// A failed quote — used when the RPC cannot even be reached, so the UI
  /// can render one uniform "here is why it did not work" state.
  factory VoucherQuote.failure(String reason, String message) =>
      VoucherQuote(ok: false, reason: reason, message: message);
}

/// Every failure reason `public.voucher_evaluate` can return. Mirrored
/// here so the UI can branch on the reason instead of string-matching a
/// human-readable message.
class VoucherReason {
  const VoucherReason._();

  static const ok = 'ok';
  static const invalidCode = 'invalid_code';
  static const inactive = 'inactive';
  static const notStarted = 'not_started';
  static const expired = 'expired';
  static const maxUsesReached = 'max_uses_reached';
  static const perUserLimitReached = 'per_user_limit_reached';
  static const belowMinimum = 'below_minimum';
  static const wrongStore = 'wrong_store';
  static const emptyCart = 'empty_cart';

  /// Reasons that mean "this code will never work for this customer" —
  /// the UI clears the field instead of keeping a stale code around.
  static const fatal = {
    invalidCode,
    inactive,
    notStarted,
    expired,
    maxUsesReached,
    perUserLimitReached,
    wrongStore,
  };
}

class VoucherException implements Exception {
  final String message;
  final String? code;

  const VoucherException(this.message, {this.code});

  @override
  String toString() => message;
}

/// Client for the voucher RPCs / tables.
///
/// Validation and redemption are both server-side:
///   • [validate] is an ADVISORY preview used to render the checkout total.
///   • The real enforcement is `orders_apply_voucher()` — a BEFORE INSERT
///     trigger on `orders` that re-evaluates the code inside the order's
///     own transaction and overwrites the totals. A stale preview can
///     therefore never be charged; the order insert simply fails with the
///     same customer-readable message and the UI shows it.
class VoucherService {
  final SupabaseClient _client;

  VoucherService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  String? get _uid => _client.auth.currentUser?.id;

  /// Quote a code against the current cart. [items] is the checkout cart in
  /// the servers own shape: `{product_id, size, quantity}` — prices are
  /// looked up server-side, so unit prices are neither needed nor trusted.
  Future<VoucherQuote> validate({
    required String code,
    required List<Map<String, dynamic>> items,
  }) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return VoucherQuote.failure(
        VoucherReason.invalidCode,
        'Enter a voucher code to apply a discount.',
      );
    }
    try {
      final data = await _client.rpc('validate_voucher', params: {
        'p_code': trimmed,
        'p_items': items,
      });
      final map =
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      return VoucherQuote.fromJson(map);
    } on PostgrestException catch (e) {
      // The RPC raises for cart problems (item gone, size gone, mixed
      // stores) — those messages are already customer-readable.
      return VoucherQuote.failure(
        VoucherReason.invalidCode,
        e.message.trim().isEmpty
            ? 'We could not check that code. Please try again.'
            : e.message.trim(),
      );
    } catch (e) {
      debugPrint('[VOUCHER] validate failed: $e');
      return VoucherQuote.failure(
        VoucherReason.invalidCode,
        'We could not check that code. Please check your connection and try again.',
      );
    }
  }

  /// Seller: vouchers visible to this store (own + platform-wide ones).
  Future<List<Map<String, dynamic>>> listVouchers() async {
    try {
      final rows = await _client
          .from('vouchers')
          .select(
            'id, code, store_id, discount_type, discount_value, '
            'max_discount_amount, min_order_amount, max_uses, uses_count, '
            'per_user_limit, starts_at, ends_at, funded_by, is_active, created_at',
          )
          .order('created_at', ascending: false);
      return (rows as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } catch (e) {
      debugPrint('[VOUCHER] list failed: $e');
      throw VoucherException('We could not load your vouchers. Please try again.');
    }
  }

  /// Seller: create a store-scoped code. RLS rejects any attempt to write a
  /// platform-wide or platform-funded voucher, so there is nothing for the
  /// client to guard here.
  Future<Map<String, dynamic>> createVoucher({
    required String storeId,
    required String code,
    required String discountType, // 'fixed' | 'percent'
    required double discountValue,
    double minOrderAmount = 0,
    double? maxDiscountAmount,
    int? maxUses,
    int perUserLimit = 1,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    final uid = _uid;
    if (uid == null) throw const VoucherException('Please sign in again.');
    try {
      final row = await _client
          .from('vouchers')
          .insert({
            'store_id': storeId,
            'code': code.trim().toUpperCase(),
            'discount_type': discountType,
            'discount_value': discountValue,
            'min_order_amount': minOrderAmount,
            'max_discount_amount': ?maxDiscountAmount,
            'max_uses': ?maxUses,
            'per_user_limit': perUserLimit,
            'starts_at': ?startsAt?.toUtc().toIso8601String(),
            'ends_at': ?endsAt?.toUtc().toIso8601String(),
            'funded_by': 'store',
            'created_by': uid,
          })
          .select()
          .single();
      return Map<String, dynamic>.from(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505' || e.message.contains('uq_vouchers_code')) {
        throw const VoucherException(
            'That code is already in use. Pick a different one.');
      }
      throw VoucherException(
          e.message.trim().isEmpty ? 'We could not save that code.' : e.message);
    } catch (e) {
      debugPrint('[VOUCHER] create failed: $e');
      throw const VoucherException('We could not save that code. Please try again.');
    }
  }

  /// Seller: edit the parts that are still editable. Money terms are frozen
  /// once a code has been redeemed (server-enforced), so this deliberately
  /// does not send code/discount_type/discount_value.
  Future<void> updateVoucher({
    required String voucherId,
    double? minOrderAmount,
    double? maxDiscountAmount,
    int? maxUses,
    int? perUserLimit,
    DateTime? startsAt,
    DateTime? endsAt,
    bool? isActive,
  }) async {
    final patch = <String, dynamic>{
      'min_order_amount': ?minOrderAmount,
      'max_discount_amount': ?maxDiscountAmount,
      'max_uses': ?maxUses,
      'per_user_limit': ?perUserLimit,
      'starts_at': ?startsAt?.toUtc().toIso8601String(),
      'ends_at': ?endsAt?.toUtc().toIso8601String(),
      'is_active': ?isActive,
    };
    if (patch.isEmpty) return;
    try {
      await _client.from('vouchers').update(patch).eq('id', voucherId);
    } on PostgrestException catch (e) {
      throw VoucherException(
          e.message.trim().isEmpty ? 'We could not update that voucher.' : e.message);
    }
  }

  /// Seller/admin: retire a code immediately (the supported alternative to
  /// deleting it, which would break redemption history).
  Future<void> deactivateVoucher(String voucherId) async {
    try {
      await _client.rpc('deactivate_voucher', params: {'p_voucher_id': voucherId});
    } on PostgrestException catch (e) {
      throw VoucherException(
          e.message.trim().isEmpty ? 'We could not stop that voucher.' : e.message);
    }
  }

  /// Seller: redemption history (who used what, on which order, for how
  /// much) — the reconciliation view.
  Future<List<Map<String, dynamic>>> listRedemptions() async {
    try {
      final rows = await _client
          .from('voucher_redemptions')
          .select(
            'id, code, discount_amount, funded_by, created_at, order_id, '
            'voucher_id, store_id, customer_id, '
            'profiles(full_name), vouchers(discount_type, discount_value)',
          )
          .order('created_at', ascending: false)
          .limit(200);
      return (rows as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } catch (e) {
      debugPrint('[VOUCHER] redemptions failed: $e');
      throw const VoucherException(
          'We could not load the redemption history. Please try again.');
    }
  }

  /// The seller's own store id (one store per seller — see
  /// 20260709_one_store_per_seller.sql).
  Future<String?> myStoreId() async {
    final uid = _uid;
    if (uid == null) return null;
    final row = await _client
        .from('stores')
        .select('id')
        .eq('owner_id', uid)
        .maybeSingle();
    return row?['id']?.toString();
  }
}
