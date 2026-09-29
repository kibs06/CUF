import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/glb_validator.dart';
import '../utils/shoe_model_request.dart';

/// A row of `public.shoe_model_requests`, plus the two names the admin queue
/// shows beside it.
///
/// A typed record rather than the `Map<String, dynamic>` the older screens pass
/// around, because this row is read in four places (the seller's sheet, the
/// seller's queue, the admin's queue, and the tests) and the four fields that
/// matter — `status`, `productId`, `modelId`, `adminNote` — are exactly the
/// ones a typo'd string key would turn into a null that reads as "no request".
class ShoeModelRequestRecord {
  final String id;
  final String productId;
  final String storeId;
  final ShoeModelRequestStatus? status;

  /// The raw wire value, kept beside the parsed one so a status this build does
  /// not know is still visible in a log rather than only appearing as null.
  final String statusWire;

  final double? externalLengthMm;
  final double? externalWidthMm;
  final double? heelHeightMm;

  /// The pair's overall height, sole to its highest point (2026-09-29).
  final double? upperHeightMm;

  final double? measuredSizeEu;

  /// Every EU size the shoe is made in, ascending. Empty means the seller did
  /// not say — which is a complete answer, not a gap to fill in.
  final List<double> sizesEu;
  final String? note;
  final String? adminNote;
  final String? assignedTo;

  /// `product_models.id` — BIGINT in the database, so an int here.
  final int? modelId;

  final DateTime? createdAt;
  final DateTime? reviewedAt;

  /// Denormalised for the admin queue. Null when the embed was not requested.
  final String? productName;
  final String? storeName;

  const ShoeModelRequestRecord({
    required this.id,
    required this.productId,
    required this.storeId,
    required this.statusWire,
    this.status,
    this.externalLengthMm,
    this.externalWidthMm,
    this.heelHeightMm,
    this.upperHeightMm,
    this.measuredSizeEu,
    this.sizesEu = const [],
    this.note,
    this.adminNote,
    this.assignedTo,
    this.modelId,
    this.createdAt,
    this.reviewedAt,
    this.productName,
    this.storeName,
  });

  /// Whether the ask is still occupying the product's single open slot.
  bool get isOpen => status?.isOpen ?? false;

  /// The size run as a sentence — `40–44` — for the surfaces that show it. Built
  /// from the same rule the form and the sheets use, so the seller's "40–44" and
  /// the team's are the same string rather than two renderings that agree today.
  String get sizeRunSentence => ShoeModelRequestMeasurements(
        externalLengthMm: 0,
        sizesEu: sizesEu,
      ).sizeRunSentence;

  static ShoeModelRequestRecord fromRow(Map<String, dynamic> row) {
    final product = row['products'];
    final store = row['stores'];
    return ShoeModelRequestRecord(
      id: row['id'].toString(),
      productId: row['product_id'].toString(),
      storeId: row['store_id'].toString(),
      statusWire: row['status']?.toString() ?? '',
      status: ShoeModelRequestStatus.parse(row['status']),
      externalLengthMm: _double(row['external_length_mm']),
      externalWidthMm: _double(row['external_width_mm']),
      heelHeightMm: _double(row['heel_height_mm']),
      upperHeightMm: _double(row['upper_height_mm']),
      measuredSizeEu: _double(row['measured_size_eu']),
      sizesEu: _doubleList(row['sizes_eu']),
      note: row['note']?.toString(),
      adminNote: row['admin_note']?.toString(),
      assignedTo: row['assigned_to']?.toString(),
      modelId: _int(row['model_id']),
      createdAt: _date(row['created_at']),
      reviewedAt: _date(row['reviewed_at']),
      productName: product is Map ? product['name']?.toString() : null,
      storeName: store is Map ? store['name']?.toString() : null,
    );
  }

  static double? _double(Object? value) => value == null
      ? null
      : (value is num ? value.toDouble() : double.tryParse(value.toString()));

  static int? _int(Object? value) => value == null
      ? null
      : (value is num ? value.toInt() : int.tryParse(value.toString()));

  /// A `numeric[]` column, which PostgREST hands back as a JSON array. Anything
  /// unparseable is dropped rather than turned into a 0 — a size of `0` would
  /// render as a real size in the queue, where a missing one just reads absent.
  /// Canonicalised on the way in, so the sentence the two surfaces print has one
  /// implementation rather than one per screen.
  static List<double> _doubleList(Object? value) {
    if (value is! List) return const [];
    return normaliseSizeRun(
      value.map(_double).whereType<double>(),
    );
  }

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString());
}

/// The seam every test fakes: every call the feature makes to the database, and
/// nothing else.
///
/// It exists for the reason `shoe_model_upload_service.dart`'s seam does — the
/// rules that matter (what a seller may ask for, who may close an ask) live in
/// the database's RPCs, and a screen test should be able to assert what the
/// seller SEES without a socket, a server or a row.
abstract class ShoeModelRequestDataSource {
  /// The store's most recent request for one product, or null.
  Future<ShoeModelRequestRecord?> latestForProduct(String productId);

  /// Whether the product carries a model a customer could render — an
  /// `active` `product_models` row. Readable by the whole store because an
  /// active row is world-readable by that table's own RLS policy.
  Future<bool> productHasLiveModel(String productId);

  /// A product's model rows, newest first — what the admin queue offers when a
  /// request is being closed as done.
  ///
  /// It returns the raw rows rather than a typed record on purpose: the only
  /// consumer is the picker in the admin sheet, which shows a status and a
  /// length and passes an id back, so a second model class would be a wrapper
  /// around three fields nobody else reads.
  Future<List<Map<String, dynamic>>> modelsForProduct(String productId);

  /// Every request for one store, newest first — the seller's own history.
  Future<List<ShoeModelRequestRecord>> forStore(String storeId);

  /// The admin queue, newest first, with the product and store names embedded.
  Future<List<ShoeModelRequestRecord>> queue();

  Future<Object?> request({
    required String productId,
    required ShoeModelRequestMeasurements measurements,
    String? note,
  });

  Future<Object?> cancel(String requestId);

  Future<Object?> claim(String requestId);

  Future<Object?> fulfil({
    required String requestId,
    required int modelId,
    String? note,
  });

  Future<Object?> decline({required String requestId, String? reason});
}

/// The feature's only entry point to the database, and the only place a
/// transport failure is turned into something a seller can read.
///
/// **Nothing here throws at the caller.** A request that cannot be sent, a
/// queue that cannot be read, a byte-for-byte failure — each comes back as
/// [ShoeModelRequestOutcome] or an empty list, because every one of these
/// surfaces sits in a sheet or a screen that a seller is using to do something
/// else. The one thing this class must never do is take the product list down
/// with it.
class ShoeModelRequestService {
  final ShoeModelRequestDataSource _data;

  /// Counts calls, so a test can prove the "don't ask again while it is open"
  /// rule is enforced before the network rather than after it.
  int readCount = 0;

  ShoeModelRequestService(this._data);

  /// The production wiring. Built lazily so a build with the switch off never
  /// touches Supabase at all.
  factory ShoeModelRequestService.createDefault() =>
      ShoeModelRequestService(SupabaseShoeModelRequestDataSource());

  /// Everything the action sheet's row needs, in one round trip's worth of
  /// reads: the product's latest request and whether it already carries a
  /// live model.
  Future<ShoeModelRequestAvailability> availability(String productId) async {
    readCount++;
    try {
      final results = await Future.wait<Object?>([
        _data.latestForProduct(productId),
        _data.productHasLiveModel(productId),
      ]);
      return ShoeModelRequestAvailability(
        request: results[0] as ShoeModelRequestRecord?,
        hasLiveModel: results[1] == true,
      );
    } catch (_) {
      // Both failures read as "no request, no model", which shows the un-asked
      // row: the RPC then refuses it if a request really is open, and the
      // seller loses nothing but a tap.
      return const ShoeModelRequestAvailability();
    }
  }

  /// The latest request for a product, or null when there is none — and null
  /// when the read itself failed.
  ///
  /// Null for both, on purpose: this is called while the action sheet is
  /// opening, and the honest thing to show when the answer is unknown is the
  /// un-asked state (which the RPC would then refuse if there really is an open
  /// request) rather than an error.
  Future<ShoeModelRequestRecord?> latestForProduct(String productId) async {
    readCount++;
    try {
      return await _data.latestForProduct(productId);
    } catch (_) {
      return null;
    }
  }

  Future<List<ShoeModelRequestRecord>> forStore(String storeId) async {
    readCount++;
    try {
      return await _data.forStore(storeId);
    } catch (_) {
      return const [];
    }
  }

  Future<List<ShoeModelRequestRecord>> queue() async {
    readCount++;
    try {
      return await _data.queue();
    } catch (_) {
      return const [];
    }
  }

  /// A product's models, for the admin's "close as done" picker. An empty list
  /// covers both "none uploaded" and "the read failed", and the picker's copy
  /// is written to be true in either case.
  Future<List<Map<String, dynamic>>> modelsForProduct(String productId) async {
    readCount++;
    try {
      return await _data.modelsForProduct(productId);
    } catch (_) {
      return const [];
    }
  }

  /// Files the ask. The bounds are checked here as well as in the form and the
  /// CHECK, so a caller that skipped the form still cannot send a 40 mm shoe.
  Future<ShoeModelRequestOutcome> request({
    required String productId,
    required ShoeModelRequestMeasurements measurements,
    String? note,
  }) async {
    if (measurements.externalLengthMm < kPlausibleLengthMinMm ||
        measurements.externalLengthMm > kPlausibleLengthMaxMm) {
      return const ShoeModelRequestOutcome(
        success: false,
        message: 'That length does not look right — enter the outside of the '
            'pair in millimetres, between 100 and 400.',
      );
    }

    try {
      final result = await _data.request(
        productId: productId,
        measurements: measurements,
        note: note,
      );
      return ShoeModelRequestOutcome.fromRpc(result);
    } on ShoeModelRequestRejected catch (e) {
      // The one refusal that is not a sentence from the RPC: a 42501 means the
      // caller does not own the store, which is a bug or a stale session rather
      // than something the seller can act on.
      return ShoeModelRequestOutcome(success: false, message: e.message);
    } on ShoeModelRequestSchemaStale {
      // ⚠️ Not the connection, and telling the seller it was sent them to the
      // WiFi settings for a problem no amount of signal can fix (the report of
      // 2026-09-29). Which sentence is true depends on what was in the payload:
      // the two newest answers are the only arguments a server that predates
      // `20260929120000` cannot resolve, so when they were sent, clearing them
      // is a real fix the seller can carry out in two taps.
      final sentTheNewOnes = measurements.upperHeightMm != null ||
          measurements.sizesEu.isNotEmpty;
      return ShoeModelRequestOutcome(
        success: false,
        message: sentTheNewOnes
            ? 'The shoe height and the sizes you stock are not ready on the '
                'team\'s side yet. Clear those two and send again — the '
                'measurements that matter will go through.'
            : 'The team\'s end is not ready for this request yet. Please try '
                'again later.',
      );
    } catch (_) {
      return const ShoeModelRequestOutcome(
        success: false,
        message: 'Could not send the request. Check your connection and try '
            'again.',
      );
    }
  }

  Future<ShoeModelRequestOutcome> cancel(String requestId) =>
      _outcome(() => _data.cancel(requestId));

  Future<ShoeModelRequestOutcome> claim(String requestId) =>
      _outcome(() => _data.claim(requestId));

  Future<ShoeModelRequestOutcome> fulfil({
    required String requestId,
    required int modelId,
    String? note,
  }) =>
      _outcome(() => _data.fulfil(
            requestId: requestId,
            modelId: modelId,
            note: note,
          ));

  Future<ShoeModelRequestOutcome> decline({
    required String requestId,
    String? reason,
  }) =>
      _outcome(() => _data.decline(requestId: requestId, reason: reason));

  Future<ShoeModelRequestOutcome> _outcome(
    Future<Object?> Function() call,
  ) async {
    try {
      return ShoeModelRequestOutcome.fromRpc(await call());
    } catch (_) {
      return const ShoeModelRequestOutcome(
        success: false,
        message: 'That did not go through. Check your connection and try again.',
      );
    }
  }
}

/// What the sheet knows about one product before the seller taps anything.
class ShoeModelRequestAvailability {
  final ShoeModelRequestRecord? request;
  final bool hasLiveModel;

  const ShoeModelRequestAvailability({this.request, this.hasLiveModel = false});

  /// The row to draw. Pure, so the four states are pinned by unit tests rather
  /// than by pumping a bottom sheet.
  ShoeModelRequestRow get row => shoeModelRequestRow(
        status: request?.status,
        productHasModel: hasLiveModel,
      );
}

/// Raised when the RPC refused on authorisation grounds (42501) — the caller
/// does not own the store, or is not an admin.
class ShoeModelRequestRejected implements Exception {
  final String message;
  const ShoeModelRequestRejected(this.message);
  @override
  String toString() => message;
}

/// Raised when the call named an argument the live database does not have yet —
/// i.e. **this build is ahead of the schema**. See [isMissingRpcError].
class ShoeModelRequestSchemaStale implements Exception {
  const ShoeModelRequestSchemaStale();
}

/// Whether a PostgREST failure means "that function signature is not here",
/// rather than a connection that dropped.
///
/// ⚠️ **The two must not share one message, and that is the whole reason this is
/// a function rather than an inline `catch`.** PostgREST resolves an RPC by its
/// argument NAMES, so a build that sends the newer arguments is refused by a
/// server that has not had
/// `20260929120000_add_request_size_run_and_upper_height.sql` applied —
/// `PGRST202`, "Could not find the function … in the schema cache". The seller
/// used to read "Check your connection and try again" for that, and retrying a
/// call that cannot succeed is exactly what they would do (reported 2026-09-29,
/// the first time anybody filled the two new boxes on the live project).
///
/// Two shapes, because PostgREST has spelled this two ways: the code on current
/// versions, and the sentence on ones that predate it. Matching either is enough,
/// and matching only the code would miss a server this project has actually
/// talked to.
bool isMissingRpcError(Object error) =>
    error is PostgrestException &&
    (error.code == 'PGRST202' ||
        error.message.contains('Could not find the function'));

/// The Supabase implementation. Every call is one the RPCs or the RLS policies
/// were designed for — nothing here reaches around them.
class SupabaseShoeModelRequestDataSource implements ShoeModelRequestDataSource {
  SupabaseClient get _client => Supabase.instance.client;

  /// The columns the record reads, plus the two embeds the admin queue needs.
  static const String _select =
      '*, products!shoe_model_requests_product_id_fkey(name), '
      'stores!shoe_model_requests_store_id_fkey(name)';

  @override
  Future<ShoeModelRequestRecord?> latestForProduct(String productId) async {
    final rows = await _client
        .from('shoe_model_requests')
        .select()
        .eq('product_id', productId)
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return ShoeModelRequestRecord.fromRow(rows.first);
  }

  @override
  Future<bool> productHasLiveModel(String productId) async {
    final rows = await _client
        .from('product_models')
        .select('id')
        .eq('product_id', productId)
        .eq('status', 'active')
        .limit(1);
    return rows.isNotEmpty;
  }

  @override
  Future<List<Map<String, dynamic>>> modelsForProduct(String productId) async {
    final rows = await _client
        .from('product_models')
        .select('id, status, version, authored_length_mm, authored_size_eu')
        .eq('product_id', productId)
        .order('version', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<List<ShoeModelRequestRecord>> forStore(String storeId) async {
    final rows = await _client
        .from('shoe_model_requests')
        .select()
        .eq('store_id', storeId)
        .order('created_at', ascending: false);
    return rows.map(ShoeModelRequestRecord.fromRow).toList();
  }

  @override
  Future<List<ShoeModelRequestRecord>> queue() async {
    final rows = await _client
        .from('shoe_model_requests')
        .select(_select)
        .order('created_at', ascending: false);
    return rows.map(ShoeModelRequestRecord.fromRow).toList();
  }

  @override
  Future<Object?> request({
    required String productId,
    required ShoeModelRequestMeasurements measurements,
    String? note,
  }) async {
    try {
      final response = await _client.rpc('request_shoe_model', params: {
        'p_product_id': productId,
        'p_external_length_mm': measurements.externalLengthMm,
        if (measurements.externalWidthMm != null)
          'p_external_width_mm': measurements.externalWidthMm,
        if (measurements.heelHeightMm != null)
          'p_heel_height_mm': measurements.heelHeightMm,
        if (measurements.measuredSizeEu != null)
          'p_measured_size_eu': measurements.measuredSizeEu,
        // ⚠️ The two newest arguments are sent ONLY when they carry something,
        // and that is a deployment rule rather than tidiness: PostgREST resolves
        // a function by its argument names, so naming an argument the live
        // database does not have yet fails the whole call (PGRST202). Omitting an
        // empty one means a plain request — the shape every seller sends until
        // they touch the new boxes — keeps working against a server that has not
        // had `20260929120000_add_request_size_run_and_upper_height.sql` applied,
        // and the new fields start working the moment it is.
        if (measurements.upperHeightMm != null)
          'p_upper_height_mm': measurements.upperHeightMm,
        if (measurements.sizesEu.isNotEmpty) 'p_sizes_eu': measurements.sizesEu,
        if (note != null && note.trim().isNotEmpty) 'p_note': note.trim(),
      });
      return response;
    } on PostgrestException catch (e) {
      // 42501 is the ownership guard inside the RPC. It is not a sentence the
      // seller can act on, so it stays an exception — unlike a 400, which is
      // the RPC's own bounds message and must reach the seller as text.
      if (e.code == '42501') {
        throw const ShoeModelRequestRejected(
          'You can only ask for a model on your own products.',
        );
      }
      // An app ahead of the schema is its own failure with its own fix — see
      // [isMissingRpcError]. Everything else keeps bubbling up as before.
      if (isMissingRpcError(e)) throw const ShoeModelRequestSchemaStale();
      rethrow;
    }
  }

  @override
  Future<Object?> cancel(String requestId) async {
    final response = await _client.rpc('cancel_shoe_model_request',
        params: {'p_request_id': requestId});
    return response;
  }

  @override
  Future<Object?> claim(String requestId) async {
    final response =
        await _client.rpc('claim_shoe_model_request', params: {'p_request_id': requestId});
    return response;
  }

  @override
  Future<Object?> fulfil({
    required String requestId,
    required int modelId,
    String? note,
  }) async {
    final response = await _client.rpc('fulfil_shoe_model_request', params: {
      'p_request_id': requestId,
      'p_model_id': modelId,
      if (note != null && note.trim().isNotEmpty) 'p_admin_note': note.trim(),
    });
    return response;
  }

  @override
  Future<Object?> decline({required String requestId, String? reason}) async {
    final response = await _client.rpc('decline_shoe_model_request', params: {
      'p_request_id': requestId,
      if (reason != null && reason.trim().isNotEmpty) 'p_reason': reason.trim(),
    });
    return response;
  }
}
