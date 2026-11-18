/// Where a seller's earnings are sent.
///
/// The admin portal already reads `profiles.payout_method` and
/// `profiles.payout_details` (`destination()` in admin-portal
/// `pages/Payouts.jsx`), and `payout_details` is documented as "payout
/// destination — GCash number, or bank name + account number".
///
/// A GCash transfer needs two things: the number to send to, and the name it
/// must match. Both live in that one column, number first:
///
///     09171234567 · JUAN CRUZ
///
/// The order is deliberate — the admin's copy button takes the text before the
/// separator, so what lands in the clipboard is exactly what goes into the
/// GCash "send to" field, while the name after it is there for the admin to
/// check the transfer against the account holder.
///
/// Pure: no I/O, so the parsing and the rules are testable without a socket.
library;

/// The separator between the number and the holder's name inside
/// `payout_details`. A middle dot with spaces reads as a divider in both the
/// admin table and the seller's own card.
const String payoutDetailsSeparator = '·';

class PayoutAccount {
  const PayoutAccount({required this.number, required this.name});

  /// 09XXXXXXXXX for a GCash account; the raw value for a legacy bank rail.
  final String number;

  /// The name on the GCash account. Empty when it was never captured.
  final String name;

  bool get isSet => number.trim().isNotEmpty;

  @override
  String toString() => 'PayoutAccount($number, $name)';
}

/// Digits only, and a +63 number becomes local form so a seller who types
/// either shape saves the same destination: `+63 917 123 4567` → `09171234567`.
String normalizeGcashNumber(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 12 && digits.startsWith('63')) {
    digits = '0${digits.substring(2)}';
  }
  return digits;
}

/// `payout_details` for a GCash account: number, separator, name.
String encodePayoutDetails({required String number, required String name}) {
  final normalized = normalizeGcashNumber(number);
  final holder = name.trim();
  return holder.isEmpty
      ? normalized
      : '$normalized $payoutDetailsSeparator $holder';
}

/// Reverses [encodePayoutDetails]. Tolerates the values that could already be
/// on file: a bare number, a number with spaces or a +63 prefix, and a bank
/// rail whose details are free text rather than a GCash number.
PayoutAccount? parsePayoutAccount(String? method, String? details) {
  final raw = (details ?? '').trim();
  if (raw.isEmpty) return null;

  final rail = (method ?? '').trim().toLowerCase();
  if (rail == 'bank') {
    // "Bank name + account number" — not a GCash number, so nothing to
    // normalize and no holder name recorded.
    return PayoutAccount(number: raw, name: '');
  }

  final parts = raw.split(payoutDetailsSeparator);
  final number = normalizeGcashNumber(parts.first);
  final name = parts.length > 1 ? parts.sublist(1).join(payoutDetailsSeparator).trim() : '';
  if (number.isEmpty) return null;
  return PayoutAccount(number: number, name: name);
}

/// What the seller sees for their current destination.
String payoutDestinationLabel(
  PayoutAccount? account, {
  String method = 'gcash',
}) {
  if (account == null || !account.isSet) return 'No payout details on file';
  final rail = method.trim().toLowerCase() == 'bank' ? 'Bank' : 'GCash';
  return '$rail · ${account.number}';
}

/// Per-field messages, so the form can point at the box that is wrong.
String? gcashNumberError(String? raw) {
  final number = normalizeGcashNumber(raw ?? '');
  if (number.isEmpty) return 'Enter the GCash number that should receive your payouts.';
  if (number.length != 11 || !number.startsWith('09')) {
    return 'Enter an 11-digit GCash number, starting with 09.';
  }
  return null;
}

String? payoutAccountNameError(String? raw) {
  final name = (raw ?? '').trim();
  if (name.length < 2) return 'Enter the name on the GCash account.';
  if (name.length > 60) return 'Keep the account name under 60 characters.';
  return null;
}

/// Both fields at once — the rule the save button follows.
String? payoutAccountError({required String number, required String name}) =>
    gcashNumberError(number) ?? payoutAccountNameError(name);
