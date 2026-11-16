import 'package:flutter_test/flutter_test.dart';

import 'package:app/constants/app_constants.dart';

/// Cover for the Google sign-in CLIENT ID as it is actually compiled in.
///
/// v1.0.81 shipped with `GOOGLE_SERVER_CLIENT_ID` empty: the value only ever
/// lived in the git-ignored `dart_defines.json`, and the tagged-release job
/// reads `RELEASE_DART_DEFINES` instead — so `AuthService.signInWithGoogle`
/// answered every tap with the dormant "not switched on yet" copy and the
/// account picker never opened. The constant's compiled default is the fix;
/// these assertions fail the suite if that default is ever taken away again.
void main() {
  group('AppConstants.googleServerClientId', () {
    test('is compiled into every build (never empty)', () {
      expect(AppConstants.googleServerClientId, isNotEmpty);
    });

    test('is a Google Web OAuth client ID, not an Android/iOS one', () {
      // The native SDK sends this to Google as the token audience, so it has
      // to be the `…apps.googleusercontent.com` form — the same value the
      // Supabase Google provider is configured with.
      expect(
        AppConstants.googleServerClientId,
        endsWith('.apps.googleusercontent.com'),
      );
      expect(
        AppConstants.googleServerClientId,
        isNot(contains(RegExp(r'\s'))),
      );
    });
  });
}
