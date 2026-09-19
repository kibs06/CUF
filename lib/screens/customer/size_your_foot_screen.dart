import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/foot_size_picker.dart';
import 'foot_size_v2/foot_scan_setup_screen_v2.dart';

/// ONE settings entry for the customer's foot size, with two swipable panels:
///
/// * **Scan with camera** — landing panel; the Foot Size 2.0 auto scan
///   ([FootScanSetupScreenV2], embedded without its own chrome).
/// * **Enter size manually** — the typed EU size + width picker
///   ([FootSizePickerPanel]).
///
/// The segmented indicator above the panels names which one is showing, and
/// is itself tappable, so both panels are reachable without the customer
/// having to discover the swipe.
class SizeYourFootScreen extends StatefulWidget {
  const SizeYourFootScreen({super.key});

  @override
  State<SizeYourFootScreen> createState() => _SizeYourFootScreenState();
}

class _SizeYourFootScreenState extends State<SizeYourFootScreen> {
  final PageController _pages = PageController();

  /// 0 = scan (the landing panel), 1 = manual.
  int _panel = 0;

  static const List<(IconData, String)> _tabs = [
    (Icons.view_in_ar_rounded, 'Scan with camera'),
    (Icons.edit_outlined, 'Enter size manually'),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == _panel) return;
    setState(() => _panel = index);
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Size Your Foot',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppConstants.secondary,
          ),
        ),
        backgroundColor: AppConstants.surfaceLight,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          _buildIndicator(),
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (index) => setState(() => _panel = index),
              children: const [
                FootScanSetupScreenV2(embedded: true),
                _ManualSizePanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Which panel is showing. Tappable, so the swipe is a shortcut rather than
  /// the only way to reach the other panel.
  Widget _buildIndicator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppConstants.sellerCardBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppConstants.borderGray.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++)
              Expanded(child: _segment(i)),
          ],
        ),
      ),
    );
  }

  Widget _segment(int index) {
    final (icon, label) = _tabs[index];
    final selected = _panel == index;
    final ink = selected
        ? AppConstants.inkInverse
        : AppConstants.secondary.withValues(alpha: 0.7);

    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        key: ValueKey('size-your-foot-panel-$index'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? AppConstants.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: ink),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The manual panel. Holds the async save (the picker itself is
/// presentation-only) and shows the customer's saved size as the starting
/// point.
class _ManualSizePanel extends StatefulWidget {
  const _ManualSizePanel();

  @override
  State<_ManualSizePanel> createState() => _ManualSizePanelState();
}

class _ManualSizePanelState extends State<_ManualSizePanel> {
  bool _saving = false;

  Future<void> _save(FootSizeSelection selection) async {
    setState(() => _saving = true);
    final auth = context.read<AuthProvider>();
    final saved = await auth.saveFootProfile(
      sizeEu: selection.euSize,
      widthLabel: selection.widthLabel,
      category: selection.sizeCategory,
      source: AppConstants.footProfileManual,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'Foot size saved.'
              : auth.errorMessage ?? 'Couldn\'t save your size right now.',
        ),
        backgroundColor: saved ? AppConstants.success : AppConstants.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    final savedSize = profile?['foot_size_ph'];

    return SingleChildScrollView(
      child: FootSizePickerPanel(
        initialEuSize: savedSize is num
            ? savedSize.toDouble()
            : double.tryParse(savedSize?.toString() ?? ''),
        initialWidth: profile?['foot_width']?.toString(),
        initialCategory: profile?['foot_size_category']?.toString(),
        isSaving: _saving,
        onSave: _save,
      ),
    );
  }
}
