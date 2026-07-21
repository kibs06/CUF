import 'dart:async';

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/followed_store.dart';
import '../services/store_service.dart';

/// Lightweight ChangeNotifier that owns all follow/unfollow state
/// for the customer. Shared across ProfileScreen, Following dialog,
/// and StoreProfileScreen so that toggling in one place instantly
/// reflects everywhere.
class FollowProvider extends ChangeNotifier {
  final StoreService _storeService;
  final Set<String> _followedStoreIds = {};
  final Set<String> _pendingStoreIds = {}; // per-store in-flight guard (Issue 3)
  final Map<String, int> _followerCountCache = {}; // Issue 2: follower count per store
  int followingCount = 0;
  List<FollowedStore> _followedStores = [];
  bool _isLoaded = false;
  String? _errorMessage;

  FollowProvider(this._storeService);

  bool get isLoaded => _isLoaded;
  String? get errorMessage => _errorMessage;
  bool isFollowing(String storeId) => _followedStoreIds.contains(storeId);
  bool isPending(String storeId) => _pendingStoreIds.contains(storeId);
  List<FollowedStore> get followedStores => _followedStores;

  /// Issue 2: Read the reconciled follower count for a specific store.
  /// Falls back to [fallback] if not yet cached.
  int followerCountFor(String storeId, {int fallback = 0}) {
    return _followerCountCache[storeId] ?? fallback;
  }

  /// Classify errors into user-friendly messages (Issue 4).
  String _classifyError(Object error) {
    if (error is TimeoutException) {
      return "Couldn't connect. Check your internet connection and try again.";
    }
    final msg = error.toString().toLowerCase();
    if (msg.contains('socket') || msg.contains('connection') ||
        msg.contains('network') || msg.contains('timeout')) {
      return "Couldn't connect. Check your internet connection and try again.";
    }
    if (error is PostgrestException) {
      if (error.code == 'PGRST301' || msg.contains('jwt')) {
        return 'Your session expired. Please log in again.';
      }
      return 'Something went wrong. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  /// Load followed stores for the current user.
  /// Call once on login / app start, and again if the user logs
  /// out and back in as a different account.
  Future<void> loadForUser(String userId) async {
    debugPrint('[FollowProvider] loadForUser called: userId=$userId');
    _errorMessage = null;
    try {
      final stores = await _storeService.getFollowedStores(userId);
      debugPrint('[FollowProvider] loaded ${stores.length} followed stores');
      _followedStoreIds
        ..clear()
        ..addAll(stores.map((s) => s.storeId));
      followingCount = stores.length;
      _followedStores = stores;
      _isLoaded = true;
      notifyListeners();
    } catch (e, st) {
      debugPrint('[FollowProvider] loadForUser FAILED: $e');
      debugPrint('[FollowProvider] Stack: $st');
      _errorMessage = _classifyError(e);
      _isLoaded = true;
      notifyListeners();
    }
  }

  /// Reconcile followingCount against the DB source of truth.
  /// Called when the Following dialog opens to catch any drift.
  Future<void> reconcileCount(String userId) async {
    try {
      final trueCount = await _storeService.getFollowingCount(userId);
      if (followingCount != trueCount) {
        debugPrint('[FollowProvider] reconciliation: $followingCount -> $trueCount');
        followingCount = trueCount;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[FollowProvider] reconcileCount failed: $e');
    }
  }

  /// Reset state (e.g. on logout).
  void reset() {
    _followedStoreIds.clear();
    _pendingStoreIds.clear();
    _followerCountCache.clear();
    followingCount = 0;
    _followedStores = [];
    _isLoaded = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Optimistic toggle with automatic rollback on failure.
  /// Throws on failure so callers can show a SnackBar.
  /// Issue 3: per-store in-flight guard prevents duplicate toggles.
  /// Issue 2: reconciles follower count for the store immediately.
  Future<void> toggle(String storeId) async {
    // Issue 3: guard against concurrent toggles on the same store
    if (_pendingStoreIds.contains(storeId)) return;
    _pendingStoreIds.add(storeId);

    final wasFollowing = _followedStoreIds.contains(storeId);

    // Optimistic update
    wasFollowing
        ? _followedStoreIds.remove(storeId)
        : _followedStoreIds.add(storeId);
    followingCount = math.max(0, followingCount + (wasFollowing ? -1 : 1));
    notifyListeners();

    try {
      await _storeService.toggleFollow(storeId);
      // Re-fetch the followed list to keep _followedStores in sync
      // (especially for the dialog's list view).
      final userId = _storeService.currentUserId;
      if (userId != null) {
        _followedStores = await _storeService.getFollowedStores(userId);
        // Reconcile both counts with DB after successful toggle
        followingCount = await _storeService.getFollowingCount(userId);
        _followerCountCache[storeId] =
            await _storeService.getFollowerCount(storeId);
      }
      notifyListeners();
    } catch (e) {
      // Rollback
      wasFollowing
          ? _followedStoreIds.add(storeId)
          : _followedStoreIds.remove(storeId);
      followingCount = math.max(0, followingCount + (wasFollowing ? 1 : -1));
      notifyListeners();
      rethrow;
    } finally {
      _pendingStoreIds.remove(storeId);
      // Do NOT call notifyListeners() here — it can fire during a build
      // phase (when the widget tree is mid-rebuild), causing the
      // 'setState() called during build' error. The try/catch blocks
      // already call notifyListeners() at the right times.
    }
  }
}
