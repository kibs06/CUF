/// Calls `validate-shoe-model` — the server-side model gate (roadmap V2.4).
///
/// **Why the app asks the server to check a file it already checked.** The
/// client-side validation in `shoe_model_upload_service.dart` is not a security
/// boundary (architecture §2.5.4): it gives an artisan a sentence in seconds.
/// The server re-reads the stored bytes, hashes them against the row and runs
/// the same rule set — and, since
/// `20260928120000_gate_product_model_active.sql`, it is the *only* caller the
/// database lets write `product_models.status='active'`. So a row can be a
/// draft or rejected without this function, but never live.
///
/// That is also why nothing here is behind an `AppConstants` switch. Every
/// other visible surface in this pipeline can be turned off and degrade to
/// today's behaviour; this call is the transition itself. A build with it
/// disabled would upload models and then never be able to publish one.
///
/// **Three answers, and the difference matters.** [ShoeModelServerOutcome]
/// separates "the server ran the checks and refused" (422, the row is now
/// `rejected` and the seller has failing rows to read) from "no verdict
/// arrived" (transport failure, 401/403/429/500 — the row is untouched and
/// still a draft). Collapsing those would either hide a rejection or demote a
/// model that was never judged.
library;

import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// The Edge Function's name, in one place so tests and logs cannot disagree.
const String kValidateShoeModelFunction = 'validate-shoe-model';

/// What one call to the server validator produced.
enum ShoeModelServerOutcome {
  /// The server ran the contract and accepted the bytes.
  validated,

  /// The server ran the contract and refused them; the row is `rejected`.
  rejected,

  /// No verdict: the call did not complete, or it was refused before the
  /// checks ran. The row keeps the status it had (a draft).
  undetermined,
}

/// The result of one `validate-shoe-model` call.
///
/// Immutable and comparable by hand in tests; built by
/// [shoeModelServerVerdictFrom], which is pure so the response shapes — a pass,
/// a 422 with failing rows, a 429, an HTML error page — are all testable
/// without a server.
class ShoeModelServerVerdict {
  final ShoeModelServerOutcome outcome;

  /// `product_models.status` after the call: `active` when the server
  /// published it, `rejected` when it refused, `draft` when nothing was
  /// decided.
  final String status;

  /// The names of the contract rows that failed, as the report named them
  /// (`materials`, `scale`, …). Empty unless [outcome] is rejected.
  final List<String> failedChecks;

  /// What the contract cannot decide and a reviewer must: toe-vs-heel,
  /// de-lit albedo, likeness, on-device fps. Echoed from the response so the
  /// app never implies a green server run is approval.
  final List<String> notChecked;

  /// One sentence for the seller when [outcome] is [undetermined]; null
  /// otherwise.
  final String? detail;

  const ShoeModelServerVerdict({
    required this.outcome,
    required this.status,
    this.failedChecks = const [],
    this.notChecked = const [],
    this.detail,
  });

  /// A call that produced no verdict, with the reason phrased for the seller.
  const ShoeModelServerVerdict.undetermined(String this.detail)
      : outcome = ShoeModelServerOutcome.undetermined,
        status = 'draft',
        failedChecks = const [],
        notChecked = const [];

  bool get passed => outcome == ShoeModelServerOutcome.validated;

  /// True when the server refused the model, as opposed to not judging it.
  bool get refused => outcome == ShoeModelServerOutcome.rejected;

  /// The sentence the seller reads when the model did not go live. Null when
  /// it did.
  String? get sellerMessage {
    switch (outcome) {
      case ShoeModelServerOutcome.validated:
        return null;
      case ShoeModelServerOutcome.rejected:
        if (failedChecks.isEmpty) {
          return 'The server refused the model without naming a failing row, '
              'which it should not do — upload it again, and report it if that '
              'happens twice. It stays hidden until it passes.';
        }
        return 'The server checked the model and refused it '
            '(${failedChecks.join(', ')}), so it is saved as a draft and is not '
            'shown to customers. Fix those and upload again.';
      case ShoeModelServerOutcome.undetermined:
        return 'The model is saved as a draft: the server could not check it '
            '(${detail ?? 'no response'}), so it is not shown to customers yet. '
            'Publish the product again to retry.';
    }
  }
}

/// Builds a verdict from one HTTP response. Pure: no client, no clock.
///
/// The shapes this has to survive: `200 {ok:true,…}`, `422 {ok:false,
/// report:{checks:[…]}}`, the 4xx/5xx objects the other functions return
/// (`{error: "…"}`), a body that arrives as an undecoded JSON string, and
/// anything that is not JSON at all.
///
/// **422 means refused, whether or not the body parses.** The status code is
/// the function's own refusal signal (it is the only layer that returns 422 —
/// the gateway returns 401/403/404/502), so a response whose body is lost in
/// transit must still count as a judgement rather than degrade into "no
/// verdict" — otherwise a refused model would sit in drafts with nobody told
/// why.
ShoeModelServerVerdict shoeModelServerVerdictFrom({
  required int statusCode,
  Object? body,
}) {
  final map = _asJsonMap(body);

  if (statusCode == 422) {
    // Growable: [shoeModelServerFailedChecks] returns a const list when there
    // is nothing to report, and the sha row may be prepended to it below.
    final failed = [...shoeModelServerFailedChecks(map?['report'])];
    // The server-only check, which no offline run can perform: the bytes in the
    // bucket must hash to the digest the row records. It is reported under
    // `integrity` rather than as a contract row, so the app names it here — a
    // seller debugging "it passed my validator" needs to see this one.
    final integrity = map?['integrity'];
    final sha = integrity is Map ? integrity['sha256'] : null;
    if (sha is Map && sha['matches'] == false) {
      failed.insert(0, 'sha256 (the stored bytes do not match the row)');
    }
    return ShoeModelServerVerdict(
      outcome: ShoeModelServerOutcome.rejected,
      status: map?['status']?.toString() ?? 'rejected',
      failedChecks: failed,
      notChecked: _stringList(map?['notChecked']),
      detail: map?['error']?.toString(),
    );
  }

  if (statusCode == 200 && map != null && map['ok'] == true) {
    return ShoeModelServerVerdict(
      outcome: ShoeModelServerOutcome.validated,
      status: map['status']?.toString() ?? 'active',
      notChecked: _stringList(map['notChecked']),
    );
  }

  // Everything else is "no verdict": the function's own error sentence when it
  // gave one, and the status code when it did not (a gateway 502, an HTML page).
  final message = map?['error']?.toString() ?? map?['message']?.toString();
  return ShoeModelServerVerdict.undetermined(
    message == null || message.isEmpty ? 'HTTP $statusCode' : message,
  );
}

/// A response body as a map: already decoded, or a JSON string that still has
/// to be. `functions.invoke` decodes JSON today, but `FunctionException.details`
/// is only documented as dynamic and a proxy can hand back `text/plain` for a
/// JSON payload — both of which would otherwise turn a verdict into silence.
Map<String, dynamic>? _asJsonMap(Object? body) {
  if (body is Map) return Map<String, dynamic>.from(body);
  if (body is String) {
    final text = body.trimLeft();
    if (!text.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Not JSON after all — the caller's fallback (the status code) is the
      // honest answer.
    }
  }
  return null;
}

/// The failing check names out of a report, whatever wrapper they arrive in
/// (`report` as a map, or the report itself). Tolerant on purpose: this runs on
/// the refusal path, where throwing would lose the reason for the refusal.
List<String> shoeModelServerFailedChecks(Object? report) {
  final source = report is Map
      ? (report['checks'] is List ? report['checks'] : report)
      : report;
  if (source is! List) return const [];
  final names = <String>[];
  for (final check in source) {
    if (check is! Map) continue;
    if (check['status']?.toString() != 'fail') continue;
    final name = check['name']?.toString();
    if (name != null && name.isNotEmpty) names.add(name);
  }
  return names;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList(growable: false);
}

/// The seam: one method, so a test can hand back a verdict and the production
/// implementation is the only thing that touches the network.
abstract class ShoeModelServerValidator {
  Future<ShoeModelServerVerdict> validate({
    required int modelId,
    bool activate = true,
  });
}

/// The real call, through `functions.invoke` with the seller's own JWT.
///
/// `functions.invoke` throws [FunctionException] on any non-2xx — including the
/// 422 that *is* our verdict — so the exception's body is decoded as carefully
/// as a success, and nothing here is allowed to throw upward: a validator that
/// throws would turn "not judged" into "upload failed" and lose the row.
class SupabaseShoeModelServerValidator implements ShoeModelServerValidator {
  final SupabaseClient Function() _clientProvider;

  /// Injectable so a test can supply a client without `Supabase.instance`.
  SupabaseShoeModelServerValidator({SupabaseClient Function()? client})
      : _clientProvider = client ?? _defaultClient;

  static SupabaseClient _defaultClient() => Supabase.instance.client;

  @override
  Future<ShoeModelServerVerdict> validate({
    required int modelId,
    bool activate = true,
  }) async {
    try {
      final response = await _clientProvider().functions.invoke(
            kValidateShoeModelFunction,
            body: {'model_id': modelId, 'activate': activate},
          );
      return shoeModelServerVerdictFrom(
        statusCode: response.status,
        body: response.data,
      );
    } on FunctionException catch (e) {
      return shoeModelServerVerdictFrom(statusCode: e.status, body: e.details);
    } catch (_) {
      return ShoeModelServerVerdict.undetermined('could not reach the server');
    }
  }
}
