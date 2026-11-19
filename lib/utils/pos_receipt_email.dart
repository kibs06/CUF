import 'pos_receipt_format.dart';

/// The customer's copy of a POS sale as an email message.
///
/// Same sale, same numbers as the PDF and the on-screen receipt, but written
/// as plain text so it survives every mail client: the Gmail compose screen
/// the cashier opens, a forwarded copy, or a bounce to another address. The
/// receipt code sits in the subject and in the closing line, because that is
/// what the store will ask for if anything is wrong with the sale.
///
/// There is no attachment here on purpose: `mailto:` links cannot carry one.
/// The PDF stays one tap away through Share on the receipt screen.
class PosReceiptEmail {
  final String subject;
  final String body;

  const PosReceiptEmail({required this.subject, required this.body});
}

PosReceiptEmail buildPosReceiptEmail({
  required Map<String, dynamic> order,
  required String storeName,
  String storeLocation = '',
  String sellerName = '',
}) {
  final shop = storeName.trim().isEmpty ? 'Store' : storeName.trim();
  final location = storeLocation.trim();
  final cashier = sellerName.trim();
  final code = receiptCode(order['id']);
  final placedAt = receiptTime(order);
  final method = paymentMethodLabel(order['payment_method']);
  final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
  final tendered = (order['amount_tendered'] as num?)?.toDouble();
  final change = (order['change_amount'] as num?)?.toDouble();
  final reference = (order['gcash_reference_number'] ?? '').toString().trim();
  final items = (order['order_items'] as List? ?? const [])
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();

  final lines = <String>[
    shop,
    if (location.isNotEmpty) location,
    '',
    'SALES RECEIPT · #$code',
    if (placedAt != null) receiptStamp(placedAt),
    if (cashier.isNotEmpty) 'Cashier: $cashier',
    '',
    'ITEMS',
  ];

  if (items.isEmpty) {
    lines.add('(no line items recorded)');
  } else {
    for (final item in items) {
      final name = (item['product_name'] ?? 'Product').toString();
      final size = (item['size'] ?? '').toString().trim();
      final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
      final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0;
      final sizePart = size.isEmpty ? '' : ' (Size $size)';
      lines.add(
        '$quantity × $name$sizePart — ${formatPeso(unitPrice * quantity)}',
      );
    }
  }

  lines
    ..add('')
    ..add('TOTAL: ${formatPeso(total)}')
    ..add('Paid via: $method');
  if (tendered != null) lines.add('Cash tendered: ${formatPeso(tendered)}');
  if (change != null) lines.add('Change: ${formatPeso(change)}');
  if (reference.isNotEmpty) lines.add('GCash ref: $reference');

  lines
    ..add('')
    ..add('Thank you for shopping at $shop.')
    ..add(
      'Keep this email as your proof of purchase — quote receipt #$code if '
      'you need help with this sale.',
    );

  return PosReceiptEmail(
    subject: 'Receipt #$code from $shop',
    body: lines.join('\n'),
  );
}
