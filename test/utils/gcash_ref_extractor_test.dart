import 'package:app/utils/gcash_ref_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GcashRefExtractor.extract — label-first', () {
    test('extracts from a "Ref No." line (the real GCash receipt format)', () {
      const lines = [
        'Express Send',
        'Sent to Juan Dela Cruz',
        'Ref No.  4043 676 687260',
        'Amount  ₱1,250.00',
      ];
      final result = GcashRefExtractor.extract(lines);
      expect(result.detected, isTrue);
      expect(result.reference, '4043676687260');
      expect(result.matchedLabel, isTrue);
      expect(result.displayGrouped, '4043 676 687260');
    });

    test('accepts "Reference Number:" and "ref#" labels', () {
      final a = GcashRefExtractor.extract(
          ['Reference Number: 9876543210123', 'Thanks!']);
      expect(a.reference, '9876543210123');
      final b = GcashRefExtractor.extract(['ref# 1234567890123']);
      expect(b.reference, '1234567890123');
    });

    test('checks the next line when the label line has no digits', () {
      final result = GcashRefExtractor.extract(
          ['Ref No.', '4043 676 687260']);
      expect(result.reference, '4043676687260');
      expect(result.matchedLabel, isTrue);
    });
  });

  group('GcashRefExtractor.extract — fallback', () {
    test('falls back to the best digit run when no label is present', () {
      const lines = [
        'Transaction complete',
        '4043 676 687260',
        'Please keep this receipt',
      ];
      final result = GcashRefExtractor.extract(lines);
      expect(result.reference, '4043676687260');
      expect(result.matchedLabel, isFalse);
    });

    test('does not pick amounts, dates, or times', () {
      const lines = [
        'Amount Paid ₱1,234.56',
        'Total: 1234567890',
        'Date 07/15/2026 10:30 PM',
        '4043 676 687260',
      ];
      final result = GcashRefExtractor.extract(lines);
      expect(result.reference, '4043676687260');
    });

    test('returns empty when nothing plausible is found', () {
      final result = GcashRefExtractor.extract([
        'Hello there',
        'Amount ₱100.00',
        'No numbers here',
      ]);
      expect(result.detected, isFalse);
      expect(result.reference, isNull);
    });

    test('prefers the 13-digit run over a shorter phone-like run', () {
      const lines = [
        'Contact 09171234567',
        '4043 676 687260',
      ];
      final result = GcashRefExtractor.extract(lines);
      expect(result.reference, '4043676687260');
    });

    test('returns multiple candidates when ambiguous', () {
      const lines = [
        '4043 676 687260',
        '4043676687261',
      ];
      final result = GcashRefExtractor.extract(lines);
      expect(result.detected, isTrue);
      expect(result.candidates.length, greaterThanOrEqualTo(2));
    });

    test('a lone PH mobile number is never returned as a reference', () {
      final result = GcashRefExtractor.extract(
          ['Contact 09171234567', 'Thanks for shopping!']);
      expect(result.detected, isFalse);
      expect(result.reference, isNull);
    });
  });

  group('GcashRefExtractor.formatGrouped', () {
    test('matches GCash receipt grouping (4-3-6) for 13 digits', () {
      expect(GcashRefExtractor.formatGrouped('4043676687260'),
          '4043 676 687260');
      expect(GcashRefExtractor.formatGrouped('1234567890123'),
          '1234 567 890123');
    });

    test('falls back to 4-digit chunks for other lengths', () {
      expect(GcashRefExtractor.formatGrouped('12345678'), '1234 5678');
      expect(GcashRefExtractor.formatGrouped('123456789012'),
          '1234 5678 9012');
    });
  });
}
