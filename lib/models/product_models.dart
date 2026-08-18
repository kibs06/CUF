/// Data models for the product management feature.
///
/// Used by [ProductService] and the add/edit product screen.
library;

import 'package:image_picker/image_picker.dart';

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

// ─── Per-color image ──────────────────────────────────────────────

/// A single image attached to a product color.
///
/// Either [url] (existing remote image) or [file] (newly picked local file)
/// must be non-null — never both.
class ProductColorImage {
  final String? id;       // DB id (null for new images)
  final String? url;      // Remote URL for existing images
  final XFile? file;      // Local file for new picks
  final int displayOrder; // 0 = primary thumbnail for this color

  const ProductColorImage({
    this.id,
    this.url,
    this.file,
    this.displayOrder = 0,
  });

  bool get isExisting => url != null;
  bool get isNew => file != null;
}

// ─── Product color (top-level entity) ──────────────────────────────

/// A color variant of a product, owning its own photo gallery and
/// size/stock variants. This is the top-level entity the seller
/// interacts with — they add colors, not individual variants.
///
/// The `color` field on [ProductVariant] must match this color's [name]
/// so that flat queries and inventory sync keep working.
class ProductColor {
  final String? id;                     // DB id (null for new colors)
  final String name;                    // e.g. "White", "Beige", "Khaki"
  final List<ProductColorImage> images; // must have length >= 1 to be valid
  final List<ProductVariant> variants;  // sizes/stock/price/sku for this color

  const ProductColor({
    this.id,
    required this.name,
    this.images = const [],
    this.variants = const [],
  });

  /// True when this color has at least one photo and at least one size/variant.
  bool get hasImages => images.isNotEmpty;
  bool get hasVariants => variants.isNotEmpty;
  bool get isValid => hasImages && hasVariants;

  /// Total stock across all sizes for this color.
  int get totalStock => variants.fold<int>(0, (sum, v) => sum + v.stock);

  /// Number of distinct sizes.
  int get sizeCount => variants.map((v) => v.size).toSet().length;

  ProductColor copyWith({
    String? id,
    String? name,
    List<ProductColorImage>? images,
    List<ProductVariant>? variants,
  }) {
    return ProductColor(
      id: id ?? this.id,
      name: name ?? this.name,
      images: images ?? this.images,
      variants: variants ?? this.variants,
    );
  }
}
