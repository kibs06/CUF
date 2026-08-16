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

  group('SellerApplicationController.store photos', () {
    test('required upload count includes the store photos and all 5 '
        'product photos', () {
      final ctrl = SellerApplicationController();
      // member: ID + selfie + store front + 5 product photos
      expect(ctrl.requiredUploadCount, 8);

      ctrl.isCufmaiMember = false;
      // + barangay proof
      expect(ctrl.requiredUploadCount, 9);
    });
  });

  group('SellerApplicationController.idType', () {
    test('starts unselected', () {
      final ctrl = SellerApplicationController();
      expect(ctrl.idType, isNull);
    });

    test('setting a value notifies listeners (so the identity step picker '
        'repaints with the chosen ID)', () {
      final ctrl = SellerApplicationController();
      var notified = 0;
      ctrl.addListener(() => notified++);

      ctrl.idType = 'philid';

      expect(ctrl.idType, 'philid');
      expect(notified, 1, reason: 'the UI must be told to rebuild');
    });

    test('setting the same value does not notify again', () {
      final ctrl = SellerApplicationController()..idType = 'passport';
      var notified = 0;
      ctrl.addListener(() => notified++);

      ctrl.idType = 'passport';

      expect(notified, 0, reason: 'no pointless rebuild for a no-op change');
    });

    test('clearing the selection notifies listeners', () {
      final ctrl = SellerApplicationController()..idType = 'prc';
      var notified = 0;
      ctrl.addListener(() => notified++);

      ctrl.idType = null;

      expect(ctrl.idType, isNull);
      expect(notified, 1);
    });
  });
}
