import 'package:flutter/material.dart';
import '../../../constants/app_constants.dart';
import '../../../services/search_history_service.dart';

/// Search-history dropdown shown when the home search bar gains focus with
/// an empty field. Lists recent terms as tappable rows (tap = run that
/// search), each with a remove ✕, plus a "Clear all" footer. Renders as a
/// floating card so it can sit over the hero/scroll content.
class SearchHistoryOverlay extends StatefulWidget {
  const SearchHistoryOverlay({
    super.key,
    required this.onSelect,
    this.onChanged,
    this.horizontalMargin = 16,
  });

  /// Called with the chosen term — the parent sets it as the search text.
  final ValueChanged<String> onSelect;

  /// Called after any history mutation so the panel can refresh.
  final VoidCallback? onChanged;

  /// Horizontal inset of the floating card. Set to 0 when the parent
  /// container already applies its own horizontal padding.
  final double horizontalMargin;

  @override
  State<SearchHistoryOverlay> createState() => _SearchHistoryOverlayState();
}

class _SearchHistoryOverlayState extends State<SearchHistoryOverlay> {
  List<String> _terms = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final terms = await SearchHistoryService.instance.history();
    if (!mounted) return;
    setState(() {
      _terms = terms;
      _loading = false;
    });
  }

  Future<void> _remove(String term) async {
    await SearchHistoryService.instance.remove(term);
    await _load();
    widget.onChanged?.call();
  }

  Future<void> _clearAll() async {
    await SearchHistoryService.instance.clear();
    await _load();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_terms.isEmpty) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: widget.horizontalMargin),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          // Sharp corners to match the squared search bar.
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: const Color(0x2E140F0A).withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
              spreadRadius: -6,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.history,
                    size: 14,
                    color: AppConstants.secondary.withValues(alpha: 0.45),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Recent searches',
                      style: AppConstants.bodyStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color:
                            AppConstants.secondary.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _clearAll,
                    child: Text(
                      'Clear all',
                      style: AppConstants.bodyStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.primary.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(
                height: 1, color: AppConstants.borderGray, indent: 16, endIndent: 16),
            for (final term in _terms)
              InkWell(
                onTap: () => widget.onSelect(term),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.north_west,
                        size: 13,
                        color: AppConstants.secondary.withValues(alpha: 0.35),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          term,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppConstants.bodyStyle(
                            fontSize: 13,
                            color: AppConstants.secondary,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _remove(term),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.close,
                            size: 15,
                            color:
                                AppConstants.secondary.withValues(alpha: 0.35),
                          ),
                        ),
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
}
