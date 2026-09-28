import 'package:app/services/shoe_model_server_validator.dart';
import 'package:flutter_test/flutter_test.dart';

/// `validate-shoe-model` (roadmap V2.4) is the only caller the database lets
/// write `product_models.status='active'`, so its answers decide whether a
/// model a seller paid to have made is visible at all. These tests pin the
/// three-way distinction the publish path depends on — validated / refused /
/// no verdict — because collapsing any two of them either publishes something
/// unjudged or hides a working model behind a network blip.
///
/// The parsing is pure ([shoeModelServerVerdictFrom]), which is why the awkward
/// shapes can be tested at all: a 200, the 422 that *is* a refusal, the
/// function's `{error: …}` objects, and a body that is not JSON.
void main() {
  group('a published verdict', () {
    test('200 with ok:true is validated, and carries the reviewer rows', () {
      final verdict = shoeModelServerVerdictFrom(
        statusCode: 200,
        body: {
          'ok': true,
          'action': 'activated',
          'status': 'active',
          'notChecked': ['toe vs heel direction', 'on-device frame rate'],
          'report': {
            'passed': true,
            'checks': [
              {'name': 'materials', 'status': 'pass', 'detail': 'upper, sole'},
            ],
          },
        },
      );

      expect(verdict.outcome, ShoeModelServerOutcome.validated);
      expect(verdict.passed, isTrue);
      expect(verdict.refused, isFalse);
      expect(verdict.status, 'active');
      expect(verdict.sellerMessage, isNull,
          reason: 'nothing to tell the seller when it worked');
      expect(verdict.notChecked, hasLength(2));
    });

    test('a held-back answer stays a draft', () {
      final verdict = shoeModelServerVerdictFrom(
        statusCode: 200,
        body: {'ok': true, 'status': 'draft', 'report': {'passed': true}},
      );

      expect(verdict.outcome, ShoeModelServerOutcome.validated);
      expect(verdict.status, 'draft');
    });

    test('a 200 without ok:true is not treated as a pass', () {
      // A gateway that answers 200 with an HTML-ish object must never be read
      // as approval: "not judged" is the safe reading, and it is also true.
      final verdict = shoeModelServerVerdictFrom(
        statusCode: 200,
        body: {'message': 'welcome to the edge runtime'},
      );

      expect(verdict.outcome, ShoeModelServerOutcome.undetermined);
      expect(verdict.status, 'draft');
      expect(verdict.detail, 'welcome to the edge runtime');
    });
  });

  group('a refusal', () {
    test('422 names the failing rows', () {
      final verdict = shoeModelServerVerdictFrom(
        statusCode: 422,
        body: {
          'ok': false,
          'action': 'rejected',
          'status': 'rejected',
          'report': {
            'passed': false,
            'checks': [
              {'name': 'file size', 'status': 'pass', 'detail': '1.2 MiB'},
              {'name': 'materials', 'status': 'fail', 'detail': 'no materials'},
              {'name': 'scale', 'status': 'fail', 'detail': 'off by 40 mm'},
            ],
          },
        },
      );

      expect(verdict.outcome, ShoeModelServerOutcome.rejected);
      expect(verdict.refused, isTrue);
      expect(verdict.status, 'rejected');
      expect(verdict.failedChecks, ['materials', 'scale']);
      expect(verdict.sellerMessage, contains('materials, scale'));
    });

    test('the server-only sha256 refusal is named, not guessed at', () {
      // The one refusal that has no failing contract row: the bytes in the
      // bucket no longer hash to the digest the row records. The contract
      // report passes, so the reason lives in `integrity` — and a seller
      // reading "it passed my validator" needs to see this one.
      final verdict = shoeModelServerVerdictFrom(
        statusCode: 422,
        body: {
          'ok': false,
          'status': 'rejected',
          'report': {'passed': true},
          'integrity': {
            'sha256': {
              'declared': List.filled(64, 'a').join(),
              'measured': List.filled(64, 'b').join(),
              'matches': false,
            },
          },
        },
      );

      expect(verdict.refused, isTrue);
      expect(verdict.failedChecks.single, contains('sha256'));
      expect(verdict.sellerMessage, contains('sha256'));
    });

    test('422 is a refusal even when its body does not parse', () {
      // The status is the function's own refusal signal — no other layer in
      // front of it returns 422 — so a body lost in transit must still count
      // as a judgement rather than leave the model silently in drafts.
      final withoutBody = shoeModelServerVerdictFrom(statusCode: 422, body: null);
      expect(withoutBody.outcome, ShoeModelServerOutcome.rejected);
      expect(withoutBody.status, 'rejected');
      expect(withoutBody.failedChecks, isEmpty);
      expect(withoutBody.sellerMessage, contains('refused the model'));
    });

    test('a JSON body that arrives as a string is decoded, not ignored', () {
      final verdict = shoeModelServerVerdictFrom(
        statusCode: 422,
        body: '{"ok":false,"status":"rejected","report":{"checks":'
            '[{"name":"materials","status":"fail"}]}}',
      );

      expect(verdict.refused, isTrue);
      expect(verdict.failedChecks, ['materials']);
    });

    test('a bare check list is read as well as a wrapped one', () {
      expect(
        shoeModelServerFailedChecks([
          {'name': 'origin', 'status': 'fail'},
          {'name': 'units', 'status': 'warning'},
        ]),
        ['origin'],
      );
      expect(shoeModelServerFailedChecks(null), isEmpty);
      expect(shoeModelServerFailedChecks('not a report'), isEmpty);
    });
  });

  group('no verdict', () {
    test('a 429 keeps the function\'s own sentence', () {
      final verdict = shoeModelServerVerdictFrom(
        statusCode: 429,
        body: {'error': 'rate limited', 'message': 'Too many requests'},
      );

      expect(verdict.outcome, ShoeModelServerOutcome.undetermined);
      expect(verdict.status, 'draft');
      expect(verdict.passed, isFalse);
      expect(verdict.refused, isFalse,
          reason: 'a 429 is not a judgement about the model');
      expect(verdict.detail, 'rate limited');
      expect(verdict.sellerMessage, contains('rate limited'));
    });

    test('a non-object body falls back to the status code', () {
      final verdict = shoeModelServerVerdictFrom(
        statusCode: 502,
        body: '<html>bad gateway</html>',
      );

      expect(verdict.outcome, ShoeModelServerOutcome.undetermined);
      expect(verdict.detail, 'HTTP 502');
    });

    test('403 (not your store) is a non-judgement, not a refusal', () {
      final verdict = shoeModelServerVerdictFrom(
        statusCode: 403,
        body: {'error': 'That model belongs to another store.'},
      );

      expect(verdict.outcome, ShoeModelServerOutcome.undetermined);
      expect(verdict.detail, contains('another store'));
    });

    test('the const constructor is the shape the service degrades to', () {
      const verdict = ShoeModelServerVerdict.undetermined('could not reach the server');

      expect(verdict.status, 'draft');
      expect(verdict.failedChecks, isEmpty);
      expect(verdict.notChecked, isEmpty);
      expect(verdict.sellerMessage, contains('Publish the product again to retry'));
    });
  });

  test('the function name lives in one place', () {
    expect(kValidateShoeModelFunction, 'validate-shoe-model');
  });
}
