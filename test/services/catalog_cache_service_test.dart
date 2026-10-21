import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/services/catalog_cache_service.dart';
import 'package:app/utils/product_stock.dart';
import 'package:app/utils/size_match.dart';

Map<String, dynamic> _fullProduct() => {
  'id': 'p1',
  'name': 'Test Runner',
  'category': 'Sneakers',
  'price': 1999.0,
  'sale_price': 1499.0,
  'sale_starts_at': null,
  'sale_ends_at': null,
  'avg_rating': 4.5,
  'review_count': 12,
  'units_sold': 7,
  'audience': 'men',
  'collection': 'Workshop',
  'is_featured': true,
  'is_published': true,
  'store_id': 's1',
  'store_name': 'Test Store',
  'description': 'A great shoe',
  'images': ['https://example.com/a.png', 'https://example.com/b.png'],
  'sizes': {'EU 42': 3, 'EU 43': 0},
  'tags': ['leather', 'handmade'],
  // Heavy embeds that must NOT be persisted:
  'product_images': [
    {'image_url': 'https://example.com/a.png', 'display_order': 0},
  ],
  'inventory': [
    {'size': 'EU 42', 'stock': 3},
    {'size': 'EU 43', 'stock': 0},
  ],
  'product_variants': [
    {'size': 'EU 42', 'stock': 3, 'color': 'brown'},
  ],
  'product_color_images': [],
  'stores': {'name': 'Test Store'},
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('CatalogCacheService', () {
    test('catalog round-trips slimmed products + units sold', () async {
      final service = CatalogCacheService.instance;

      await service.saveCatalog(
        hideOutOfStock: true,
        products: [_fullProduct()],
        unitsSold: const {'p1': 7},
      );

      final loaded = await service.loadCatalog(hideOutOfStock: true);
      expect(loaded, isNotNull);
      expect(loaded!.products, hasLength(1));

      final p = loaded.products.single;
      expect(p['id'], 'p1');
      expect(p['name'], 'Test Runner');
      expect(p['units_sold'], 7);
      expect(p['images'], [
        'https://example.com/a.png',
        'https://example.com/b.png',
      ]);
      expect(p['sizes'], {'EU 42': 3, 'EU 43': 0});
      expect(loaded.unitsSold, {'p1': 7});

      // Heavy embeds are dropped — the payload stays small — but the slimmed
      // raw `inventory` is kept so totalStock/purchasableProducts/stockByEuSize
      // behave identically on cached rows.
      expect(p.containsKey('product_images'), isFalse);
      expect(p.containsKey('product_variants'), isFalse);
      expect(p.containsKey('stores'), isFalse);
      expect(p['inventory'], [
        {'size': 'EU 42', 'stock': 3},
        {'size': 'EU 43', 'stock': 0},
      ]);
    });

    test('hideOutOfStock variants are cached separately', () async {
      final service = CatalogCacheService.instance;
      await service.saveCatalog(
        hideOutOfStock: false,
        products: [_fullProduct()],
        unitsSold: const {},
      );

      // The other key was never written.
      final other = await service.loadCatalog(hideOutOfStock: true);
      expect(other, isNull);
    });

    test('returns null when nothing was cached', () async {
      final cached = await CatalogCacheService.instance.loadCatalog(
        hideOutOfStock: true,
      );
      expect(cached, isNull);

      final banners = await CatalogCacheService.instance.loadBanners();
      expect(banners, isNull);
    });

    test('banners round-trip', () async {
      final service = CatalogCacheService.instance;
      await service.saveBanners([
        {'id': 'b1', 'title': 'Sale', 'display_order': 0},
      ]);

      final loaded = await service.loadBanners();
      expect(loaded, isNotNull);
      expect(loaded!.banners.single['title'], 'Sale');
    });

    test('slimmed rows keep stock-helper semantics', () {
      // The regression this guards: dropping the raw `inventory` embed made
      // every cached product read as out of stock (total 0, no EU sizes).
      final full = _fullProduct();
      expect(purchasableProducts([full]), hasLength(1));

      final slim = CatalogCacheService.slimProduct(full);
      expect(purchasableProducts([slim]), hasLength(1));
      expect(stockByEuSize(slim), stockByEuSize(full));
      expect(slim['sizes'], {'EU 42': 3, 'EU 43': 0});

      // A zero-stock row stays hidden after slimming — same as network rows.
      final oos = Map<String, dynamic>.from(full)
        ..['inventory'] = [
          {'size': 'EU 42', 'stock': 0},
        ];
      expect(
        purchasableProducts([CatalogCacheService.slimProduct(oos)]),
        isEmpty,
      );
    });

    test('slimProduct coerces numeric sizes and string ids', () {
      final slim = CatalogCacheService.slimProduct({
        'id': 42,
        'name': 'N',
        'price': 100,
        'images': [1, 2],
        'sizes': {'EU 42': 2.0},
      });
      expect(slim['id'], '42');
      expect(slim['images'], ['1', '2']);
      expect(slim['sizes'], {'EU 42': 2});
    });
  });
}
