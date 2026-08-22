import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// App-root provider that manages the home-screen banner carousel.
///
/// Banners are admin-managed rows in the `banners` table. The RLS policy
/// already restricts anonymous reads to active + in-schedule rows, so the
/// query itself is simple — no client-side filtering needed.
class BannerProvider extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  List<Map<String, dynamic>> _banners = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> get banners => _banners;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Fetch active banners ordered by display_order.
  ///
  /// The RLS policy on the `banners` table already filters to:
  ///   is_active = true
  ///   AND (starts_at IS NULL OR starts_at <= now())
  ///   AND (ends_at IS NULL OR ends_at >= now())
  ///
  /// So we just select everything — the database handles visibility.
  Future<void> loadBanners() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _client
          .from('banners')
          .select()
          .order('display_order', ascending: true)
          .order('created_at', ascending: false);

      // PostgrestException is thrown on error — no .error getter on PostgrestList.
      _banners = (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[BannerProvider] loadBanners failed: $e');
      _errorMessage = e.toString();
      // Keep existing banners on error — don't clear a previously loaded list
    }

    _isLoading = false;
    notifyListeners();
  }
}
