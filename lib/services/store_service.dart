import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/followed_store.dart';
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
  ///
  /// Enforces one store per seller — throws if the seller already owns a store.
  Future<Map<String, dynamic>> createStore({
    required String name,
    required String tagline,
    required String location,
    required String brandColor,
    // Optional — collected separately from the Step 4 description so a
    // seller can add their story after store creation.
    String? description,
    List<String> tags = const [],
    XFile? logoImage,
    XFile? bannerImage,
  }) async {
    final sellerId = _client.auth.currentUser!.id;

    // Guard: one store per seller
    final existing = await getMyStore();
    if (existing != null) {
      throw Exception(
          'You already have a store. Each seller can only manage one store.');
    }

    final store = await _client
        .from('stores')
        .insert({
          'owner_id': sellerId,
          'name': name.trim(),
          'tagline': tagline.trim(),
          'location': location.trim(),
          'brand_color': brandColor,
          // Null when left blank — not an empty string.
          'description': (description == null || description.trim().isEmpty)
              ? null
              : description.trim(),
          // Store tags — same preset vocabulary as product tags. Falls
          // back to the application's profiles.store_tags when the caller
          // passed none (mirrors the banner fallback below).
          'tags': tags.isNotEmpty ? tags : null,
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
    } else {
      // Fall back to the store-front photo submitted with the seller
      // application (uploaded to the PUBLIC store-assets bucket as
      // `{userId}/storefront.jpg`) so the banner is pre-filled from the
      // application. The seller can still replace it via Edit Store.
      final profile = await _client
          .from('profiles')
          .select('store_front_url')
          .eq('id', sellerId)
          .maybeSingle();
      final fallback = profile?['store_front_url']?.toString();
      if (fallback != null && fallback.isNotEmpty) {
        updates['banner_url'] = _client
            .storage
            .from('store-assets')
            .getPublicUrl(fallback);
      }
    }

    // Tags fallback: when the caller passed none (first-time setup with no
    // tag edits), carry over the application's store_tags from the profile.
    if (tags.isEmpty) {
      final profileTags = await _client
          .from('profiles')
          .select('store_tags')
          .eq('id', sellerId)
          .maybeSingle();
      final fallback = _stringListOf(profileTags?['store_tags']);
      if (fallback.isNotEmpty) {
        updates['tags'] = fallback;
      }
    }

    if (updates.isNotEmpty) {
      await _client.from('stores').update(updates).eq('id', storeId);
      store.addAll(updates);
    }

    return Map<String, dynamic>.from(store);
  }

  /// The storefront the seller already submitted in their Tier 1
  /// application (Steps 3–5): the proposed store name, description, tags,
  /// map-picked location, and the store-front photo as a ready-to-render
  /// public URL (it doubles as the store banner). Used to pre-fill
  /// CreateStoreScreen so a seller never re-enters what they already
  /// typed/uploaded. Returns null when the seller has no storefront
  /// application data on their profile.
  Future<Map<String, dynamic>?> getApplicationStorefront() async {
    final sellerId = _client.auth.currentUser!.id;
    final profile = await _client
        .from('profiles')
        .select(
          'store_name, store_description, store_front_url, '
          'store_location, store_lat, store_lng, store_tags',
        )
        .eq('id', sellerId)
        .maybeSingle();
    if (profile == null) return null;
    final storeFrontPath = profile['store_front_url']?.toString() ?? '';
    return {
      'store_name': profile['store_name']?.toString() ?? '',
      'store_description': profile['store_description']?.toString() ?? '',
      'banner_url': storeFrontPath.isEmpty
          ? null
          : _client.storage.from('store-assets').getPublicUrl(storeFrontPath),
      'store_location': profile['store_location']?.toString() ?? '',
      'store_lat': (profile['store_lat'] as num?)?.toDouble(),
      'store_lng': (profile['store_lng'] as num?)?.toDouble(),
      'store_tags': _stringListOf(profile['store_tags']),
    };
  }

  static List<String> _stringListOf(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  /// Update an existing store.
  Future<void> updateStoreSeller({
    required String storeId,
    required String name,
    required String tagline,
    required String location,
    required String brandColor,
    required bool isOpen,
    String? description,
    List<String> tags = const [],
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
      'description': (description == null || description.trim().isEmpty)
          ? null
          : description.trim(),
      // Null when cleared — not an empty array (keeps legacy rows tidy).
      'tags': tags.isEmpty ? null : tags,
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

  /// Update the store's static GCash QR settings (used at POS checkout).
  ///
  /// Uploads the QR image to the public `store-assets` bucket and stores the
  /// public URL plus optional account name/number for display under the QR.
  /// Pass [removeQr] to clear an existing QR without uploading a new one.
  Future<void> updateGcashSettings({
    required String storeId,
    XFile? qrImage,
    String? accountName,
    String? gcashNumber,
    bool removeQr = false,
  }) async {
    final sellerId = _client.auth.currentUser!.id;
    final updates = <String, dynamic>{};

    if (qrImage != null) {
      // Stable path + upsert: replacing the QR overwrites the same object,
      // so old files never orphan in the bucket.
      updates['gcash_qr_url'] = await _uploadStoreImage(
        bucket: 'store-assets',
        path: '$sellerId/$storeId/gcash_qr.png',
        file: qrImage,
        contentType: 'image/png',
      );
    } else if (removeQr) {
      updates['gcash_qr_url'] = null;
      // Best-effort removal of the stored object (and any legacy timestamped
      // file) so removing the QR doesn't leave files behind in the bucket.
      await _removeStoreObject(
        bucket: 'store-assets',
        path: '$sellerId/$storeId/gcash_qr.png',
      );
    }

    if (accountName != null) {
      updates['gcash_account_name'] = accountName.trim();
    }
    if (gcashNumber != null) {
      updates['gcash_number'] = gcashNumber.trim();
    }

    if (updates.isNotEmpty) {
      await _client.from('stores').update(updates).eq('id', storeId);
    }
  }

  /// Toggle store open/closed.
  /// When auto-schedule is enabled:
  /// - Closing (isOpen=false) sets manual_override = true (seller closing against schedule)
  /// - Reopening (isOpen=true) clears manual_override = false (matches schedule)
  Future<void> toggleStoreOpen(String storeId, bool isOpen, {bool autoScheduleEnabled = false}) async {
    final updates = <String, dynamic>{'is_open': isOpen};
    if (autoScheduleEnabled) {
      // Closing manually = override; reopening manually = clear override
      updates['manual_override'] = !isOpen;
    }
    await _client.from('stores').update(updates).eq('id', storeId);
  }

  /// Clear manual override and let the schedule resume.
  Future<void> clearManualOverride(String storeId) async {
    await _client
        .from('stores')
        .update({'manual_override': false}).eq('id', storeId);
  }

  /// Update store auto-schedule settings.
  Future<void> updateStoreSchedule({
    required String storeId,
    required bool autoScheduleEnabled,
    required String? openTime,
    required String? closeTime,
  }) async {
    final updates = <String, dynamic>{
      'auto_schedule_enabled': autoScheduleEnabled,
      'open_time': openTime,
      'close_time': closeTime,
    };
    // When enabling schedule, clear any manual override so schedule takes effect
    if (autoScheduleEnabled) {
      updates['manual_override'] = false;
    }
    await _client.from('stores').update(updates).eq('id', storeId);
  }



  /// Best-effort removal of a stored object. Ignores errors so removing an
  /// already-gone object never fails the settings save.
  Future<void> _removeStoreObject({
    required String bucket,
    required String path,
  }) async {
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (_) {
      // Best effort — the DB column is the source of truth for availability.
    }
  }

  /// Upload a store image (logo, banner, or GCash QR) and return the public URL.
  Future<String> _uploadStoreImage({
    required String bucket,
    required String path,
    required XFile file,
    String contentType = 'image/jpeg',
  }) async {
    final bytes = await file.readAsBytes();
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
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
    debugPrint('[Follow] followStore: userId=$userId storeId=$storeId');
    if (userId == null) {
      throw Exception('You must be logged in to follow a store.');
    }
    try {
      // Upsert: idempotent — safe for rapid double-taps.
      // If the row already exists, this is a harmless no-op.
      await _client.from('store_follows').upsert(
        {'user_id': userId, 'store_id': storeId},
        onConflict: 'user_id,store_id',
      );
      debugPrint('[Follow] Upsert succeeded');
    } catch (e, st) {
      debugPrint('[Follow] UPSERT FAILED: $e');
      debugPrint('[Follow] Stack: $st');
      rethrow;
    }
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

  String? get currentUserId => _client.auth.currentUser?.id;

  Future<void> toggleFollow(String storeId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('You must be logged in to follow a store.');
    }
    final following = await isFollowingAsync(storeId);
    debugPrint('[Follow] toggleFollow: isFollowing=$following → toggling');
    if (following) {
      await unfollowStore(storeId);
    } else {
      await followStore(storeId);
    }
  }

  /// Full list of stores a user follows, with store details.
  /// Tries the join query first; falls back to separate queries if the
  /// foreign key relationship between store_follows and stores is missing.
  Future<List<FollowedStore>> getFollowedStores(String userId) async {
    debugPrint('[StoreService] getFollowedStores called: userId=$userId');
    try {
      // Try the join query (requires FK from store_follows.store_id → stores.id)
      final data = await _client
          .from('store_follows')
          .select('created_at, stores(id, name, logo_url, tagline, brand_color)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      debugPrint('[StoreService] Join query returned ${data.length} rows');

      if (data.isEmpty) {
        debugPrint('[StoreService] No follows found for user');
        return [];
      }

      // Check if the join actually returned store data
      final hasStoreData =
          data.every((r) => r['stores'] != null && r['stores'] is Map);
      debugPrint('[StoreService] hasStoreData=$hasStoreData');

      if (hasStoreData) {
        final storeIds = data.map((r) => r['stores']['id'] as String).toList();
        final counts = await getFollowerCounts(storeIds);

        return data.map((r) {
          final store = r['stores'];
          return FollowedStore(
            storeId: store['id'],
            name: store['name'],
            logoUrl: store['logo_url'],
            tagline: store['tagline'],
            color: store['brand_color'],
            followedAt: DateTime.parse(r['created_at']),
            followerCount: counts[store['id']] ?? 0,
          );
        }).toList();
      }

      // Fallback: no FK — do two separate queries
      debugPrint('[StoreService] Join data missing store info, using fallback');
      return _getFollowedStoresFallback(userId);
    } catch (e) {
      debugPrint('[StoreService] getFollowedStores ERROR: $e');
      // Fallback: no FK — do two separate queries
      return _getFollowedStoresFallback(userId);
    }
  }

  /// Fallback: fetch follows and stores separately (no FK required).
  Future<List<FollowedStore>> _getFollowedStoresFallback(String userId) async {
    final follows = await _client
        .from('store_follows')
        .select('store_id, created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    if (follows.isEmpty) return [];

    final storeIds = follows.map((r) => r['store_id'] as String).toList();
    final storeData = await _client
        .from('stores')
        .select('id, name, logo_url, tagline, brand_color')
        .inFilter('id', storeIds);

    final storeMap = <String, Map<String, dynamic>>{};
    for (final s in storeData) {
      storeMap[s['id'] as String] = s;
    }

    final counts = await getFollowerCounts(storeIds);

    return follows.map((r) {
      final storeId = r['store_id'] as String;
      final store = storeMap[storeId];
      return FollowedStore(
        storeId: storeId,
        name: store?['name'] as String? ?? 'Unknown Store',
        logoUrl: store?['logo_url'] as String?,
        tagline: store?['tagline'] as String?,
        color: store?['brand_color'] as String?,
        followedAt: DateTime.parse(r['created_at']),
        followerCount: counts[storeId] ?? 0,
      );
    }).toList();
  }

  /// Batched follower counts for a list of store IDs (single query).
  Future<Map<String, int>> getFollowerCounts(List<String> storeIds) async {
    if (storeIds.isEmpty) return {};
    final data = await _client
        .from('store_follows')
        .select('store_id')
        .inFilter('store_id', storeIds);
    final counts = <String, int>{};
    for (final row in data) {
      final id = row['store_id'] as String;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  /// Total number of stores the given user follows (source of truth).
  Future<int> getFollowingCount(String userId) async {
    final response = await _client
        .from('store_follows')
        .select('store_id')
        .eq('user_id', userId)
        .count(CountOption.exact);
    return response.count;
  }

  /// Single-store follower count.
  Future<int> getFollowerCount(String storeId) async {
    final response = await _client
        .from('store_follows')
        .select('user_id')
        .eq('store_id', storeId)
        .count(CountOption.exact);
    return response.count;
  }
}
