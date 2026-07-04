import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/store.dart';

class StoreService {
  static final StoreService instance = StoreService._internal();
  StoreService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  // ─── SELLER STORE METHODS ────────────────────────────────────

  /// Get the current seller's store. Returns null if not created yet.
  Future<Map<String, dynamic>?> getMyStore() async {
    final sellerId = _client.auth.currentUser!.id;
    final data = await _client
        .from('stores')
        .select()
        .eq('owner_id', sellerId)
        .maybeSingle();
    return data == null
        ? null
        : Map<String, dynamic>.from(data as Map);
  }

  /// Create a new store with optional logo and banner uploads.
  Future<Map<String, dynamic>> createStore({
    required String name,
    required String tagline,
    required String location,
    required String brandColor,
    XFile? logoImage,
    XFile? bannerImage,
  }) async {
    final sellerId = _client.auth.currentUser!.id;

    final store = await _client
        .from('stores')
        .insert({
          'owner_id': sellerId,
          'name': name.trim(),
          'tagline': tagline.trim(),
          'location': location.trim(),
          'brand_color': brandColor,
          'is_open': true,
          'is_active': true,
        })
        .select()
        .single();

    final storeId = store['id'] as String;
    final updates = <String, dynamic>{};

    if (logoImage != null) {
      updates['logo_url'] = await _uploadStoreImage(
        bucket: 'store-assets',
        path: '$sellerId/$storeId/logo.jpg',
        file: logoImage,
      );
    }

    if (bannerImage != null) {
      updates['banner_url'] = await _uploadStoreImage(
        bucket: 'store-assets',
        path: '$sellerId/$storeId/banner.jpg',
        file: bannerImage,
      );
    }

    if (updates.isNotEmpty) {
      await _client.from('stores').update(updates).eq('id', storeId);
      store.addAll(updates);
    }

    return Map<String, dynamic>.from(store);
  }

  /// Update an existing store.
  Future<void> updateStoreSeller({
    required String storeId,
    required String name,
    required String tagline,
    required String location,
    required String brandColor,
    required bool isOpen,
    XFile? newLogoImage,
    XFile? newBannerImage,
    bool removeLogo = false,
    bool removeBanner = false,
  }) async {
    final sellerId = _client.auth.currentUser!.id;
    final updates = <String, dynamic>{
      'name': name.trim(),
      'tagline': tagline.trim(),
      'location': location.trim(),
      'brand_color': brandColor,
      'is_open': isOpen,
    };

    if (newLogoImage != null) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      updates['logo_url'] = await _uploadStoreImage(
        bucket: 'store-assets',
        path: '$sellerId/$storeId/logo_$ts.jpg',
        file: newLogoImage,
      );
    } else if (removeLogo) {
      updates['logo_url'] = null;
    }

    if (newBannerImage != null) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      updates['banner_url'] = await _uploadStoreImage(
        bucket: 'store-assets',
        path: '$sellerId/$storeId/banner_$ts.jpg',
        file: newBannerImage,
      );
    } else if (removeBanner) {
      updates['banner_url'] = null;
    }

    await _client.from('stores').update(updates).eq('id', storeId);
  }

  /// Toggle store open/closed.
  Future<void> toggleStoreOpen(String storeId, bool isOpen) async {
    await _client
        .from('stores')
        .update({'is_open': isOpen}).eq('id', storeId);
  }

  /// Upload a store image (logo or banner) and return the public URL.
  Future<String> _uploadStoreImage({
    required String bucket,
    required String path,
    required XFile file,
  }) async {
    final bytes = await file.readAsBytes();
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions:
              const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    return _client.storage.from(bucket).getPublicUrl(path);
  }

  // ─── CUSTOMER-FACING STORE METHODS ───────────────────────────

  Future<List<Store>> fetchAllStores() async {
    final data = await _client
        .from('stores')
        .select()
        .eq('is_active', true)
        .order('created_at', ascending: false);

    return (data as List)
        .map((row) => Store.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<Store?> fetchStoreById(String storeId) async {
    final data = await _client
        .from('stores')
        .select()
        .eq('id', storeId)
        .maybeSingle();
    return data == null ? null : Store.fromMap(Map<String, dynamic>.from(data));
  }

  int getProductCountForStore(
    String storeId,
    List<Map<String, dynamic>> allProducts,
  ) {
    return allProducts
        .where((p) => p['store_id']?.toString() == storeId)
        .length;
  }

  Future<List<Map<String, dynamic>>> getStoryEntriesForStore(
    String storeId,
  ) async {
    final data = await _client
        .from('story_entries')
        .select()
        .eq('store_id', storeId)
        .order('display_order');

    return (data as List).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      return {...map, 'title': map['title'] ?? 'Our Story'};
    }).toList();
  }

  Future<String> uploadStoreAsset(
    String storeId,
    String sellerId,
    String filePath,
    String type,
  ) async {
    final bucket = _client.storage.from('store-assets');
    final ext = filePath.split('.').last.toLowerCase();
    final path =
        '$sellerId/$storeId-$type-${DateTime.now().millisecondsSinceEpoch}.$ext';

    await bucket.upload(path, File(filePath));
    final url = bucket.getPublicUrl(path);
    await _client
        .from('stores')
        .update({type == 'logo' ? 'logo_url' : 'banner_url': url})
        .eq('id', storeId);
    return url;
  }

  Future<void> updateStore(String storeId, Map<String, dynamic> data) async {
    await _client.from('stores').update(data).eq('id', storeId);
  }

  Future<void> followStore(String storeId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('You must be logged in to follow a store.');
    }
    await _client.from('store_follows').upsert({
      'user_id': userId,
      'store_id': storeId,
    });
  }

  Future<void> unfollowStore(String storeId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('You must be logged in to unfollow a store.');
    }
    await _client
        .from('store_follows')
        .delete()
        .eq('user_id', userId)
        .eq('store_id', storeId);
  }

  Future<bool> isFollowingAsync(String storeId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    final data = await _client
        .from('store_follows')
        .select('store_id')
        .eq('user_id', userId)
        .eq('store_id', storeId)
        .maybeSingle();
    return data != null;
  }

  void toggleFollow(String storeId) {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    isFollowingAsync(storeId).then((following) {
      if (following) {
        unfollowStore(storeId);
      } else {
        followStore(storeId);
      }
    });
  }

  bool isFollowing(String storeId) => false;
}
