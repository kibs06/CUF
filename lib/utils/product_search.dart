/// The customer search rule: what a typed query matches, and what to suggest
/// while it is still being typed.
///
/// Pure Dart, no Flutter — the same precedent as `size_key.dart`,
/// `product_audience.dart` and `size_match.dart`, so the rule is unit-testable
/// without a widget harness.
///
/// **Why a new rule rather than the catalog filter.** `ProductProvider
/// .getFilteredProducts()` matches the whole query against a product's name and
/// each query word against its tags. That is correct for filtering an
/// already-narrowed catalog, but it made the customer's search a dead end:
/// "Formal Shoes" found nothing at all, because `Formal` is a **category** —
/// the catalog's own word for those products — and no product is *named* it or
/// *tagged* it. Searching the catalog with the catalog's own vocabulary has to
/// work, so [matchesSearchQuery] adds the category, and matches names per word
/// as well as by whole phrase.
library;

/// A query split into its lowercase words — `'Formal  Shoes '` →
/// `['formal', 'shoes']`. Empty for a blank query.
///
/// Lowercasing happens once here so every comparison downstream can use `==`
/// and `contains` directly, and so `'Formal'` and `'formal'` cannot match
/// differently on two surfaces.
List<String> searchWords(String query) => query
    .toLowerCase()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .toList();

/// Whether [product] matches [query].
///
/// A product matches when **any** of these holds:
///
///  * its name contains the whole query (`'formal derby'` → "Formal Derby");
///  * its name contains any query word (so `'leather formal'` still finds
///    "Formal Leather Derby");
///  * its **category** contains any query word — the one that stops
///    "Formal Shoes" being a dead end, since `Formal` is a category value;
///  * one of its **tags** contains any query word (the previous rule, kept).
///
/// Any single word matching is enough, so a two-word query is a wider net than
/// either word alone — the opposite of an AND, deliberately: a customer typing
/// more words is narrowing in their head, not asking for a conjunction, and an
/// empty page is the worse failure.
///
/// A blank query matches **nothing** (not everything): "no query" is not a
/// search, and a caller that wants the whole catalog should ask for the
/// catalog. Unknown fields (no `category`, `tags` not a list) simply do not
/// match.
bool matchesSearchQuery(Map<String, dynamic> product, String query) {
  final words = searchWords(query);
  if (words.isEmpty) return false;

  final name = (product['name'] ?? '').toString().toLowerCase();
  final category = (product['category'] ?? '').toString().toLowerCase();
  final tags = product['tags'] is List
      ? (product['tags'] as List).map((t) => t.toString().toLowerCase()).toList()
      : const <String>[];

  if (name.contains(query.trim().toLowerCase())) return true;

  for (final word in words) {
    if (name.contains(word)) return true;
    if (category.isNotEmpty && category.contains(word)) return true;
    if (tags.any((tag) => tag.contains(word))) return true;
  }
  return false;
}

/// What a suggestion *is*, so the panel can label it without guessing from the
/// string.
enum SearchSuggestionKind {
  /// A catalog category (`Formal`) — searching it returns that whole shelf.
  category,

  /// A product tag (`handmade`) — searching it returns every tagged product.
  tag,

  /// A product name — searching it returns that product.
  product,
}

/// One row of the search-suggestion panel: a term to run, and what it is.
typedef SearchSuggestion = ({String term, SearchSuggestionKind kind});

/// Ranked search suggestions for a partially typed [query], derived from the
/// catalog already in memory — **no query, no network**, so the panel can
/// update on every keystroke.
///
/// Candidates are the categories, tags and product names whose text contains
/// any typed word. Ranking, in order:
///
///  1. **prefix before substring** — typing `boo` should offer `Boots` above
///     `School Shoes`; matching the start of a word is a stronger signal than
///     matching its middle;
///  2. **popularity** — how many products the term would return, so a live
///     category outranks a tag used once;
///  3. **kind** — categories, then tags, then product names;
///  4. **alphabetical**, so the order is stable between rebuilds.
///
/// The typed query itself is never returned as a suggestion (the panel renders
/// "search for what I typed" as its own first row), and a blank query returns
/// nothing — the panel shows recent/trending terms instead.
List<SearchSuggestion> searchSuggestionsFor(
  List<Map<String, dynamic>> products, {
  required String query,
  int limit = 8,
}) {
  final words = searchWords(query);
  if (words.isEmpty || limit <= 0) return const [];

  // term (lowercased) → (display term, kind, products it would return)
  final counts = <String, ({String term, SearchSuggestionKind kind, int count})>{};

  void consider(String rawTerm, SearchSuggestionKind kind) {
    final term = rawTerm.trim();
    if (term.isEmpty) return;
    final lower = term.toLowerCase();
    // The thing they already typed is not a suggestion.
    if (lower == query.trim().toLowerCase()) return;
    if (!words.any((w) => lower.contains(w))) return;
    final existing = counts[lower];
    counts[lower] = (
      term: existing?.term ?? term,
      kind: existing?.kind ?? kind,
      count: (existing?.count ?? 0) + 1,
    );
  }

  for (final product in products) {
    // Category/tag are per-value, not per-product, so they are deduped by the
    // map above while still counting how many products back them.
    final category = product['category']?.toString() ?? '';
    if (category.isNotEmpty) consider(category, SearchSuggestionKind.category);
    final tags = product['tags'];
    if (tags is List) {
      for (final tag in tags) {
        consider(tag.toString(), SearchSuggestionKind.tag);
      }
    }
    final name = product['name']?.toString() ?? '';
    if (name.isNotEmpty) consider(name, SearchSuggestionKind.product);
  }

  bool startsAWord(String term) {
    final lower = term.toLowerCase();
    // Prefix of any typed word, at a word boundary in the candidate.
    for (final word in words) {
      if (lower.startsWith(word)) return true;
      if (RegExp('(^|\\s)${RegExp.escape(word)}').hasMatch(lower)) return true;
    }
    return false;
  }

  final ranked = counts.values.toList()
    ..sort((a, b) {
      final byPrefix = (startsAWord(b.term) ? 1 : 0)
          .compareTo(startsAWord(a.term) ? 1 : 0);
      if (byPrefix != 0) return byPrefix;
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) return byCount;
      final byKind = a.kind.index.compareTo(b.kind.index);
      if (byKind != 0) return byKind;
      return a.term.toLowerCase().compareTo(b.term.toLowerCase());
    });

  return ranked
      .take(limit)
      .map((c) => (term: c.term, kind: c.kind))
      .toList();
}
