import 'package:flutter_test/flutter_test.dart';
import 'package:app/screens/auth_gate.dart';

void main() {
  Map<String, dynamic> customer({
    String id = 'customer-1',
    String? provider,
    DateTime? acceptedAt,
  }) {
    final profile = <String, dynamic>{
      'id': id,
      'role': 'customer',
      'seller_status': 'none',
      'full_name': 'Terry',
    };
    if (acceptedAt != null) {
      profile['terms_accepted_at'] = acceptedAt.toIso8601String();
    }
    return profile;
  }

  group('shouldShowFirstTimeTerms — once-ever social terms gate', () {
    test('social + unaccepted shows the terms', () {
      expect(
        shouldShowFirstTimeTerms(customer(), 'google', <String>{}),
        isTrue,
      );
      expect(
        shouldShowFirstTimeTerms(customer(), 'facebook', <String>{}),
        isTrue,
      );
    });

    test('email provider never shows (checkbox covered it)', () {
      expect(
        shouldShowFirstTimeTerms(customer(), 'email', <String>{}),
        isFalse,
      );
    });

    test('server timestamp set never shows, even with an empty set', () {
      expect(
        shouldShowFirstTimeTerms(
          customer(acceptedAt: DateTime.utc(2026, 10, 24)),
          'google',
          <String>{},
        ),
        isFalse,
      );
    });

    test('in-memory id never shows (agreed earlier this launch)', () {
      expect(
        shouldShowFirstTimeTerms(
          customer(),
          'google',
          {'customer-1'},
        ),
        isFalse,
      );
    });

    test('non-customer never shows', () {
      final seller = customer()
        ..['role'] = 'seller'
        ..['seller_status'] = 'approved';
      expect(
        shouldShowFirstTimeTerms(seller, 'google', <String>{}),
        isFalse,
      );
    });

    test('missing id never shows', () {
      final noId = customer(id: '')
        ..remove('id');
      expect(
        shouldShowFirstTimeTerms(noId, 'google', <String>{}),
        isFalse,
      );
    });
  });
}
