import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../constants/app_constants.dart';
import '../../../providers/product_provider.dart';
import '../../../services/search_history_service.dart';
import '../../../utils/product_search.dart';
import 'search_results_screen.dart';

/// Full-screen search page (Shopee-style) opened when the home search bar is
/// tapped.
///
/// Layout:
///   • Top bar: back arrow + search field with a clear button and a filled
///     search button
///   • **While typing: a suggestion panel** — "search for what I typed", then
///     catalog-derived keyword suggestions (categories, tags, product names)
///   • Empty field: "Recently Searched" history chips + trash (clear all), then
///     "Search Discovery" trending chips (🔥-tagged)
///
/// **Nothing here filters the Home feed.** Committing a term pushes
/// [SearchResultsScreen] on top of this page, so Back returns to the search
/// field with the term still in it, and Back again returns to a Home feed
/// showing the whole catalog. The previous version popped a term back to Home,
/// which filtered the feed in place and left the customer inside a search with
/// no clear button and no way back out — the trap this page no longer creates.
class ProductSearchScreen extends StatefulWidget {
  const ProductSearchScreen({super.key, this.initialQuery = ''});

  /// Pre-fills the field (e.g. re-opening search on an existing term).
  final String initialQuery;

  @override
  State<ProductSearchScreen> createState() => _ProductSearchScreenState();
}

class _ProductSearchScreenState extends State<ProductSearchScreen> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  List<String> _recent = [];
  bool _loading = true;
  bool _showAllRecent = false;

  // Discovery suggestions — static for now; these read as trending terms.
  static const _discovery = <String>[
    'Leather Sandals',
    'Loafers',
    'Sneakers',
    'Boots',
    'Formal Shoes',
    'Slip-ons',
    'School Shoes',
    'Bridal Shoes',
    'Custom Leather',
  ];

  /// Which discovery chips get the 🔥 "hot" marker — deterministic pseudo-
  /// random pick so it's stable across rebuilds but looks curated.
  static final Set<int> _hotIndices = () {
    final rng = Random(7);
    return {
      for (final i in List.generate(_discovery.length, (i) => i))
        if (rng.nextDouble() < 0.3) i,
    };
  }();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final terms = await SearchHistoryService.instance.history();
    if (!mounted) return;
    setState(() {
      _recent = terms;
      _loading = false;
    });
    // Auto-open the keyboard like modern search pages.
    FocusScope.of(context).requestFocus(_focusNode);
  }

  /// Record [term] and show its results. The page stays underneath, so Back
  /// lands on this field with the term still in it.
  Future<void> _commit(String term) async {
    final t = term.trim();
    if (t.isEmpty) return;
    SearchHistoryService.instance.record(t);
    _focusNode.unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchResultsScreen(initialQuery: t),
      ),
    );
    // Coming back, the term just searched belongs at the top of the history.
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopBar(),
            Divider(height: 1, color: AppConstants.borderGray),
            Expanded(
              child: _loading
                  ? const SizedBox.shrink()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: query.isNotEmpty
                            ? _buildSuggestionSection(query)
                            : _buildDiscoverySections(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Discovery state: recents + trending (no typing yet) ──

  List<Widget> _buildDiscoverySections() {
    return [
      if (_recent.isNotEmpty) ...[
        _buildSectionHeader(
          title: 'Recently Searched',
          trailing: GestureDetector(
            onTap: () async {
              await SearchHistoryService.instance.clear();
              await _load();
            },
            child: Icon(
              Icons.delete_outline,
              size: 20,
              color: AppConstants.secondary.withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildChipWrap(
          terms: _showAllRecent ? _recent : _recent.take(6).toList(),
          onTap: _commit,
        ),
        if (_recent.length > 6)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: () =>
                  setState(() => _showAllRecent = !_showAllRecent),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _showAllRecent ? 'Less' : 'More',
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: AppConstants.secondary.withValues(alpha: 0.6),
                    ),
                  ),
                  Icon(
                    _showAllRecent
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 18,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 24),
      ],
      _buildSectionHeader(title: 'Search Discovery'),
      const SizedBox(height: 10),
      _buildChipWrap(
        terms: _discovery,
        onTap: _commit,
        hotIndices: _hotIndices,
      ),
    ];
  }

  // ── Typing state: what this query could mean ──

  List<Widget> _buildSuggestionSection(String query) {
    final suggestions = context.watch<ProductProvider>().suggestionsFor(query);

    return [
      _buildSectionHeader(title: 'Suggestions'),
      const SizedBox(height: 6),
      // The query itself, always first: tapping it is the plain "search what I
      // typed" the customer may have meant all along.
      _suggestionRow(
        key: const ValueKey('search-suggestion-query'),
        term: query,
        leading: Icons.search,
        highlightPrefix: null,
        onTap: () => _commit(query),
      ),
      for (final suggestion in suggestions)
        _suggestionRow(
          // Keyed so a test (and a future golden) can target a row without
          // depending on how its text happens to be split into spans.
          key: ValueKey('search-suggestion-${suggestion.term}'),
          term: suggestion.term,
          leading: switch (suggestion.kind) {
            SearchSuggestionKind.category => Icons.category_outlined,
            SearchSuggestionKind.tag => Icons.sell_outlined,
            SearchSuggestionKind.product => Icons.image_outlined,
          },
          // The bit they typed is emphasised, so a row reads as "this is why
          // you're seeing it".
          highlightPrefix: query,
          onTap: () => _commit(suggestion.term),
        ),
      if (suggestions.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(
            'No suggestions for that — try "sandals", "leather" or "boots".',
            style: AppConstants.bodyStyle(
              fontSize: 13,
              color: AppConstants.secondary.withValues(alpha: 0.55),
            ),
          ),
        ),
    ];
  }

  Widget _suggestionRow({
    Key? key,
    required String term,
    required IconData leading,
    required String? highlightPrefix,
    required VoidCallback onTap,
  }) {
    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Icon(
                leading,
                size: 17,
                color: AppConstants.secondary.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 12),
              Expanded(child: _highlighted(term, highlightPrefix)),
              Icon(
                Icons.north_west,
                size: 15,
                color: AppConstants.secondary.withValues(alpha: 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [term] with the typed part in bold ink — the rest stays muted.
  Widget _highlighted(String term, String? prefix) {
    final base = AppConstants.bodyStyle(
      fontSize: 14,
      color: AppConstants.secondary.withValues(alpha: 0.75),
    );
    final typed = prefix?.trim() ?? '';
    final index =
        typed.isEmpty ? -1 : term.toLowerCase().indexOf(typed.toLowerCase());
    if (index < 0) return Text(term, style: base);

    return RichText(
      text: TextSpan(
        style: base,
        children: [
          if (index > 0) TextSpan(text: term.substring(0, index)),
          TextSpan(
            text: term.substring(index, index + typed.length),
            style: base.copyWith(
              fontWeight: FontWeight.bold,
              color: AppConstants.secondary,
            ),
          ),
          if (index + typed.length < term.length)
            TextSpan(text: term.substring(index + typed.length)),
        ],
      ),
    );
  }

  // ── Top bar: back + field + clear + filled search button ──────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: AppConstants.secondary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                color: AppConstants.surfaceLight,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppConstants.secondary,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      autofocus: false,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _commit,
                      onChanged: (_) => setState(() {}),
                      style: AppConstants.bodyStyle(
                        fontSize: 15,
                        color: AppConstants.secondary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search leather shoes…',
                        hintStyle: AppConstants.bodyStyle(
                          fontSize: 15,
                          color:
                              AppConstants.secondary.withValues(alpha: 0.4),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 12),
                      ),
                    ),
                  ),
                  if (_controller.text.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(_controller.clear),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: AppConstants.secondary.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  // Filled search button (dark square, like the reference)
                  GestureDetector(
                    onTap: () => _commit(_controller.text),
                    child: Container(
                      width: 52,
                      height: double.infinity,
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AppConstants.secondary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.search,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({required String title, Widget? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: AppConstants.headlineStyle(fontSize: 17),
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _buildChipWrap({
    required List<String> terms,
    required ValueChanged<String> onTap,
    Set<int> hotIndices = const {},
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (int i = 0; i < terms.length; i++)
          GestureDetector(
            onTap: () => onTap(terms[i]),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: AppConstants.surfaceLight,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: AppConstants.borderGray.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hotIndices.contains(i)) ...[
                    const Text('🔥', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    terms[i],
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: AppConstants.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
