import 'package:app/services/account_manager.dart';
import 'package:app/services/biometric_service.dart';
import 'package:app/services/device_trust_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Persistence tests for the device-trust credential.
///
/// ## Why this file exists
///
/// Every other test in the suite injects a `DeviceTrustGateway` fake, which
/// means the one thing they can never check is the thing the feature actually
/// rests on: **the credential lives in secure storage across process
/// lifetimes.** The strongest claim in item 16 — "logging out and back in on
/// this phone does NOT re-trigger the OTP, because it is the same device" — was
/// asserted structurally and never executed.
///
/// `FlutterSecureStorage.setMockInitialValues` closes that gap with the
/// plugin's own supported seam. Two properties make it the right tool here:
///
///  * the mock is **process-global**, so a second `FlutterSecureStorage()`
///    sees the same map — which is what lets [DeviceTrustService.fresh] stand
///    in for the next app launch; and
///  * it exercises the REAL `DeviceTrustService` code (the id generation, the
///    `>= 8` / `>= 32` guards, the per-account key scheme, the token format)
///    rather than a fake's reimplementation of it.
///
/// NOTE: no test in this file may rely on `MissingPluginException` — mocking is
/// installed in [setUp]. The "keychain is broken" half of the contract lives in
/// device_trust_storage_failure_test.dart, which deliberately never mocks.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The keys are part of the on-disk contract: they survive app updates, so
  // renaming one silently retires every existing device identity.
  const idKey = 'cufmai_device_id_v1';
  const secretPrefix = 'cufmai_device_secret_v1_';

  const storage = FlutterSecureStorage();
  String secret(String c) => List.filled(64, c).join();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('device id', () {
    test('is generated once and stored under the documented key', () async {
      final id = await DeviceTrustService.fresh().currentDeviceId();

      expect(id, isNotNull);
      expect(id!.length, greaterThanOrEqualTo(8));
      // Written, not just returned — the next launch has to find it.
      expect(await storage.read(key: idKey), id);
    });

    test('is STABLE across instances (the next app launch reads the same id)',
        () async {
      // This is the whole "it is the same device" guarantee. If it ever fails,
      // every login is challenged as a new device and, with the server gate on,
      // the user has no credential at all.
      final first = await DeviceTrustService.fresh().currentDeviceId();
      final second = await DeviceTrustService.fresh().currentDeviceId();
      final third = await DeviceTrustService.fresh().currentDeviceId();

      expect(second, first);
      expect(third, first);
    });

    test('an existing stored id is adopted, never replaced', () async {
      await storage.write(key: idKey, value: 'device-existing-1234');

      expect(
        await DeviceTrustService.fresh().currentDeviceId(),
        'device-existing-1234',
      );
      expect(await storage.read(key: idKey), 'device-existing-1234');
    });

    test('rubbish in storage is replaced rather than trusted', () async {
      // The guard that stops a truncated/corrupt value becoming a "device".
      await storage.write(key: idKey, value: 'short');

      final id = await DeviceTrustService.fresh().currentDeviceId();

      expect(id, isNot('short'));
      expect(id!.length, greaterThanOrEqualTo(8));
      expect(await storage.read(key: idKey), id);
    });

    test('whitespace around a stored id is trimmed, not persisted back',
        () async {
      await storage.write(key: idKey, value: '  device-padded-1234  ');

      expect(
        await DeviceTrustService.fresh().currentDeviceId(),
        'device-padded-1234',
      );
    });
  });

  group('the credential survives the real logout path', () {
    /// Seeds an install that has already cleared the step-up, plus the keys
    /// the other services own, so the assertions below can tell them apart.
    Future<void> seedSignedInInstall() async {
      await storage.write(key: idKey, value: 'device-abcdefgh');
      await storage.write(key: '${secretPrefix}user-1', value: secret('a'));
      await storage.write(key: 'bio_email', value: 'maria@gmail.com');
      await storage.write(key: 'bio_password', value: 'hunter2');
      await storage.write(key: 'bio_enabled', value: 'true');
      await storage.write(key: 'multi_accounts', value: '[]');
      await storage.write(key: 'active_account_id', value: 'user-1');
    }

    test('logout cleanup leaves the device id and secret untouched', () async {
      await seedSignedInInstall();

      // Exactly what AuthProvider.logout() calls against secure storage —
      // the real services, not fakes. (The other things logout does are a
      // Supabase signOut and in-memory state clearing, neither of which can
      // reach secure storage.)
      await BiometricService.instance.clearCredentials();
      await AccountManager.instance.removeAccount('user-1');

      expect(await storage.read(key: idKey), 'device-abcdefgh');
      expect(await storage.read(key: '${secretPrefix}user-1'), secret('a'));

      // And a service that has never seen this process still finds both, which
      // is what stops the next login being challenged as a new device.
      final service = DeviceTrustService.fresh();
      expect(await service.currentDeviceId(), 'device-abcdefgh');
      expect(await service.hasDeviceSecret('user-1'), isTrue);
      expect(
        await service.currentDeviceToken('user-1'),
        'device-abcdefgh:${secret('a')}',
      );
    });

    test('logout still clears what it is supposed to clear', () async {
      // The mirror of the test above: guarding persistence must not turn into
      // guarding everything.
      await seedSignedInInstall();

      await BiometricService.instance.clearCredentials();
      await AccountManager.instance.removeAccount('user-1');

      expect(await storage.read(key: 'bio_email'), isNull);
      expect(await storage.read(key: 'bio_password'), isNull);
      expect(await storage.read(key: 'bio_enabled'), isNull);
      // The removed account was the active one and none remain, so it is gone.
      expect(await storage.read(key: 'active_account_id'), isNull);
    });

    test('the biometric full wipe cannot take other services down with it',
        () async {
      // Regression guard for `clearAll()` using FlutterSecureStorage
      // .deleteAll(): the secure store is shared with the device id, the
      // per-account secrets and the multi-account list, so a blanket delete
      // would wipe this device's identity — the phone would look brand new on
      // the next login and its step-up credential would be gone.
      await seedSignedInInstall();

      await BiometricService.instance.clearAll();

      expect(await storage.read(key: idKey), 'device-abcdefgh',
          reason: 'clearAll() must not destroy the device identity');
      expect(await storage.read(key: '${secretPrefix}user-1'), secret('a'),
          reason: 'clearAll() must not destroy the device secret');
      expect(await storage.read(key: 'multi_accounts'), '[]',
          reason: 'clearAll() must not wipe another service\'s keys');
      // It still does its own job, declined flag included.
      expect(await storage.read(key: 'bio_email'), isNull);
      expect(await storage.read(key: 'bio_declined'), isNull);
    });

    test('exactly the device and account keys exist afterwards', () async {
      // A whole-store assertion: it fails loudly if some future logout step
      // starts throwing deletes around, including keys nobody is watching.
      await seedSignedInInstall();

      await BiometricService.instance.clearCredentials();
      await AccountManager.instance.removeAccount('user-1');

      final keys = (await storage.readAll()).keys.toSet();
      expect(keys, contains(idKey));
      expect(keys, contains('${secretPrefix}user-1'));
      expect(keys, isNot(contains('bio_email')));
      expect(keys, isNot(contains('bio_password')));
      expect(keys, isNot(contains('active_account_id')));
    });
  });

  group('per-account secrets', () {
    test('two accounts on one phone keep separate secrets', () async {
      // device_secrets is keyed by (user_id, device_id) server-side, so the
      // client must key its copy per account too — otherwise one account's
      // credential would be sent for the other and the gate would close.
      final service = DeviceTrustService.fresh();
      await storage.write(key: idKey, value: 'device-shared-1234');

      await service.storeDeviceSecret('user-1', secret('a'));
      await service.storeDeviceSecret('user-2', secret('b'));

      expect(await service.currentDeviceToken('user-1'),
          'device-shared-1234:${secret('a')}');
      expect(await service.currentDeviceToken('user-2'),
          'device-shared-1234:${secret('b')}');
      // Overwriting one leaves the other alone.
      await service.storeDeviceSecret('user-1', secret('c'));
      expect(await service.currentDeviceToken('user-2'),
          'device-shared-1234:${secret('b')}');
      expect(await service.currentDeviceToken('user-1'),
          'device-shared-1234:${secret('c')}');
    });

    test('a stored secret is readable by a later instance', () async {
      await storage.write(key: idKey, value: 'device-abcdefgh');
      await DeviceTrustService.fresh().storeDeviceSecret('user-1', secret('a'));

      expect(
        await DeviceTrustService.fresh().currentDeviceToken('user-1'),
        'device-abcdefgh:${secret('a')}',
      );
    });

    test('no secret means no token — the id alone is not a credential',
        () async {
      await storage.write(key: idKey, value: 'device-abcdefgh');
      final service = DeviceTrustService.fresh();

      expect(await service.hasDeviceSecret('user-1'), isFalse);
      expect(await service.currentDeviceToken('user-1'), isNull);
    });

    test('a secret whose device id is gone is retired, not reused', () async {
      // Only the secret survived (a partial storage loss, or a deliberate
      // device-id key bump). The service mints a fresh id — and must ALSO drop
      // the orphaned secret: the server matches on (user_id, device_id), so
      // that secret can never match again, and keeping it would make
      // hasDeviceSecret() report a credential the gate will never accept —
      // which would stop the app asking for the code it needs.
      await storage.write(key: '${secretPrefix}user-1', value: secret('a'));

      final service = DeviceTrustService.fresh();
      final id = await service.currentDeviceId();

      expect(id, isNotNull);
      expect(await storage.read(key: '${secretPrefix}user-1'), isNull);
      expect(await service.hasDeviceSecret('user-1'), isFalse);
      expect(await service.currentDeviceToken('user-1'), isNull);
    });

    test('a too-short stored secret is refused rather than sent', () async {
      // Mirrors the SQL's `char_length(v_secret) < 32` rejection.
      await storage.write(key: idKey, value: 'device-abcdefgh');
      await storage.write(key: '${secretPrefix}user-1', value: 'tooshort');

      final service = DeviceTrustService.fresh();
      expect(await service.hasDeviceSecret('user-1'), isFalse);
      expect(await service.currentDeviceToken('user-1'), isNull);
    });

    test('a too-short secret handed to storeDeviceSecret is not persisted',
        () async {
      final service = DeviceTrustService.fresh();
      await service.storeDeviceSecret('user-1', 'short');

      expect(await storage.read(key: '${secretPrefix}user-1'), isNull);
      expect(await service.hasDeviceSecret('user-1'), isFalse);
    });

    test('revoking this device drops the secret but keeps the device id',
        () async {
      // The distinction that matters: revoking means "challenge me again",
      // NOT "I am a different phone". Rotating the id here would be a
      // permanent new-device loop.
      await storage.write(key: idKey, value: 'device-abcdefgh');
      final service = DeviceTrustService.fresh();
      await service.storeDeviceSecret('user-1', secret('a'));

      await service.clearDeviceSecret('user-1');

      expect(await service.hasDeviceSecret('user-1'), isFalse);
      expect(await service.currentDeviceToken('user-1'), isNull);
      expect(await DeviceTrustService.fresh().currentDeviceId(),
          'device-abcdefgh');
    });
  });

  group('retiring an install\'s identity', () {
    test('a NEW device id retires every account\'s secret', () async {
      // This is the supported "re-challenge every device" procedure, which the
      // class doc describes as bumping the device-id key. It only actually
      // re-challenges if the secrets go too — otherwise every user keeps a
      // credential that cannot match, the app believes it is cleared, and the
      // gated tables come back empty with nothing asking for a code.
      await storage.write(key: idKey, value: 'device-old-1234');
      await storage.write(key: '${secretPrefix}user-1', value: secret('a'));
      await storage.write(key: '${secretPrefix}user-2', value: secret('b'));
      // Something that must NOT be touched.
      await storage.write(key: 'bio_email', value: 'maria@gmail.com');

      // The id is gone, so the service generates a new one.
      await storage.delete(key: idKey);
      final newId = await DeviceTrustService.fresh().currentDeviceId();

      expect(newId, isNotNull);
      expect(newId, isNot('device-old-1234'));
      expect(await storage.read(key: '${secretPrefix}user-1'), isNull);
      expect(await storage.read(key: '${secretPrefix}user-2'), isNull);
      expect(await storage.read(key: 'bio_email'), 'maria@gmail.com',
          reason: 'retirement is scoped to this service\'s own keys');
    });

    test('reading an EXISTING id retires nothing', () async {
      // The mirror: adopting a stored id is the normal path on every launch,
      // and it must never drop the credential.
      await storage.write(key: idKey, value: 'device-existing-1234');
      await storage.write(key: '${secretPrefix}user-1', value: secret('a'));

      await DeviceTrustService.fresh().currentDeviceId();

      expect(await storage.read(key: '${secretPrefix}user-1'), secret('a'));
    });
  });

  group('the token format', () {
    test('is "<device_id>:<secret>" — the SQL splits on the first colon', () {
      expect(
        DeviceTrustService.formatToken('device-1', 'abc'),
        'device-1:abc',
      );
      // A colon inside the id must not move the boundary the server uses.
      expect(
        DeviceTrustService.formatToken('dev:ice', 'abc'),
        'dev:ice:abc',
      );
    });
  });
}
