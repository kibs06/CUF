/// Thrown when a cart item's requested quantity exceeds available stock.
///
/// Caught by [OrderProvider] and surfaced to the checkout screen as a
/// friendly, actionable message — never displayed raw to the customer.
class StockUnavailableException implements Exception {
  final String productName;
  final String size;
  final int requestedQty;
  final int availableStock;

  StockUnavailableException({
    required this.productName,
    required this.size,
    this.requestedQty = 1,
    this.availableStock = 0,
  });

  /// Human-readable message safe for customer-facing display.
  String get friendlyMessage {
    if (availableStock <= 0) {
      return '$productName (size $size) is no longer available.';
    }
    return '$productName (size $size) only has $availableStock left in stock. '
        'Please reduce the quantity to continue.';
  }

  @override
  String toString() =>
      'StockUnavailableException: $productName size $size '
      '(requested: $requestedQty, available: $availableStock)';
}
