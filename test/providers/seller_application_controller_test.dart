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
    test('required upload count includes the identity, business, store and '
        'product documents', () {
      final ctrl = SellerApplicationController();
      // member: ID + selfie + DTI + BIR + permit + store front + 5 photos
      expect(ctrl.requiredUploadCount, 11);

      ctrl.isCufmaiMember = false;
      // + barangay proof
      expect(ctrl.requiredUploadCount, 12);
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

  // ANQUI item 16, Part A. The seller flow creates its account at final
  // submit, so with "Confirm email" ON the code has to be cleared BEFORE the
  // private-bucket uploads (their RLS needs a session) and before the profile
  // write. These assert the ordering rule; the end-to-end effects (a pending
  // application, never an approved one) are covered by the flow that calls
  // it plus the pgTAP suite.
  group('email-verification pre-flight', () {
    test('no verification step when the account already has a session', () {
      expect(
        SellerApplicationController.needsVerificationStep(
          emailVerificationRequired: false,
        ),
        isFalse,
      );
    });

    test('a verification step is required when signUp returned no session', () {
      expect(
        SellerApplicationController.needsVerificationStep(
          emailVerificationRequired: true,
        ),
        isTrue,
      );
    });

    test('a verified code + a live session lets the application continue', () {
      expect(
        SellerApplicationController.canProceedAfterVerification(
          verified: true,
          hasSession: true,
        ),
        isTrue,
      );
    });

    test('backing out of verification does NOT half-complete the application',
        () {
      // The screen popped without a code, so there is nothing to upload as.
      expect(
        SellerApplicationController.canProceedAfterVerification(
          verified: false,
          hasSession: false,
        ),
        isFalse,
      );
      expect(
        SellerApplicationController.canProceedAfterVerification(
          verified: null,
          hasSession: false,
        ),
        isFalse,
      );
    });

    test('a claimed verification without a session still blocks', () {
      // Defensive: if the caller reports success but no session materialised,
      // the uploads that follow would be a permission error — and writing the
      // profile from signup metadata would downgrade a seller application to
      // a plain customer row.
      expect(
        SellerApplicationController.canProceedAfterVerification(
          verified: true,
          hasSession: false,
        ),
        isFalse,
      );
    });
  });
}
