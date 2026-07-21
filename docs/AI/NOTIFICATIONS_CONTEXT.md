# SoleVision — Notifications AI Context

> Condensed reference for AI agents working on the notification system.
> Derived from NOTIFICATIONS_ARCHITECTURE.md v1.0.0 (July 16, 2026).
>
> **Where do I start?** Read `lib/services/notification_service.dart` for customer CRUD,
> `lib/services/seller_notification_service.dart` for seller CRUD + deduplication,
> and `supabase/functions/send-message-push/index.ts` for the push delivery Edge Function.

---

## Quick Facts

- **Stack:** Flutter + Supabase + Firebase Cloud Messaging (FCM)
- **Three notification systems:** Customer in-app, Seller in-app, Push (FCM)
- **Notification types:** 6 customer categories + 5 seller types (11 total)
- **Push only fires for messages** — order status changes do NOT trigger push

---

## Architecture Overview

```
Customer In-App               Seller In-App               Push (FCM)
┌──────────────────┐         ┌──────────────────┐        ┌──────────────────┐
│ notifications    │         │ seller_          │        │ device_tokens    │
│ table            │         │ notifications    │        │ table            │
│                  │         │ table            │        │                  │
│ NotificationSvc  │         │ SellerNotifSvc   │        │ PushNotifSvc     │
│ NotificationProv │         │ SellerNotifProv  │        │ (FCM handlers)   │
│ NotificationsScr │         │ SellerNotifScr   │        │                  │
└──────────────────┘         └──────────────────┘        └──────────────────┘
```

---

## File Map

| File | Purpose |
|------|---------|
| `lib/models/app_notification.dart` | Customer notification data model |
| `lib/models/notification_category.dart` | Category enum (unpaid, processing, shipped, review, returns, message) |
| `lib/services/notification_service.dart` | Customer CRUD — fetchNotifications, fetchUnreadCounts, markAsRead, markAllAsRead |
| `lib/providers/notification_provider.dart` | Customer state — optimistic updates, auth listener |
| `lib/screens/notifications_screen.dart` | Customer feed UI — tabs (All/Catalog/Custom), card list |
| `lib/services/seller_notification_service.dart` | Seller CRUD + creation helpers with deduplication |
| `lib/providers/seller_notification_provider.dart` | Seller state — realtime subscription on seller_notifications table |
| `lib/screens/seller/seller_notification_center_screen.dart` | Seller center UI — tap navigates by type |
| `lib/services/push_notification_service.dart` | FCM token mgmt, foreground display, deep-link navigation |
| `lib/services/message_service.dart` | Triggers push after message send (`_triggerPushNotification`) |
| `supabase/functions/send-message-push/index.ts` | Edge Function — looks up recipient, queries device_tokens, sends FCM HTTP v1 |

---

## Notification Types

### Customer (6 categories)

| Category | Trigger | UI |
|----------|---------|-----|
| `unpaid` | Order placed | Customer feed |
| `processing` | Status → preparing | Customer feed |
| `shipped` | Status → ready | Customer feed |
| `review` | Status → received | Customer feed |
| `returns` | Return requested | Customer feed (not implemented) |
| `message` | New message from store | Customer feed + push |

### Seller (5 types)

| Type | Icon | Trigger | Deduplication |
|------|------|---------|---------------|
| `new_order` | Receipt/Blue | Customer places order | No |
| `stale_order` | Clock/Amber | Order pending > X hours | Yes (per order) |
| `low_stock` | Warning/Red | Stock ≤ 5 or 0 | Yes (per product+size) |
| `custom_order_request` | Design/Brand | Custom order submitted | No |
| `new_message` | Chat/Blue | Customer sends message | Yes (per conversation) |

---

## Data Models

### AppNotification (Customer)
```dart
class AppNotification {
  String id;
  String? orderId;
  NotificationCategory category;
  String title;
  String message;
  bool isRead;
  DateTime createdAt;
  Map<String, dynamic>? metadata; // JSONB: conversation_id, store_name, sender_id
}
```

### SellerNotification
```dart
class SellerNotification {
  String id;
  String storeId;
  String type;          // 'new_order' | 'stale_order' | 'low_stock' | etc.
  String title;
  String body;
  String? referenceId;  // Order ID, product ID, or conversation ID
  bool isRead;
  DateTime createdAt;
}
```

---

## Database Schema

### notifications (Customer)
```sql
CREATE TABLE public.notifications (
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

CREATE TYPE notification_category AS ENUM (
  'unpaid', 'processing', 'shipped', 'review', 'returns', 'message'
);
```

**RLS:** Users read/update own. System (service role) can insert.

### seller_notifications (Seller)
```sql
CREATE TABLE public.seller_notifications (
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

**RLS:** Store owners read/update own store's. System can insert.

### device_tokens (Push)
```sql
CREATE TABLE public.device_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fcm_token TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(customer_id, fcm_token)
);
```

### DB Trigger: on_new_message_notify
Fires on INSERT to `messages`. Creates customer in-app notification **only for seller→customer** messages.

```sql
CREATE OR REPLACE FUNCTION notify_on_new_message()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.sender_type = 'seller' THEN
    INSERT INTO notifications (user_id, category, title, message, metadata)
    SELECT
      (SELECT customer_id FROM conversations WHERE id = NEW.conversation_id),
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
```

---

## Push Notification Flow

```
MessageService.sendMessage()
  └→ _createMessageNotification()
       ├→ SellerNotificationService.createNewMessage() (if customer→seller)
       └→ _triggerPushNotification() (fire-and-forget)
            └→ Edge Function: send-message-push
                 ├→ Lookup recipient (customer_id or store.owner_id)
                 ├→ Query device_tokens for FCM tokens
                 ├→ Build title:
                 │   • Seller→Customer: store name
                 │   • Customer→Seller: customer name
                 └→ Send via FCM HTTP v1 API
```

### Deep-Link Navigation
- **Foreground:** `onMessage` → `flutter_local_notifications.show()` (in-app banner)
- **Background:** OS displays → user taps → `onMessageOpenedApp` → `_handleNotificationTap()`
- **Terminated:** OS displays → user taps → `getInitialMessage` → `_handleNotificationTap()`

### Wrong-Account Detection
If `target_user_id` in payload ≠ current user → `onWrongAccount` callback fires → shows `WrongAccountScreen`.

---

## Deduplication Pattern (Seller)

```dart
Future<void> createStaleOrder({...}) async {
  final existing = await _client
      .from('seller_notifications')
      .select('id')
      .eq('store_id', storeId)
      .eq('type', 'stale_order')
      .eq('reference_id', orderId)
      .eq('is_read', false)
      .limit(1);

  if ((existing as List).isNotEmpty) return; // already notified

  await _create(...);
}
```

Used for: `stale_order`, `low_stock`, `new_message`. Not used for: `new_order`, `custom_order_request`.

---

## Notification Creation Points

### Customer Notifications
| Trigger | Where Created | Category |
|---------|--------------|----------|
| Order placed (unpaid) | `SupabaseService.createOrder()` | `unpaid` |
| Order status → preparing | `OrderProvider.updateOrderStatus()` | `processing` |
| Order status → ready | `OrderProvider.updateOrderStatus()` | `shipped` |
| Order status → received | `OrderProvider.updateOrderStatus()` | `review` |
| Message from store | DB trigger `on_new_message_notify` | `message` |

### Seller Notifications
| Trigger | Where Created | Type |
|---------|--------------|------|
| Customer places order | `SupabaseService.createOrder()` | `new_order` |
| Order pending too long | `SellerDashboardScreen._fetchDashboardData()` | `stale_order` |
| Stock drops low | `ProductService.updateProduct()` / `syncProductActiveStatus()` | `low_stock` |
| Customer sends message | `MessageService._createMessageNotification()` | `new_message` |
| Custom order submitted | `SupabaseService` (custom order flow) | `custom_order_request` |

---

## Known Issues

| # | Issue | Severity |
|---|-------|----------|
| 1 | No realtime subscription for customer notifications (must pull-to-refresh) | Medium |
| 2 | Order notification categories don't auto-update on status change | Medium |
| 3 | Only message notifications have push — order status changes don't trigger push | Medium |
| 4 | SMS opt-in is a stub ("coming soon") | Low |
| 5 | No notification preferences / opt-out | Low |
| 6 | No notification grouping | Low |
| 7 | Token cleanup is best-effort (stale tokens may accumulate) | Low |

---

## Key Patterns to Follow

1. **Optimistic updates** — Update UI immediately, roll back on failure
2. **Singleton services** — `static final XyzService instance = XyzService._()`
3. **Auth listener** — Providers listen to `onAuthStateChange` for lifecycle management
4. **RLS everywhere** — All tables have Row Level Security; service role for inserts
5. **Deduplication** — Check for unread existing notification before creating new one
6. **Edge Functions** — Push delivery is handled server-side via Supabase Edge Functions
