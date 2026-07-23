import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for submitting and fetching user reports (messages, products, sellers, general).
///
/// Categories use machine keys (e.g. "spam_scam") as stored values.
/// Display labels are provided separately via [categoryLabel].
class ReportService {
  ReportService._();
  static final ReportService instance = ReportService._();

  final _client = Supabase.instance.client;

  // ── Category definitions: machine key → display label ─────────────

  static const Map<String, Map<String, String>> categoriesByType = {
    'message': {
      'harassment': 'Harassment / abusive language',
      'spam_scam': 'Spam or scam attempt',
      'inappropriate_content': 'Inappropriate content (images, links, etc.)',
      'off_platform': 'Trying to move the deal off-platform',
      'other': 'Other',
    },
    'product': {
      'not_as_described': 'Item not as described',
      'damaged_defective': 'Item damaged or defective',
      'wrong_item': 'Wrong item received',
      'never_received': 'Item never received',
      'seller_refuses': 'Seller refuses to resolve/negotiate',
      'buyer_misuse': 'Customer damaged/misused item before dispute',
      'other': 'Other',
    },
    'seller': {
      'scam_fraud': 'Suspected scam or fraud',
      'fake_listings': 'Fake or misleading listings',
      'counterfeit': 'Counterfeit goods',
      'repeated_violations': 'Repeated policy violations',
      'harassment_outside_chat': 'Harassment outside the chat',
      'other': 'Other',
    },
    'other': {
      'app_bug': 'App bug or technical issue',
      'payment_billing': 'Payment or billing issue',
      'account_issue': 'Account issue',
      'general_feedback': 'General complaint / feedback',
      'other': 'Other',
    },
  };

  // ── High-priority categories ────────────────────────────────────

  static const Set<String> highPriorityCategories = {
    'spam_scam',
    'never_received',
    'scam_fraud',
    'counterfeit',
  };

  // ── Notification templates (exact copy from spec) ────────────────

  static const Map<String, String> notificationTemplates = {
    'reviewed_action_taken':
        "We've reviewed your report and taken action. Thank you for helping keep our community safe.",
    'reviewed_no_violation':
        "We've reviewed your report and didn't find a violation of our policies. Thanks for flagging it — feel free to reach out if anything else comes up.",
    'needs_more_info':
        "We're looking into your report and may reach out if we need more details. Thanks for your patience.",
  };

  /// Get display label for a machine key within a report type.
  static String categoryLabel(String type, String key) {
    return categoriesByType[type]?[key] ?? key;
  }

  /// Get all categories for a type as [machineKey, displayLabel] pairs.
  static List<MapEntry<String, String>> categoriesForType(String type) {
    final cats = categoriesByType[type];
    if (cats == null) return [];
    return cats.entries.toList();
  }

  // ── Submit a report ──────────────────────────────────────────────

  Future<void> submitReport({
    required String reporterRole, // 'customer' | 'seller'
    required String type, // 'message' | 'product' | 'seller' | 'other'
    required String category, // machine key e.g. "spam_scam"
    String? customDetails, // only for category == 'other'
    String? targetMessageId,
    int? targetOrderId,
    String? targetSellerId,
    String? targetStoreId,
    String? targetProductId,
    String? conversationId,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    // Validate: 'other' category requires customDetails (min 10 chars)
    if (category == 'other') {
      final trimmed = customDetails?.trim() ?? '';
      if (trimmed.isEmpty) {
        throw Exception('Please describe the issue.');
      }
      if (trimmed.length < 10) {
        throw Exception('Please add a few more details (min 10 characters).');
      }
      if (trimmed.length > 500) {
        throw Exception('Custom details must be 500 characters or fewer.');
      }
    }

    final data = <String, dynamic>{
      'reporter_id': userId,
      'reporter_role': reporterRole,
      'type': type,
      'category': category,
      'custom_details': category == 'other' ? customDetails?.trim() : null,
      'target_message_id': targetMessageId,
      'target_order_id': targetOrderId,
      'target_seller_id': targetSellerId,
      'target_store_id': targetStoreId,
      'target_product_id': targetProductId,
      'conversation_id': conversationId,
    };

    // Remove null values
    data.removeWhere((_, v) => v == null);

    await _client.from('reports').insert(data);
  }

  // ── Fetch reports for the current user ───────────────────────────

  Future<List<Map<String, dynamic>>> getMyReports() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await _client
        .from('reports')
        .select('*')
        .eq('reporter_id', userId)
        .order('created_at', ascending: false);

    return (response as List<dynamic>).cast<Map<String, dynamic>>();
  }

  // ── Fetch a single report by ID (for detail view) ───────────────

  Future<Map<String, dynamic>?> getReportById(String reportId) async {
    final response = await _client
        .from('reports')
        .select('*, profiles!reports_reporter_id_fkey(full_name, email, avatar_url, role)')
        .eq('id', reportId)
        .maybeSingle();

    return response as Map<String, dynamic>?;
  }

  // ── Admin: Fetch all reports with filters ────────────────────────

  Future<List<Map<String, dynamic>>> getAllReports({
    String? typeFilter,
    String? statusFilter,
    String? priorityFilter,
    int limit = 50,
    int offset = 0,
  }) async {
    var query = _client
        .from('reports')
        .select('*, profiles!reports_reporter_id_fkey(full_name, email, avatar_url)');

    if (typeFilter != null && typeFilter != 'all') {
      query = query.eq('type', typeFilter);
    }
    if (statusFilter != null && statusFilter != 'all') {
      query = query.eq('status', statusFilter);
    }
    if (priorityFilter != null && priorityFilter != 'all') {
      query = query.eq('priority', priorityFilter);
    }

    final response = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (response as List<dynamic>).cast<Map<String, dynamic>>();
  }

  // ── Admin: Update report status/action ───────────────────────────

  Future<void> updateReport({
    required String reportId,
    String? status,
    String? actionTaken,
    String? adminNotes,
  }) async {
    // Validate: resolving requires action_taken
    if (status == 'resolved' && actionTaken == null) {
      final existing = await getReportById(reportId);
      if (existing != null && (existing['action_taken'] == null || existing['action_taken'] == 'none')) {
        throw Exception('action_required_to_resolve');
      }
    }

    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (status != null) updates['status'] = status;
    if (actionTaken != null) updates['action_taken'] = actionTaken;
    if (adminNotes != null) updates['admin_notes'] = adminNotes;

    await _client.from('reports').update(updates).eq('id', reportId);
  }

  // ── Admin: Notify reporter ───────────────────────────────────────

  Future<void> notifyReporter({
    required String reportId,
    String? templateKey,
    String? customText,
  }) async {
    String messageText;
    if (customText != null && customText.trim().isNotEmpty) {
      messageText = customText.trim();
    } else if (templateKey != null && notificationTemplates.containsKey(templateKey)) {
      messageText = notificationTemplates[templateKey]!;
    } else {
      throw Exception('Either templateKey or customText must be provided');
    }

    await _client.from('reports').update({
      'reporter_notified': true,
      'reporter_notification_text': messageText,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', reportId);
  }

  // ── Admin: Get report counts by status ───────────────────────────

  Future<Map<String, int>> getReportCounts() async {
    final results = await Future.wait([
      _client.from('reports').select().count(CountOption.exact),
      _client.from('reports').select().eq('status', 'pending').count(CountOption.exact),
      _client.from('reports').select().eq('priority', 'high').count(CountOption.exact),
      _client.from('reports').select().eq('status', 'resolved').count(CountOption.exact),
    ]);

    return {
      'total': results[0].count,
      'pending': results[1].count,
      'high_priority': results[2].count,
      'resolved': results[3].count,
    };
  }
}
