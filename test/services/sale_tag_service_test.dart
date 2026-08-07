import 'package:app/services/sale_tag_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SaleTagService (local SharedPreferences persistence)', () {
    test('empty user has no reveals', () async {
      expect(await SaleTagService.instance.loadRevealedIds('u1'), isEmpty);
    });

    test('saveRevealed persists per-user and is idempotent', () async {
      final svc = SaleTagService.instance;
      await svc.saveRevealed('u1', 'p1');
      await svc.saveRevealed('u1', 'p2');
      // Idempotent — re-saving the same product must not duplicate.
      await svc.saveRevealed('u1', 'p1');

      expect(await svc.loadRevealedIds('u1'), {'p1', 'p2'});
      // A different user never sees another account's reveals.
      expect(await svc.loadRevealedIds('u2'), isEmpty);
    });

    test('survives an app restart (new instance reads the same store)', () async {
      final svc = SaleTagService.instance;
      await svc.saveRevealed('u1', 'p1');
      await svc.saveRevealed('u1', 'p2');

      // Fresh prefs instance simulates a cold start.
      SharedPreferences.setMockInitialValues({});
      expect(await svc.loadRevealedIds('u1'), isEmpty);
      SharedPreferences.setMockInitialValues(
        {'sale_tag_reveals_u1': '["p1","p2"]'},
      );
      expect(await svc.loadRevealedIds('u1'), {'p1', 'p2'});
    });
  });
}
