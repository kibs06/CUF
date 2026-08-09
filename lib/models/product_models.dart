/// Data models for the product management feature.
///
/// Used by [ProductService] and the add/edit product screen.
library;

class ProductVariant {
  final String? id;
  final String size;
  final String? color;
  final int stock;
  final double additionalPrice;
  final String? sku;

  const ProductVariant({
    this.id,
    required this.size,
    this.color,
    required this.stock,
    this.additionalPrice = 0,
    this.sku,
  });

  factory ProductVariant.fromMap(Map<String, dynamic> map) => ProductVariant(
        id: map['id']?.toString(),
        size: map['size']?.toString() ?? '',
        color: map['color']?.toString(),
        stock: (map['stock'] as num?)?.toInt() ?? 0,
        additionalPrice: (map['additional_price'] as num?)?.toDouble() ?? 0,
        sku: map['sku']?.toString(),
      );

  Map<String, dynamic> toInsertMap(String productId) => {
        'product_id': productId,
        'size': size,
        'color': color,
        'stock': stock,
        'additional_price': additionalPrice,
        'sku': sku,
      };
}

class ProductCustomization {
  final String? id;
  final String optionName;
  final String optionType; // 'text', 'select', 'color'
  final List<String> options;
  final bool isRequired;
  final double additionalPrice;

  const ProductCustomization({
    this.id,
    required this.optionName,
    required this.optionType,
    this.options = const [],
    this.isRequired = false,
    this.additionalPrice = 0,
  });

  factory ProductCustomization.fromMap(Map<String, dynamic> map) =>
      ProductCustomization(
        id: map['id']?.toString(),
        optionName: map['option_name']?.toString() ?? '',
        optionType: map['option_type']?.toString() ?? 'text',
        options: List<String>.from(map['options'] ?? []),
        isRequired: map['is_required'] ?? false,
        additionalPrice: (map['additional_price'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toInsertMap(String productId) => {
        'product_id': productId,
        'option_name': optionName,
        'option_type': optionType,
        'options': options,
        'is_required': isRequired,
        'additional_price': additionalPrice,
      };
}
