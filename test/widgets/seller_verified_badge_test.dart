import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/constants/app_constants.dart';
import 'package:app/utils/seller_verification.dart';
import 'package:app/widgets/seller/seller_header_badges.dart';

/// **The seller profile's own trust state.**
///
/// The approval trigger writes `profiles.seller_verified_at`; the profile reads
/// the docs verdict into `_bizStatus` and must then show the Verified Seller
/// badge and drop the Business Verification row. Both decisions live in
/// `seller_verification.dart` so this screen and its test cannot drift; the
/// header widget is pumped for the rendering half.
///
/// Every assertion fails if its rule is removed:
///  • always showing the badge → the pending/rejected/customer cases fail;
///  • always hiding the verification row → the none/pending/rejected cases fail;
///  • never hiding it → the verified case fails.
void main() {
  group('the trust-flag rules', () {
    test('the header badge needs a seller AND a verified verdict', () {
      expect(
        showsVerifiedSellerBadge(
          role: AppConstants.roleSeller,
          businessStatus: AppConstants.bizStatusVerified,
        ),
        isTrue,
      );

      for (final status in [
        AppConstants.bizStatusNone,
        AppConstants.bizStatusPending,
        AppConstants.bizStatusRejected,
      ]) {
        expect(
          showsVerifiedSellerBadge(
            role: AppConstants.roleSeller,
            businessStatus: status,
          ),
          isFalse,
          reason: 'a seller whose docs are $status must not look verified',
        );
      }

      // A leftover flag on a non-seller account is not a seller badge.
      expect(
        showsVerifiedSellerBadge(
          role: AppConstants.roleCustomer,
          businessStatus: AppConstants.bizStatusVerified,
        ),
        isFalse,
      );
      expect(
        showsVerifiedSellerBadge(
          role: AppConstants.roleAdmin,
          businessStatus: AppConstants.bizStatusVerified,
        ),
        isFalse,
      );
    });

    test('the cached trust state is re-read after the TTL, not before', () {
      final fetchedAt = DateTime(2026, 1, 1, 12);

      expect(sellerTrustIsStale(null, fetchedAt), isFalse,
          reason: 'the first load is already in flight');
      expect(
        sellerTrustIsStale(
          fetchedAt,
          fetchedAt.add(const Duration(seconds: 29)),
        ),
        isFalse,
        reason: 'a quick tab bounce must not re-query',
      );
      expect(
        sellerTrustIsStale(
          fetchedAt,
          fetchedAt.add(const Duration(seconds: 31)),
        ),
        isTrue,
        reason: 'an admin approval on another device must eventually land',
      );
    });

    test('only a verified seller loses the Business Verification row', () {
      expect(
        showsBusinessVerificationRow(AppConstants.bizStatusVerified),
        isFalse,
        reason: 'there is nothing left to submit once verified',
      );
      for (final status in [
        AppConstants.bizStatusNone,
        AppConstants.bizStatusPending,
        AppConstants.bizStatusRejected,
      ]) {
        expect(
          showsBusinessVerificationRow(status),
          isTrue,
          reason: 'a $status seller still has work to do in that row',
        );
      }
    });
  });

  group('the seller header badges', () {
    testWidgets('render Verified Seller once the docs are verified',
        (tester) async {
      await _pumpHeader(
        tester,
        role: AppConstants.roleSeller,
        status: AppConstants.bizStatusVerified,
      );

      expect(find.text('Seller'), findsOneWidget);
      expect(find.text('Verified Seller'), findsOneWidget);
    });

    testWidgets('keep the role badge but not the trust badge while review is '
        'outstanding', (tester) async {
      for (final status in [
        AppConstants.bizStatusNone,
        AppConstants.bizStatusPending,
        AppConstants.bizStatusRejected,
      ]) {
        await _pumpHeader(
          tester,
          role: AppConstants.roleSeller,
          status: status,
        );

        expect(find.text('Seller'), findsOneWidget);
        expect(find.text('Verified Seller'), findsNothing,
            reason: 'a $status seller is not a verified seller');
      }
    });

    testWidgets('never put the seller badge on a customer', (tester) async {
      await _pumpHeader(
        tester,
        role: AppConstants.roleCustomer,
        status: AppConstants.bizStatusVerified,
      );

      expect(find.text('Customer'), findsOneWidget);
      expect(find.text('Verified Seller'), findsNothing);
    });
  });
}

Future<void> _pumpHeader(
  WidgetTester tester, {
  required String role,
  required String status,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SellerHeaderBadges(
            role: role,
            roleLabel: role == AppConstants.roleSeller ? 'Seller' : 'Customer',
            roleColor: AppConstants.primary,
            businessStatus: status,
          ),
        ),
      ),
    ),
  );
}
