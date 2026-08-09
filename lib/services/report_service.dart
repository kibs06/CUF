import 'dart:async';
import 'package:flutter/foundation.dart';
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

  /// Human-readable status labels for notification messages.
  static const Map<String, String> statusLabels = {
    'pending': 'Pending',
    'under_review': 'Under Review',
    'resolved': 'Resolved',
    'dismissed': 'Dismissed',
  };

  /// Human-readable report type labels for notification messages.
  static const Map<String, String> typeLabels = {
    'message': 'Message Report',
    'product': 'Product Report',
    'seller': 'Seller Report',
    'other': 'General Report',
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

    return response;
  }

  // ── Fetch a single report by ID (for detail view) ───────────────

  Future<Map<String, dynamic>?> getReportById(String reportId) async {
    final response = await _client
        .from('reports')
        .select('*, profiles!reports_reporter_id_fkey(full_name, email, avatar_url, role)')
        .eq('id', reportId)
        .maybeSingle();

    return response;
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

    return response;
  }

  // ── Admin: Update report status/action ───────────────────────────

  Future<void> updateReport({
    required String reportId,
    String? status,
    String? actionTaken,
    String? adminNotes,
  }) async {
    // 1. Only fetch if we need to check status change or validate resolve
    String? oldStatus;
    String? reporterId;
    bool statusChanged = false;
    String reportType = 'other'; // default; set inside the block below

    if (status != null) {
      final existing = await getReportById(reportId);
      if (existing == null) throw Exception('Report not found');
      oldStatus = existing['status']?.toString() ?? 'pending';
      reportType = existing['type']?.toString() ?? 'other';
      reporterId = existing['reporter_id']?.toString();
      statusChanged = status != oldStatus;

      // Validate: resolving requires action_taken
      if (status == 'resolved' && actionTaken == null) {
        if (existing['action_taken'] == null || existing['action_taken'] == 'none') {
          throw Exception('action_required_to_resolve');
        }
      }
    }

    // 2. Perform the update
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (status != null) updates['status'] = status;
    if (actionTaken != null) updates['action_taken'] = actionTaken;
    if (adminNotes != null) updates['admin_notes'] = adminNotes;

    await _client.from('reports').update(updates).eq('id', reportId);

    // 3. If status actually changed, fire notification + push (fire-and-forget)
    // status is guaranteed non-null here because statusChanged can only be true
    // when status != oldStatus, which requires status != null.
    if (statusChanged && reporterId != null && reporterId.isNotEmpty && status != null) {
      final statusLabel = statusLabels[status] ?? status;
      final typeLabel = typeLabels[reportType] ?? 'Report';

      _fireStatusChangeNotification(
        reportId: reportId,
        reporterId: reporterId,
        reportType: reportType,
        typeLabel: typeLabel,
        newStatus: status,
        statusLabel: statusLabel,
      );
    }
  }

  /// Fires a status-change notification + push to the reporter.
  void _fireStatusChangeNotification({
    required String reportId,
    required String reporterId,
    required String reportType,
    required String typeLabel,
    required String newStatus,
    required String statusLabel,
  }) {
    final title = 'Report Update';
    final body = 'Your $typeLabel is now $statusLabel.';

    _insertNotificationAndPush(
      userId: reporterId,
      title: title,
      body: body,
      metadata: {
        'report_id': reportId,
        'report_type': reportType,
        'notification_type': 'report_status_update',
        'new_status': newStatus,
        'order_type': 'custom',
      },
      pushType: 'report_update',
      pushReferenceId: reportId,
      pushScreen: 'my_reports',
    );
  }

  // ── Admin: Notify reporter ───────────────────────────────────────

  /// Notifies the reporter of a report outcome (support response).
  ///
  /// This method performs three steps:
  /// 1. Inserts a row into the `notifications` table (so it appears in the
  ///    reporter's notification feed under the "Custom" tab)
  /// 2. Updates the report row with reporter_notified + reporter_notification_text
  ///    (set AFTER notification insert so the flag reflects delivery attempt)
  /// 3. Triggers a push notification via the send-notification-push edge function
  ///
  /// Push delivery is fire-and-forget — failures are logged but never thrown,
  /// because the DB notification + report update are the critical path.
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

    // 1. Fetch the report to get the reporter_id
    final report = await getReportById(reportId);
    if (report == null) throw Exception('Report not found');

    final reporterId = report['reporter_id']?.toString();
    if (reporterId == null || reporterId.isEmpty) {
      throw Exception('Report has no reporter_id');
    }

    // 2. Insert into notifications table (appears in the reporter's feed under Custom tab)
    _insertNotificationAndPush(
      userId: reporterId,
      title: 'Support Responded',
      body: messageText.length > 100 ? '${messageText.substring(0, 100)}...' : messageText,
      metadata: {
        'report_id': reportId,
        'report_type': report['type']?.toString() ?? 'other',
        'notification_type': 'report_support_response',
        'order_type': 'custom',
      },
      pushType: 'report_update',
      pushTitle: 'Support Responded',
      pushBody: messageText.length > 100 ? '${messageText.substring(0, 100)}...' : messageText,
      pushReferenceId: reportId,
      pushScreen: 'my_reports',
    );

    // 3. Update the report row (set reporter_notified AFTER notification insert
    // so the flag accurately reflects delivery attempt)
    await _client.from('reports').update({
      'reporter_notified': true,
      'reporter_notification_text': messageText,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', reportId);
  }

  // ── Shared notification + push helper ────────────────────────────

  /// Inserts an in-app notification row and triggers a push notification.
  /// Both are fire-and-forget — failures are logged but never thrown.
  void _insertNotificationAndPush({
    required String userId,
    required String title,
    required String body,
    required Map<String, dynamic> metadata,
    required String pushType,
    String? pushTitle,
    String? pushBody,
    String? pushReferenceId,
    String? pushScreen,
  }) {
    // Insert in-app notification (fire-and-forget)
    // order_type: 'custom' ensures it appears in the Custom tab
    _client.from('notifications').insert({
      'user_id': userId,
      'category': 'support',
      'title': title,
      'message': body,
      'order_type': 'custom',
      'is_read': false,
      'metadata': metadata,
    }).catchError((e) {
      _log('Failed to insert notification: $e');
    });

    // Trigger push notification
    _triggerPush(
      recipientUserId: userId,
      type: pushType,
      title: pushTitle ?? title,
      body: pushBody ?? body,
      referenceId: pushReferenceId,
      screen: pushScreen,
    );
  }

  /// Fire-and-forget push to a user device via the send-notification-push edge function.
  void _triggerPush({
    required String recipientUserId,
    required String type,
    required String title,
    required String body,
    String? referenceId,
    String? screen,
  }) {
    final payload = <String, dynamic>{
      'recipientUserId': recipientUserId,
      'title': title,
      'body': body,
      'type': type,
    };
    if (referenceId != null) payload['referenceId'] = referenceId;
    if (screen != null) payload['screen'] = screen;
    unawaited(_client.functions.invoke('send-notification-push', body: payload).then(
      (_) {},
      onError: (Object e) {
        _log('Push trigger failed: $e');
      },
    ));
  }

  void _log(String message) {
    debugPrint('[ReportService] $message');
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
