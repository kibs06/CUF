import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/account_security_overview.dart';

/// Raised when the account-security diagnostics cannot be read.
///
/// [code] carries the database error code so the screen can distinguish
/// "you are not an admin" (42501) from "no such account" (P0002) rather
/// than showing both as a generic failure.
class AccountSecurityException implements Exception {
  final String message;
  final String? code;

  const AccountSecurityException(this.message, {this.code});

  @override
  String toString() => message;
}

/// Client for `public.admin_account_security_overview` (migration
/// 20260915160000) — the admin-side view of trusted devices, credentials,
/// the GoTrue event timeline and password lockouts for ONE account.
///
/// Everything is read through a single SECURITY DEFINER RPC that authorises
/// the CALLER with `public.is_admin()`:
///
///   • The subject's user id is an ARGUMENT, because an admin investigating
///     someone else's account is the whole point.
///   • The function is the only thing that can read `device_secrets` (the
///     table has no grants at all), and it returns only whether a
///     credential EXISTS plus when it was minted — never the hash.
///   • It is granted to `authenticated` only; `anon` is refused so an
///     unauthenticated caller cannot enumerate accounts.
class AccountSecurityService {
  final SupabaseClient _client;

  AccountSecurityService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  /// Read the diagnostics document for [userId].
  ///
  /// Throws [AccountSecurityException] with a message that can be shown
  /// as-is; the caller is expected to be an admin, and a non-admin gets
  /// the same 42501 the database raises.
  Future<AccountSecurityOverview> fetchOverview(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) {
      throw const AccountSecurityException(
        'An account is required to read its security diagnostics.',
      );
    }

    try {
      final data = await _client.rpc(
        'admin_account_security_overview',
        params: {'p_user_id': id},
      );
      final map = data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
      if (map.isEmpty) {
        // The function always returns a document or raises; an empty map
        // means something upstream changed shape, and guessing would put
        // a blank screen in front of an admin who is debugging.
        throw const AccountSecurityException(
          'The server returned an empty security report.',
        );
      }
      return AccountSecurityOverview.fromJson(map);
    } on PostgrestException catch (e) {
      debugPrint('[ACCOUNT_SECURITY] rpc failed: ${e.code} ${e.message}');
      throw AccountSecurityException(_messageFor(e), code: e.code);
    } on AccountSecurityException {
      rethrow;
    } catch (e) {
      debugPrint('[ACCOUNT_SECURITY] unexpected failure: $e');
      throw const AccountSecurityException(
        'Could not load the account security report. Please try again.',
      );
    }
  }

  String _messageFor(PostgrestException e) {
    final raw = e.message.trim();
    switch (e.code) {
      case '42501':
        return 'Only an admin account can read security diagnostics.';
      case 'P0002':
        // The server names the id it could not find; that is more useful
        // than a generic message when an admin pasted the wrong id.
        return raw.isEmpty ? 'No such account.' : raw;
      case '22023':
        return raw.isEmpty ? 'A valid user id is required.' : raw;
      default:
        if (raw.isNotEmpty) return raw;
        return 'Could not load the account security report. Please try again.';
    }
  }
}
