import 'package:app/services/device_trust_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The "keychain is unavailable" half of the device-trust contract.
///
/// This file deliberately **never** calls
/// `FlutterSecureStorage.setMockInitialValues`. With no mock installed the
/// plugin has no platform implementation, so every call throws
/// `MissingPluginException` — which is exactly the shape of a real keystore
/// failure (a locked Android keystore, an iOS keychain the app has no access
/// to). Because the mock is process-global, that has to live in its own file:
/// any mocking in this file would silently turn these assertions into happy
/// paths. See device_trust_persistence_test.dart for the mocked counterpart.
///
/// The governing rule is the one from the architecture doc:
///
///   **Never lock a legitimate user out because of our own plumbing.**
///
/// So every storage failure must degrade to "we cannot tell", never to a throw
/// and never to a fabricated identity — a fabricated id would look like a new
/// device on every launch and re-send an OTP code forever.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('an unavailable keychain fails OPEN', () {
    test('the device id is reported as unknown instead of throwing', () async {
      // assertDoesNotThrow is implicit: a throw here fails the test. The
      // LoginChallengeService treats a null id as "cannot tell whether this is
      // a new device" and proceeds, so this must not become an exception on
      // the login path.
      final id = await DeviceTrustService.fresh().currentDeviceId();

      expect(id, isNull);
    });

    test('the id is not invented when it cannot be read', () async {
      // Two calls must agree. If a failed read produced a fresh UUID each
      // time, every launch would be a new device AND a new OTP.
      final first = await DeviceTrustService.fresh().currentDeviceId();
      final second = await DeviceTrustService.fresh().currentDeviceId();

      expect(first, isNull);
      expect(second, isNull);
      expect(second, first);
    });

    test('the label lookup never throws, whatever the platform reports',
        () async {
      // Unlike the keychain, device_info_plus works in the test host, so this
      // asserts the CONTRACT (a usable label or a clean null — never an
      // exception on the login path) rather than assuming a failure.
      final label = await DeviceTrustService.fresh().currentDeviceLabel();
      expect(label == null || label.trim().isNotEmpty, isTrue);
    });

    test('no secret is assumed when storage cannot be read', () async {
      // Must be FALSE, not true: "we hold a credential" is what makes the app
      // skip the step-up, so a broken keychain must never imply it.
      final service = DeviceTrustService.fresh();

      expect(await service.hasDeviceSecret('user-1'), isFalse);
      expect(await service.currentDeviceToken('user-1'), isNull);
    });

    test('storing a secret swallows the failure instead of breaking login',
        () async {
      // Reached right after a successful verification: the user has already
      // typed a valid code, so a failed write must not undo their login. It
      // costs them one more challenge next time, which is the cheap side of
      // the trade.
      await expectLater(
        DeviceTrustService.fresh().storeDeviceSecret('user-1', List.filled(64, 'a').join()),
        completes,
      );
    });

    test('the header refresh degrades quietly (no Supabase, no keystore)',
        () async {
      // Called from main() before the first request and on every auth-state
      // change, so it runs in environments with neither a Supabase client nor
      // a keystore. It must never be the thing that crashes startup.
      await expectLater(
        DeviceTrustService.fresh().refreshRequestHeader(),
        completes,
      );
    });
  });
}
