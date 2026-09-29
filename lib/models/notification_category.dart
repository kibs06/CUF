/// Shared notification categories for the notification feed.
///
/// These match the `notification_category` Postgres enum in the migrations.
/// 'message' was added for push notification support (seller → customer messages).
/// 'support' was added for admin report response notifications.
/// 'approval' was added for the seller-application-approved notification
/// (DB trigger trg_notify_on_seller_approved).
/// 'models' was added for the 3D-model-ready notification, written by
/// `fulfil_shoe_model_request` (V2.11, P3 — migration
/// 20260928130000_add_models_notification_category.sql).
///
/// The list is checked against the SQL in both directions by
/// `test/services/notification_category_contract_test.dart`: a name added here
/// without its `ALTER TYPE` would be a value the database cannot store, and a
/// label added there without a case here would arrive as `unpaid` (the
/// parser's fallback) on a real seller's screen.
enum NotificationCategory {
  unpaid,
  processing,
  shipped,
  review,
  returns,
  message,
  support,
  approval,
  reservations,
  models,
}

/// Returns a display-friendly label for each category.
String notificationCategoryLabel(NotificationCategory cat) {
  switch (cat) {
    case NotificationCategory.unpaid:
      return 'Unpaid';
    case NotificationCategory.processing:
      return 'Processing';
    case NotificationCategory.shipped:
      return 'Shipped';
    case NotificationCategory.review:
      return 'Review';
    case NotificationCategory.returns:
      return 'Returns';
    case NotificationCategory.message:
      return 'Message';
    case NotificationCategory.support:
      return 'Support';
    case NotificationCategory.approval:
      return 'Approval';
    case NotificationCategory.reservations:
      return 'Reservation';
    case NotificationCategory.models:
      return '3D fitting';
  }
}
