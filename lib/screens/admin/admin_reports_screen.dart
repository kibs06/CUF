import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/app_constants.dart';
import 'admin_helpers.dart';

/// Admin Reports — port of admin-portal/src/pages/Reports.jsx.
///
/// User-submitted reports with summary cards, filters, and a detail sheet
/// to change status/action, add admin notes, and notify the reporter.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  static const _pageSize = 20;

  static const _statusOptions = ['pending', 'under_review', 'resolved', 'dismissed'];
  static const _typeOptions = ['message', 'product', 'seller', 'other'];

  static const _categoryLabels = {
    'harassment': 'Harassment / abusive language',
    'spam_scam': 'Spam or scam attempt',
    'inappropriate_content': 'Inappropriate content',
    'off_platform': 'Trying to move the deal off-platform',
    'not_as_described': 'Item not as described',
    'damaged_defective': 'Item damaged or defective',
    'wrong_item': 'Wrong item received',
    'never_received': 'Item never received',
    'seller_refuses': 'Seller refuses to resolve/negotiate',
    'buyer_misuse': 'Customer damaged/misused item before dispute',
    'scam_fraud': 'Suspected scam or fraud',
    'fake_listings': 'Fake or misleading listings',
    'counterfeit': 'Counterfeit goods',
    'repeated_violations': 'Repeated policy violations',
    'harassment_outside_chat': 'Harassment outside the chat',
    'app_bug': 'App bug or technical issue',
    'payment_billing': 'Payment or billing issue',
    'account_issue': 'Account issue',
    'general_feedback': 'General complaint / feedback',
    'other': 'Other',
  };

  final _searchCtrl = TextEditingController();
  String _search = '';
  String _statusFilter = 'all';
  String _typeFilter = 'all';
  String _priorityFilter = 'all';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  int _page = 1;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _reports = [];
  Map<String, int> _counts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final data = await client
          .from('reports')
          .select('*, profiles!reports_reporter_id_fkey(full_name, email, avatar_url)')
          .order('created_at', ascending: false)
          .limit(500);
      final reports = List<Map<String, dynamic>>.from(data);
      // High-priority first (stable within priority: newest first).
      reports.sort((a, b) {
        final aHigh = a['priority'] == 'high';
        final bHigh = b['priority'] == 'high';
        if (aHigh != bHigh) return aHigh ? -1 : 1;
        return 0;
      });

      // Counts
      Future<int> count(Future<dynamic> q) async =>
          ((await q) as List).length;

      final pending = count(
        client.from('reports').select('id').eq('status', 'pending'),
      );
      final high = count(
        client
            .from('reports')
            .select('id')
            .eq('priority', 'high')
            .inFilter('status', ['pending', 'under_review']),
      );
      final underReview = count(
        client.from('reports').select('id').eq('status', 'under_review'),
      );
      final resolved7d = count(
        client
            .from('reports')
            .select('id')
            .eq('status', 'resolved')
            .gte(
              'updated_at',
              DateTime.now().subtract(const Duration(days: 7)).toUtc().toIso8601String(),
            ),
      );

      final counts = {
        'pending': await pending,
        'high': await high,
        'under_review': await underReview,
        'resolved_7d': await resolved7d,
      };
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _counts = counts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _updateReport(
    String id, {
    Map<String, dynamic> updates = const {},
  }) async {
    try {
      await Supabase.instance.client
          .from('reports')
          .update({
            ...updates,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e'), backgroundColor: AppConstants.error),
      );
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    return _reports.where((r) {
      final id = (r['id'] ?? '').toString().toLowerCase();
      final reporter =
          ((r['profiles'] as Map<String, dynamic>?)?['full_name'] ?? '')
              .toString()
              .toLowerCase();
      final category = (r['category'] ?? '').toString().toLowerCase();
      final details = (r['custom_details'] ?? '').toString().toLowerCase();
      if (q.isNotEmpty &&
          !id.contains(q) &&
          !reporter.contains(q) &&
          !category.contains(q) &&
          !details.contains(q)) {
        return false;
      }
      if (_statusFilter != 'all' && r['status'] != _statusFilter) return false;
      if (_typeFilter != 'all' && r['type'] != _typeFilter) return false;
      if (_priorityFilter != 'all' && r['priority'] != _priorityFilter) return false;
      final created = adminParseTime(r['created_at']);
      if (_dateFrom != null && (created == null || created.isBefore(_dateFrom!))) {
        return false;
      }
      if (_dateTo != null) {
        final endOfDay = DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day, 23, 59, 59);
        if (created == null || created.isAfter(endOfDay)) return false;
      }
      return true;
    }).toList();
  }

  String _categoryLabel(String key) => _categoryLabels[key] ?? key;

  String _targetLabel(Map<String, dynamic> r) {
    final category = (r['category'] ?? '').toString();
    if (category == 'other' && r['custom_details'] != null) {
      final details = (r['custom_details'] ?? '').toString();
      final short = details.length > 40 ? '${details.substring(0, 40)}…' : details;
      return 'Other: "$short"';
    }
    return _categoryLabel(category);
  }

  void _openReport(Map<String, dynamic> report) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppConstants.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ReportDetailSheet(
        report: report,
        onSave: (updates) => _updateReport((report['id'] ?? '').toString(), updates: updates),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final totalPages = (filtered.length / _pageSize).ceil().clamp(1, 1 << 31);
    final pageRows = filtered.length <= _pageSize
        ? filtered
        : filtered.sublist(
            ((_page - 1) * _pageSize).clamp(0, filtered.length),
            (_page * _pageSize).clamp(0, filtered.length),
          );

    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text('Reports', style: AppConstants.headlineStyle(fontSize: 20)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          AppConstants.noiseOverlay(opacity: 0.03),
          Column(
            children: [
              // Stat cards
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    _statCard(
                      label: 'Pending',
                      value: _counts['pending'] ?? 0,
                      icon: Icons.hourglass_empty,
                      color: const Color(0xFFE8A020),
                      onTap: () => setState(() {
                        _statusFilter = 'pending';
                        _page = 1;
                      }),
                      active: _statusFilter == 'pending',
                    ),
                    const SizedBox(width: 10),
                    _statCard(
                      label: 'High Priority',
                      value: _counts['high'] ?? 0,
                      icon: Icons.priority_high,
                      color: AppConstants.error,
                      highlight: (_counts['high'] ?? 0) > 0,
                      onTap: () => setState(() {
                        _priorityFilter = 'high';
                        _page = 1;
                      }),
                      active: _priorityFilter == 'high',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    _statCard(
                      label: 'Under Review',
                      value: _counts['under_review'] ?? 0,
                      icon: Icons.manage_search,
                      color: const Color(0xFF5C6BC0),
                      onTap: () => setState(() {
                        _statusFilter = 'under_review';
                        _page = 1;
                      }),
                      active: _statusFilter == 'under_review',
                    ),
                    const SizedBox(width: 10),
                    _statCard(
                      label: 'Resolved (7d)',
                      value: _counts['resolved_7d'] ?? 0,
                      icon: Icons.check_circle_outline,
                      color: AppConstants.accent,
                      onTap: () => setState(() {
                        _statusFilter = 'resolved';
                        _page = 1;
                      }),
                      active: _statusFilter == 'resolved',
                    ),
                  ],
                ),
              ),
              // Search + filters
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() {
                    _search = v;
                    _page = 1;
                  }),
                  style: AppConstants.bodyStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search reporter, target, or report ID…',
                    hintStyle: AppConstants.bodyStyle(fontSize: 13, color: Colors.black38),
                    prefixIcon: const Icon(Icons.search, color: AppConstants.primary),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _dropdownFilter(
                        value: _statusFilter,
                        options: {
                          'all': 'All statuses',
                          for (final s in _statusOptions) s: _titleCase(s),
                        },
                        onChanged: (v) => setState(() {
                          _statusFilter = v;
                          _page = 1;
                        }),
                      ),
                      const SizedBox(width: 8),
                      _dropdownFilter(
                        value: _typeFilter,
                        options: {
                          'all': 'All types',
                          for (final t in _typeOptions) t: _titleCase(t),
                        },
                        onChanged: (v) => setState(() {
                          _typeFilter = v;
                          _page = 1;
                        }),
                      ),
                      const SizedBox(width: 8),
                      _dropdownFilter(
                        value: _priorityFilter,
                        options: {
                          'all': 'All priorities',
                          'high': 'High',
                          'normal': 'Normal',
                        },
                        onChanged: (v) => setState(() {
                          _priorityFilter = v;
                          _page = 1;
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              // List
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppConstants.primary))
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: AppConstants.bodyStyle(color: AppConstants.error),
                              ),
                            ),
                          )
                        : pageRows.isEmpty
                            ? Center(
                                child: Text(
                                  'No reports found.\nTry adjusting your search and filters.',
                                  textAlign: TextAlign.center,
                                  style: AppConstants.bodyStyle(color: Colors.black45),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                itemCount: pageRows.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == pageRows.length) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            onPressed: _page <= 1 ? null : () => setState(() => _page--),
                                            icon: const Icon(Icons.chevron_left, color: AppConstants.primary),
                                          ),
                                          Text(
                                            'Page $_page of $totalPages · ${filtered.length} reports',
                                            style: AppConstants.bodyStyle(fontSize: 11, color: Colors.black45),
                                          ),
                                          IconButton(
                                            onPressed: _page >= totalPages ? null : () => setState(() => _page++),
                                            icon: const Icon(Icons.chevron_right, color: AppConstants.primary),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  final r = pageRows[index];
                                  final status = (r['status'] ?? '').toString();
                                  final type = (r['type'] ?? '').toString();
                                  final high = r['priority'] == 'high';
                                  return GestureDetector(
                                    onTap: () => _openReport(r),
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      child: AdminCard(
                                        padding: const EdgeInsets.all(14),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                if (high) ...[
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: AppConstants.error.withValues(alpha: 0.1),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      'HIGH',
                                                      style: AppConstants.bodyStyle(
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.bold,
                                                        color: AppConstants.error,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                ],
                                                Expanded(
                                                  child: Text(
                                                    _titleCase(type),
                                                    style: AppConstants.bodyStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                                AdminStatusChip(label: status.replaceAll('_', ' '), status: status),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              r['profiles']?['full_name'] ?? '—',
                                              style: AppConstants.bodyStyle(fontSize: 13),
                                            ),
                                            Text(
                                              _targetLabel(r),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: AppConstants.bodyStyle(fontSize: 11, color: Colors.black45),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              '#${adminShortId((r['id'] ?? '').toString())} · ${adminDate(adminParseTime(r['created_at']))}',
                                              style: AppConstants.bodyStyle(fontSize: 10, color: Colors.black45),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _titleCase(String s) {
    return s
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  Widget _statCard({
    required String label,
    required int value,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool active = false,
    bool highlight = false,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active ? AppConstants.primary : AppConstants.borderGray.withValues(alpha: 0.6),
              width: active ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppConstants.bodyStyle(fontSize: 10, color: Colors.black45),
                    ),
                    Text(
                      '$value',
                      style: AppConstants.monoStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: highlight ? AppConstants.error : AppConstants.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropdownFilter({
    required String value,
    required Map<String, String> options,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppConstants.borderGray),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: Colors.white,
          style: AppConstants.bodyStyle(fontSize: 12),
          items: [
            for (final entry in options.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (v) => onChanged(v ?? 'all'),
        ),
      ),
    );
  }
}

/// Detail bottom sheet: report info, status/action/notes + notify reporter.
class _ReportDetailSheet extends StatefulWidget {
  final Map<String, dynamic> report;
  final Future<void> Function(Map<String, dynamic> updates) onSave;

  const _ReportDetailSheet({required this.report, required this.onSave});

  @override
  State<_ReportDetailSheet> createState() => _ReportDetailSheetState();
}

class _ReportDetailSheetState extends State<_ReportDetailSheet> {
  static const _statusOptions = ['pending', 'under_review', 'resolved', 'dismissed'];
  static const _actionOptions = [
    'none', 'warning_issued', 'content_removed', 'seller_suspended', 'refund_issued', 'other',
  ];
  static const _notificationTemplates = {
    'reviewed_action_taken':
        "We've reviewed your report and taken action. Thank you for helping keep our community safe.",
    'reviewed_no_violation':
        "We've reviewed your report and didn't find a violation of our policies. Thanks for flagging it — feel free to reach out if anything else comes up.",
    'needs_more_info':
        "We're looking into your report and may reach out if we need more details. Thanks for your patience.",
  };

  late String _status = (widget.report['status'] ?? 'pending').toString();
  late String _action = (widget.report['action_taken'] ?? 'none').toString();
  late final TextEditingController _notesCtrl =
      TextEditingController(text: (widget.report['admin_notes'] ?? '').toString());
  bool _saving = false;
  String? _actionError;
  bool _notifyOpen = false;
  String? _notifyMode; // 'template' | 'custom'
  String? _selectedTemplate;
  final _customCtrl = TextEditingController();

  String _titleCase(String s) {
    return s
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_status == 'resolved' && (_action.isEmpty || _action == 'none')) {
      setState(() => _actionError = 'Action Taken is required when resolving a report.');
      return;
    }
    setState(() {
      _actionError = null;
      _saving = true;
    });
    await widget.onSave({
      'status': _status,
      'action_taken': _action,
      'admin_notes': _notesCtrl.text,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report updated'), backgroundColor: AppConstants.success),
    );
    Navigator.of(context).pop();
  }

  Future<void> _handleNotify() async {
    String msg = '';
    if (_notifyMode == 'template' && _selectedTemplate != null) {
      msg = _notificationTemplates[_selectedTemplate] ?? '';
    } else if (_notifyMode == 'custom' && _customCtrl.text.trim().isNotEmpty) {
      msg = _customCtrl.text.trim();
    }
    if (msg.isEmpty) return;
    setState(() => _saving = true);
    await widget.onSave({
      'reporter_notified': true,
      'reporter_notification_text': msg,
    });
    if (!mounted) return;
    setState(() {
      _saving = false;
      _notifyOpen = false;
      _customCtrl.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reporter notified'), backgroundColor: AppConstants.success),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final reporterNotified = r['reporter_notified'] == true;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppConstants.borderGray,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${adminShortId((r['id'] ?? '').toString())} · ${adminDate(adminParseTime(r['created_at']))}',
                          style: AppConstants.bodyStyle(fontSize: 11, color: Colors.black45),
                        ),
                        const SizedBox(height: 4),
                        if (r['priority'] == 'high')
                          Text(
                            'HIGH PRIORITY',
                            style: AppConstants.bodyStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppConstants.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                  AdminStatusChip(label: _titleCase((r['type'] ?? '').toString())),
                ],
              ),
              const SizedBox(height: 16),
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reporter',
                      style: AppConstants.bodyStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black45),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      r['profiles']?['full_name'] ?? 'Unknown',
                      style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      '${r['reporter_role'] ?? '—'} · ${r['profiles']?['email'] ?? ''}',
                      style: AppConstants.bodyStyle(fontSize: 12, color: Colors.black45),
                    ),
                  ],
                ),
              ),
              if (r['category'] == 'other' && r['custom_details'] != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8A020).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE8A020).withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Reporter's Description",
                        style: AppConstants.bodyStyle(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFFC47D00)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (r['custom_details'] ?? '').toString(),
                        style: AppConstants.bodyStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // Status
              Text('Status', style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              _dropdown(_status, _statusOptions, (v) {
                setState(() {
                  _status = v;
                  _actionError = null;
                });
              }),
              const SizedBox(height: 14),
              // Action taken
              Text(
                _status == 'resolved' ? 'Action Taken *' : 'Action Taken',
                style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              _dropdown(_action, _actionOptions, (v) {
                setState(() {
                  _action = v;
                  _actionError = null;
                });
              }),
              if (_actionError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _actionError!,
                    style: AppConstants.bodyStyle(fontSize: 11, color: AppConstants.error),
                  ),
                ),
              const SizedBox(height: 14),
              // Admin notes
              Text('Admin Notes', style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _notesCtrl,
                maxLines: 3,
                style: AppConstants.bodyStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Internal notes (not visible to reporter)',
                  hintStyle: AppConstants.bodyStyle(fontSize: 12, color: Colors.black38),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppConstants.borderGray),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Notify reporter
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Notify Reporter', style: AppConstants.bodyStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Text(
                                reporterNotified ? 'Already notified' : 'Send an update to the reporter',
                                style: AppConstants.bodyStyle(fontSize: 11, color: Colors.black45),
                              ),
                            ],
                          ),
                        ),
                        if (!_notifyOpen)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppConstants.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            ),
                            onPressed: () => setState(() {
                              _notifyOpen = true;
                              _notifyMode = 'template';
                            }),
                            child: Text('Notify', style: AppConstants.bodyStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    if (_notifyOpen) ...[
                      const SizedBox(height: 10),
                      for (final entry in _notificationTemplates.entries)
                        GestureDetector(
                          onTap: () => setState(() {
                            _selectedTemplate = entry.key;
                            _notifyMode = 'template';
                          }),
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _selectedTemplate == entry.key
                                  ? AppConstants.surfaceLight
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _selectedTemplate == entry.key
                                    ? AppConstants.primary
                                    : AppConstants.borderGray,
                              ),
                            ),
                            child: Text(
                              entry.value,
                              style: AppConstants.bodyStyle(fontSize: 11),
                            ),
                          ),
                        ),
                      GestureDetector(
                        onTap: () => setState(() {
                          _notifyMode = 'custom';
                          _selectedTemplate = null;
                        }),
                        child: Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _notifyMode == 'custom'
                                  ? AppConstants.primary
                                  : AppConstants.borderGray,
                              style: _notifyMode == 'custom' ? BorderStyle.solid : BorderStyle.solid,
                            ),
                          ),
                          child: Text(
                            '✏️ Write custom message',
                            style: AppConstants.bodyStyle(fontSize: 11, color: Colors.black54),
                          ),
                        ),
                      ),
                      if (_notifyMode == 'custom') ...[
                        TextField(
                          controller: _customCtrl,
                          maxLines: 2,
                          style: AppConstants.bodyStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Type a custom message…',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppConstants.borderGray),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => setState(() {
                              _notifyOpen = false;
                              _notifyMode = null;
                              _selectedTemplate = null;
                              _customCtrl.clear();
                            }),
                            child: Text('Cancel', style: AppConstants.bodyStyle(fontSize: 13, color: Colors.black54)),
                          ),
                          const Spacer(),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppConstants.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            ),
                            onPressed: _saving ||
                                    (_notifyMode == 'template'
                                        ? _selectedTemplate == null
                                        : _customCtrl.text.trim().isEmpty)
                                ? null
                                : _handleNotify,
                            child: Text(
                              _saving ? 'Sending…' : 'Send',
                              style: AppConstants.bodyStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppConstants.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _saving ? null : _handleSave,
                  child: Text(
                    _saving ? 'Saving…' : 'Save Changes',
                    style: AppConstants.bodyStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropdown(String value, List<String> options, ValueChanged<String> onChanged) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppConstants.borderGray),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: Colors.white,
          style: AppConstants.bodyStyle(fontSize: 13),
          items: [
            for (final s in options)
              DropdownMenuItem(value: s, child: Text(_titleCase(s))),
          ],
          onChanged: (v) => onChanged(v ?? value),
        ),
      ),
    );
  }
}
