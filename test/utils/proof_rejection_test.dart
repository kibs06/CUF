import 'package:app/utils/proof_rejection.dart';
import 'package:flutter_test/flutter_test.dart';

// The seller makes a money decision on this button, so the message has to match
// what the server did. These tests pin the two real answers, because the bug was
// telling a seller "the customer can correct it" about an order that had just
// been cancelled.
void main() {
  ProofRejectionOutcome awaiting({int attemptNo = 1, int? attemptsLeft}) =>
      ProofRejectionOutcome.fromJson({
        'status': 'awaiting_payment_confirmation',
        'attempt_no': attemptNo,
        // Null is meaningful here: the server omitted it, and the wording test
        // below covers that fallback.
        'attempts_left': attemptsLeft,
      });

  ProofRejectionOutcome cancelled({int attemptNo = 3}) =>
      ProofRejectionOutcome.fromJson({
        'status': 'cancelled',
        'attempt_no': attemptNo,
        'cancelled': true,
      });

  group('fromJson', () {
    test('reads the attempt-1 shape', () {
      final outcome = awaiting(attemptNo: 1, attemptsLeft: 2);
      expect(outcome.isCancelled, isFalse);
      expect(outcome.attemptNo, 1);
      expect(outcome.attemptsLeft, 2);
    });

    test('reads the third-attempt shape', () {
      final outcome = cancelled();
      expect(outcome.isCancelled, isTrue);
      expect(outcome.attemptNo, 3);
      expect(outcome.attemptsLeft, isNull);
    });

    test('tolerates an empty answer instead of throwing', () {
      final outcome = ProofRejectionOutcome.fromJson(const {});
      expect(outcome.attemptNo, 0);
      expect(outcome.isCancelled, isFalse);
    });
  });

  group('notice', () {
    test('a cancelled order says it is cancelled, not correctable', () {
      final notice = proofRejectionNotice(cancelled());
      expect(notice.refundOwed, isTrue);
      expect(notice.text, contains('cancelled'));
      expect(notice.text, contains('refund'));
      expect(notice.text.toLowerCase(), isNot(contains('corrected proof')));
    });

    test('an open order keeps the attempt count the server sent', () {
      final notice = proofRejectionNotice(awaiting(attemptNo: 1, attemptsLeft: 2));
      expect(notice.refundOwed, isFalse);
      expect(notice.text, contains('2 attempts left'));
    });

    test('the last remaining attempt reads as one', () {
      final notice = proofRejectionNotice(awaiting(attemptNo: 2, attemptsLeft: 1));
      expect(notice.text, contains('1 attempt left'));
    });

    test('falls back to the three-attempt cap when the server omits it', () {
      final notice = proofRejectionNotice(awaiting(attemptNo: 1));
      expect(notice.text, contains('2 attempts left'));
    });

    test('never promises another attempt when there are none', () {
      final notice = proofRejectionNotice(awaiting(attemptNo: 3, attemptsLeft: 0));
      expect(notice.refundOwed, isFalse);
      expect(notice.text, contains('no attempts left'));
    });
  });
}
