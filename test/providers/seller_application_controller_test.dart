import 'package:flutter_test/flutter_test.dart';

import 'package:app/providers/seller_application_controller.dart';

void main() {
  group('SellerApplicationController.termsAccepted', () {
    test('starts unchecked', () {
      final ctrl = SellerApplicationController();
      expect(ctrl.termsAccepted, isFalse);
    });

    test('setting true notifies listeners (so the Step 1 checkbox repaints '
        'with a checkmark after the read-and-agree flow)', () {
      final ctrl = SellerApplicationController();
      var notified = 0;
      ctrl.addListener(() => notified++);

      ctrl.termsAccepted = true;

      expect(ctrl.termsAccepted, isTrue);
      expect(notified, 1, reason: 'the UI must be told to rebuild');
    });

    test('setting the same value does not notify again', () {
      final ctrl = SellerApplicationController()..termsAccepted = true;
      var notified = 0;
      ctrl.addListener(() => notified++);

      ctrl.termsAccepted = true;

      expect(notified, 0, reason: 'no pointless rebuild for a no-op change');
    });

    test('setting false notifies listeners (unchecking directly)', () {
      final ctrl = SellerApplicationController()..termsAccepted = true;
      var notified = 0;
      ctrl.addListener(() => notified++);

      ctrl.termsAccepted = false;

      expect(ctrl.termsAccepted, isFalse);
      expect(notified, 1);
    });
  });
}
