import 'package:app/utils/glb_validator.dart';
import 'package:app/utils/shoe_model_request.dart';
import 'package:flutter_test/flutter_test.dart';

/// The 3D model request's rules, pinned (roadmap V2.10).
///
/// The three things worth a test in here, in order of what they cost if they
/// break: the **centimetre trap** (27 instead of 270 makes every mesh from then
/// on four-tenths of life size), the **row's four sentences** (the seller reads
/// them to decide whether to ask again), and the **prefill's refusal to offer a
/// last length** (the internal measurement is 8–15 mm short of the external one
/// the request needs).
void main() {
  group('the four measurements the form reads', () {
    test('all four blank is "nothing to send", not an error', () {
      final result = _read();
      expect(result.isEmpty, isTrue);
      expect(result.isError, isFalse);
      expect(result.measurements, isNull);
    });

    test('the length alone is a complete request', () {
      // The three others are genuinely optional: nothing scales from them.
      final result = _read(length: '270');
      expect(result.isError, isFalse);
      expect(result.measurements!.externalLengthMm, 270);
      expect(result.measurements!.externalWidthMm, isNull);
      expect(result.measurements!.heelHeightMm, isNull);
      expect(result.measurements!.measuredSizeEu, isNull);
    });

    test('a width with no length is reported as the length, not the width', () {
      final result = _read(width: '105');
      expect(result.errorField, ShoeModelRequestField.externalLengthMm);
      expect(result.error, contains('cannot be started'));
    });

    test('all four in one go', () {
      final result = _read(
        length: '272',
        width: '105',
        heel: '25',
        size: '42',
      );
      final m = result.measurements!;
      expect(m.externalLengthMm, 272);
      expect(m.externalWidthMm, 105);
      expect(m.heelHeightMm, 25);
      expect(m.measuredSizeEu, 42);
    });

    test('an optional field left blank never raises an error', () {
      final result = _read(length: '270', width: '', heel: '', size: '');
      expect(result.isError, isFalse);
    });
  });

  group('the centimetre trap', () {
    // ⚠️ The most expensive mistake this feature can make. A tape measure reads
    // 27 cm, and 27 is a *plausible* number to a parser: it is below the
    // 100–400 mm band, so the naive message would be "enter a number between
    // 100 and 400", which sends the seller hunting for a different number
    // instead of a different unit.
    test('a bare centimetre figure earns a message about units', () {
      final result = _read(length: '27');
      expect(result.isError, isTrue);
      expect(result.errorField, ShoeModelRequestField.externalLengthMm);
      expect(result.error, contains('millimetres, not centimetres'));
      expect(result.error, contains('write 270, not 27'));
    });

    test('⚠️ a cm suffix is honoured now, not scolded', () {
      // This changed on 2026-09-29 with the unit toggle, and it is worth
      // knowing which way it moved: the suffix used to be refused as a mistake,
      // and it is now the *more recent* statement of the unit, so `27cm` is
      // 270 mm. The refusal is kept for a bare number in the mm box — the test
      // above — because that one really is the app guessing at a missing unit.
      final result = _read(length: '27cm');
      expect(result.isError, isFalse);
      expect(result.measurements!.externalLengthMm, 270);
    });

    test('a millimetre suffix is accepted and stripped', () {
      expect(_read(length: '270mm').measurements!.externalLengthMm, 270);
    });

    test('a width in centimetres is caught the same way', () {
      final result = _read(length: '270', width: '10');
      expect(result.errorField, ShoeModelRequestField.externalWidthMm);
      expect(result.error, contains('not centimetres'));
    });

    test('the heel is NOT given the centimetre hint — a 2 mm heel is a shoe',
        () {
      // Deliberately unlike the other two: a stack height can be small, so a
      // small number there is a measurement rather than a units mistake.
      final result = _read(length: '270', heel: '2');
      expect(result.isError, isFalse);
      expect(result.measurements!.heelHeightMm, 2);
    });
  });

  group('the bounds mirror the database', () {
    test('the length band is the mesh declaration band', () {
      expect(_read(length: '99').isError, isTrue);
      expect(_read(length: '401').isError, isTrue);
      expect(_read(length: '100').isError, isFalse);
      expect(_read(length: '400').isError, isFalse);
      // …and it is the SAME constant the validator uses, not a copy.
      expect(_read(length: '${kPlausibleLengthMinMm.toInt() + 1}').isError, isFalse);
    });

    test('a number that is not a number says so', () {
      expect(_read(length: 'about 270').error, contains('like 270'));
    });

    test('the size accepts the ways a size gets written', () {
      expect(_read(length: '270', size: 'EU 42').measurements!.measuredSizeEu, 42);
      expect(_read(length: '270', size: '42.0').measurements!.measuredSizeEu, 42.0);
      expect(_read(length: '270', size: '60').isError, isTrue);
      expect(_read(length: '270', size: 'XL').error, contains('like 42'));
    });
  });

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

  group('the prefill from a product', () {
    test('offers the heel and the size, which are the same measurement', () {
      final prefill = shoeModelRequestPrefill({
        'heel_height_mm': 25.0,
        'fit_ref_size_eu': 42.0,
      });
      expect(prefill.heelHeightMm, '25');
      expect(prefill.measuredSizeEu, '42');
    });

    test('⚠️ refuses to offer the last length, even when the product has one',
        () {
      // THE assertion in this group. `products.last_length_mm` is the INTERNAL
      // measurement; the request needs the outside of the shoe, and the guide
      // puts the gap at 8–15 mm. Prefilling it would put a plausible wrong
      // number in the one field that scales every mesh from then on.
      final prefill = shoeModelRequestPrefill({
        'last_length_mm': 278.0,
        'heel_height_mm': 25.0,
        'fit_ref_size_eu': 42.0,
      });
      expect(prefill.externalLengthMm, isEmpty);
    });

    test('an empty or missing spec prefills nothing', () {
      for (final spec in <Map<String, dynamic>?>[null, const {}]) {
        final prefill = shoeModelRequestPrefill(spec);
        expect(prefill.externalLengthMm, isEmpty);
        expect(prefill.heelHeightMm, isEmpty);
        expect(prefill.measuredSizeEu, isEmpty);
      }
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

  // ── 2026-09-29: the sheet gets friendlier, and the rules move with it ──────
  group('the unit toggle', () {
    test('centimetres are converted, not refused', () {
      // The whole point of the toggle: `27` stops being a mistake to catch and
      // becomes 270 mm, which is what the column and the renderer want.
      final result = _read(length: '27', unit: ShoeModelRequestUnit.cm);
      expect(result.isError, isFalse);
      expect(result.measurements!.externalLengthMm, 270);
    });

    test('a written unit outranks the toggle, both ways', () {
      // The toggle says what the seller is ABOUT to type; the suffix is what
      // they just typed, and the more recent statement wins.
      expect(
        _read(length: '27cm').measurements!.externalLengthMm,
        270,
        reason: 'an explicit cm suffix, while the toggle says mm',
      );
      expect(
        _read(length: '270mm', unit: ShoeModelRequestUnit.cm)
            .measurements!
            .externalLengthMm,
        270,
        reason: 'an explicit mm suffix, while the toggle says cm',
      );
    });

    test('a centimetre figure is not scolded once cm is chosen', () {
      // The old advice line exists because a bare 27 in the mm box is a units
      // mistake. In the cm box it is simply the answer.
      final result = _read(length: '27', unit: ShoeModelRequestUnit.cm);
      expect(result.error, isNull);
    });

    test('a bare 27 in mm is still the centimetres message', () {
      final result = _read(length: '27');
      expect(result.errorField, ShoeModelRequestField.externalLengthMm);
      expect(result.error, contains('millimetres, not centimetres'));
    });

    test('the band is reported in the unit the seller is typing', () {
      // A cm band stated in mm would send them hunting for the wrong number:
      // "between 100 and 400 mm" beside a box labelled cm is a contradiction.
      final result = _read(length: '2.7', unit: ShoeModelRequestUnit.cm);
      expect(result.error, contains('cm'));
      expect(result.error, contains('10'));
      expect(result.error, contains('40'));
    });
  });

  group('the height of the shoe', () {
    test('is optional', () {
      final result = _read(length: '270');
      expect(result.isError, isFalse);
      expect(result.measurements!.upperHeightMm, isNull);
    });

    test('rides along with the other numbers when given', () {
      final result = _read(length: '270', upper: '40');
      expect(result.measurements!.upperHeightMm, 40);
    });

    test('is checked against its own band, on its own field', () {
      final result = _read(length: '270', upper: '5');
      expect(result.errorField, ShoeModelRequestField.upperHeightMm);
      expect(result.isError, isTrue);
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

    test('⚠️ a run with no length is a missing length, not "nothing to send"',
        () {
      // The distinction matters: "empty" sends nothing and shows no error, so a
      // seller who picked a run and stopped would get silence about the one
      // number the request cannot be made without.
      final result = _read(sizes: {42});
      expect(result.isEmpty, isFalse);
      expect(result.errorField, ShoeModelRequestField.externalLengthMm);
    });

    test('travels with the measurements when the form is complete', () {
      final result = _read(length: '270', sizes: {44, 42});
      expect(result.measurements!.sizesEu, [42, 44]);
    });
  });

  group('the sample hints', () {
    test('every box has one, and none is empty', () {
      for (final field in ShoeModelRequestField.values) {
        expect(
          shoeModelRequestSampleHint(field).trim(),
          isNotEmpty,
          reason: '$field has no sample hint',
        );
      }
    });

    test('the length hint names the size it is about', () {
      // "about 270 mm" is a statement about a size-42 sandal, and a size 38 is
      // 27 mm shorter — so the sentence has to say which shoe it means.
      final hint = shoeModelRequestSampleHint(
        ShoeModelRequestField.externalLengthMm,
      );
      expect(hint, contains('42'));
      expect(hint, contains('270'));
    });
  });
}

/// One read of the form, with everything blank unless a test fills it in.
ShoeModelRequestFormResult _read({
  String length = '',
  String width = '',
  String heel = '',
  String upper = '',
  String size = '',
  ShoeModelRequestUnit unit = ShoeModelRequestUnit.mm,
  Set<double> sizes = const {},
}) =>
    ShoeModelRequestFormResult.fromFields(
      externalLengthMm: length,
      externalWidthMm: width,
      heelHeightMm: heel,
      upperHeightMm: upper,
      measuredSizeEu: size,
      unit: unit,
      sizesEu: sizes.toList(),
    );
