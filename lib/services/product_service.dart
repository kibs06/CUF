import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product_models.dart';
import 'seller_notification_service.dart';

/// Service handling all product-related Supabase operations for sellers.
///
/// Manages products, product images (Storage + DB), variants, and
/// customizations. Screens should call this service — never Supabase directly.
class ProductService {
  ProductService._();
  static final ProductService instance = ProductService._();

  SupabaseClient get _client => Supabase.instance.client;

  // ─── CREATE ─────────────────────────────────────────────────────

  /// Create a new product with all related data (images, variants, customizations).
  /// Returns the new product ID.
  Future<String> createProduct({
    required String storeId,
    required String name,
    required String description,
    required double price,
    required String category,
    required List<String> tags,
    required List<XFile> images,
    required List<ProductVariant> variants,
    required List<ProductCustomization> customizations,
    List<ProductColor> colors = const [],
    bool isActive = true,
    bool isFeatured = false,
    String? barcode,
    double? salePrice,
    DateTime? saleStartsAt,
    DateTime? saleEndsAt,
  }) async {
    final sellerId = _client.auth.currentUser!.id;

    // 1. Insert product row
    final product = await _client
        .from('products')
        .insert({
          'store_id': storeId,
          'seller_id': sellerId,
          'name': name.trim(),
          'description': description.trim(),
          'price': price,
          'category': category,
          'tags': tags,
          'is_active': isActive,
          'is_featured': isFeatured,
          if (barcode != null && barcode.isNotEmpty) 'barcode': barcode.trim(),
          // Sale fields — `price` stays the ORIGINAL price; sale_price is
          // the discounted price (active-sale rules live in sale_price.dart).
          'sale_price': ?salePrice,
          if (saleStartsAt != null)
            'sale_starts_at': saleStartsAt.toIso8601String(),
          if (saleEndsAt != null) 'sale_ends_at': saleEndsAt.toIso8601String(),
        })
        .select()
        .single();

    final productId = product['id'] as String;

    // 2. Upload images to Supabase Storage
    final imageUrls = await _uploadImages(
      sellerId: sellerId,
      productId: productId,
      images: images,
    );

    // 3. Validate URLs before inserting into product_images
    final validUrls = imageUrls.where((url) => url.isNotEmpty).toList();

    if (validUrls.isEmpty && images.isNotEmpty) {
      throw Exception(
        'Image upload succeeded but no valid URLs were returned. '
        'Please check that the product-images bucket is set to public in Supabase Storage.',
      );
    }

    if (validUrls.isNotEmpty) {
      await _client.from('product_images').insert(
            validUrls.asMap().entries.map((e) => {
                  'product_id': productId,
                  'image_url': e.value,
                  'is_primary': e.key == 0,
                  'display_order': e.key,
                }).toList(),
          );
    }

    // 4. Insert variants
    if (variants.isNotEmpty) {
      await _client.from('product_variants').insert(
            variants.map((v) => v.toInsertMap(productId)).toList(),
          );
    }

    // 5. Sync inventory from variants — one row per unique size
    //    Must run after variants are inserted so the data is available
    await _syncInventoryFromVariants(productId, variants);

    // 6. Insert customizations
    if (customizations.isNotEmpty) {
      await _client.from('product_customizations').insert(
            customizations.map((c) => c.toInsertMap(productId)).toList(),
          );
    }

    // 7. Upload and insert per-color images
    for (final color in colors) {
      await _syncColorImages(
        productId: productId,
        colorName: color.name,
        images: color.images,
      );
    }

    return productId;
  }

  // ─── UPDATE ─────────────────────────────────────────────────────

  /// Update an existing product and replace its variants/customizations.
  Future<void> updateProduct({
    required String productId,
    required String name,
    required String description,
    required double price,
    required String category,
    required List<String> tags,
    required List<XFile> newImages,
    required List<String> existingImageUrls,
    required List<ProductVariant> variants,
    required List<ProductCustomization> customizations,
    List<ProductColor> colors = const [],
    required bool isActive,
    required bool isFeatured,
    String? barcode,
    double? salePrice,
    DateTime? saleStartsAt,
    DateTime? saleEndsAt,
  }) async {
    final sellerId = _client.auth.currentUser!.id;

    // 1. Update product row
    //    Sale fields are ALWAYS sent (null clears an existing sale) so the
    //    form can start/stop a sale by editing those fields.
    await _client
        .from('products')
        .update({
          'name': name.trim(),
          'description': description.trim(),
          'price': price,
          'category': category,
          'tags': tags,
          'is_active': isActive,
          'is_featured': isFeatured,
          'barcode': (barcode != null && barcode.isNotEmpty) ? barcode.trim() : null,
          'sale_price': salePrice,
          'sale_starts_at': saleStartsAt?.toIso8601String(),
          'sale_ends_at': saleEndsAt?.toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', productId);

    // 2. Upload any new images
    if (newImages.isNotEmpty) {
      final newUrls = await _uploadImages(
        sellerId: sellerId,
        productId: productId,
        images: newImages,
      );

      // Validate URLs before inserting
      final validNewUrls = newUrls.where((url) => url.isNotEmpty).toList();

      if (validNewUrls.isEmpty) {
        debugPrint('⚠️ No valid URLs returned from new image uploads — skipping insert');
      } else {
        final currentCount = existingImageUrls.length;
        await _client.from('product_images').insert(
              validNewUrls.asMap().entries.map((e) => {
                    'product_id': productId,
                    'image_url': e.value,
                    'is_primary': currentCount == 0 && e.key == 0,
                    'display_order': currentCount + e.key,
                  }).toList(),
            );
      }
    }

    // 3. Replace variants (delete + re-insert)
    await _client
        .from('product_variants')
        .delete()
        .eq('product_id', productId);
    if (variants.isNotEmpty) {
      await _client.from('product_variants').insert(
            variants.map((v) => v.toInsertMap(productId)).toList(),
          );
    }

    // 4. Sync inventory after variants are replaced
    //    Old inventory rows are deleted and replaced with fresh aggregated rows
    await _syncInventoryFromVariants(productId, variants);

    // 5. Replace customizations (delete + re-insert)
    await _client
        .from('product_customizations')
        .delete()
        .eq('product_id', productId);
    if (customizations.isNotEmpty) {
      await _client.from('product_customizations').insert(
            customizations.map((c) => c.toInsertMap(productId)).toList(),
          );
    }

    // 6. Replace per-color images (delete + re-insert)
    await _client
        .from('product_color_images')
        .delete()
        .eq('product_id', productId);
    for (final color in colors) {
      await _syncColorImages(
        productId: productId,
        colorName: color.name,
        images: color.images,
      );
    }
  }

  // ─── DELETE ─────────────────────────────────────────────────────

  /// Delete a product and all related data. Also removes images from Storage.
  ///
  /// Deletion order respects foreign key constraints:
  /// 1. Nullify references in tables with NO ACTION FK constraints
  ///    (order_items, sales_transaction_items, customization_requests)
  /// 2. Delete rows in CASCADE tables (inventory, product_variants, images, customizations)
  /// 3. Delete the product itself
  Future<void> deleteProduct(String productId) async {
    try {
      // 1. Nullify references in tables with NO ACTION FK constraints
      //    These preserve order/transaction history but remove the product reference
      await _client
          .from('order_items')
          .update({'product_id': null})
          .eq('product_id', productId);

      await _client
          .from('sales_transaction_items')
          .update({'product_id': null})
          .eq('product_id', productId);

      await _client
          .from('customization_requests')
          .update({'base_product_id': null})
          .eq('base_product_id', productId);

      // 2. Delete rows in CASCADE tables
      await _client
          .from('inventory')
          .delete()
          .eq('product_id', productId);

      await _client
          .from('product_variants')
          .delete()
          .eq('product_id', productId);

      // Delete product images + storage files
      final images = await _client
          .from('product_images')
          .select('id, image_url')
          .eq('product_id', productId);

      for (final img in images) {
        final url = img['image_url'] as String;
        await _removeStorageFile(url);
      }
      await _client
          .from('product_images')
          .delete()
          .eq('product_id', productId);

      // Delete per-color images + storage files
      final colorImages = await _client
          .from('product_color_images')
          .select('id, url')
          .eq('product_id', productId);

      for (final img in colorImages) {
        final url = img['url'] as String;
        await _removeStorageFile(url);
      }
      await _client
          .from('product_color_images')
          .delete()
          .eq('product_id', productId);

      await _client
          .from('product_customizations')
          .delete()
          .eq('product_id', productId);

      // 3. Now safe to delete the product itself
      await _client.from('products').delete().eq('id', productId);
    } catch (e) {
      // Rethrow so the UI layer can catch it and show an error SnackBar
      throw Exception('Failed to delete product: $e');
    }
  }

  /// Remove a single image from storage and the database.
  Future<void> removeImage(String imageId, String imageUrl) async {
    await _client.from('product_images').delete().eq('id', imageId);
    _removeStorageFile(imageUrl);
  }

  /// Remove a single color image from storage and the database.
  Future<void> removeColorImage(String imageId, String imageUrl) async {
    await _client.from('product_color_images').delete().eq('id', imageId);
    _removeStorageFile(imageUrl);
  }

  // ─── READ ───────────────────────────────────────────────────────

  /// Get all products belonging to the current seller's store, with all relations.
  ///
  /// Filters by both seller_id and store_id for defense-in-depth scoping,
  /// even though the one-store-per-seller constraint should make store_id
  /// redundant in practice.
  Future<List<Map<String, dynamic>>> getSellerProducts() async {
    final sellerId = _client.auth.currentUser!.id;
    final storeId = await getSellerStoreId();
    if (storeId == null) return [];

    final data = await _client
        .from('products')
        .select(
            '*, product_images(*), product_variants(*), product_customizations(*), inventory(*), product_color_images(*)')
        .eq('seller_id', sellerId)
        .eq('store_id', storeId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  /// Get a single product with all its relations.
  Future<Map<String, dynamic>> getProduct(String productId) async {
    return await _client
        .from('products')
        .select(
            '*, product_images(*), product_variants(*), product_customizations(*), inventory(*), product_color_images(*)')
        .eq('id', productId)
        .single();
  }

  /// Get the seller's store ID. Returns null if no store exists.
  ///
  /// Uses maybeSingle() without .limit(1) so it throws if the
  /// one-store-per-seller constraint is ever violated (multiple rows).
  Future<String?> getSellerStoreId() async {
    final sellerId = _client.auth.currentUser!.id;
    final store = await _client
        .from('stores')
        .select('id')
        .eq('owner_id', sellerId)
        .eq('is_active', true)
        .maybeSingle();
    return store?['id']?.toString();
  }

  /// Toggle active status for a product.
  Future<void> toggleActive(String productId, bool isActive) async {
    await _client
        .from('products')
        .update({'is_active': isActive, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', productId);
  }

  /// Toggle featured status for a product.
  Future<void> toggleFeatured(String productId, bool isFeatured) async {
    await _client
        .from('products')
        .update({'is_featured': isFeatured, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', productId);
  }

  /// Start (or update) a sale on a product.
  ///
  /// `price` is untouched — only the sale fields change. Passing null for
  /// [salePrice] clears the sale entirely.
  Future<void> setSale(
    String productId, {
    double? salePrice,
    DateTime? saleStartsAt,
    DateTime? saleEndsAt,
  }) async {
    await _client
        .from('products')
        .update({
          'sale_price': salePrice,
          'sale_starts_at': saleStartsAt?.toIso8601String(),
          'sale_ends_at': saleEndsAt?.toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', productId);
  }

  /// End a product's sale (clears all sale fields — original price restored).
  Future<void> clearSale(String productId) async {
    await setSale(productId);
  }

  // ─── STOCK SYNC ─────────────────────────────────────────────────

  /// Sync a product's `is_active` flag based on current stock levels.
  ///
  /// If ANY inventory or variant row has stock > 0 → active.
  /// If ALL stock is 0 (or no rows exist) → inactive.
  Future<void> syncProductActiveStatus(String productId) async {
    // Fetch all inventory stock for this product
    final inventoryData = await _client
        .from('inventory')
        .select('stock')
        .eq('product_id', productId);

    // Fetch all variant stock for this product
    final variantData = await _client
        .from('product_variants')
        .select('stock')
        .eq('product_id', productId);

    // Check if any row has stock > 0
    final hasInventoryStock = (inventoryData as List)
        .any((row) => (row['stock'] as int? ?? 0) > 0);

    final hasVariantStock = (variantData as List)
        .any((row) => (row['stock'] as int? ?? 0) > 0);

    final shouldBeActive = hasInventoryStock || hasVariantStock;

    // Update products.is_active accordingly
    await _client
        .from('products')
        .update({
          'is_active': shouldBeActive,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', productId);
  }

  // ─── PRIVATE HELPERS ────────────────────────────────────────────

  /// Upload a list of image files to Supabase Storage and return their public URLs.
  ///
  /// [onProgress] is called with (current, total) after each image is queued
  /// for upload. It fires at index N *before* the Nth upload starts and
  /// once more at (total, total) after the last upload completes.
  Future<List<String>> _uploadImages({
    required String sellerId,
    required String productId,
    required List<XFile> images,
    void Function(int current, int total)? onProgress,
  }) async {
    const bucketName = 'product-images';
    final urls = <String>[];

    for (int i = 0; i < images.length; i++) {
      try {
        final file = images[i];
        final bytes = await file.readAsBytes();

        if (bytes.isEmpty) {
          throw Exception('Image $i is empty — could not read file');
        }

        final ext = file.path.split('.').last.toLowerCase();
        final safeExt = ext == 'jpg' ? 'jpeg' : ext;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final path = '$sellerId/$productId/${timestamp}_$i.$ext';

        onProgress?.call(i, images.length);

        debugPrint('⬆️ Uploading image $i to $bucketName/$path');

        // Upload to product-images bucket (uppercase — matches Supabase)
        await _client.storage.from(bucketName).uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                contentType: 'image/$safeExt',
                upsert: true,
              ),
            );

        final url = _client.storage.from(bucketName).getPublicUrl(path);

        debugPrint('🔗 Public URL for image $i: $url');

        // Validate URL is not empty
        if (url.isEmpty) {
          throw Exception(
            'getPublicUrl() returned empty string for image $i. '
            'Check that the "$bucketName" bucket is set to PUBLIC in Supabase Storage.',
          );
        }

        urls.add(url);
        debugPrint('✅ Image $i upload complete: $url');
      } catch (e) {
        debugPrint('❌ Image $i upload failed: $e');
        throw Exception('Failed to upload image ${i + 1}: ${e.toString()}');
      }
    }

    onProgress?.call(images.length, images.length);
    return urls;
  }

  /// Sync the inventory table from a variants list.
  ///
  /// Groups variants by size and sums their stock across all colors,
  /// then replaces all inventory rows for this product with one row
  /// per unique size. This keeps inventory in sync with product_variants
  /// so the customer size selector always has accurate data.
  Future<void> _syncInventoryFromVariants(
    String productId,
    List<ProductVariant> variants,
  ) async {
    // Group stock by size — sum across all colors for the same size
    final Map<String, int> stockBySize = {};
    for (final v in variants) {
      final size = v.size.trim();
      if (size.isEmpty) continue;
      stockBySize[size] = (stockBySize[size] ?? 0) + v.stock;
    }

    // Delete existing inventory rows for this product
    // (must run before the early return so stale rows are cleared
    //  even when all variants are removed)
    await _client
        .from('inventory')
        .delete()
        .eq('product_id', productId);

    if (stockBySize.isEmpty) return;

    // Insert one row per unique size
    await _client.from('inventory').insert(
      stockBySize.entries.map((e) => {
        'product_id': productId,
        'size': e.key,
        'stock': e.value,
        'updated_at': DateTime.now().toIso8601String(),
      }).toList(),
    );

    // ── Notification: low_stock ──────────────────────────────────
    // Fire-and-forget: notify seller about low stock after inventory sync.
    try {
      final storeId = await getSellerStoreId();
      if (storeId != null) {
        // Get product name for the notification
        final product = await _client
            .from('products')
            .select('name')
            .eq('id', productId)
            .maybeSingle();
        final productName = product?['name']?.toString() ?? 'Product';

        for (final entry in stockBySize.entries) {
          if (entry.value <= 5) {
            SellerNotificationService.instance.createLowStock(
              storeId: storeId,
              productId: productId,
              productName: productName,
              size: entry.key,
              currentStock: entry.value,
            ); // intentionally not awaited
          }
        }
      }
    } catch (e) {
      debugPrint('[ProductService] low_stock notification failed: $e');
    }
  }

  /// Sync per-color images: upload new files, insert DB rows.
  ///
  /// Called during both create and update flows. On update, the caller
  /// deletes all existing product_color_images rows for this product
  /// before calling this method (delete + re-insert strategy).
  Future<void> _syncColorImages({
    required String productId,
    required String colorName,
    required List<ProductColorImage> images,
  }) async {
    if (images.isEmpty) return;

    final sellerId = _client.auth.currentUser!.id;
    final bucketName = 'product-images';
    final rowsToInsert = <Map<String, dynamic>>[];

    for (int i = 0; i < images.length; i++) {
      final img = images[i];

      if (img.isExisting && img.url != null) {
        // Existing image — keep its URL as-is
        rowsToInsert.add({
          'product_id': productId,
          'color_name': colorName,
          'url': img.url!,
          'display_order': img.displayOrder,
        });
      } else if (img.isNew && img.file != null) {
        // New image — upload to Storage
        final file = img.file!;
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;

        final ext = file.path.split('.').last.toLowerCase();
        final safeExt = ext == 'jpg' ? 'jpeg' : ext;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        // Per-color path: {sellerId}/{productId}/colors/{colorName}/{timestamp}_{i}.{ext}
        final safeColorName = colorName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
        final path = '$sellerId/$productId/colors/$safeColorName/${timestamp}_$i.$ext';

        await _client.storage.from(bucketName).uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                contentType: 'image/$safeExt',
                upsert: true,
              ),
            );

        final url = _client.storage.from(bucketName).getPublicUrl(path);
        if (url.isEmpty) {
          throw Exception('Color image upload returned empty URL for $colorName image $i');
        }

        rowsToInsert.add({
          'product_id': productId,
          'color_name': colorName,
          'url': url,
          'display_order': img.displayOrder,
        });
      }
    }

    if (rowsToInsert.isNotEmpty) {
      await _client.from('product_color_images').insert(rowsToInsert);
    }
  }

  /// Best-effort removal of a file from storage by its public URL.
  Future<void> _removeStorageFile(String url) async {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final bucketIndex = segments.indexOf('product-images');
      if (bucketIndex >= 0 && bucketIndex + 1 < segments.length) {
        final path = segments.sublist(bucketIndex + 1).join('/');
        await _client.storage.from('product-images').remove([path]);
      }
    } catch (_) {
      // Silently fail — image may have already been removed
    }
  }
}
