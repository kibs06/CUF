# 🔔 Notifications & Messaging

> In-app notifications (customer + seller), push (FCM), and the real-time messaging system. **#moc**

---

## 📌 Overview

**Three notification systems** that work together:

| System | Scope | Table | Purpose |
|--------|-------|-------|---------|
| Customer in-app | Customer | `notifications` | Order status updates, messages |
| Seller in-app | Seller | `seller_notifications` | New orders, stale orders, low stock, messages, custom requests |
| Push (FCM) | Both | `device_tokens` | OS-level notifications when app is background/killed |

**Messaging** is a **shared-widget architecture** — one `ChatView` serves both seller and customer sides, parameterized by `viewerRole`. No role-specific chat code.

---

## 🔔 Notification types

| Type | Direction | Trigger |
|------|-----------|---------|
| `unpaid` / `processing` / `shipped` / `review` / `returns` | System → Customer | Order placed / preparing / ready / delivered / return requested |
| `message` | Seller → Customer | New message (feed + push) |
| `new_order` / `stale_order` / `low_stock` | System → Seller | Order placed / pending too long / stock low |
| `custom_order_request` | Customer → Seller | Custom order submitted |
| `new_message` | Customer → Seller | New message (feed + push) |

---

## 🧩 Components

| File | Role |
|------|------|
| `lib/models/app_notification.dart` / `notification_category.dart` | Customer models |
| `lib/services/notification_service.dart` | Customer notification CRUD |
| `lib/providers/notification_provider.dart` | Customer notification state |
| `lib/screens/notifications_screen.dart` | Customer feed (Unpaid/Processing/Shipped/Review/Returns tabs, read/unread, tap → tracking) |
| `lib/services/seller_notification_service.dart` | Seller CRUD + creation helpers (e.g. `createStaleOrder`) |
| `lib/providers/seller_notification_provider.dart` | Seller state + realtime + `unreadBadge` |
| `lib/screens/seller/seller_notification_center_screen.dart` | Seller center (tap navigates by type) |
| `lib/services/push_notification_service.dart` | FCM token management + foreground display |
| `lib/services/message_service.dart` | Message/Conversation models, CRUD, upload, subscriptions, typing, `_triggerPush()` |
| `lib/widgets/chat/chat_view.dart` | **Shared chat UI** — bubbles, input bar, attachments, full-screen viewers |
| `lib/screens/customer/customer_inbox_screen.dart` | Customer inbox (`ChatView` viewerRole: 'customer') |
| `lib/screens/seller/seller_inbox_screen.dart` | Seller inbox (`ChatView` viewerRole: 'seller') |
| `lib/providers/chat_attachment_provider.dart` | Persists failed attachment messages across rebuilds |
| `supabase/functions/send-message-push/index.ts` | Edge Function: lookup recipient → query `device_tokens` → FCM HTTP v1 |

---

## 💬 Messaging — architecture

```
ChatView(conversationId, viewerRole: 'seller'|'customer', otherPartyName)
├── _loadMessages()          → MessageService.getMessages()
├── _subscribeToMessages()   → MessageService.subscribeToConversation() (realtime)
├── _subscribeToTyping()     → MessageService.subscribeToTyping() (broadcast channel)
├── _sendMessage()           → Optimistic text send with UUID matching
├── _sendAttachmentMessage() → Chunked upload with real progress + optimistic UI
├── _buildMessageBubble()    → text, image, video, sending, failed states
└── _buildInputBar()         → text field + attachment button + send button
```

`viewerRole` controls: bubble alignment, read receipts (own messages only), DB `sender_type`, typing filtering. Features: realtime delivery, optimistic sends with merge logic preserving local-only fields (`isSending`, `sendFailed`, `localFile`, `progress`), read receipts (`markConversationRead` → UPDATE `is_read` → ✓✓), typing indicators (broadcast channel), chunked attachment uploads (image/video + thumbnails + duration/size), push on new message.

**Data models**: `Message` (id, conversationId, senderId, senderType, body, orderReferenceId, isRead, createdAt, attachmentUrl/Type/Thumbnail/Duration/Size + local-only fields) · `Conversation` (storeId, customerId, lastMessageAt, lastMessagePreview + joined customerName/storeName, unreadCount).

## 📱 Push (FCM)

- `device_tokens` table; `push_notification_service.dart` registers tokens, handles foreground (local notification) / background (OS) / cold start (deep-link navigate).
- `send-message-push` Edge Function delivers via FCM HTTP v1.
- ⚠️ **Known gap**: the legacy direct-GCash RPC doesn't fire FCM push (in-app realtime badge works, push doesn't) — noted in [[docs/AI/CHECKOUT_AND_GCASH_ARCHITECTURE|Checkout & GCash architecture]] §7.

## ⚠️ Gotchas

1. Realtime requires the tables in the Supabase Realtime publication.
2. Optimistic merge must preserve local-only fields or sends flicker back to "failed".
3. Attachment uploads are chunked with byte-level progress — keep `copyWith` efficient to avoid jank.
4. Notifications RLS: customers read own, sellers read own store's.

## 📚 Deep-dive docs

- [[docs/NOTIFICATIONS_ARCHITECTURE|Notifications architecture]] — full system reference (v1.0.0)
- [[docs/AI/NOTIFICATIONS_CONTEXT|Notifications context]] — for AI agents
- [[docs/AI/NOTIFICATION_SWIPE_GESTURES_REFERENCE|Notification swipe gestures reference]]
- [[docs/push notification/PUSH_NOTIFICATIONS|Push notifications]] — FCM plan + wiring
- [[docs/message/MESSAGING_SYSTEM|Messaging system]] — full real-time messaging reference
- [[docs/AI_PROJECT_SUMMARY|⚡ AI Project Summary — Notifications Screen]]

## 🔗 Related

- [[obsidian/MOCs/02 - Customer App|📱 Customer App]]
- [[obsidian/MOCs/03 - Seller Module|👞 Seller Module]] — seller notification center / inbox
