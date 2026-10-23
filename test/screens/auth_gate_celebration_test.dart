import 'package:flutter_test/flutter_test.dart';
import 'package:app/screens/auth_gate.dart';

void main() {
  Map<String, dynamic> approvedSeller({
    String id = 'seller-1',
    bool? seenOnServer,
  }) {
    final profile = <String, dynamic>{
      'id': id,
      'role': 'seller',
      'seller_status': 'approved',
      'full_name': 'Janella',
    };
    final seen = seenOnServer;
    if (seen != null) profile['has_seen_approval_celebration'] = seen;
    return profile;
  }

  group('shouldShowApprovalCelebration — once-ever seller welcome', () {
    test('approved + unseen on both sources shows the celebration', () {
      expect(
        shouldShowApprovalCelebration(approvedSeller(), <String>{}),
        isTrue,
      );
    });

    test('server flag true never shows, even with an empty device cache', () {
      expect(
        shouldShowApprovalCelebration(
          approvedSeller(seenOnServer: true),
          <String>{},
        ),
        isFalse,
      );
    });

    test('device cache hit never shows (logout/login on same device)', () {
      expect(
        shouldShowApprovalCelebration(
          approvedSeller(),
          {'seller-1'},
        ),
        isFalse,
      );
    });

    test('server flag true wins over a stale unseen cache', () {
      expect(
        shouldShowApprovalCelebration(
          approvedSeller(seenOnServer: true),
          <String>{},
        ),
        isFalse,
      );
    });

    test('pending seller never shows the celebration', () {
      expect(
        shouldShowApprovalCelebration(
          {
            'id': 'seller-1',
            'role': 'seller',
            'seller_status': 'pending',
          },
          <String>{},
        ),
        isFalse,
      );
    });

    test('customer never shows the celebration', () {
      expect(
        shouldShowApprovalCelebration(
          {
            'id': 'customer-1',
            'role': 'customer',
            'seller_status': 'none',
          },
          <String>{},
        ),
        isFalse,
      );
    });

    test('missing user id never shows the celebration', () {
      expect(
        shouldShowApprovalCelebration(approvedSeller(id: ''), <String>{}),
        isFalse,
      );
    });
  });

  group('shouldRetryCelebrationPush — offline-tap convergence', () {
    test('local hit + server false retries the push', () {
      expect(
        shouldRetryCelebrationPush(
          approvedSeller(seenOnServer: false),
          {'seller-1'},
        ),
        isTrue,
      );
    });

    test('local hit + missing server key retries the push', () {
      expect(
        shouldRetryCelebrationPush(approvedSeller(), {'seller-1'}),
        isTrue,
      );
    });

    test('server true never retries (already converged)', () {
      expect(
        shouldRetryCelebrationPush(
          approvedSeller(seenOnServer: true),
          {'seller-1'},
        ),
        isFalse,
      );
    });

    test('cache miss never retries (nothing to converge)', () {
      expect(
        shouldRetryCelebrationPush(
          approvedSeller(seenOnServer: false),
          <String>{},
        ),
        isFalse,
      );
    });

    test('non-seller and empty id never retry', () {
      expect(
        shouldRetryCelebrationPush(
          {
            'id': 'customer-1',
            'role': 'customer',
            'seller_status': 'none',
          },
          {'customer-1'},
        ),
        isFalse,
      );
      expect(
        shouldRetryCelebrationPush(approvedSeller(id: ''), {''}),
        isFalse,
      );
      expect(
        shouldRetryCelebrationPush(
          {
            'id': 'seller-1',
            'role': 'seller',
            'seller_status': 'pending',
          },
          {'seller-1'},
        ),
        isFalse,
      );
    });
  });
}
