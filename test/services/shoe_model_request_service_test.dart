import 'package:app/services/shoe_model_request_service.dart';
import 'package:app/utils/shoe_model_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The request service, exercised without a socket (roadmap V2.10).
///
/// The seam (`ShoeModelRequestDataSource`) is the whole reason these tests can
/// exist: the rules that matter live in the database's RPCs, and what is left
/// here is the app's half — which is exactly the half that decides whether a
/// failure reaches a seller as a sentence or as a crash.
void main() {
  group('filing a request', () {
    test('an out-of-band length never reaches the network', () async {
      final data = _FakeData();
      final service = ShoeModelRequestService(data);

      final outcome = await service.request(
        productId: 'p1',
        measurements: const ShoeModelRequestMeasurements(externalLengthMm: 40),
      );

      expect(outcome.success, isFalse);
      expect(outcome.message, contains('100 and 400'));
      // The point: the same guard as the form, this side of the wire, so a
      // caller that skipped the form cannot put a 40 mm shoe in the queue.
      expect(data.calls, 0);
    });

    test('a valid request is sent, parameters and all', () async {
      final data = _FakeData()
        ..nextResult = {
          'success': true,
          'message': 'Request sent.',
          'request_id': 'r-1',
        };
      final service = ShoeModelRequestService(data);

      final outcome = await service.request(
        productId: 'p1',
        measurements: const ShoeModelRequestMeasurements(
          externalLengthMm: 272,
          externalWidthMm: 105,
          measuredSizeEu: 42,
        ),
        note: 'Samples with the team.',
      );

      expect(outcome.success, isTrue);
      expect(outcome.requestId, 'r-1');
      expect(data.calls, 1);
      expect(data.lastProductId, 'p1');
      expect(data.lastMeasurements!.externalLengthMm, 272);
      expect(data.lastNote, 'Samples with the team.');
    });

    test('a refused ask comes back as the RPC''s own sentence', () async {
      final data = _FakeData()
        ..nextResult = {
          'success': false,
          'message': 'You have already asked for a 3D model for this product.',
        };
      final service = ShoeModelRequestService(data);

      final outcome = await service.request(
        productId: 'p1',
        measurements: const ShoeModelRequestMeasurements(externalLengthMm: 272),
      );

      expect(outcome.success, isFalse);
      expect(outcome.message, contains('already asked'));
    });

    test('a dropped connection is a sentence, never a throw', () async {
      final data = _FakeData()..throwOnRequest = true;
      final service = ShoeModelRequestService(data);

      final outcome = await service.request(
        productId: 'p1',
        measurements: const ShoeModelRequestMeasurements(externalLengthMm: 272),
      );

      expect(outcome.success, isFalse);
      expect(outcome.message, contains('try again'));
    });

    test('the ownership refusal (42501) keeps its own message', () async {
      final data = _FakeData()..rejectOnRequest = true;
      final service = ShoeModelRequestService(data);

      final outcome = await service.request(
        productId: 'p1',
        measurements: const ShoeModelRequestMeasurements(externalLengthMm: 272),
      );

      expect(outcome.success, isFalse);
      expect(outcome.message, contains('your own products'));
    });

    test('an app ahead of the schema does NOT blame the connection', () async {
      // ⚠️ The 2026-09-29 report. Filling "Height of the shoe" or "Sizes you
      // make this shoe in" sends arguments the live database does not have
      // until `20260929120000` is applied, and PostgREST refuses the whole call
      // with PGRST202. The old copy sent the seller to check their signal for
      // something no amount of signal could fix, so the sentence names the two
      // boxes and the one fix that works.
      final data = _FakeData()..staleSchemaOnRequest = true;
      final service = ShoeModelRequestService(data);

      final outcome = await service.request(
        productId: 'p1',
        measurements: const ShoeModelRequestMeasurements(
          externalLengthMm: 272,
          upperHeightMm: 40,
        ),
      );

      expect(outcome.success, isFalse);
      expect(outcome.message, isNot(contains('connection')));
      expect(outcome.message, contains('shoe height'));
      expect(outcome.message, contains('sizes you stock'));
      expect(outcome.message, contains('Clear those two'));
    });

    test('a stale schema with no new fields does not send them hunting', () async {
      // Same failure, different payload: nothing the seller typed is at fault,
      // so the copy must not tell them to clear a box they never filled.
      final data = _FakeData()..staleSchemaOnRequest = true;
      final service = ShoeModelRequestService(data);

      final outcome = await service.request(
        productId: 'p1',
        measurements: const ShoeModelRequestMeasurements(externalLengthMm: 272),
      );

      expect(outcome.success, isFalse);
      expect(outcome.message, isNot(contains('connection')));
      expect(outcome.message, isNot(contains('Clear those two')));
      expect(outcome.message, contains('try again later'));
    });
  });

  group('telling a missing function apart from a dropped socket', () {
    test('the current shape (the code) counts', () {
      expect(
        isMissingRpcError(
          PostgrestException(
            message: 'Could not find the function public.request_shoe_model',
            code: 'PGRST202',
          ),
        ),
        isTrue,
      );
    });

    test('the older shape (only the sentence) counts too', () {
      expect(
        isMissingRpcError(
          PostgrestException(
            message:
                'Could not find the function public.request_shoe_model(p_upper_height_mm) in the schema cache',
          ),
        ),
        isTrue,
      );
    });

    test('a real network failure does not', () {
      expect(isMissingRpcError(Exception('SocketException')), isFalse);
      expect(
        isMissingRpcError(
          PostgrestException(message: 'FetchError: connection closed'),
        ),
        isFalse,
      );
      // And a refusal that IS about the schema (400 from the RPC's own bands)
      // stays a sentence from the database rather than becoming this one.
      expect(
        isMissingRpcError(
          PostgrestException(message: 'value too long', code: '22001'),
        ),
        isFalse,
      );
    });
  });

  group('what the sheet needs to know about a product', () {
    test('one call answers both halves', () async {
      final data = _FakeData()
        ..latest = _row(status: 'in_progress')
        ..hasLiveModel = false;
      final service = ShoeModelRequestService(data);

      final availability = await service.availability('p1');

      expect(availability.request!.status, ShoeModelRequestStatus.inProgress);
      expect(availability.hasLiveModel, isFalse);
      expect(availability.row.label, '3D fitting requested');
      expect(service.readCount, 1);
    });

    test('a live model wins over an old fulfilled request', () async {
      final data = _FakeData()
        ..latest = _row(status: 'fulfilled')
        ..hasLiveModel = true;
      final service = ShoeModelRequestService(data);

      final availability = await service.availability('p1');

      expect(availability.row.label, '3D fitting ready');
    });

    test('a failed read shows the un-asked row rather than an error', () async {
      final data = _FakeData()..throwOnRead = true;
      final service = ShoeModelRequestService(data);

      final availability = await service.availability('p1');

      expect(availability.request, isNull);
      expect(availability.hasLiveModel, isFalse);
      expect(availability.row.action, ShoeModelRequestAction.ask);
    });
  });

  group('the reads that must never take a screen down', () {
    test('a failing queue is an empty queue', () async {
      final service = ShoeModelRequestService(_FakeData()..throwOnRead = true);
      expect(await service.queue(), isEmpty);
      expect(await service.forStore('s1'), isEmpty);
      expect(await service.modelsForProduct('p1'), isEmpty);
      expect(await service.latestForProduct('p1'), isNull);
    });

    test('a queue comes back in the order the data source gave it', () async {
      final data = _FakeData()
        ..queueRows = [_row(id: 'r-2', status: 'requested'), _row(id: 'r-1')];
      final service = ShoeModelRequestService(data);
      final rows = await service.queue();
      expect(rows.map((r) => r.id), ['r-2', 'r-1']);
    });
  });

  group('the admin transitions', () {
    test('each one returns the RPC message', () async {
      final data = _FakeData()..nextResult = {'success': true, 'message': 'Done.'};
      final service = ShoeModelRequestService(data);

      expect((await service.claim('r-1')).message, 'Done.');
      expect((await service.decline(requestId: 'r-1', reason: 'no pair')).message,
          'Done.');
      expect(
        (await service.fulfil(requestId: 'r-1', modelId: 7)).message,
        'Done.',
      );
      expect((await service.cancel('r-1')).message, 'Done.');
      expect(data.lastModelId, 7);
    });

    test('a refusal keeps the reason the RPC gave', () async {
      final data = _FakeData()
        ..nextResult = {
          'success': false,
          'message':
              'That model is still a draft — publish it through the validator first, then close this request.',
        };
      final service = ShoeModelRequestService(data);

      final outcome = await service.fulfil(requestId: 'r-1', modelId: 7);
      expect(outcome.success, isFalse);
      expect(outcome.message, contains('still a draft'));
    });
  });

  group('reading a row', () {
    test('parses the columns the UI shows, including the bigint model id', () {
      final record = ShoeModelRequestRecord.fromRow({
        'id': 'r-1',
        'product_id': 'p-1',
        'store_id': 's-1',
        'status': 'fulfilled',
        'external_length_mm': 272,
        'external_width_mm': null,
        'measured_size_eu': 42,
        'model_id': 12,
        'note': 'samples',
        'admin_note': 'done on the bench',
        'assigned_to': 'u-1',
        'created_at': '2026-09-28T09:00:00Z',
        'reviewed_at': '2026-09-28T10:00:00Z',
        'products': {'name': 'Chelsea Boot'},
        'stores': {'name': 'Carcar Leather'},
      });

      expect(record.status, ShoeModelRequestStatus.fulfilled);
      expect(record.isOpen, isFalse);
      expect(record.externalLengthMm, 272);
      expect(record.externalWidthMm, isNull);
      expect(record.measuredSizeEu, 42);
      // BIGINT in the database: an int here, and it survives a JSON string too.
      expect(record.modelId, 12);
      expect(record.adminNote, 'done on the bench');
      expect(record.productName, 'Chelsea Boot');
      expect(record.storeName, 'Carcar Leather');
      expect(record.createdAt!.isUtc, isTrue);
    });

    test('an unknown status reads as null rather than as a wrong state', () {
      final record = ShoeModelRequestRecord.fromRow({
        'id': 'r-1',
        'product_id': 'p-1',
        'store_id': 's-1',
        'status': 'archived',
      });
      expect(record.status, isNull);
      // …and the raw value is kept, so a log or a debug screen can show it.
      expect(record.statusWire, 'archived');
      expect(record.isOpen, isFalse);
    });

    test('a row with no embeds reads without them', () {
      final record = ShoeModelRequestRecord.fromRow({
        'id': 'r-1',
        'product_id': 'p-1',
        'store_id': 's-1',
        'status': 'requested',
      });
      expect(record.productName, isNull);
      expect(record.storeName, isNull);
      expect(record.status, ShoeModelRequestStatus.requested);
      expect(record.isOpen, isTrue);
    });
  });
}

ShoeModelRequestRecord _row({
  String id = 'r-1',
  String status = 'requested',
  String productId = 'p-1',
}) =>
    ShoeModelRequestRecord(
      id: id,
      productId: productId,
      storeId: 's-1',
      statusWire: status,
      status: ShoeModelRequestStatus.parse(status),
    );

class _FakeData implements ShoeModelRequestDataSource {
  int calls = 0;
  Object? nextResult;
  bool throwOnRequest = false;
  bool rejectOnRequest = false;
  bool staleSchemaOnRequest = false;
  bool throwOnRead = false;

  ShoeModelRequestRecord? latest;
  bool hasLiveModel = false;
  List<ShoeModelRequestRecord> queueRows = const [];

  String? lastProductId;
  ShoeModelRequestMeasurements? lastMeasurements;
  String? lastNote;
  int? lastModelId;

  @override
  Future<ShoeModelRequestRecord?> latestForProduct(String productId) async {
    if (throwOnRead) throw Exception('no table');
    return latest;
  }

  @override
  Future<bool> productHasLiveModel(String productId) async {
    if (throwOnRead) throw Exception('no table');
    return hasLiveModel;
  }

  @override
  Future<List<Map<String, dynamic>>> modelsForProduct(String productId) async {
    if (throwOnRead) throw Exception('no table');
    return const [];
  }

  @override
  Future<List<ShoeModelRequestRecord>> forStore(String storeId) async {
    if (throwOnRead) throw Exception('no table');
    return queueRows;
  }

  @override
  Future<List<ShoeModelRequestRecord>> queue() async {
    if (throwOnRead) throw Exception('no table');
    return queueRows;
  }

  @override
  Future<Object?> request({
    required String productId,
    required ShoeModelRequestMeasurements measurements,
    String? note,
  }) async {
    calls++;
    lastProductId = productId;
    lastMeasurements = measurements;
    lastNote = note;
    if (rejectOnRequest) {
      throw const ShoeModelRequestRejected(
          'You can only ask for a model on your own products.');
    }
    if (staleSchemaOnRequest) throw const ShoeModelRequestSchemaStale();
    if (throwOnRequest) throw Exception('offline');
    return nextResult;
  }

  @override
  Future<Object?> cancel(String requestId) async => nextResult;

  @override
  Future<Object?> claim(String requestId) async => nextResult;

  @override
  Future<Object?> fulfil({
    required String requestId,
    required int modelId,
    String? note,
  }) async {
    lastModelId = modelId;
    return nextResult;
  }

  @override
  Future<Object?> decline({required String requestId, String? reason}) async =>
      nextResult;
}
