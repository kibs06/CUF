import 'dart:math';

import 'package:flutter/material.dart';
import '../../../constants/app_constants.dart';
import '../../../services/search_history_service.dart';

/// Full-screen search page (Shopee-style) opened when the home search bar
/// is tapped.
///
/// Layout:
///   • Top bar: back arrow + search field with a filled search button
///   • "Recently Searched" — history chips + trash (clear all)
///   • "Search Discovery" — trending suggestion chips (🔥-tagged)
///
/// Choosing a term pops back and hands it to [onSearchSelected]; the home
/// screen applies it as the active keyword.
class ProductSearchScreen extends StatefulWidget {
  const ProductSearchScreen({
    super.key,
    this.initialQuery = '',
    required this.onSearchSelected,
  });

  /// Pre-fills the field (e.g. the user had already typed something).
  final String initialQuery;

  /// Called with the chosen term before popping back to the home screen.
  final ValueChanged<String> onSearchSelected;

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

  void _commit(String term) {
    final t = term.trim();
    if (t.isEmpty) return;
    SearchHistoryService.instance.record(t);
    widget.onSearchSelected(t);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopBar(),
            const Divider(height: 1, color: AppConstants.borderGray),
            Expanded(
              child: _loading
                  ? const SizedBox.shrink()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                                  color: AppConstants.secondary
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildChipWrap(
                              terms: _showAllRecent
                                  ? _recent
                                  : _recent.take(6).toList(),
                              onTap: _commit,
                            ),
                            if (_recent.length > 6)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: GestureDetector(
                                  onTap: () => setState(
                                      () => _showAllRecent = !_showAllRecent),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _showAllRecent ? 'Less' : 'More',
                                        style: AppConstants.bodyStyle(
                                          fontSize: 13,
                                          color: AppConstants.secondary
                                              .withValues(alpha: 0.6),
                                        ),
                                      ),
                                      Icon(
                                        _showAllRecent
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        size: 18,
                                        color: AppConstants.secondary
                                            .withValues(alpha: 0.6),
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
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar: back + field + filled search button ────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back,
                color: AppConstants.secondary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                color: Colors.white,
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
