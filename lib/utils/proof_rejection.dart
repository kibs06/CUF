/// What `reject_gcash_proof` actually did, and how to say it.
///
/// The RPC answers two different things from the same button:
///
///   attempts 1–2 → {status: 'awaiting_payment_confirmation',
///                   attempt_no: n, attempts_left: 3 - n}
///   attempt 3    → {status: 'cancelled', attempt_no: 3, cancelled: true}
///
/// The seller used to be told "the customer can correct it (3 attempts total)"
/// either way, which was false exactly when it mattered: on the third rejection
/// the order is cancelled, the stock is released and the customer's money is
/// already in the platform account. The status the server returns is the only
/// thing that knows which of those happened, so the message is built from it.
///
/// Pure: no clock, no socket, so the wording is testable.
library;

import 'package:flutter/foundation.dart';

/// The server's account of one rejection.
@immutable
class ProofRejectionOutcome {
  const ProofRejectionOutcome({
    required this.status,
    required this.attemptNo,
    this.attemptsLeft,
    this.cancelled = false,
  });

  /// `awaiting_payment_confirmation` (back to the customer) or `cancelled`.
  final String status;

  /// Which attempt was just rejected.
  final int attemptNo;

  /// Attempts the customer still has. Null when the order is gone.
  final int? attemptsLeft;

  /// True when this rejection ended the order.
  final bool cancelled;

  /// Reads the RPC's jsonb. Tolerates an empty map rather than throwing: a
  /// rejection that already succeeded must never become an error on the phone.
  factory ProofRejectionOutcome.fromJson(Map<String, dynamic> json) {
    final status = (json['status'] ?? '').toString();
    return ProofRejectionOutcome(
      status: status,
      attemptNo: (json['attempt_no'] as num?)?.toInt() ?? 0,
      attemptsLeft: (json['attempts_left'] as num?)?.toInt(),
      cancelled: status == 'cancelled' || json['cancelled'] == true,
    );
  }

  bool get isCancelled => cancelled || status == 'cancelled';
}

/// The snackbar the seller reads: what happened, in the terms they can act on.
@immutable
class RejectionNotice {
  const RejectionNotice({required this.text, required this.refundOwed});

  final String text;

  /// True when the platform now owes the customer a transfer. The caller uses
  /// this for the snackbar colour — a refund owed is not a plain success.
  final bool refundOwed;
}

RejectionNotice proofRejectionNotice(ProofRejectionOutcome outcome) {
  if (outcome.isCancelled) {
    return const RejectionNotice(
      text: 'Proof rejected — that was the last attempt, so the order is '
          'cancelled and the items are back in stock. The customer\'s money is '
          'in the platform GCash account and CUFMAI will refund it to them.',
      refundOwed: true,
    );
  }

  // The server says how many are left; if it did not, the cap is three.
  final left = outcome.attemptsLeft ??
      (outcome.attemptNo > 0 && outcome.attemptNo < 3 ? 3 - outcome.attemptNo : 0);

  if (left <= 0) {
    // Defensive: the order is still open but there are no attempts left — the
    // honest thing is to point at the customer's window, not promise another.
    return const RejectionNotice(
      text: 'Proof rejected — the customer has no attempts left. Do not expect '
          'another submission; reject again if the order needs to end.',
      refundOwed: false,
    );
  }

  return RejectionNotice(
    text: left == 1
        ? 'Proof rejected — the customer has 1 attempt left to send a '
            'corrected proof.'
        : 'Proof rejected — the customer can send a corrected proof '
            '($left attempts left).',
    refundOwed: false,
  );
}
