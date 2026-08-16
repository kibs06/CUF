import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/services/seller_application_draft_store.dart';

/// In-memory FlutterSecureStorage platform so the password half of the
/// draft can round-trip in a unit test without platform channels.
class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  _FakeSecureStoragePlatform() : super();

  final Map<String, String> _values = {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _values[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    return _values[key];
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    return _values.containsKey(key);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    return Map.of(_values);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _values.clear();
  }
}

SellerApplicationDraft _sampleDraft() {
  return SellerApplicationDraft(
    step: 2,
    fullName: 'Josefa Reyes',
    email: 'josefa@gmail.com',
    phone: '09171234567',
    password: 'secret-password',
    termsAccepted: true,
    isCufmaiMember: true,
    cufmaiMemberId: 'CUF-2021-0184',
    idType: 'drivers_license',
    storeName: 'Reyes Handcrafted',
    storeDescription: 'Handmade leather shoes from Carcar.',
    idDocumentPath: '/tmp/id.jpg',
    storeFrontPath: '/tmp/store-front.jpg',
    productPhotoPaths: [
      '/tmp/product-1.jpg',
      '/tmp/product-2.jpg',
      '/tmp/product-3.jpg',
      '/tmp/product-4.jpg',
      '/tmp/product-5.jpg',
    ],
    savedAt: DateTime.now(),
  );
}

void main() {
  late _FakeSecureStoragePlatform fakeSecure;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeSecure = _FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = fakeSecure;
  });

  tearDown(() {
    // Restore the default method-channel implementation for other tests.
    FlutterSecureStoragePlatform.instance =
        MethodChannelFlutterSecureStorage();
  });

  test('save → load round-trips every field including the password', () async {
    final store = SellerApplicationDraftStore.instance;
    await store.save(_sampleDraft());

    final restored = await store.load();
    expect(restored, isNotNull);
    expect(restored!.step, 2);
    expect(restored.fullName, 'Josefa Reyes');
    expect(restored.email, 'josefa@gmail.com');
    expect(restored.phone, '09171234567');
    expect(restored.password, 'secret-password');
    expect(restored.termsAccepted, isTrue);
    expect(restored.isCufmaiMember, isTrue);
    expect(restored.cufmaiMemberId, 'CUF-2021-0184');
    expect(restored.idType, 'drivers_license');
    expect(restored.storeName, 'Reyes Handcrafted');
    expect(restored.storeDescription, 'Handmade leather shoes from Carcar.');
    expect(restored.idDocumentPath, '/tmp/id.jpg');
    expect(restored.storeFrontPath, '/tmp/store-front.jpg');
    expect(restored.productPhotoPaths, [
      '/tmp/product-1.jpg',
      '/tmp/product-2.jpg',
      '/tmp/product-3.jpg',
      '/tmp/product-4.jpg',
      '/tmp/product-5.jpg',
    ]);
  });

  test('an expired draft is discarded and cleared on load', () async {
    final store = SellerApplicationDraftStore.instance;
    await store.save(_sampleDraft());

    // Backdate the saved draft beyond the 30-minute window.
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('seller_application_draft_v1')!;
    final stale = raw.replaceFirst(
      RegExp(r'"saved_at":"[^"]*"'),
      '"saved_at":"${DateTime.now().subtract(const Duration(minutes: 31)).toIso8601String()}"',
    );
    await prefs.setString('seller_application_draft_v1', stale);

    final restored = await store.load();
    expect(restored, isNull, reason: 'expired drafts must not resume');

    // The draft (and its password) should have been wiped from storage.
    final after = prefs.getString('seller_application_draft_v1');
    expect(after, isNull);
    expect(
      await fakeSecure.read(
        key: 'seller_application_draft_password_v1',
        options: const {},
      ),
      isNull,
    );
  });

  test('a draft inside the window survives a re-load', () async {
    final store = SellerApplicationDraftStore.instance;
    await store.save(_sampleDraft());

    // 5 minutes later (still inside expiry) the draft is still there.
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('seller_application_draft_v1')!;
    final fresh = raw.replaceFirst(
      RegExp(r'"saved_at":"[^"]*"'),
      '"saved_at":"${DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String()}"',
    );
    await prefs.setString('seller_application_draft_v1', fresh);

    final restored = await store.load();
    expect(restored, isNotNull);
    expect(restored!.email, 'josefa@gmail.com');
  });

  test('corrupt stored JSON loads as null without throwing', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('seller_application_draft_v1', 'not-json{');

    final restored = await SellerApplicationDraftStore.instance.load();
    expect(restored, isNull);
  });

  test('clear removes both the draft and its password', () async {
    final store = SellerApplicationDraftStore.instance;
    await store.save(_sampleDraft());

    await store.clear();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('seller_application_draft_v1'), isNull);
    expect(
      await fakeSecure.read(
        key: 'seller_application_draft_password_v1',
        options: const {},
      ),
      isNull,
    );
  });
}
