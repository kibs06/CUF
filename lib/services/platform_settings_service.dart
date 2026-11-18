import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The platform's own checkout numbers, read from `public.platform_settings`.
///
/// That table is a single row (`id = 1`) the admin portal owns, and it is what
/// the checkout RPCs charge: the delivery line in an order comes from
/// `delivery_fee_amount`, never from a constant in the app. The app therefore
/// displays this value instead of keeping its own copy — otherwise raising the
/// fee in the admin portal would change the total the server charges while the
/// customer kept seeing the old number.
class PlatformSettingsService {
  PlatformSettingsService._();

  static final PlatformSettingsService instance = PlatformSettingsService._();

  /// The seeded value of `delivery_fee_amount` and the fallback when the row
  /// cannot be read. Matches the column default in
  /// `20261118020000_add_platform_payment_account.sql`.
  static const double fallbackDeliveryFee = 100.0;

  double? _deliveryFee;

  /// The last value read from the server, if any.
  double? get cachedDeliveryFee => _deliveryFee;

  /// Reads `platform_settings.delivery_fee_amount`.
  ///
  /// Never throws: a network failure or a missing row returns the last value
  /// read, or [fallbackDeliveryFee].
  Future<double> fetchDeliveryFee() async {
    try {
      final row = await Supabase.instance.client
          .from('platform_settings')
          .select('delivery_fee_amount')
          .eq('id', 1)
          .maybeSingle();

      final value = (row?['delivery_fee_amount'] as num?)?.toDouble();
      if (value == null || value < 0) {
        return _deliveryFee ?? fallbackDeliveryFee;
      }
      _deliveryFee = value;
      return value;
    } catch (e) {
      debugPrint('PlatformSettingsService: delivery fee fetch failed: $e');
      return _deliveryFee ?? fallbackDeliveryFee;
    }
  }
}
