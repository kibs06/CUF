import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../services/product_service.dart';
import '../services/supabase_service.dart';
import '../utils/nav_perf.dart';
import '../utils/product_audience.dart';
import '../utils/product_search.dart';
import '../utils/sale_price.dart';
import '../utils/size_match.dart';

enum SortMode {
  /// Default browse order — the catalog is shuffled once per
  /// `loadProducts()` call, so this mode shows the shuffled "fresh feed"
  /// rather than a chronological order. Explicit sorts below fully override it.
  featured,
  priceLowToHigh,
  priceHighToLow,
  nameAZ,
  nameZA,

  /// Highest average product rating first (trigger-maintained
  /// `avg_rating` on products). Ties break toward more reviews.
  topRated,

  /// Most units sold first (aggregated from paid, non-cancelled orders).
  bestSelling,
}

/// Label of the 'Best Sellers' pseudo-category — a *filter* (like the
/// 'On Sale' pseudo-category), not a [SortMode]. See
/// [ProductProvider.categories] / [ProductProvider.getFilteredProducts].
const String kBestSellersCategory = 'Best Sellers';

/// How many products the 'Best Sellers' filter/rail keeps.
///
/// A best-seller set has to be curated: "has sold at least one unit" alone
/// would return most of an established catalog and leave the chip pointless.
/// Top-N of the live `units_sold` aggregation is the rule; catalogs smaller
/// than [kBestSellerLimit] simply return every product that has sold.
const int kBestSellerLimit = 20;

/// Units sold for [product] per the [unitsSold] aggregation (absent = 0).
int unitsSoldOf(Map<String, dynamic> product, Map<String, int> unitsSold) =>
    unitsSold[product['id']?.toString() ?? ''] ?? 0;

/// How many keyword suggestions the search panel shows at once.
///
/// A panel, not a page: past about eight rows it stops being scannable and the
/// customer is reading a list instead of searching. The screen above it also
/// renders "search for `what I typed`" as its own first row, so this is on top
/// of that.
const int kSearchSuggestionLimit = 8;

/// How many products the "nothing matched" panel offers.
///
/// The same taste-not-a-catalog number as [kAudienceRailLimit] and
/// [kSearchSuggestionLimit] — it renders through the same rail.
const int kSearchRelatedLimit = 8;

/// How many products an audience rail (Men's / Women's / Kids') keeps.
///
/// The same taste-not-a-second-catalog rule the home preview uses
/// (`kHomePreviewCount`), and the same number on purpose: these strips sit
/// beside each other on the home feed, so a different cap would make one
/// visibly shorter for no reason a customer could see.
const int kAudienceRailLimit = 12;

/// The 'Best Sellers' set, derived live from the loaded catalog and the
/// `units_sold` aggregation. Single source of truth for BOTH the home rail and
/// the 'Best Sellers' filter, so the rail can never show a product the chip
/// excludes (or vice versa).
///
/// Rules:
/// - only products that have actually sold (units_sold > 0) — a brand-new
///   catalog yields an empty set, and the chip/rail hide themselves;
/// - most-sold first, so the rail and the filtered catalog agree on order;
/// - capped at [limit];
/// - ties break on rating then name, because the catalog list itself is
///   reshuffled per load and an unstable sort would reshuffle the rail too.
List<Map<String, dynamic>> bestSellerProducts(
  List<Map<String, dynamic>> products,
  Map<String, int> unitsSold, {
  int limit = kBestSellerLimit,
}) {
  final ranked = products.where((p) => unitsSoldOf(p, unitsSold) > 0).toList()
    ..sort((a, b) {
      final byUnits = unitsSoldOf(
        b,
        unitsSold,
      ).compareTo(unitsSoldOf(a, unitsSold));
      if (byUnits != 0) return byUnits;
      final rA = (a['avg_rating'] as num?)?.toDouble() ?? 0;
      final rB = (b['avg_rating'] as num?)?.toDouble() ?? 0;
      final byRating = rB.compareTo(rA);
      if (byRating != 0) return byRating;
      return (a['name'] ?? '').toString().compareTo(
        (b['name'] ?? '').toString(),
      );
    });
  return limit > 0 && ranked.length > limit ? ranked.sublist(0, limit) : ranked;
}

String sortModeLabel(SortMode mode) {
  switch (mode) {
    case SortMode.featured:
      return 'Featured';
    case SortMode.priceLowToHigh:
      return 'Price: Low to High';
    case SortMode.priceHighToLow:
      return 'Price: High to Low';
    case SortMode.nameAZ:
      return 'Name: A to Z';
    case SortMode.nameZA:
      return 'Name: Z to A';
    case SortMode.topRated:
      return 'Top Rated';
    case SortMode.bestSelling:
      return 'Best Selling';
  }
}

/// The same option said shortly — for the "The Workshop Collection" poster,
/// which shows the current sort in the corner of a card about a third of the
/// sheet's width.
///
/// Two labels rather than one, because the two surfaces are different sizes of
/// the same promise: the sheet has the room for `Price: Low to High` and is
/// where the customer is choosing, and the poster has room for `Low to High`
/// and is where they are *reading* which one is in force. Only the scoping
/// qualifier is dropped — `Feature`, `Top Rated` and `Best Selling` already read
/// whole at a glance, so shortening them further would change what they say.
///
/// It stays a second switch next to [sortModeLabel] rather than a field on the
/// enum so that both lists are exhaustive over [SortMode] and a new mode cannot
/// be added with a label but no short one (the compiler names the missing
/// case). `product_provider_test.dart` pins every pair.
String sortModeShortLabel(SortMode mode) {
  switch (mode) {
    case SortMode.featured:
      return 'Featured';
    case SortMode.priceLowToHigh:
      return 'Low to High';
    case SortMode.priceHighToLow:
      return 'High to Low';
    case SortMode.nameAZ:
      return 'A to Z';
    case SortMode.nameZA:
      return 'Z to A';
    case SortMode.topRated:
      return 'Top Rated';
    case SortMode.bestSelling:
      return 'Best Selling';
  }
}

class ProductProvider extends ChangeNotifier {
  final SupabaseService _db;

  List<Map<String, dynamic>> _products = [];
  bool _isLoading = false;
  String? _selectedCategory = 'All';
  SortMode _sortMode = SortMode.featured;

  /// product_id → total units sold across paid, non-cancelled orders.
  /// Loaded alongside the catalog; missing id = 0 units.
  Map<String, int> _unitsSold = const {};

  /// Owner of the seller-scoped catalog currently in [_products]: the user id
  /// that loaded it, and the store id it was scoped to. Both stay null while
  /// [_products] holds the all-stores catalog (the [loadProducts] path used by
  /// customers and admins). Recording the user is what stops a customer browse
  /// — or the next account's seller session — from reading as a cache hit.
  String? _sellerCatalogUserId;
  String? _sellerCatalogStoreId;

  /// The seller-catalog fetch in flight, if any. The Dashboard, POS and
  /// Products tabs all ask for this one catalog and can ask in the same frame;
  /// a late caller joins this future instead of firing a duplicate query.
  Future<void>? _sellerCatalogFetch;

  /// Why the last seller-catalog fetch failed, or null when it succeeded (or
  /// never ran). The Products tab renders its error card + Retry from this, now
  /// that the provider owns the fetch instead of the screen.
  Object? _sellerCatalogError;

  ProductProvider() : _db = SupabaseService.instance;

  /// Test seam: a provider seeded with a catalog + sold-count aggregation and
  /// no network access. Mirrors exactly what [loadProducts] leaves in memory
  /// (see [_stampUnitsSold]) so filtering/sorting can be asserted directly.
  @visibleForTesting
  ProductProvider.seeded({
    List<Map<String, dynamic>> products = const [],
    Map<String, int> unitsSold = const {},
  }) : _db = SupabaseService.instance {
    _products = products.map(Map<String, dynamic>.from).toList();
    _unitsSold = Map<String, int>.from(unitsSold);
    _stampUnitsSold();
  }

  /// Copy [units_sold] onto each product map so widgets that render products
  /// directly (product cards) can display it without reaching back into the
  /// provider.
  void _stampUnitsSold() {
    for (final p in _products) {
      p['units_sold'] = _unitsSold[p['id']?.toString()] ?? 0;
    }
  }

  List<Map<String, dynamic>> get products => _products;
  bool get isLoading => _isLoading;
  String? get selectedCategory => _selectedCategory;
  SortMode get sortMode => _sortMode;

  /// Why the last seller-catalog load failed, or null.
  Object? get sellerCatalogError => _sellerCatalogError;

  /// Whether [_products] is [userId]'s own seller-scoped catalog.
  ///
  /// Keyed on the user as well as the store: one-store-per-seller means a
  /// store id alone would let the NEXT account's session read this as a hit.
  bool _isSellerCatalogOf(String? userId) =>
      _sellerCatalogStoreId != null && _sellerCatalogUserId == userId;

  // Fetch all categories present in the products list, UNIONed with the
  // canonical [AppConstants.productCategories] (the same presets the seller
  // product form offers), so chips like Boots/Sneakers/Slip-ons are always
  // filterable even before any product uses them. Any category actually on a
  // product that isn't canonical (legacy values, custom entries) still shows
  // up, so nothing already filterable disappears. 'All' stays first and the
  // pseudo-categories are appended last, each only when it can actually offer
  // something: 'On Sale' when a product is actively on sale, 'Best Sellers'
  // when a product has sold at least one unit. Both act like filter chips, not
  // real categories — a dead-end chip is never rendered.
  List<String> get categories {
    final Set<String> uniqueCats = {'All'};
    uniqueCats.addAll(AppConstants.productCategories);
    for (var prod in _products) {
      if (prod.containsKey('category')) {
        uniqueCats.add(prod['category']);
      }
    }
    if (_products.any(isOnSale)) {
      uniqueCats.add('On Sale');
    }
    if (hasBestSellers) {
      uniqueCats.add(kBestSellersCategory);
    }
    return uniqueCats.toList();
  }

  /// The live best-seller set — most-sold first, never-sold excluded.
  ///
  /// Derived on every read from [_products] + [_unitsSold], so it always
  /// reflects the current aggregation rather than a stale cached snapshot.
  List<Map<String, dynamic>> get bestSellers =>
      bestSellerProducts(_products, _unitsSold);

  /// Whether the catalog holds any best seller at all — gates whether the
  /// 'Best Sellers' chip and the home rail are rendered.
  bool get hasBestSellers =>
      _products.any((p) => unitsSoldOf(p, _unitsSold) > 0);

  /// Products the customer can actually buy right now in [euSize], most-sold
  /// first — the "Based on your size" grid's source.
  ///
  /// The inclusion rule lives in `size_match.dart` ([stocksMySize]), so this
  /// rail and any later size surface (chip, badge, product-page pre-select)
  /// can never disagree about whether a product has the customer's size. It
  /// reuses the `inventory`/`units_sold` data the catalog already fetched — no
  /// second query, no schema change.
  ///
  /// [euSize] null (signed out, or a customer who never gave a size) returns
  /// EMPTY, never a guess or a fallback size: every size surface is
  /// absent-safe by design (plan §8 R6).
  ///
  /// Ranking is [_compareSuggestions] — units sold, then rating, then name, the
  /// same tie-break [bestSellerProducts] uses, so the per-load catalog shuffle
  /// cannot reorder the shelf under the customer. Unlike the best-seller rule, a
  /// product that has never sold still qualifies on its merits.
  ///
  /// **[limit] of 0 means the whole shelf**, the same convention
  /// [productsInAudience] and [productsInSearch] follow. It used to default to a
  /// rail-sized sample; the home section now decides its own preview length (ten
  /// cells plus a "See more" card) and asks for the *whole* shelf so that card
  /// can be honest about what is behind it.
  List<Map<String, dynamic>> productsInSize(double? euSize, {int limit = 0}) {
    if (euSize == null) return const [];

    final matches = _products.where((p) => stocksMySize(p, euSize)).toList()
      ..sort(_compareSuggestions);

    return limit > 0 && matches.length > limit
        ? matches.sublist(0, limit)
        : matches;
  }

  /// Products a seller stated as being for [audience], most-sold first — the
  /// Men's / Women's / Kids' home rails' source.
  ///
  /// Sibling of [productsInSize]: filter → rank → cap, so the per-load catalog
  /// shuffle can never reorder a rail under the customer.
  ///
  /// **`null` and `'unisex'` are skipped, never treated as "any audience".**
  /// A product whose audience is unset stays in the catalog, in search and in
  /// every category — it is only absent from these curated rails (stated data
  /// only, never inferred from the size band, plan §1.1). And a `unisex`
  /// product would otherwise be listed in Men's, Women's AND Kids' at once,
  /// putting one card three times down the feed (plan §4 R4).
  ///
  /// [audience] goes through [productAudienceFrom] and an unrecognised, empty
  /// or rail-ineligible value (`null`, `'unisex'`, garbage) returns EMPTY —
  /// never a default audience that would show the wrong customers a rail.
  List<Map<String, dynamic>> productsForAudience(
    String? audience, {
    int limit = kAudienceRailLimit,
  }) {
    final wanted = productAudienceFrom(audience);
    if (wanted == null || wanted == kUnisexAudience) return const [];

    final matches =
        _products
            .where(
              (p) => productAudienceFrom(p['audience']?.toString()) == wanted,
            )
            .toList()
          ..sort(_compareSuggestions);

    return limit > 0 && matches.length > limit
        ? matches.sublist(0, limit)
        : matches;
  }

  /// Products a seller stated as being for [audience], in an order the caller
  /// chooses — the audience **listing page**'s source.
  ///
  /// Deliberately NOT the same method as [productsForAudience], and the
  /// difference is the point:
  ///
  ///  * [productsForAudience] answers "what belongs in this rail?", where a
  ///    `unisex` product must be skipped or it would appear in Men's, Women's
  ///    and Kids' at once (§4 R4) and the rail caps its length anyway.
  ///  * this one answers "show me the [audience] shelf", which a customer
  ///    reached by tapping that audience's own chip. `'unisex'` is a real
  ///    answer there (it is the only way to see those products together), and
  ///    a page a customer opened deliberately is not capped.
  ///
  /// What the two DO share: products whose audience is unset are excluded from
  /// both. A `null` product is not part of any audience — it stays in the
  /// catalog, search and category browsing, untouched.
  ///
  /// [sort] defaults to [SortMode.featured] (the session's shuffled catalog
  /// order); the listing page passes its own, exactly like the search results
  /// page — passing one never re-sorts Home underneath it. [limit] of 0 means
  /// no cap, the same convention as [productsInSize] and [searchResults].
  List<Map<String, dynamic>> productsInAudience(
    String? audience, {
    SortMode? sort,
    int limit = 0,
  }) {
    final wanted = productAudienceFrom(audience);
    if (wanted == null) return const [];

    final matches = _products
        .where((p) => productAudienceFrom(p['audience']?.toString()) == wanted)
        .toList();
    final sorted = _applySort(matches, sort ?? SortMode.featured);

    return limit > 0 && sorted.length > limit
        ? sorted.sublist(0, limit)
        : sorted;
  }

  /// The audiences the catalog actually holds products for, in
  /// [productAudienceOptions] order — the Home category row's audience chips.
  ///
  /// Data-derived on purpose, the same rule the 'On Sale' and 'Best Sellers'
  /// chips already follow: an audience with no products is not offered, because
  /// a chip that can only ever lead to an empty page is worse than no chip.
  /// With every product in today's catalog `audience = null` this returns an
  /// empty list, so Home shows today's row until a seller tags something.
  ///
  /// A `unisex` product DOES surface here (unlike in the rails): it is the only
  /// way for a customer to reach those products as a group.
  List<String> get audiencesInCatalog {
    final found = <String>{};
    for (final product in _products) {
      final audience = productAudienceFrom(product['audience']?.toString());
      if (audience != null) found.add(audience);
    }
    return [
      for (final (value, _) in productAudienceOptions)
        if (found.contains(value)) value,
    ];
  }

  /// The ranking every suggestion rail shares — units sold, then rating, then
  /// name (the same tie-break [bestSellerProducts] uses). Kept in one place so
  /// "Based on your size" and the audience rails cannot drift into disagreeing about
  /// order, and so a tie is resolved the same way on every reload rather than
  /// inheriting the shuffled catalog order.
  int _compareSuggestions(Map<String, dynamic> a, Map<String, dynamic> b) {
    final byUnits = unitsSoldOf(
      b,
      _unitsSold,
    ).compareTo(unitsSoldOf(a, _unitsSold));
    if (byUnits != 0) return byUnits;
    final rA = (a['avg_rating'] as num?)?.toDouble() ?? 0;
    final rB = (b['avg_rating'] as num?)?.toDouble() ?? 0;
    final byRating = rB.compareTo(rA);
    if (byRating != 0) return byRating;
    return (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
  }

  /// Load ALL products (customer / admin screens).
  ///
  /// The fetched list is shuffled once right after the fetch so the default
  /// browse order (SortMode.featured) looks fresh each time — a "new
  /// products" feel without any backend change. Filtering and explicit sort
  /// modes still operate on this shuffled base list, so search/category/sort
  /// behavior is unaffected.
  ///
  /// [reshuffle] defaults to true: every load (including pull-to-refresh)
  /// produces a new order. Set to false if a caller wants to preserve the
  /// current session's shuffled order.
  ///
  /// [hideOutOfStock] removes products with no stock on any size — used by
  /// customer browse screens so out-of-stock items disappear from the
  /// catalog and reappear automatically once a seller restocks them.
  /// Sellers and admins keep the full list (default false).
  Future<void> loadProducts({
    bool reshuffle = true,
    bool hideOutOfStock = false,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Fetch the catalog and the units-sold aggregation in parallel —
      // the sold counts power the Best Selling sort mode.
      final results = await Future.wait([
        _db.fetchProducts(hideOutOfStock: hideOutOfStock),
        _db.fetchUnitsSold().catchError((_) => <String, int>{}),
      ]);
      _products = results[0] as List<Map<String, dynamic>>;
      _unitsSold = results[1] as Map<String, int>;
      _stampUnitsSold();
      // This is the all-stores catalog, not a seller-scoped one: drop the
      // seller cache identity so a later seller tab fetches its own scoped
      // list instead of mistaking these rows for its store's cache.
      _sellerCatalogUserId = null;
      _sellerCatalogStoreId = null;
      _sellerCatalogError = null;
      if (reshuffle) {
        _products.shuffle();
      }
    } catch (_) {
      // Gracefully handle empty
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Load only the current seller's products (POS / seller screens).
  ///
  /// Cache-aware and non-destructive — the two properties that let the
  /// Dashboard, POS and Products tabs share ONE fetch:
  ///
  ///  * **A cache hit is free.** When this seller's catalog is already in
  ///    [products], this returns without a store lookup, without a catalog
  ///    query and deliberately without a `notifyListeners()` — so switching to
  ///    a tab that already has the data cannot repaint (or flash a skeleton
  ///    over) it.
  ///  * **A fetch never clears what is on screen.** The previous rows stay
  ///    until the new ones arrive; only a seller with nothing to show yet sees
  ///    the loading state. This is why POS/Products no longer blank out on
  ///    every load.
  ///  * **Concurrent callers share one request.** The Dashboard's
  ///    `Future.wait` and POS's `initState` both arrive within the same frame;
  ///    they join the in-flight fetch instead of stacking two duplicate
  ///    catalog queries.
  ///
  /// Pass [force] to refetch over a warm cache — pull-to-refresh, or after a
  /// write. The current rows stay visible while it runs.
  ///
  /// Fetches the seller's store ID via [ProductService] and passes it to
  /// [SupabaseService.fetchProducts] so the query is server-side scoped.
  /// A seller with no store yields an empty list rather than every store's
  /// products.
  Future<void> loadSellerProducts({bool force = false}) {
    final userId = _db.currentUser?.id;

    if (!force && _isSellerCatalogOf(userId)) return Future.value();

    final inFlight = _sellerCatalogFetch;
    if (inFlight != null) {
      // A forced refetch exists to observe a write that just landed, so it
      // cannot simply join a fetch that may have STARTED before that write and
      // will return pre-write rows. Queue a fresh one behind it instead. An
      // unforced caller has no such obligation, so it joins.
      if (!force) return inFlight;
      return inFlight.whenComplete(() => loadSellerProducts(force: true));
    }

    final fetch = _fetchSellerProducts();
    _sellerCatalogFetch = fetch;
    return fetch.whenComplete(() {
      // Only the fetch that is still registered clears the slot, so a caller
      // that force-refreshes mid-flight is never left thinking one is running.
      if (identical(_sellerCatalogFetch, fetch)) _sellerCatalogFetch = null;
    });
  }

  /// The actual seller-catalog fetch. Never call directly — go through
  /// [loadSellerProducts] so the cache check and in-flight coalescing apply.
  Future<void> _fetchSellerProducts() async {
    final userId = _db.currentUser?.id;

    // Anything that is NOT this seller's own catalog has to go before the
    // fetch resolves. The provider is an app-root singleton shared across
    // roles: a prior customer browse (`loadProducts()`) or a previous account's
    // seller session can have left a different list in memory, and showing it
    // under the seller's Products/POS tab would be wrong (and a cross-account
    // leak). Rows belonging to THIS seller are the only ones allowed to
    // survive a refresh.
    if (!_isSellerCatalogOf(userId)) {
      _products = [];
      _sellerCatalogUserId = null;
      _sellerCatalogStoreId = null;
    }

    // Loading state only when there is genuinely nothing to show. With rows
    // already on screen this is a quiet background refresh — that is the whole
    // point of the cache.
    if (_products.isEmpty) {
      _isLoading = true;
      _sellerCatalogError = null;
      notifyListeners();
    }

    try {
      // Timed separately from the catalog query below: this is an extra
      // serialised round trip in front of every seller catalog load, so it is
      // worth being able to see its cost on its own in the export.
      final storeId = await PerfTrace.span(
        'catalog:seller store lookup',
        ProductService.instance.getSellerStoreId,
      );
      if (storeId == null) {
        // Seller has no store — keep empty, don't leak all products.
        // MUST clear the loading flag here (no fall-through past the try).
        _products = [];
        _sellerCatalogUserId = null;
        _sellerCatalogStoreId = null;
        _sellerCatalogError = null;
        _isLoading = false;
        notifyListeners();
        return;
      }
      final fetched = await _db.fetchProducts(storeId: storeId);
      // Defense in depth: even if the query ever drifted, only keep products
      // that actually belong to this seller's store. Other sellers' products
      // can never appear (their store_id differs). Products in this store
      // with a NULL seller_id (e.g. admin-seeded) stay visible; rows tagged
      // with a DIFFERENT seller are dropped as not owned.
      _products = fetched.where((p) {
        final belongsToStore = p['store_id']?.toString() == storeId;
        if (!belongsToStore) return false;
        if (userId == null) return true; // no user context — store only
        final ownerId = p['seller_id']?.toString();
        return ownerId == null || ownerId == userId;
      }).toList();
      _sellerCatalogUserId = userId;
      _sellerCatalogStoreId = storeId;
      _sellerCatalogError = null;
    } catch (e) {
      // A failed fetch must NEVER leave another store's products on screen.
      // This seller's OWN rows are safe to keep: a refresh that fails should
      // not blank a grid the seller is already looking at.
      debugPrint('[ProductProvider] loadSellerProducts failed: $e');
      if (!_isSellerCatalogOf(userId)) _products = [];
      _sellerCatalogError = e;
    }

    _isLoading = false;
    PerfTrace.mark('catalog:seller ready (${_products.length} products)');
    notifyListeners();
  }

  /// Drop [id] from the in-memory catalog after a successful delete.
  ///
  /// The Products grid owns the delete flow and used to prune its own copy of
  /// the list; with the provider as the single source of truth the prune has to
  /// land here. Saves refetching the whole catalog just to lose one card.
  void removeProductLocally(dynamic id) {
    final key = id?.toString();
    final before = _products.length;
    _products.removeWhere((p) => p['id']?.toString() == key);
    if (_products.length != before) notifyListeners();
  }

  /// Replace [id]'s stock in place after an Adjust Stock save, so the grid's
  /// badges and filters update without a refetch (and without a reload tearing
  /// down the still-open editor sheet).
  ///
  /// Writes BOTH surfaces: the raw `inventory` relation the seller grid reads,
  /// and the mapped `sizes` map every other surface (POS tiles, customer size
  /// selectors) reads — keeping them in step the same way [_mapProduct] does.
  void applyStockLocally(dynamic id, Map<String, int> sizes) {
    final key = id?.toString();
    final index = _products.indexWhere((p) => p['id']?.toString() == key);
    if (index == -1) return;
    final updated = Map<String, dynamic>.from(_products[index]);
    updated['inventory'] = sizes.entries
        .map((e) => {'size': e.key, 'stock': e.value})
        .toList();
    updated['sizes'] = Map<String, int>.from(sizes);
    _products[index] = updated;
    notifyListeners();
  }

  /// Set the sort mode and rebuild the UI.
  void setSortMode(SortMode mode) {
    _sortMode = mode;
    notifyListeners();
  }

  /// Total units sold for a product (paid, non-cancelled orders).
  /// Returns 0 for products never sold or not in the last aggregation.
  int unitsSoldFor(String productId) => _unitsSold[productId] ?? 0;

  /// Returns the EFFECTIVE price (sale-aware) from a product map.
  ///
  /// Delegates to the shared [isOnSale]/[effectivePrice] helpers so the
  /// active-sale rule stays in one place (sale_price.dart). This single
  /// change makes price sorting correct under active sales.
  double _extractPrice(Map<String, dynamic> product) => effectivePrice(product);

  /// Whether a product is currently on sale (delegates to the shared helper).
  bool isProductOnSale(Map<String, dynamic> product) => isOnSale(product);

  /// The price the customer pays right now (delegates to the shared helper).
  double productEffectivePrice(Map<String, dynamic> product) =>
      effectivePrice(product);

  /// Filtered + sorted products list.
  List<Map<String, dynamic>> getFilteredProducts(String searchKeyword) {
    List<Map<String, dynamic>> filtered = _products;

    // Category filter — 'On Sale' and 'Best Sellers' are pseudo-categories
    // that filter by a derived rule (active sale / live units sold) instead of
    // the product's category field, and they behave identically to one
    // another. Each rule is only applied while it currently yields something:
    // its chip is hidden the moment it doesn't, so the branch below is only
    // reachable if the data changed under a selected chip (sale expired, a
    // reload dropped the units-sold aggregation). That state degrades exactly
    // like a category with no matching products — the empty state, whose
    // "browse all" action clears the selection.
    final bool saleFilterActive =
        _selectedCategory == 'On Sale' && _products.any(isOnSale);
    final bool bestSellerFilterActive =
        _selectedCategory == kBestSellersCategory && hasBestSellers;
    if (saleFilterActive) {
      filtered = filtered.where((p) => isOnSale(p)).toList();
    } else if (bestSellerFilterActive) {
      final bestSellerIds = bestSellers.map((p) => p['id']?.toString()).toSet();
      filtered = filtered
          .where((p) => bestSellerIds.contains(p['id']?.toString()))
          .toList();
    } else if (_selectedCategory != 'All' && _selectedCategory != null) {
      filtered = filtered
          .where((p) => p['category'] == _selectedCategory)
          .toList();
    }

    // Search keyword — matches the product NAME or any of its TAGS.
    // The name keeps its exact-substring behavior; tags additionally match
    // per-word, so a multi-word query like "handmade leather" finds
    // products tagged with any of those words.
    if (searchKeyword.isNotEmpty) {
      final query = searchKeyword.trim().toLowerCase();
      final words = query
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      filtered = filtered.where((p) {
        final name = (p['name'] ?? '').toString().toLowerCase();
        if (name.contains(query)) return true;
        // Tag match: any whitespace-separated word of the query as a
        // substring of any tag (covers single-word "leather" and
        // multi-word "handmade leather" queries alike).
        final tags = p['tags'];
        if (tags is List) {
          for (final tag in tags) {
            final tagText = tag.toString().toLowerCase();
            if (words.any((w) => tagText.contains(w))) return true;
          }
        }
        return false;
      }).toList();
    }

    return _applySort(filtered, _sortMode);
  }

  /// Products matching a customer's search [query], most relevant first — the
  /// search results page's source.
  ///
  /// **No query, no network**: the catalog is already loaded, so this filters
  /// the same list Home renders. The matching rule itself lives in
  /// `product_search.dart` ([matchesSearchQuery]) so this and the suggestion
  /// panel can never disagree about what a query means.
  ///
  /// [category] is an optional second filter (the results page's category
  /// chips); null means every category. [sort] defaults to the current catalog
  /// sort — the results page passes its own, and passing one does NOT change
  /// what Home is sorted by. [limit] of 0 means no cap, exactly like
  /// [productsInSize].
  List<Map<String, dynamic>> searchResults(
    String query, {
    String? category,
    SortMode? sort,
    int limit = 0,
  }) {
    final matches = _products
        .where(
          (p) =>
              matchesSearchQuery(p, query) &&
              (category == null || p['category'] == category),
        )
        .toList();

    final sorted = _applySort(matches, sort ?? _sortMode);
    return limit > 0 && sorted.length > limit
        ? sorted.sublist(0, limit)
        : sorted;
  }

  /// The distinct categories this query's matches actually fall into — the
  /// search results page's chip list, alphabetical.
  ///
  /// Derived from the matches **before** any category filter, and only from
  /// categories that matched something. Deliberately not [categories]: that is
  /// the whole catalog's vocabulary — it starts with `'All'` (which this page
  /// renders itself, so listing it again produced two of them), it always
  /// contains `AppConstants.productCategories` whether or not anything is in
  /// them, and it appends the 'On Sale' / 'Best Sellers' pseudo-categories. A
  /// chip that can only lead to "0 results" is worse than no chip.
  List<String> searchCategories(String query) {
    final found = <String>{};
    for (final product in _products) {
      if (!matchesSearchQuery(product, query)) continue;
      final category = product['category']?.toString() ?? '';
      if (category.isNotEmpty) found.add(category);
    }
    return found.toList()..sort();
  }

  /// A [shelf] — a list this provider already derived ([productsInSize], an
  /// audience, the on-sale set, a rail) — narrowed by a search [query] and a
  /// [category], then ordered by [sort]. The shelf listing pages' one answer to
  /// "what do search, filter and sort mean on a list that is not the catalog".
  ///
  /// **The catalog's own rules, not new ones.** The term goes through
  /// [matchesSearchQuery] — the same rule the search page and its suggestion
  /// panel use, so a word means one thing everywhere in the app — and the order
  /// goes through [_applySort], so the same products read the same way on Home,
  /// in search and on a shelf. Nothing here writes to the catalog: a shelf page
  /// narrowing its own list can never re-sort or re-filter the feed underneath
  /// it.
  ///
  /// [sort] of null (or [SortMode.featured]) keeps the shelf's own order — the
  /// ranking [productsInSize] returns, the catalog order the home feed shows —
  /// which is what "Featured" has always meant on a listing page.
  List<Map<String, dynamic>> shelfProducts(
    List<Map<String, dynamic>> shelf, {
    String query = '',
    String? category,
    SortMode? sort,
  }) {
    final term = query.trim();
    final matches = shelf
        .where(
          (p) =>
              (term.isEmpty || matchesSearchQuery(p, term)) &&
              (category == null || p['category'] == category),
        )
        .toList();

    return _applySort(matches, sort ?? SortMode.featured);
  }

  /// The distinct categories a [shelf] actually holds, alphabetical — the chip
  /// list its listing page offers.
  ///
  /// Derived from the shelf itself, never from [categories]: that is the whole
  /// catalog's vocabulary, includes categories with nothing in them and appends
  /// the 'On Sale' / 'Best Sellers' pseudo-categories. A chip beside a shelf
  /// that can only lead to an empty grid is worse than no chip — the same rule
  /// [searchCategories] follows for a query.
  List<String> shelfCategories(List<Map<String, dynamic>> shelf) {
    final found = <String>{};
    for (final product in shelf) {
      final category = product['category']?.toString() ?? '';
      if (category.isNotEmpty) found.add(category);
    }
    return found.toList()..sort();
  }

  /// Keyword suggestions for a partially typed query — the search panel's
  /// source. Delegates to [searchSuggestionsFor] so the rule is testable
  /// without a provider.
  List<SearchSuggestion> suggestionsFor(
    String query, {
    int limit = kSearchSuggestionLimit,
  }) => searchSuggestionsFor(_products, query: query, limit: limit);

  /// What to offer when a search matched nothing: the catalog's own picks,
  /// most-sold then best-rated then name.
  ///
  /// Deliberately **not** "similar to your query" — a query that matched
  /// nothing is a query whose words appear nowhere in the catalog (name, tag or
  /// category), so there is nothing similar to compute from. Rather than invent
  /// a similarity, this shows the shop's own best, which is honest and — unlike
  /// a text-overlap heuristic — can never include something the customer was
  /// already told does not exist. Empty only when the catalog is.
  List<Map<String, dynamic>> relatedProducts({
    int limit = kSearchRelatedLimit,
  }) {
    final sorted = List<Map<String, dynamic>>.from(_products)
      ..sort(_compareSuggestions);
    return limit > 0 && sorted.length > limit
        ? sorted.sublist(0, limit)
        : sorted;
  }

  /// The catalog sort, in one place: [getFilteredProducts] and [searchResults]
  /// must order the same way, or the same products would read differently on
  /// Home and on the results page.
  List<Map<String, dynamic>> _applySort(
    List<Map<String, dynamic>> items,
    SortMode mode,
  ) {
    final sorted = List<Map<String, dynamic>>.from(items);
    switch (mode) {
      // Featured = the shuffled order from loadProducts(); no-op here so the
      // session's shuffle is preserved (never re-sorted per keystroke).
      case SortMode.featured:
        break;
      case SortMode.priceLowToHigh:
        sorted.sort((a, b) => _extractPrice(a).compareTo(_extractPrice(b)));
      case SortMode.priceHighToLow:
        sorted.sort((a, b) => _extractPrice(b).compareTo(_extractPrice(a)));
      case SortMode.nameAZ:
        sorted.sort(
          (a, b) => (a['name'] ?? '').toString().compareTo(
            (b['name'] ?? '').toString(),
          ),
        );
      case SortMode.nameZA:
        sorted.sort(
          (a, b) => (b['name'] ?? '').toString().compareTo(
            (a['name'] ?? '').toString(),
          ),
        );
      case SortMode.topRated:
        sorted.sort((a, b) {
          final rA = (a['avg_rating'] as num?)?.toDouble() ?? 0;
          final rB = (b['avg_rating'] as num?)?.toDouble() ?? 0;
          // Higher rating first; ties break toward more reviews so a
          // 5.0 from one review doesn't beat 4.8 from forty.
          final c = rB.compareTo(rA);
          if (c != 0) return c;
          final nA = (a['review_count'] as num?)?.toInt() ?? 0;
          final nB = (b['review_count'] as num?)?.toInt() ?? 0;
          return nB.compareTo(nA);
        });
      case SortMode.bestSelling:
        sorted.sort((a, b) {
          final idA = a['id']?.toString() ?? '';
          final idB = b['id']?.toString() ?? '';
          final uA = _unitsSold[idA] ?? 0;
          final uB = _unitsSold[idB] ?? 0;
          return uB.compareTo(uA);
        });
    }

    return sorted;
  }

  void selectCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  /// Reload the product list after a write, scoped to the current user's
  /// role.
  ///
  /// The provider is an app-root singleton shared across roles. A seller's
  /// write (add / update / Adjust Stock) must NOT reload the full catalog:
  /// `loadProducts()` fetches every store's products, and the POS/dashboard
  /// render from this same provider — so after a stock adjustment the seller
  /// would suddenly see products that don't belong to them. If the current
  /// user owns a store, reload seller-scoped; otherwise (customer/admin
  /// browsing context) fall back to the full catalog.
  ///
  /// Best-effort: errors are swallowed so a reload hiccup can never flip a
  /// successful DB write into a reported failure — and on failure the
  /// in-memory list simply stays as it was (already seller-scoped for
  /// sellers, so nothing leaks).
  Future<void> _reloadAfterWrite() async {
    try {
      final storeId = await ProductService.instance.getSellerStoreId();
      if (storeId != null) {
        // Forced: a write just landed, so the warm cache is known-stale and
        // has to be re-read. [loadSellerProducts] keeps the current rows on
        // screen while it refetches.
        await loadSellerProducts(force: true);
      } else {
        await loadProducts();
      }
    } catch (e) {
      debugPrint('[ProductProvider] post-write reload failed: $e');
    }
  }

  // Add Product (UC015)
  Future<bool> addProduct(Map<String, dynamic> productData) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _db.addProduct(productData);
      await _reloadAfterWrite();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (_) {
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Update Product (UC015)
  Future<bool> updateProduct(
    dynamic id,
    Map<String, dynamic> productData,
  ) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _db.updateProduct(id, productData);
      await _reloadAfterWrite();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      // Log the real reason (e.g. PostgrestException code/message) so a
      // failed write is never a silent dead end during debugging.
      debugPrint('[ProductProvider] updateProduct failed for $id: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Delete Product (UC015)
  Future<bool> deleteProduct(dynamic id) async {
    try {
      await _db.deleteProduct(id);
      await _reloadAfterWrite();
      return true;
    } catch (_) {
      return false;
    }
  }
}
