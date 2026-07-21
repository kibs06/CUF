# SoleVision — Notifications System Architecture

**Version:** 1.0.0  
**Last Updated:** July 16, 2026  
**Purpose:** Complete reference for the notification system — customer in-app, seller in-app, and push notifications.

---

## Table of Contents

1. [Overview](#1-overview)
2. [System Architecture](#2-system-architecture)
3. [Customer Notifications](#3-customer-notifications)
4. [Seller Notifications](#4-seller-notifications)
5. [Push Notifications](#5-push-notifications)
6. [Data Models](#6-data-models)
7. [Database Schema](#7-database-schema)
8. [Data Flow Diagrams](#8-data-flow-diagrams)
9. [Notification Creation Points](#9-notification-creation-points)
10. [UI Components](#10-ui-components)
11. [Known Issues](#11-known-issues)

---

## 1. Overview

SoleVision has **three notification systems** that work together:

| System | Scope | Table | Purpose |
|--------|-------|-------|---------|
| **Customer In-App** | Customer | `notifications` | Order status updates, message notifications |
| **Seller In-App** | Seller | `seller_notifications` | New orders, stale orders, low stock, messages, custom requests |
| **Push (FCM)** | Both | `device_tokens` | OS-level notifications when app is background/killed |

### Notification Types

| Type | Direction | Trigger | UI |
|------|-----------|---------|-----|
| `unpaid` | System → Customer | Order placed with unpaid status | Customer notification feed |
| `processing` | System → Customer | Order status changes to preparing | Customer notification feed |
| `shipped` | System → Customer | Order status changes to ready | Customer notification feed |
| `review` | System → Customer | Order delivered, awaiting review | Customer notification feed |
| `returns` | System → Customer | Return requested | Customer notification feed |
| `message` | Seller → Customer | New message in conversation | Customer notification feed + push |
| `new_order` | System → Seller | Customer places order | Seller notification center |
| `stale_order` | System → Seller | Order pending too long | Seller notification center |
| `low_stock` | System → Seller | Product stock drops low | Seller notification center |
| `custom_order_request` | Customer → Seller | Custom order submitted | Seller notification center |
| `new_message` | Customer → Seller | New message in conversation | Seller notification center + push |

---

## 2. System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    NOTIFICATION SYSTEMS                          │
│                                                                 │
│  ┌─────────────────────┐  ┌─────────────────────┐              │
│  │  CUSTOMER IN-APP    │  │   SELLER IN-APP     │              │
│  │                     │  │                     │              │
│  │  notifications      │  │  seller_notifications│              │
│  │  table              │  │  table              │              │
│  │                     │  │                     │              │
│  │  ┌───────────────┐  │  │  ┌───────────────┐  │              │
│  │  │NotificationSvc│  │  │  │SellerNotifSvc │  │              │
│  │  └───────┬───────┘  │  │  └───────┬───────┘  │              │
│  │          │          │  │          │          │              │
│  │  ┌───────┴───────┐  │  │  ┌───────┴───────┐  │              │
│  │  │Notification   │  │  │  │SellerNotif    │  │              │
│  │  │Provider       │  │  │  │Provider       │  │              │
│  │  └───────┬───────┘  │  │  └───────┬───────┘  │              │
│  │          │          │  │          │          │              │
│  │  ┌───────┴───────┐  │  │  ┌───────┴───────┐  │              │
│  │  │Notifications  │  │  │  │SellerNotif    │  │              │
│  │  │Screen         │  │  │  │CenterScreen   │  │              │
│  │  └───────────────┘  │  │  └───────────────┘  │              │
│  └─────────────────────┘  └─────────────────────┘              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  PUSH NOTIFICATIONS (FCM)                │   │
│  │                                                         │   │
│  │  ┌───────────────┐     ┌──────────────────────────┐    │   │
│  │  │MessageService │────→│Edge Function:             │    │   │
│  │  │._triggerPush() │     │send-message-push          │    │   │
│  │  └───────────────┘     │                           │    │   │
│  │                        │ 1. Lookup recipient       │    │   │
│  │                        │ 2. Query device_tokens    │    │   │
│  │                        │ 3. Build FCM payload      │    │   │
│  │                        │ 4. Send via FCM HTTP v1   │    │   │
│  │                        └──────────────────────────┘    │   │
│  │                                                         │   │
│  │  ┌───────────────┐     ┌──────────────────────────┐    │   │
│  │  │PushNotifSvc   │←────│Firebase Cloud Messaging   │    │   │
│  │  │               │     │                           │    │   │
│  │  │ foreground    │     │  • Background: OS displays │    │   │
│  │  │ background    │     │  • Foreground: local notif │    │   │
│  │  │ cold start    │     │  • Tap: deep-link navigate │    │   │
│  │  └───────────────┘     └──────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### File Reference

| File | Purpose |
|------|---------|
| `lib/models/app_notification.dart` | Customer notification data model |
| `lib/models/notification_category.dart` | Notification category enum |
| `lib/services/notification_service.dart` | Customer notification CRUD |
| `lib/providers/notification_provider.dart` | Customer notification state |
| `lib/screens/notifications_screen.dart` | Customer notification feed UI |
| `lib/services/seller_notification_service.dart` | Seller notification CRUD + creation helpers |
| `lib/providers/seller_notification_provider.dart` | Seller notification state + realtime |
| `lib/screens/seller/seller_notification_center_screen.dart` | Seller notification center UI |
| `lib/services/push_notification_service.dart` | FCM token management + foreground display |
| `lib/services/message_service.dart` | Triggers push after message send |
| `supabase/functions/send-message-push/index.ts` | Edge Function for FCM delivery |

---

## 3. Customer Notifications

### 3.1 Notification Categories

```dart
enum NotificationCategory { 
  unpaid,       // Order placed, awaiting payment
  processing,   // Order being prepared
  shipped,      // Order ready for pickup/delivery
  review,       // Order delivered, awaiting review
  returns,      // Return requested
  message       // New message from store
}
```

### 3.2 Data Model: AppNotification

```dart
class AppNotification {
  final String id;
  final String? orderId;                    // Links to order (for order notifications)
  final NotificationCategory category;
  final String title;                       // "New order #f8adaf22"
  final String message;                     // "₱1,299 — tap to view"
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;     // JSONB (conversation_id, store_name, sender_id)

  // Computed getters
  String? get conversationId;               // From metadata (message notifications)
  String? get storeName;                    // From metadata (message notifications)
  String? get senderId;                     // From metadata (message notifications)
  bool get isMessageNotification;           // category == message
  String get relativeTime;                  // "2h ago", "3d ago"
}
```

### 3.3 Service: NotificationService

**File:** `lib/services/notification_service.dart`

| Method | Purpose | SQL |
|--------|---------|-----|
| `fetchNotifications()` | Get notifications with optional filters | `SELECT * FROM notifications WHERE user_id = ?` |
| `fetchUnreadCounts()` | Get unread counts grouped by category | `SELECT category FROM notifications WHERE user_id = ? AND is_read = false` |
| `markAsRead()` | Mark single notification as read | `UPDATE notifications SET is_read = true WHERE id = ?` |
| `markAllAsRead()` | Mark all as read (optional category scope) | `UPDATE notifications SET is_read = true WHERE user_id = ? AND is_read = false` |

### 3.4 Provider: NotificationProvider

**File:** `lib/providers/notification_provider.dart`

```dart
class NotificationProvider extends ChangeNotifier {
  List<AppNotification> _notifications;
  Map<NotificationCategory, int> _unreadCounts;
  bool _isLoading;
  String? _userId;

  // Computed
  int get totalUnread;  // Sum of all unread counts

  // Methods
  Future<void> loadNotifications({categoryFilter, orderTypeFilter});
  Future<void> loadUnreadCounts();
  Future<void> markAsRead(String id);       // Optimistic with rollback
  Future<void> markAllAsRead();             // Optimistic with rollback
}
```

**Lifecycle:**
- Constructor listens to `Supabase.instance.client.auth.onAuthStateChange`
- On login: loads unread counts immediately
- On logout: clears all state

### 3.5 Screen: NotificationsScreen

**File:** `lib/screens/notifications_screen.dart`

```
NotificationsScreen
├── AppBar
│   ├── Title: "Notifications"
│   ├── "Mark all read" button (if unread > 0)
│   └── TabBar: All | Catalog | Custom
│
├── Category filter (optional, from profile screen)
│
└── ListView of _NotificationCard
    ├── Leading icon (category-colored circle)
    ├── Title + unread dot
    ├── Message preview
    ├── Relative timestamp
    └── onTap → _handleTap()
        ├── Mark as read
        ├── If message → ChatView
        └── If order → fetch order → OrderTrackingScreen
```

**Entry Points:**
- CustomerShell Tab 2 (Notifications icon)
- Profile screen "My Orders" icon row (with category filter)

---

## 4. Seller Notifications

### 4.1 Notification Types

| Type | Icon | Color | Trigger | Deduplication |
|------|------|-------|---------|---------------|
| `new_order` | Receipt | Blue | Customer places order | No (each order gets one) |
| `stale_order` | Clock | Amber | Order pending > X hours | Yes (per order) |
| `low_stock` | Warning | Red | Stock drops to 0 or ≤5 | Yes (per product+size) |
| `custom_order_request` | Design | Brand | Customer submits custom order | No |
| `new_message` | Chat | Blue | Customer sends message | Yes (per conversation) |

### 4.2 Data Model: SellerNotification

```dart
class SellerNotification {
  final String id;
  final String storeId;
  final String type;          // 'new_order' | 'stale_order' | 'low_stock' | etc.
  final String title;         // "New order #f8adaf22"
  final String body;          // "₱1,299 — tap to view"
  final String? referenceId;  // Order ID, product ID, or conversation ID
  final bool isRead;
  final DateTime createdAt;

  String get relativeTime;    // "5 min ago", "3d ago"
}
```

### 4.3 Service: SellerNotificationService

**File:** `lib/services/seller_notification_service.dart`

| Method | Purpose | Deduplication |
|--------|---------|---------------|
| `getNotifications(storeId)` | Fetch recent notifications | — |
| `getUnreadCount(storeId)` | Count unread for badge | — |
| `markAsRead(id)` | Mark single as read | — |
| `markAllAsRead(storeId)` | Mark all as read | — |
| `createNewOrder()` | Insert new order notification | No |
| `createStaleOrder()` | Insert stale order alert | Yes (per order) |
| `createLowStock()` | Insert low stock alert | Yes (per product+size) |
| `createNewMessage()` | Insert message notification | Yes (per conversation) |
| `createCustomOrderRequest()` | Insert custom order alert | No |

**Deduplication Pattern:**
```dart
Future<void> createStaleOrder({...}) async {
  // Check if unread notification already exists for this order
  final existing = await _client
      .from('seller_notifications')
      .select('id')
      .eq('store_id', storeId)
      .eq('type', 'stale_order')
      .eq('reference_id', orderId)
      .eq('is_read', false)
      .limit(1);

  if ((existing as List).isNotEmpty) return; // already notified

  // Create new notification
  await _create(...);
}
```

### 4.4 Provider: SellerNotificationProvider

**File:** `lib/providers/seller_notification_provider.dart`

```dart
class SellerNotificationProvider extends ChangeNotifier {
  List<SellerNotification> _notifications;
  int _unreadCount;
  bool _isLoading;
  String? _storeId;
  StreamSubscription? _realtimeSub;

  // Computed
  String get unreadBadge;  // "9+" if > 9, else count
  bool get hasUnread;

  // Methods
  void init(String storeId);              // Start listening
  void reset();                          // Clear on logout
  Future<void> loadNotifications();      // Fetch from DB
  Future<void> loadUnreadCount();        // Count unread
  Future<void> markAsRead(String id);    // Optimistic with rollback
  Future<void> markAllAsRead();          // Optimistic with rollback
  Future<void> refreshNotifications();   // Force refresh count
}
```

**Realtime Subscription:**
```dart
void _subscribeToRealtime() {
  _realtimeSub = _client
      .from('seller_notifications')
      .stream(primaryKey: ['id'])
      .eq('store_id', _storeId!)
      .order('created_at', ascending: false)
      .limit(50)
      .listen((data) {
        _notifications = data.map(...).toList();
        _unreadCount = _notifications.where((n) => !n.isRead).length;
        notifyListeners();
      });
}
```

### 4.5 Screen: SellerNotificationCenterScreen

**File:** `lib/screens/seller/seller_notification_center_screen.dart`

```
SellerNotificationCenterScreen
├── AppBar
│   ├── Title: "Notifications"
│   ├── Back button
│   └── "Mark all read" button (if unread)
│
└── ListView of _NotificationRow
    ├── Leading icon (type-colored circle)
    ├── Title + unread dot
    ├── Body preview
    ├── Relative timestamp
    └── onTap → _handleTap()
        ├── Mark as read
        └── Navigate based on type:
            ├── new_order/stale_order → OrderDetailScreen
            ├── low_stock → ManageInventoryScreen
            ├── custom_order_request → CustomOrdersScreen
            └── new_message → SellerInboxScreen
```

---

## 5. Push Notifications

### 5.1 Flow Overview

```
MessageService.sendMessage()
  └→ _createMessageNotification()
       ├→ SellerNotificationService.createNewMessage() (if customer→seller)
       └→ _triggerPushNotification() (fire-and-forget)
            └→ Edge Function: send-message-push
                 ├→ Lookup recipient (customer_id or store.owner_id)
                 ├→ Query device_tokens for FCM tokens
                 ├→ Build title (store name or customer name)
                 └→ Send via FCM HTTP v1 API
                      └→ Firebase delivers to devices
```

### 5.2 PushNotificationService

**File:** `lib/services/push_notification_service.dart`

```dart
class PushNotificationService {
  static final PushNotificationService instance = PushNotificationService._();

  // Callbacks (set by shell screens)
  void Function(String conversationId, String storeName)? onNavigateToChat;
  void Function(String conversationId, String targetUserId)? onWrongAccount;

  // Methods
  Future<void> init();           // Request permission, get token, setup listeners
  void _storeToken(String token); // Store FCM token in device_tokens table
  void _handleForegroundMessage(RemoteMessage message);  // Show local notification
  void _handleNotificationTap(RemoteMessage message);    // Deep-link navigation
}
```

### 5.3 Notification Title Logic

| Direction | Recipient | Title | Source |
|-----------|-----------|-------|--------|
| Seller → Customer | Customer | Store name | `stores.name` |
| Customer → Seller | Seller | Customer name | `profiles.full_name` |

### 5.4 Deep-Link Navigation

```
User taps push notification
  │
  ├── App in FOREGROUND
  │   └── onMessage listener → flutter_local_notifications.show()
  │
  ├── App in BACKGROUND
  │   └── OS auto-displays → user taps → onMessageOpenedApp
  │        └── _handleNotificationTap()
  │             └── onNavigateToChat?.call(conversationId, storeName)
  │
  └── App TERMINATED
       └── OS auto-displays → user taps → getInitialMessage
            └── _handleNotificationTap()
                 └── onNavigateToChat?.call(conversationId, storeName)
```

### 5.5 Wrong-Account Detection

```dart
// In _handleNotificationTap():
final targetUserId = data['target_user_id'] as String?;
final currentUserId = Supabase.instance.client.auth.currentUser?.id;

if (targetUserId != null && currentUserId != null && targetUserId != currentUserId) {
  // Notification is for a different account
  onWrongAccount?.call(conversationId, targetUserId);
  return;
}

onNavigateToChat?.call(conversationId, storeName);
```

---

## 6. Data Models

### AppNotification (Customer)

| Field | Type | Source |
|-------|------|--------|
| `id` | String | `notifications.id` |
| `orderId` | String? | `notifications.order_id` |
| `category` | NotificationCategory | `notifications.category` (enum) |
| `title` | String | `notifications.title` |
| `message` | String | `notifications.message` |
| `isRead` | bool | `notifications.is_read` |
| `createdAt` | DateTime | `notifications.created_at` |
| `metadata` | Map? | `notifications.metadata` (JSONB) |

**Metadata fields (for message notifications):**
- `conversation_id` — Links to conversation
- `store_name` — Store name for display
- `sender_id` — Sender's user ID

### SellerNotification (Seller)

| Field | Type | Source |
|-------|------|--------|
| `id` | String | `seller_notifications.id` |
| `storeId` | String | `seller_notifications.store_id` |
| `type` | String | `seller_notifications.type` |
| `title` | String | `seller_notifications.title` |
| `body` | String | `seller_notifications.body` |
| `referenceId` | String? | `seller_notifications.reference_id` |
| `isRead` | bool | `seller_notifications.is_read` |
| `createdAt` | DateTime | `seller_notifications.created_at` |

---

## 7. Database Schema

### `notifications` Table (Customer)

```sql
CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  order_id TEXT,
  category notification_category NOT NULL,
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  metadata JSONB DEFAULT NULL
);

-- Enum type
CREATE TYPE notification_category AS ENUM (
  'unpaid', 'processing', 'shipped', 'review', 'returns', 'message'
);
```

**RLS Policies:**
```sql
-- Users can read their own notifications
CREATE POLICY "Users can read own notifications"
  ON notifications FOR SELECT
  USING (auth.uid() = user_id);

-- System can insert notifications (via triggers/service role)
CREATE POLICY "System can insert notifications"
  ON notifications FOR INSERT
  WITH CHECK (true);

-- Users can update their own (mark as read)
CREATE POLICY "Users can update own notifications"
  ON notifications FOR UPDATE
  USING (auth.uid() = user_id);
```

### `seller_notifications` Table (Seller)

```sql
CREATE TABLE IF NOT EXISTS public.seller_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  reference_id TEXT,
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

**RLS Policies:**
```sql
-- Store owners can read their store's notifications
CREATE POLICY "Store owners can read notifications"
  ON seller_notifications FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM stores
      WHERE stores.id = store_id AND stores.owner_id = auth.uid()
    )
  );

-- System can insert (via triggers/service role)
CREATE POLICY "System can insert seller notifications"
  ON seller_notifications FOR INSERT
  WITH CHECK (true);

-- Store owners can update their own
CREATE POLICY "Store owners can update notifications"
  ON seller_notifications FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM stores
      WHERE stores.id = store_id AND stores.owner_id = auth.uid()
    )
  );
```

### `device_tokens` Table (Push)

```sql
CREATE TABLE IF NOT EXISTS public.device_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fcm_token TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(customer_id, fcm_token)
);
```

### DB Trigger: Notify on New Message

```sql
CREATE OR REPLACE FUNCTION notify_on_new_message()
RETURNS TRIGGER AS $$
BEGIN
  -- Create in-app notification for seller→customer messages
  IF NEW.sender_type = 'seller' THEN
    INSERT INTO notifications (user_id, category, title, message, metadata)
    SELECT
      NEW.sender_id,  -- This is actually the customer_id from conversations
      'message',
      'New message',
      LEFT(NEW.body, 100),
      jsonb_build_object(
        'conversation_id', NEW.conversation_id,
        'store_name', (SELECT name FROM stores WHERE id = (SELECT store_id FROM conversations WHERE id = NEW.conversation_id)),
        'sender_id', NEW.sender_id
      );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_new_message_notify
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION notify_on_new_message();
```

---

## 8. Data Flow Diagrams

### 8.1 Customer Notification Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    CUSTOMER NOTIFICATION FLOW                │
│                                                             │
│  ORDER STATUS CHANGE                                        │
│  ────────────────────                                       │
│  Seller updates order status                                │
│       │                                                     │
│       ├── DB trigger or app code inserts into notifications │
│       │    table with appropriate category                  │
│       │                                                     │
│       └── Customer opens NotificationsScreen                │
│            ├── loadNotifications() → fetch from DB          │
│            ├── Tab: All / Catalog / Custom                  │
│            ├── Category filter (optional)                   │
│            └── Tap card → mark read + navigate to tracking  │
│                                                             │
│  MESSAGE NOTIFICATION                                       │
│  ─────────────────────                                      │
│  Seller sends message                                       │
│       │                                                     │
│       ├── DB trigger creates notification (category=message)│
│       ├── _triggerPushNotification() → Edge Function → FCM │
│       │                                                     │
│       └── Customer receives:                                │
│            ├── Foreground: local notification banner        │
│            ├── Background: OS notification                  │
│            └── Tap → deep-link to ChatView                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 8.2 Seller Notification Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    SELLER NOTIFICATION FLOW                  │
│                                                             │
│  NEW ORDER                                                  │
│  ──────────                                                 │
│  Customer places order                                      │
│       │                                                     │
│       ├── SupabaseService.createOrder()                     │
│       │    └── SellerNotificationService.createNewOrder()   │
│       │         └── INSERT INTO seller_notifications        │
│       │                                                     │
│       └── SellerDashboardScreen                             │
│            ├── Bell icon shows unread badge                 │
│            └── Tap → SellerNotificationCenterScreen         │
│                 └── Tap notification → OrderDetailScreen    │
│                                                             │
│  STALE ORDER                                                │
│  ────────────                                               │
│  SellerDashboardScreen._fetchDashboardData()                │
│       │                                                     │
│       ├── Checks orders stuck in 'placed' status            │
│       ├── If pending > X hours:                             │
│       │    └── SellerNotificationService.createStaleOrder() │
│       │         └── Deduplicated per order                  │
│       │                                                     │
│       └── Seller sees alert chip on dashboard               │
│                                                             │
│  LOW STOCK                                                  │
│  ──────────                                                 │
│  ProductService.updateProduct() or syncProductActiveStatus()│
│       │                                                     │
│       ├── Checks inventory levels                           │
│       ├── If stock ≤ 5 or 0:                                │
│       │    └── SellerNotificationService.createLowStock()   │
│       │         └── Deduplicated per product+size           │
│       │                                                     │
│       └── Seller sees alert chip on dashboard               │
│                                                             │
│  NEW MESSAGE                                                │
│  ────────────                                               │
│  Customer sends message                                     │
│       │                                                     │
│       ├── MessageService.sendMessage()                      │
│       │    └── _createMessageNotification()                 │
│       │         ├── SellerNotificationService.createNewMessage()│
│       │         │    └── Deduplicated per conversation      │
│       │         └── _triggerPushNotification()              │
│       │              └── Edge Function → FCM                │
│       │                                                     │
│       └── Seller sees notification + push                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 8.3 Push Notification Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    PUSH NOTIFICATION FLOW                    │
│                                                             │
│  SENDER SIDE                                                │
│  ───────────                                                │
│  MessageService.sendMessage()                               │
│       │                                                     │
│       └── _triggerPushNotification()                        │
│            │ (fire-and-forget)                              │
│            ├── Query conversation for store name            │
│            ├── Edge Function: send-message-push             │
│            │    ├── Lookup recipient user ID                │
│            │    │   (customer_id or store.owner_id)         │
│            │    ├── Query device_tokens for FCM tokens      │
│            │    ├── Build notification title:                │
│            │    │   • Seller→Customer: store name            │
│            │    │   • Customer→Seller: customer name         │
│            │    ├── Build FCM payload with data fields      │
│            │    └── Send via FCM HTTP v1 API                │
│            │         └── Clean up UNREGISTERED tokens       │
│            │                                               │
│            └── Firebase delivers to recipient devices       │
│                                                             │
│  RECEIVER SIDE                                              │
│  ─────────────                                              │
│  PushNotificationService                                    │
│       │                                                     │
│       ├── FOREGROUND:                                       │
│       │    onMessage listener                               │
│       │    └── _handleForegroundMessage()                   │
│       │         └── flutter_local_notifications.show()      │
│       │              └── Shows in-app banner                │
│       │                                                     │
│       ├── BACKGROUND:                                       │
│       │    OS auto-displays notification                    │
│       │    └── User taps → onMessageOpenedApp               │
│       │         └── _handleNotificationTap()                │
│       │              └── Check wrong-account                │
│       │              └── onNavigateToChat?.call()           │
│       │                                                     │
│       └── TERMINATED:                                       │
│            OS auto-displays notification                    │
│            └── User taps → getInitialMessage                │
│                 └── _handleNotificationTap()                │
│                      └── Buffer until callback is set       │
│                      └── onNavigateToChat?.call()           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 9. Notification Creation Points

### Customer Notifications

| Trigger | Where Created | Category |
|---------|--------------|----------|
| Order placed (unpaid) | `SupabaseService.createOrder()` | `unpaid` |
| Order status → preparing | `OrderProvider.updateOrderStatus()` | `processing` |
| Order status → ready | `OrderProvider.updateOrderStatus()` | `shipped` |
| Order status → received | `OrderProvider.updateOrderStatus()` | `review` |
| Return requested | (not yet implemented) | `returns` |
| Message from store | DB trigger `on_new_message_notify` | `message` |

### Seller Notifications

| Trigger | Where Created | Type | Deduplication |
|---------|--------------|------|---------------|
| Customer places order | `SupabaseService.createOrder()` | `new_order` | No |
| Order pending too long | `SellerDashboardScreen._fetchDashboardData()` | `stale_order` | Yes (per order) |
| Stock drops low | `ProductService.updateProduct()` / `syncProductActiveStatus()` | `low_stock` | Yes (per product+size) |
| Customer sends message | `MessageService._createMessageNotification()` | `new_message` | Yes (per conversation) |
| Custom order submitted | `SupabaseService` (custom order flow) | `custom_order_request` | No |

---

## 10. UI Components

### 10.1 Customer Notification Card

```
┌─────────────────────────────────────────────┐
│  ┌────┐  Order Update              ● (red)  │
│  │ 💳 │  Your order #f8adaf22 is processing │
│  └────┘  2h ago                              │
└─────────────────────────────────────────────┘
```

| Element | Style |
|---------|-------|
| Leading icon | 40×40 circle with category color at 12% opacity |
| Title | 14px bold, secondary color |
| Unread dot | 8×8 red circle |
| Message | 12px, secondary at 60% opacity |
| Timestamp | 11px, secondary at 40% opacity |
| Card background | White (read) or primary at 4% (unread) |

### 10.2 Seller Notification Row

```
┌─────────────────────────────────────────────┐
│  ┌────┐  New order #f8adaf22        ● (blue)│
│  │ 📋 │  ₱1,299 — tap to view               │
│  └────┘  5 min ago                           │
└─────────────────────────────────────────────┘
```

| Element | Style |
|---------|-------|
| Leading icon | 40×40 circle with type color at 12% opacity |
| Title | 14px, bold if unread, secondary color |
| Unread dot | 8×8 blue circle |
| Body | 12px, secondary at 60% opacity |
| Timestamp | 11px, secondary at 40% opacity |
| Card background | White (read) or blue at 4% (unread) |

### 10.3 Profile Screen Order Icons

```
┌─────────────────────────────────────────────┐
│  My Orders              View all →          │
│  ┌─────────────────────────────────────────┐│
│  │  💳    📦    🚚    💬    📋           ││
│  │ Unpaid Proc. Ship. Review Ret.          ││
│  │  (2)   (1)   (0)   (0)   (0)           ││
│  └─────────────────────────────────────────┘│
└─────────────────────────────────────────────┘
```

Each icon shows unread count badge. Tapping navigates to `MyOrdersScreen` with filter.

### 10.4 Seller Dashboard Bell Icon

```
┌──────────────────────────────┐
│  🔔 (with badge "3")        │
└──────────────────────────────┘
```

Badge shows `unreadBadge` ("9+" if > 9). Tapping navigates to `SellerNotificationCenterScreen`.

---

## 11. Known Issues

### Customer Notifications

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 1 | No realtime subscription for customer notifications | Medium | Must pull-to-refresh to see new notifications |
| 2 | Order notification categories don't update automatically | Medium | Categories are static, don't reflect actual status changes |
| 3 | SMS opt-in is a stub | Low | "Enable" button shows "coming soon" |
| 4 | No notification preferences | Low | Can't opt out of specific categories |
| 5 | Tab filtering (All/Catalog/Custom) doesn't match categories | Low | Tabs filter by `order_type`, not `category` |

### Seller Notifications

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 1 | `createNewOrder` has no deduplication | Low | Each order creates one notification (intentional) |
| 2 | Stale order threshold is hardcoded | Low | No configurable hours threshold |
| 3 | No notification sound/vibration | Low | Only visual feedback |

### Push Notifications

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 1 | Only message notifications have push | Medium | Order status changes don't trigger push |
| 2 | Token cleanup is best-effort | Low | Stale tokens may accumulate |
| 3 | No notification grouping | Low | Multiple notifications show separately |

---

*SoleVision Notifications Architecture v1.0.0 — July 16, 2026*
