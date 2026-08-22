import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A stored account entry with display info and session tokens.
class AccountEntry {
  final String userId;
  final String email;
  final String? fullName;
  final String? avatarUrl;
  final String refreshToken;
  final DateTime savedAt;

  AccountEntry({
    required this.userId,
    required this.email,
    this.fullName,
    this.avatarUrl,
    required this.refreshToken,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'email': email,
        'fullName': fullName,
        'avatarUrl': avatarUrl,
        'refreshToken': refreshToken,
        'savedAt': savedAt.toIso8601String(),
      };

  factory AccountEntry.fromJson(Map<String, dynamic> json) => AccountEntry(
        userId: json['userId'] as String,
        email: json['email'] as String,
        fullName: json['fullName'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        refreshToken: json['refreshToken'] as String,
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
}

/// Manages multiple Supabase account sessions on a single device.
///
/// Each logged-in account is stored as a JSON object in [FlutterSecureStorage]
/// under the key `multi_accounts`. The currently active account ID is stored
/// under `active_account_id`.
///
/// This allows instant switching between previously-logged-in accounts
/// without re-entering credentials, similar to Gmail/Instagram account
/// switching.
class AccountManager {
  AccountManager._();
  static final AccountManager instance = AccountManager._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const _keyAccounts = 'multi_accounts';
  static const _keyActiveId = 'active_account_id';

  SupabaseClient get _client => Supabase.instance.client;

  // ── Read operations ───────────────────────────────────────────

  /// Returns all stored accounts, ordered by most recently used.
  Future<List<AccountEntry>> getAccounts() async {
    final raw = await _storage.read(key: _keyAccounts);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => AccountEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      // Most recent first
      list.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Returns the active account entry, or null if none set.
  Future<AccountEntry?> getActiveAccount() async {
    final activeId = await _storage.read(key: _keyActiveId);
    if (activeId == null) return null;
    final accounts = await getAccounts();
    try {
      return accounts.firstWhere((a) => a.userId == activeId);
    } catch (_) {
      return null;
    }
  }

  /// Returns the active account ID, or null.
  Future<String?> getActiveAccountId() async {
    return _storage.read(key: _keyActiveId);
  }

  // ── Write operations ──────────────────────────────────────────

  /// Saves or updates the current Supabase session as a stored account.
  /// Called after login/signup to persist the session for future switching.
  Future<void> saveCurrentSession({Map<String, dynamic>? profile}) async {
    final session = _client.auth.currentSession;
    final user = _client.auth.currentUser;
    if (session == null || user == null) return;

    final entry = AccountEntry(
      userId: user.id,
      email: user.email ?? '',
      fullName: profile?['full_name'] as String? ??
          user.userMetadata?['full_name'] as String?,
      avatarUrl: profile?['avatar_url'] as String?,
      refreshToken: session.refreshToken ?? '',
      savedAt: DateTime.now(),
    );

    final accounts = await getAccounts();
    // Remove existing entry for this user (update case)
    accounts.removeWhere((a) => a.userId == user.id);
    accounts.add(entry);

    await _storage.write(key: _keyAccounts, value: jsonEncode(accounts));
    await _storage.write(key: _keyActiveId, value: user.id);
  }

  /// Sets the active account ID (without switching the Supabase session).
  Future<void> setActiveAccountId(String userId) async {
    await _storage.write(key: _keyActiveId, value: userId);
  }

  /// Removes an account from the stored list (does NOT delete the account
  /// on the server — just forgets it locally).
  Future<void> removeAccount(String userId) async {
    final accounts = await getAccounts();
    accounts.removeWhere((a) => a.userId == userId);
    await _storage.write(key: _keyAccounts, value: jsonEncode(accounts));

    // If the removed account was active, clear it
    final activeId = await _storage.read(key: _keyActiveId);
    if (activeId == userId) {
      if (accounts.isNotEmpty) {
        // Fall back to the most recent remaining account
        await _storage.write(
            key: _keyActiveId, value: accounts.first.userId);
      } else {
        await _storage.delete(key: _keyActiveId);
      }
    }
  }

  /// Clears all stored accounts and the active ID.
  Future<void> clearAll() async {
    await _storage.delete(key: _keyAccounts);
    await _storage.delete(key: _keyActiveId);
  }

  /// Updates display info (name, avatar) for an account without touching
  /// the refresh token. Useful after profile edits.
  Future<void> updateAccountInfo(
    String userId, {
    String? fullName,
    String? avatarUrl,
  }) async {
    final accounts = await getAccounts();
    final idx = accounts.indexWhere((a) => a.userId == userId);
    if (idx == -1) return;

    final old = accounts[idx];
    accounts[idx] = AccountEntry(
      userId: old.userId,
      email: old.email,
      fullName: fullName ?? old.fullName,
      avatarUrl: avatarUrl ?? old.avatarUrl,
      refreshToken: old.refreshToken,
      savedAt: old.savedAt,
    );
    await _storage.write(key: _keyAccounts, value: jsonEncode(accounts));
  }

  // ── Session switching ─────────────────────────────────────────

  /// Switches to a stored account by restoring its refresh token.
  ///
  /// Returns the new active [AccountEntry] on success, or null if the
  /// token is invalid/expired (the account should be removed from the list).
  Future<AccountEntry?> switchToAccount(String userId) async {
    final accounts = await getAccounts();
    final targetIdx = accounts.indexWhere((a) => a.userId == userId);
    if (targetIdx == -1) return null;
    final target = accounts[targetIdx];

    try {
      // Restore the session using the stored refresh token
      final response = await _client.auth.setSession(target.refreshToken);

      if (response.session == null) {
        // Token expired or invalid — remove this account
        await removeAccount(userId);
        return null;
      }

      // Update the stored refresh token (Supabase may have rotated it)
      final updatedEntry = AccountEntry(
        userId: target.userId,
        email: target.email,
        fullName: target.fullName,
        avatarUrl: target.avatarUrl,
        refreshToken: response.session!.refreshToken ?? '',
        savedAt: DateTime.now(),
      );

      final updatedAccounts = await getAccounts();
      updatedAccounts.removeWhere((a) => a.userId == userId);
      updatedAccounts.add(updatedEntry);
      await _storage.write(
          key: _keyAccounts, value: jsonEncode(updatedAccounts));
      await _storage.write(key: _keyActiveId, value: userId);

      return updatedEntry;
    } catch (e) {
      // Token invalid — remove the account
      await removeAccount(userId);
      return null;
    }
  }

  /// Checks if there are any stored accounts.
  Future<bool> hasAccounts() async {
    final accounts = await getAccounts();
    return accounts.isNotEmpty;
  }

  /// Returns the number of stored accounts.
  Future<int> accountCount() async {
    final accounts = await getAccounts();
    return accounts.length;
  }
}
