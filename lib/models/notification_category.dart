/// Shared notification categories for the order-status notification feed.
///
/// These map 1:1 to order lifecycle events and match the
/// `notification_category` Postgres enum in the migrations.
enum NotificationCategory { unpaid, processing, shipped, review, returns }

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
  }
}
