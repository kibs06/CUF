/// Shared notification categories for the notification feed.
///
/// These match the `notification_category` Postgres enum in the migrations.
/// 'message' was added for push notification support (seller → customer messages).
/// 'support' was added for admin report response notifications.
enum NotificationCategory { unpaid, processing, shipped, review, returns, message, support }

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
  }
}
