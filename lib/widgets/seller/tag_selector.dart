import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';

/// Shared grouped tag selector + chip family.
///
/// Originally built for the product form (AddEditProductScreen); extracted
/// here so the seller application's Storefront step, CreateStoreScreen and
/// EditStoreScreen can offer the SAME tag vocabulary (handmade, leather,
/// eco-friendly, …) without duplicating the parse/serialize logic or the
/// animated chips. Store tags and product tags therefore never drift apart.
// ─── Grouped tag selector ──────────────────────────────────────────
/// One selectable preset tag. Stored value is a stable snake_case id that is
/// globally unique across all three groups, so it never needs a group prefix.
class TagPreset {
  final String id;
  final String label;
  final IconData icon;
  const TagPreset({
    required this.id,
    required this.label,
    required this.icon,
  });
}

/// A tag group: its presets, its accent color (espresso/cream family so the
/// three groups stay visually distinct but on-palette), and the content color
/// that must contrast against [color] when a chip is selected.
class TagGroup {
  final String id; // 'type' | 'material' | 'sustainability' | 'other'
  final String label;
  final IconData icon;
  final Color color; // selected fill
  final Color onColor; // selected content
  final List<TagPreset> presets;
  const TagGroup({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.onColor,
    this.presets = const [],
  });
}

/// The three editable groups, in display order. Colors are drawn from the
/// espresso/cream palette (burnished clay, leather camel, dark olive stitch)
/// so the groups stay distinct without clashing with the theme.
const List<TagGroup> tagGroups = [
  TagGroup(
    id: 'type',
    label: 'Product type',
    icon: Icons.category_outlined,
    color: AppConstants.primary,
    onColor: AppConstants.surfaceLight,
    presets: [
      TagPreset(id: 'handmade', label: 'Handmade', icon: Icons.handyman_outlined),
      TagPreset(id: 'made_to_order', label: 'Made-to-order', icon: Icons.straighten_outlined),
      TagPreset(id: 'ready_to_wear', label: 'Ready-to-wear', icon: Icons.checkroom_outlined),
      TagPreset(id: 'limited_edition', label: 'Limited edition', icon: Icons.star_outline),
    ],
  ),
  TagGroup(
    id: 'material',
    label: 'Material',
    icon: Icons.layers_outlined,
    color: Color(0xFFC08552), // leather camel
    onColor: AppConstants.secondary,
    presets: [
      TagPreset(id: 'leather', label: 'Leather', icon: Icons.work_outline),
      TagPreset(id: 'canvas', label: 'Canvas', icon: Icons.texture),
      TagPreset(id: 'rubber', label: 'Rubber', icon: Icons.sports_tennis_outlined),
      TagPreset(id: 'suede', label: 'Suede', icon: Icons.gesture),
    ],
  ),
  TagGroup(
    id: 'sustainability',
    label: 'Sustainability',
    icon: Icons.eco_outlined,
    color: Color(0xFF556B2F), // dark olive stitch
    onColor: AppConstants.surfaceLight,
    presets: [
      TagPreset(id: 'eco_friendly', label: 'Eco-friendly', icon: Icons.eco_outlined),
      TagPreset(id: 'upcycled_materials', label: 'Upcycled materials', icon: Icons.recycling),
      TagPreset(id: 'recycled_packaging', label: 'Recycled packaging', icon: Icons.inventory_2_outlined),
    ],
  ),
];

/// Neutral bucket for legacy free-text tags (saved before the grouped
/// selector existed) that don't match any preset. Shown only when present.
const TagGroup otherBucketGroup = TagGroup(
  id: 'other',
  label: 'Custom tags',
  icon: Icons.label_outline,
  color: AppConstants.borderGray,
  onColor: AppConstants.secondary,
);

/// The store-specific tag groups (seller application Step 5 and Create/
/// Edit Store). Stores get their own curated vocabulary — distinct from
/// product tags — with an emphasis on craft heritage and locality.
const List<TagGroup> storeTagGroups = [
  TagGroup(
    id: 'craft',
    label: 'Craft & heritage',
    icon: Icons.handyman_outlined,
    color: AppConstants.primary,
    onColor: AppConstants.surfaceLight,
    presets: [
      TagPreset(id: 'handmade', label: 'Handmade', icon: Icons.handyman_outlined),
      TagPreset(id: 'family_owned', label: 'Family-owned', icon: Icons.family_restroom_outlined),
      TagPreset(id: 'multi_generation', label: 'Multi-generation', icon: Icons.history_edu_outlined),
      TagPreset(id: 'custom_orders', label: 'Custom orders', icon: Icons.design_services_outlined),
    ],
  ),
  TagGroup(
    id: 'local',
    label: 'Local pride',
    icon: Icons.place_outlined,
    color: Color(0xFFC08552), // leather camel
    onColor: AppConstants.secondary,
    presets: [
      TagPreset(id: 'local', label: 'Local', icon: Icons.location_city_outlined),
      TagPreset(id: 'carcar_made', label: 'Carcar-made', icon: Icons.location_on_outlined),
      TagPreset(id: 'cebu_made', label: 'Cebu-made', icon: Icons.map_outlined),
      TagPreset(id: 'filipino_made', label: 'Filipino-made', icon: Icons.flag_outlined),
    ],
  ),
  TagGroup(
    id: 'services',
    label: 'Services & offers',
    icon: Icons.storefront_outlined,
    color: Color(0xFF556B2F), // dark olive stitch
    onColor: AppConstants.surfaceLight,
    presets: [
      TagPreset(id: 'custom_sizing', label: 'Custom sizing', icon: Icons.straighten_outlined),
      TagPreset(id: 'repairs', label: 'Repairs & resoling', icon: Icons.build_outlined),
      TagPreset(id: 'wholesale', label: 'Wholesale', icon: Icons.inventory_2_outlined),
      TagPreset(id: 'retail', label: 'Retail / walk-ins', icon: Icons.store_outlined),
    ],
  ),
];

const int _maxCustomTagLength = 30;

/// One selected tag entry (a preset or a custom value) scoped to a group.
class _TagEntry {
  final String group;
  final String value; // preset id, or raw custom text
  final bool custom;
  const _TagEntry({
    required this.group,
    required this.value,
    required this.custom,
  });
}

/// Serialize a custom entry into its stored form: `custom:<group>:<text>`.
/// The fixed prefix makes customs unambiguously distinguishable from preset
/// ids (plain snake_case strings) and records the group so edit mode can
/// re-render the chip in the right section.
String _customStoredValue(String group, String text) => 'custom:$group:$text';

/// Parse one stored tag string into a [_TagEntry] against [groups].
///   * known preset id (case-insensitive) → preset in its group
///   * `custom:<group>:<text>`            → custom in that group
///   * anything else (legacy free text)   → custom in the 'other' bucket
_TagEntry _parseStoredTag(String raw, List<TagGroup> groups) {
  final t = raw.trim();
  final lower = t.toLowerCase();
  String? canonical;
  for (final g in groups) {
    for (final p in g.presets) {
      if (p.id.toLowerCase() == lower) {
        canonical = p.id;
        break;
      }
    }
    if (canonical != null) break;
  }
  if (canonical != null) {
    final group = groups
        .firstWhere((g) => g.presets.any((p) => p.id == canonical))
        .id;
    return _TagEntry(group: group, value: canonical, custom: false);
  }
  if (lower.startsWith('custom:')) {
    final parts = t.split(':');
    if (parts.length >= 3) {
      final group = parts[1].toLowerCase();
      final text = parts.sublist(2).join(':').trim();
      final known = groups.any((g) => g.id == group) || group == 'other';
      if (known && text.isNotEmpty) {
        return _TagEntry(group: group, value: text, custom: true);
      }
    }
    // Malformed custom entry (e.g. "custom:type:" with no text) — drop it
    // rather than rendering the raw prefix as a chip.
    return const _TagEntry(group: 'other', value: '', custom: true);
  }
  return _TagEntry(group: 'other', value: t, custom: true);
}

/// Parse a list of stored tags against [groups], dropping entries that
/// produced no value (empty strings and malformed `custom:` entries).
List<_TagEntry> _parseTags(List<String> raw, List<TagGroup> groups) {
  final result = <_TagEntry>[];
  for (final t in raw) {
    final e = _parseStoredTag(t, groups);
    if (e.value.isNotEmpty) result.add(e);
  }
  return result;
}

String? _presetLabel(List<TagGroup> groups, String id) {
  for (final g in groups) {
    for (final p in g.presets) {
      if (p.id == id) return p.label;
    }
  }
  return null;
}

/// Human-readable label for a stored tag string — the preset's display
/// label for preset ids, the free text for `custom:<group>:<text>` entries,
/// or the raw string for legacy values. Resolves against the STORE
/// vocabulary first, then the product vocabulary (legacy stores saved with
/// product tags before the store set existed). Used by read-only tag
/// display (store profile pages) so chips never show snake_case ids.
String tagDisplayLabel(String stored) {
  final entry = _parseStoredTag(stored, storeTagGroups);
  if (entry.custom) return entry.value;
  return _presetLabel(storeTagGroups, entry.value) ??
      _presetLabel(tagGroups, entry.value) ??
      entry.value;
}

/// Grouped, multi-select tag selector.
///
/// Renders the three preset groups (Product type / Material / Sustainability)
/// plus a custom "+ Other" input per group. Owns its selection state and
/// animation scope so a chip tap rebuilds only this section, and reports the
/// fully-serialized tag list up via [onChanged] — the form persists exactly
/// what's shown in the same write as the rest of the form.
class TagSelector extends StatefulWidget {
  final List<String> initialTags;
  final ValueChanged<List<String>> onChanged;

  /// Which preset groups to offer — [tagGroups] (product) by default, or
  /// [storeTagGroups] for store forms / the seller application.
  final List<TagGroup> groups;

  const TagSelector({
    super.key,
    required this.initialTags,
    required this.onChanged,
    this.groups = tagGroups,
  });

  @override
  State<TagSelector> createState() => _TagSelectorState();
}

class _TagSelectorState extends State<TagSelector> {
  late final List<_TagEntry> _entries =
      _parseTags(widget.initialTags, widget.groups);

  // Per-group "Other" input state. The controllers are owned by this widget
  // (created lazily, disposed here) — never disposed mid-teardown of a route,
  // which is what prevents the framework's `_dependents.isEmpty` assertion.
  final Map<String, TextEditingController> _otherControllers = {};
  final Map<String, bool> _otherOpen = {};
  final Map<String, String?> _otherErrors = {};

  TextEditingController _controllerFor(String group) =>
      _otherControllers.putIfAbsent(group, TextEditingController.new);

  @override
  void dispose() {
    for (final c in _otherControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<_TagEntry> _groupEntries(String group) =>
      _entries.where((e) => e.group == group).toList();

  /// Serialize the selection in display order (group by group, presets then
  /// customs) and report it up so the form persists exactly what's shown.
  void _push() {
    final stored = <String>[];
    void addGroup(String gid) {
      stored.addAll(
          _groupEntries(gid).where((e) => !e.custom).map((e) => e.value));
      stored.addAll(_groupEntries(gid)
          .where((e) => e.custom)
          .map((e) => _customStoredValue(e.group, e.value)));
    }

    for (final g in widget.groups) {
      addGroup(g.id);
    }
    addGroup(otherBucketGroup.id);
    widget.onChanged(stored);
  }

  void _togglePreset(TagGroup group, String id) {
    setState(() {
      final idx = _entries.indexWhere(
          (e) => !e.custom && e.group == group.id && e.value == id);
      if (idx >= 0) {
        _entries.removeAt(idx);
      } else {
        _entries.add(_TagEntry(group: group.id, value: id, custom: false));
      }
    });
    _push();
  }

  void _toggleOtherInput(String group) {
    setState(() {
      _otherOpen[group] = !(_otherOpen[group] ?? false);
      _otherErrors.remove(group);
    });
  }

  void _addCustom(String group) {
    final ctrl = _controllerFor(group);
    final text = ctrl.text.trim();
    if (text.isEmpty) {
      setState(() => _otherErrors[group] = 'Type a tag first.');
      return;
    }
    if (text.length > _maxCustomTagLength) {
      setState(() => _otherErrors[group] =
          'Keep it under $_maxCustomTagLength characters.');
      return;
    }
    final lower = text.toLowerCase();
    final groupPresets =
        widget.groups.firstWhere((g) => g.id == group).presets;
    if (groupPresets.any((p) => p.id.toLowerCase() == lower)) {
      setState(() => _otherErrors[group] =
          'That is already a preset option — tap it above instead.');
      return;
    }
    if (_groupEntries(group)
        .any((e) => e.custom && e.value.toLowerCase() == lower)) {
      setState(() => _otherErrors[group] = 'That tag is already added.');
      return;
    }
    setState(() {
      _entries.add(_TagEntry(group: group, value: text, custom: true));
      ctrl.clear();
      _otherErrors.remove(group);
    });
    _push();
  }

  void _removeCustom(String group, String value) {
    setState(() {
      _entries.removeWhere(
          (e) => e.custom && e.group == group && e.value == value);
    });
    _push();
  }

  @override
  Widget build(BuildContext context) {
    final otherEntries = _groupEntries(otherBucketGroup.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in widget.groups) ...[
          _buildGroup(group),
          const SizedBox(height: 22),
        ],
        if (otherEntries.isNotEmpty) ...[
          _buildGroupLabel(otherBucketGroup),
          _buildCustomChips(otherBucketGroup, otherEntries),
        ],
      ],
    );
  }

  Widget _buildGroup(TagGroup group) {
    final entries = _groupEntries(group.id);
    final customs = entries.where((e) => e.custom).toList();
    final isOpen = _otherOpen[group.id] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGroupLabel(group),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in group.presets)
              TagChip(
                label: p.label,
                icon: p.icon,
                color: group.color,
                onColor: group.onColor,
                selected: entries.any((e) => !e.custom && e.value == p.id),
                onTap: () => _togglePreset(group, p.id),
              ),
            OtherTagChip(
              color: group.color,
              open: isOpen,
              onTap: () => _toggleOtherInput(group.id),
            ),
          ],
        ),
        // Custom chips animate in/out via AnimatedSwitcher — only on user
        // interaction; the initial render (edit-mode pre-fill) is static.
        _buildCustomChips(group, customs),
        if (isOpen) ...[
          const SizedBox(height: 10),
          _buildOtherInput(group),
        ],
      ],
    );
  }

  Widget _buildCustomChips(TagGroup group, List<_TagEntry> customs) {
    return CustomChipSwitcher(
      keyValue: customs.isEmpty
          ? null
          : customs.map((e) => e.value.toLowerCase()).join('\u0001'),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in customs)
            CustomTagChip(
              label: e.value,
              color: group.color,
              onColor: group.onColor,
              onRemove: () => _removeCustom(group.id, e.value),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupLabel(TagGroup group) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: group.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(group.icon, size: 14, color: group.color),
        ),
        const SizedBox(width: 8),
        Text(
          group.label,
          style: AppConstants.bodyStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppConstants.secondary,
          ),
        ),
      ],
    );
  }

  Widget _buildOtherInput(TagGroup group) {
    final ctrl = _controllerFor(group.id);
    final error = _otherErrors[group.id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: _maxCustomTagLength,
                style: AppConstants.bodyStyle(fontSize: 14),
                decoration: InputDecoration(
                  counterText: '',
                  isDense: true,
                  hintText: 'Add your own ${group.label.toLowerCase()}…',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: AppConstants.buttonRadius,
                    borderSide:
                        const BorderSide(color: AppConstants.borderGray),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppConstants.buttonRadius,
                    borderSide:
                        const BorderSide(color: AppConstants.borderGray),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppConstants.buttonRadius,
                    borderSide: BorderSide(color: group.color, width: 1.5),
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addCustom(group.id),
              ),
            ),
            const SizedBox(width: 8),
            AddCustomButton(
              color: group.color,
              onColor: group.onColor,
              onPressed: () => _addCustom(group.id),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error,
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// One preset chip with a subtle "pop" on tap (quick scale up ~1.07 then
/// settle back) and an animated fill/border/color transition on selection.
/// Colors come from the owning [TagGroup]. The animation only plays on user
/// interaction — the initial render (edit-mode pre-fill) is static.
class TagChip extends StatefulWidget {
  final String label;
  final IconData? icon; // null → text-only chip (used by the category row)
  final Color color;
  final Color onColor;
  final bool selected;
  final VoidCallback onTap;

  const TagChip({
    super.key,
    required this.label,
    this.icon,
    required this.color,
    required this.onColor,
    required this.selected,
    required this.onTap,
  });

  @override
  State<TagChip> createState() => _TagChipState();
}

class _TagChipState extends State<TagChip> with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.07)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.07, end: 1.0)
          .chain(CurveTween(curve: Curves.easeInOut)),
      weight: 55,
    ),
  ]).animate(_pop);

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _handleTap() {
    _pop.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    // Unselected chips stay uniform (white fill, muted carob text, suede
    // border); selection fills the chip with the group's accent color and
    // swaps the content to the group's on-color.
    final offColor = AppConstants.secondary.withValues(alpha: 0.65);

    return Semantics(
      button: true,
      selected: selected,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: AnimatedBuilder(
          animation: _scale,
          builder: (context, child) =>
              Transform.scale(scale: _scale.value, child: child),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? widget.color : Colors.white,
              borderRadius: AppConstants.stadiumRadius,
              border: Border.all(
                color: selected ? widget.color : AppConstants.borderGray,
                width: 1.5,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon,
                      size: 16, color: selected ? widget.onColor : offColor),
                  const SizedBox(width: 6),
                ],
                Text(
                  widget.label,
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? widget.onColor : offColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A selected custom tag chip. Always shown in the selected (filled) state;
/// tapping removes it from the selection entirely (custom entries have no
/// reason to persist as an option once unchecked).
class CustomTagChip extends StatefulWidget {
  final String label;
  final Color color;
  final Color onColor;
  final VoidCallback onRemove;

  const CustomTagChip({
    super.key,
    required this.label,
    required this.color,
    required this.onColor,
    required this.onRemove,
  });

  @override
  State<CustomTagChip> createState() => _CustomTagChipState();
}

class _CustomTagChipState extends State<CustomTagChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.07)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.07, end: 1.0)
          .chain(CurveTween(curve: Curves.easeInOut)),
      weight: 55,
    ),
  ]).animate(_pop);

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _handleRemove() {
    _pop.forward(from: 0);
    widget.onRemove();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Remove ${widget.label}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleRemove,
        child: AnimatedBuilder(
          animation: _scale,
          builder: (context, child) =>
              Transform.scale(scale: _scale.value, child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: AppConstants.stadiumRadius,
              border: Border.all(color: widget.color, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.close, size: 14, color: widget.onColor),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: widget.onColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "+ Other" chip per group. Dashed border + distinct icon signal that it
/// adds a custom value rather than selecting a fixed option; tapping toggles
/// the group's inline text input.
class OtherTagChip extends StatelessWidget {
  final Color color;
  final bool open;
  final VoidCallback onTap;

  const OtherTagChip({
    super.key,
    required this.color,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: open ? 'Close input' : 'Add your own',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: open ? color.withValues(alpha: 0.08) : Colors.white,
            borderRadius: AppConstants.stadiumRadius,
          ),
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: color.withValues(alpha: open ? 0.95 : 0.55),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(open ? Icons.close : Icons.add, size: 15, color: color),
                  const SizedBox(width: 5),
                  Text(
                    open ? 'Close' : 'Other',
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a dashed rounded-rect border (used for the "+ Other" chip so it
/// reads as "add your own" rather than a fixed option).
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  static const double _dashLength = 5;
  static const double _gapLength = 4;

  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.height / 2),
      ));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + _dashLength),
          paint,
        );
        distance += _dashLength + _gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Small filled "+ Add" button beside the inline custom-tag input.
class AddCustomButton extends StatelessWidget {
  final Color color;
  final Color onColor;
  final VoidCallback onPressed;

  const AddCustomButton({
    super.key,
    required this.color,
    required this.onColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: AppConstants.buttonRadius,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppConstants.buttonRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 16, color: onColor),
              const SizedBox(width: 4),
              Text(
                'Add',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: onColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fade/scale switcher for custom chips — animates chips in/out on add/remove
/// (user interaction) and stays static on the initial render. Both the old
/// and new children stay left-aligned while they cross-fade, so the row
/// slides in place instead of re-centering.
class CustomChipSwitcher extends StatelessWidget {
  /// Drives the transition: changes → animate; null → collapsed (nothing).
  final String? keyValue;
  final Widget child;

  const CustomChipSwitcher({
    super.key,
    required this.keyValue,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final collapsed = keyValue == null;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: collapsed
          ? const SizedBox.shrink()
          : Padding(
              key: ValueKey(keyValue),
              padding: const EdgeInsets.only(top: 10),
              child: child,
            ),
    );
  }
}
