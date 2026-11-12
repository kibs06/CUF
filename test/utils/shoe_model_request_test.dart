import 'package:app/utils/shoe_model_request.dart';
import 'package:flutter_test/flutter_test.dart';

/// The 3D model request's rules, pinned (roadmap V2.10).
///
/// Since 2026-11-12 the seller sends no measurements — the ask is bare, and
/// the wait is the sentence that matters. What is worth a test in here is
/// the **row's four sentences** (the seller reads them to decide whether to
/// ask again), the **bare ask** (no measurements is a request, not a gap),
/// and the **modelling prefill** (old asks still carry the external length
/// the mesh is scaled to).
void main() {
  group('the status the row is drawn from', () {
    test('parses the five wire values and nothing else', () {
      expect(ShoeModelRequestStatus.parse('requested'),
          ShoeModelRequestStatus.requested);
      expect(ShoeModelRequestStatus.parse('in_progress'),
          ShoeModelRequestStatus.inProgress);
      expect(ShoeModelRequestStatus.parse('fulfilled'),
          ShoeModelRequestStatus.fulfilled);
      expect(ShoeModelRequestStatus.parse('declined'),
          ShoeModelRequestStatus.declined);
      expect(ShoeModelRequestStatus.parse('cancelled'),
          ShoeModelRequestStatus.cancelled);
      expect(ShoeModelRequestStatus.parse('archived'), isNull);
      expect(ShoeModelRequestStatus.parse(null), isNull);
    });

    test('exactly two states are open, and they are the two the index allows',
        () {
      final open = ShoeModelRequestStatus.values
          .where((s) => s.isOpen)
          .map((s) => s.wire)
          .toList();
      // The partial unique index is `status IN ('requested', 'in_progress')`.
      // If this list ever grows without the index changing, a product could
      // hold two "open" requests and the seller would see two rows.
      expect(open, ['requested', 'in_progress']);
    });
  });

  group('the action sheet row', () {
    test('a product with a live model says so, whatever the history says', () {
      // Ordering matters: a fulfilled request on a product that HAS a model is
      // already handled, and must not offer "ask again".
      for (final status in ShoeModelRequestStatus.values) {
        final row = shoeModelRequestRow(status: status, productHasModel: true);
        expect(row.action, ShoeModelRequestAction.ready);
        expect(row.label, '3D fitting ready');
      }
    });

    test('an open request says the team is on it', () {
      final row = shoeModelRequestRow(
        status: ShoeModelRequestStatus.requested,
        productHasModel: false,
      );
      expect(row.label, '3D fitting requested');
      expect(row.action, ShoeModelRequestAction.progress);
      expect(row.subtitle, ShoeModelRequestStatus.requested.sellerSentence);
    });

    test('an in-progress request is still not a "done"', () {
      final row = shoeModelRequestRow(
        status: ShoeModelRequestStatus.inProgress,
        productHasModel: false,
      );
      expect(row.action, ShoeModelRequestAction.progress);
      expect(row.label, '3D fitting requested');
    });

    test('a declined request offers the reason and a retry', () {
      final row = shoeModelRequestRow(
        status: ShoeModelRequestStatus.declined,
        productHasModel: false,
      );
      expect(row.label, '3D fitting request declined');
      expect(row.action, ShoeModelRequestAction.declined);
      expect(row.subtitle, contains('ask again'));
    });

    test('no request at all is the plain ask', () {
      final row = shoeModelRequestRow(status: null, productHasModel: false);
      expect(row.label, 'Request a 3D fitting');
      expect(row.action, ShoeModelRequestAction.ask);
      expect(row.subtitle, isNull);
    });

    test('a fulfilled request with no live model offers the ask, honestly', () {
      // Not a state the RPCs produce (fulfil refuses anything but an active
      // model) — it is what a WITHDRAWN model leaves behind, and there really
      // is nothing on the product, so "ask" is the truthful row.
      final row = shoeModelRequestRow(
        status: ShoeModelRequestStatus.fulfilled,
        productHasModel: false,
      );
      expect(row.action, ShoeModelRequestAction.ask);
      expect(row.subtitle, contains('no longer on this product'));
    });

    test('a withdrawn request is the plain ask again', () {
      final row = shoeModelRequestRow(
        status: ShoeModelRequestStatus.cancelled,
        productHasModel: false,
      );
      expect(row.action, ShoeModelRequestAction.ask);
    });
  });

  group('what an RPC answered', () {
    test('a success carries its message and the new id', () {
      final outcome = ShoeModelRequestOutcome.fromRpc({
        'success': true,
        'message': 'Request sent.',
        'request_id': 'abc',
      });
      expect(outcome.success, isTrue);
      expect(outcome.message, 'Request sent.');
      expect(outcome.requestId, 'abc');
    });

    test('a refusal is a sentence, not an exception', () {
      final outcome = ShoeModelRequestOutcome.fromRpc({
        'success': false,
        'message': 'You have already asked for a 3D model for this product.',
      });
      expect(outcome.success, isFalse);
      expect(outcome.message, contains('already asked'));
    });

    test('an empty body is NOT success', () {
      // The house rule: an unknown answer degrades to "not done, and say so".
      final outcome = ShoeModelRequestOutcome.fromRpc(null);
      expect(outcome.success, isFalse);
      expect(outcome.message, isNotEmpty);
    });

    test('a body with no success flag is not success either', () {
      expect(ShoeModelRequestOutcome.fromRpc({'message': 'ok?'}).success, isFalse);
    });
  });

  group('the team\'s side: modelling a pair that was asked for (P2)', () {
    test('⚠️ the length IS prefilled here — it is the seller\'s own external '
        'measurement this time', () {
      // The seller's form refuses to prefill the length because the only number
      // it had was the INTERNAL last (8–15 mm short). An admin answering a
      // request has the number the seller measured across the outside of the
      // pair — which is exactly what the mesh is scaled to — so retyping it
      // would only add a way to mistype it.
      final prefill = shoeModelRequestModellingPrefill(
        externalLengthMm: 272,
        measuredSizeEu: 42,
      );
      expect(prefill.externalLengthMm, '272');
      expect(prefill.authoredSizeEu, '42');
    });

    test('a request with no optional figures prefills blanks, not zeros', () {
      final prefill = shoeModelRequestModellingPrefill(
        externalLengthMm: 268,
        measuredSizeEu: null,
      );
      expect(prefill.externalLengthMm, '268');
      expect(prefill.authoredSizeEu, isEmpty);
    });

    test('a missing length prefills nothing', () {
      final prefill = shoeModelRequestModellingPrefill(
        externalLengthMm: null,
        measuredSizeEu: null,
      );
      expect(prefill.externalLengthMm, isEmpty);
      expect(prefill.authoredSizeEu, isEmpty);
    });

    test('a declaration inside the contract tolerance is not flagged', () {
      final check =
          shoeModelDeclaredLengthAgreement(measuredMm: 272, declaredMm: 270);
      expect(check.disagrees, isFalse);
      expect(check.message, isNull);

      // The boundary is inclusive, because it is the same ±kLengthToleranceMm
      // the scale check itself uses.
      expect(
        shoeModelDeclaredLengthAgreement(measuredMm: 272, declaredMm: 277)
            .disagrees,
        isFalse,
      );
    });

    test('⚠️ outside it, the note names which number is bigger AND why it matters',
        () {
      final over =
          shoeModelDeclaredLengthAgreement(measuredMm: 272, declaredMm: 292);
      expect(over.disagrees, isTrue);
      expect(over.message, contains('declared 292 mm'));
      expect(over.message, contains('measured 272 mm'));
      expect(over.message, contains('20 mm longer'));
      // The consequence is the reason this note exists: the renderer trusts the
      // declared figure, so a wrong one sizes every shoe wrong.
      expect(over.message, contains('scales every size'));

      final under =
          shoeModelDeclaredLengthAgreement(measuredMm: 272, declaredMm: 250);
      expect(under.message, contains('22 mm shorter'));
    });

    test('one missing number is not a disagreement', () {
      expect(
        shoeModelDeclaredLengthAgreement(measuredMm: null, declaredMm: 270)
            .disagrees,
        isFalse,
      );
      expect(
        shoeModelDeclaredLengthAgreement(measuredMm: 272, declaredMm: null)
            .disagrees,
        isFalse,
      );
    });

    test('live and closed is the only ending that reaches the seller', () {
      final result = shoeModelRequestModellingResult(
        modelIsLive: true,
        fulfilled: true,
        modelId: 9,
      );
      expect(result.ending, ShoeModelRequestModellingEnding.closed);
      expect(result.closed, isTrue);
      expect(result.requestStaysOpen, isFalse);
      expect(result.modelIsLive, isTrue);
      expect(result.modelId, 9);
      expect(result.message, contains('3D fitting ready'));
    });

    test('⚠️ a live model that did not close the ask is its own ending', () {
      // Not a failure — customers can render the pair — and not a success
      // either: the seller still reads "somebody is on it". Collapsing this into
      // "worked" or "failed" would misreport the state to the only person who
      // can fix it, so the message states both halves.
      final result = shoeModelRequestModellingResult(
        modelIsLive: true,
        fulfilled: false,
        modelId: 9,
      );
      expect(result.ending, ShoeModelRequestModellingEnding.liveButOpen);
      expect(result.closed, isFalse);
      expect(result.requestStaysOpen, isTrue);
      expect(result.modelIsLive, isTrue);
      expect(result.message, contains('live on the product'));
      expect(result.message, contains('could not be closed'));
    });

    test('nothing live leaves the ask waiting, and repeats the server\'s reason',
        () {
      final result = shoeModelRequestModellingResult(
        modelIsLive: false,
        fulfilled: false,
        refusal: 'The server checked the model and refused it (materials, '
            'scale), so it is saved as a draft.',
      );
      expect(result.ending, ShoeModelRequestModellingEnding.notLive);
      expect(result.modelIsLive, isFalse);
      expect(result.requestStaysOpen, isTrue);
      expect(result.message, contains('still waiting'));
      expect(result.message, contains('materials, scale'));
    });

    test('a refusal with no sentence still says the ask is waiting', () {
      final result = shoeModelRequestModellingResult(
        modelIsLive: false,
        fulfilled: false,
        refusal: '   ',
      );
      expect(result.message, contains('still waiting'));
      expect(result.message, contains('stays hidden'));
    });
  });

  group('the bare ask', () {
    test('a request with no measurements is still a request', () {
      const bare = ShoeModelRequestMeasurements();
      expect(bare.hasMeasurements, isFalse);
      expect(bare.sizeRunSentence, 'Not stated');
    });

    test('any single number counts as measurements', () {
      expect(
        const ShoeModelRequestMeasurements(externalLengthMm: 272)
            .hasMeasurements,
        isTrue,
      );
      expect(
        const ShoeModelRequestMeasurements(sizesEu: [42]).hasMeasurements,
        isTrue,
      );
    });

    test('the wait is one sentence, with both halves in it', () {
      // The ask form and the progress sheet read this one const, so the wait
      // cannot be 7 days on one surface and 9 on the other.
      expect(kShoeModelRequestTimelineMessage, contains('7 business days'));
      expect(kShoeModelRequestTimelineMessage, contains('9 business days'));
      expect(kShoeModelRequestTimelineMessage, contains('No measuring'));
    });
  });

  group('the size run', () {
    test('is canonicalised: in band, deduplicated, ascending', () {
      expect(normaliseSizeRun([42, 40, 42, 999, 0, 41]), [40, 41, 42]);
    });

    test('reads as a range when it has no gaps', () {
      const run = ShoeModelRequestMeasurements(
        externalLengthMm: 270,
        sizesEu: [40, 41, 42, 43, 44],
      );
      expect(run.sizeRunSentence, '40–44');
    });

    test('and as a list when it does', () {
      const run = ShoeModelRequestMeasurements(
        externalLengthMm: 270,
        sizesEu: [38, 39, 44],
      );
      expect(run.sizeRunSentence, '38–39, 44');
    });

    test('an empty run is "not stated", never a blank', () {
      const run = ShoeModelRequestMeasurements(externalLengthMm: 270);
      expect(run.sizeRunSentence, 'Not stated');
    });
  });
}
