# SoleVision Push Notifications — Complete System Documentation

**Last Updated:** July 15, 2026  
**Status:** Fully implemented and working (customer ↔ seller bidirectional)

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [How It Works — End-to-End Flow](#how-it-works--end-to-end-flow)
4. [Firebase Configuration](#firebase-configuration)
5. [Supabase Database Schema](#supabase-database-schema)
6. [Edge Function: send-message-push](#edge-function-send-message-push)
7. [Flutter Client: PushNotificationService](#flutter-client-pushnotificationservice)
8. [Flutter Client: MessageService (Push Trigger)](#flutter-client-messageservice-push-trigger)
9. [Token Management](#token-management)
10. [Notification Title Logic](#notification-title-logic)
11. [Bugs We Fixed & Lessons Learned](#bugs-we-fixed--lessons-learned)
12. [File Reference](#file-reference)
13. [Environment Variables & Secrets](#environment-variables--secrets)
14. [Testing & Verification](#testing--verification)
15. [Troubleshooting](#troubleshooting)

---

## Overview

SoleVision's push notification system delivers real-time OS-level notifications when messages are exchanged between customers and sellers. This is the **first push notification feature** in the app — there was no pre-existing Firebase/APNs/FCM plumbing.

### What it does

| Scenario | Notification type | Title shows | Deep link target |
|----------|------------------|-------------|-----------------|
| Seller sends message → Customer | OS push (background/killed) + local notification (foreground) | Store name | ChatView for that conversation |
| Customer sends message → Seller | OS push (background/killed) + local notification (foreground) | Customer's name | ChatView for that conversation |

### Tech stack

- **Firebase Cloud Messaging (FCM)** — HTTP v1 API for sending notifications
- **Supabase Edge Functions (Deno)** — server-side FCM call using Firebase Admin SDK
- **Supabase `device_tokens` table** — stores FCM tokens per user
- **Flutter `firebase_messaging`** — client-side token registration and message handling
- **Flutter `flutter_local_notifications`** — displays notifications when app is in foreground

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    MESSAGE SEND FLOW                         │
│                                                             │
│  ChatView (seller or customer)                              │
│       │                                                     │
│       ▼                                                     │
│  MessageService.sendMessage()                               │
│       │                                                     │
│       ├──► INSERT INTO messages (Supabase)                  │
│       │                                                     │
│       ├──► UPDATE conversations (last_message_at, preview)  │
│       │                                                     │
│       └──► _createMessageNotification()                     │
│              │                                              │
│              ├──► SellerNotificationService (if customer→seller)
│              │                                              │
│              └──► _triggerPushNotification()                │
│                     │                                       │
│                     ▼                                       │
│              Edge Function: send-message-push               │
│                     │                                       │
│                     ├──► Lookup recipient user ID           │
│                     ├──► Query device_tokens for FCM tokens │
│                     ├──► Build title + payload              │
│                     └──► FCM HTTP v1 API → Firebase         │
│                                │                            │
│                                ▼                            │
│                     Firebase delivers to devices            │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    CLIENT RECEIVE FLOW                        │
│                                                             │
│  Firebase delivers message to device                         │
│       │                                                     │
│       ├──► App in FOREGROUND                                │
│       │    └──► onMessage listener                          │
│       │         └──► PushNotificationService._handleForegroundMessage()
│       │              └──► flutter_local_notifications.show()│
│       │                                                     │
│       ├──► App in BACKGROUND                                │
│       │    └──► OS auto-displays notification               │
│       │         └──► User taps → onMessageOpenedApp         │
│       │              └──► _handleNotificationTap()          │
│       │                   └──► Navigate to ChatView         │
│       │                                                     │
│       └──► App TERMINATED                                   │
│            └──► OS auto-displays notification               │
│                 └──► User taps → getInitialMessage()        │
│                      └──► _handleNotificationTap()          │
│                           └──► Navigate to ChatView         │
└─────────────────────────────────────────────────────────────┘
```

---

## How It Works — End-to-End Flow

### Step 1: User sends a message

In `ChatView`, the user taps send → `_sendMessage()` is called → `MessageService.sendMessage()` runs:

```dart
// lib/services/message_service.dart
Future<Message> sendMessage({...}) async {
  // 1. Insert message into DB
  final inserted = await _client.from('messages').insert(insertData).select().single();

  // 2. Update conversation metadata
  await _client.from('conversations').update({
    'last_message_at': DateTime.now().toIso8601String(),
    'last_message_preview': preview,
  }).eq('id', conversationId);

  // 3. Create notification + trigger push
  await _createMessageNotification(
    conversationId: conversationId,
    senderId: senderId,
    senderType: senderType,
    body: body,
  );

  return Message.fromMap(Map<String, dynamic>.from(inserted));
}
```

### Step 2: Push notification is triggered

`_createMessageNotification()` handles both directions:

- **Customer → Seller:** Creates an in-app `SellerNotification` record + calls `_triggerPushNotification()`
- **Seller → Customer:** Only calls `_triggerPushNotification()` (DB trigger `notify_on_new_message` handles the in-app notification)

### Step 3: Edge Function is invoked

`_triggerPushNotification()` is fire-and-forget — it queries the conversation for the store name, then invokes the Supabase Edge Function:

```dart
await _client.functions.invoke('send-message-push', body: {
  'conversation_id': conversationId,
  'sender_id': senderId,
  'sender_type': senderType,  // 'customer' or 'seller'
  'body': body,
  'store_name': storeName,
});
```

### Step 4: Edge Function sends via FCM

The Edge Function (`supabase/functions/send-message-push/index.ts`):

1. Validates `sender_type`
2. Looks up the conversation → finds `customer_id` and `store_id`
3. Looks up the store → gets `name` and `owner_id`
4. **Determines recipient:**
   - `sender_type === 'seller'` → recipient is `customer_id`
   - `sender_type === 'customer'` → recipient is `store.owner_id`
5. Queries `device_tokens` for the recipient's FCM tokens
6. **Builds the notification title:**
   - Customer → Seller: title = customer's name (from `profiles.full_name`)
   - Seller → Customer: title = store name (from `stores.name`)
7. Sends to each token via FCM HTTP v1 API
8. Cleans up any `UNREGISTERED` tokens

### Step 5: Client receives and displays

**Background/killed:** Firebase OS integration auto-displays the notification with the title/body from the FCM payload.

**Foreground:** The `onMessage` listener fires → `PushNotificationService._handleForegroundMessage()` → reads `data['sender_name']` → calls `flutter_local_notifications.show()` to display a local notification banner.

---

## Firebase Configuration

### Project details

| Field | Value |
|-------|-------|
| Project ID | `carcarunitedfootwear` |
| Project Number | `162309360658` |
| Android Package | `com.solevision.app` |
| Firebase App ID | `1:162309360658:android:cbb11c6849dd127c4f1ccb` |

### Files

- `android/app/google-services.json` — Firebase Android config (package name must match `applicationId` in `build.gradle`)
- `lib/firebase_options.dart` — FlutterFire CLI-generated config (used by `Firebase.initializeApp()`)
- `android/app/build.gradle` — must have `com.google.gms.google-services` plugin applied

### Dependencies (pubspec.yaml)

```yaml
dependencies:
  firebase_core: ^3.13.0
  firebase_messaging: ^15.2.9
  flutter_local_notifications: ^18.0.1
```

### Android build.gradle requirements

```gradle
// android/app/build.gradle
android {
    defaultConfig {
        minSdkVersion 21  // Required for flutter_local_notifications
    }
    compileOptions {
        coreLibraryDesugaringEnabled true  // Required for flutter_local_notifications
    }
}

dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'  // Must be >= 2.1.4
}
```

---

## Supabase Database Schema

### `device_tokens` table

```sql
CREATE TABLE IF NOT EXISTS public.device_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    fcm_token text NOT NULL,
    platform text NOT NULL CHECK (platform IN ('ios', 'android')),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(customer_id, fcm_token)
);
```

**RLS policies:**
- Users can SELECT/INSERT/UPDATE/DELETE their own tokens (`auth.uid() = customer_id`)

### `notifications` table (extended)

Added `metadata` JSONB column and `'message'` category:

```sql
ALTER TABLE public.notifications
ADD COLUMN IF NOT EXISTS metadata jsonb DEFAULT NULL;

-- 'message' was added to the notification_category enum:
-- ALTER TYPE public.notification_category ADD VALUE 'message';
```

### Key SQL migration

**File:** `supabase/migrations/20260714_push_notifications.sql`

This migration creates:
1. `'message'` enum value in `notification_category`
2. `metadata` JSONB column on `notifications`
3. `device_tokens` table with RLS
4. `notify_on_new_message()` trigger function (creates in-app notification for seller→customer)
5. `on_new_message_notify` trigger on `messages` INSERT

---

## Edge Function: send-message-push

**File:** `supabase/functions/send-message-push/index.ts`

### Environment secrets (set via Supabase CLI)

```bash
supabase secrets set FCM_SERVICE_ACCOUNT_KEY=<base64-encoded service account JSON>
supabase secrets set FIREBASE_PROJECT_ID=carcarunitedfootwear
```

### How to deploy

```bash
supabase functions deploy send-message-push --no-verify-jwt
```

### Input payload

```typescript
interface MessagePayload {
  conversation_id: string;
  sender_id: string;       // User ID of the sender
  sender_type: string;     // 'customer' | 'seller'
  body?: string;           // Message text (truncated to 100 chars in notification)
  store_name?: string;     // Store name (for reference, not used for title)
}
```

### Processing steps

1. Validate `sender_type` is 'customer' or 'seller'
2. Get Firebase config from env vars
3. Look up conversation → get `customer_id`, `store_id`
4. Look up store → get `name`, `owner_id`
5. Determine recipient:
   - `sender_type === 'seller'` → recipient = `conversation.customer_id`
   - `sender_type === 'customer'` → recipient = `store.owner_id`
6. Query `device_tokens` for recipient's tokens
7. Build notification title:
   - Seller → Customer: `store.name`
   - Customer → Seller: `profiles.full_name` of the sender
8. Send FCM push to each token
9. Clean up `UNREGISTERED` tokens

### FCM payload structure

```json
{
  "message": {
    "token": "<fcm_token>",
    "notification": {
      "title": "Store Name or Customer Name",
      "body": "Message preview (max 100 chars)"
    },
    "data": {
      "type": "new_message",
      "conversation_id": "uuid",
      "sender_name": "Dynamic sender name",
      "store_name": "Always the store name",
      "body": "Message preview"
    },
    "android": {
      "priority": "high",
      "notification": {
        "channel_id": "solevision_messages"
      }
    },
    "apns": {
      "payload": {
        "aps": {
          "sound": "default",
          "badge": 1
        }
      }
    }
  }
}
```

### OAuth2 authentication

The function uses Firebase Admin SDK via HTTP v1 API. It generates a JWT signed with the service account's private key, exchanges it for an OAuth2 access token, then authenticates with `https://fcm.googleapis.com/v1/projects/{projectId}/messages:send`.

---

## Flutter Client: PushNotificationService

**File:** `lib/services/push_notification_service.dart`

### Singleton pattern

```dart
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();
}
```

### Initialization flow (`init()`)

Called once at app startup in `main.dart` after `Firebase.initializeApp()`:

1. **Request permission** — `FirebaseMessaging.requestPermission()` (required on iOS, Android 13+)
2. **Initialize local notifications** — `flutter_local_notifications` with Android/iOS settings
3. **Get and store FCM token** — `FirebaseMessaging.getToken()` → `_storeToken()`
4. **Listen for token refreshes** — `FirebaseMessaging.onTokenRefresh` → `_storeToken()`
5. **Handle foreground messages** — `FirebaseMessaging.onMessage.listen()`
6. **Handle background tap** — `FirebaseMessaging.onMessageOpenedApp.listen()`
7. **Handle cold start tap** — `FirebaseMessaging.getInitialMessage()` (buffered until callback is set)

### Notification channel

```
Channel ID:   solevision_messages
Channel Name: Messages
Importance:   High
```

Created explicitly via `AndroidFlutterLocalNotificationsPlugin.createNotificationChannel()` before each foreground notification display (required for Android 8+).

### Foreground message handling

```dart
void _handleForegroundMessage(RemoteMessage message) {
  final data = message.data;
  final type = data['type'] as String?;

  if (type != 'new_message') return;

  final conversationId = data['conversation_id'] as String?;
  final senderName = data['sender_name'] as String? ?? data['store_name'] as String? ?? 'Store';
  final body = data['body'] as String? ?? 'New message';

  _showForegroundNotification(title: senderName, body: body, data: data);
}
```

### Notification tap handling (deep link)

```dart
void _handleNotificationTap(RemoteMessage message) {
  final data = message.data;
  final conversationId = data['conversation_id'] as String?;
  final storeName = data['store_name'] as String? ?? 'Store';

  if (conversationId != null) {
    onNavigateToChat?.call(conversationId, storeName);
  }
}
```

The `onNavigateToChat` callback is set by the root widget (e.g., `CustomerHomeScreen`) to navigate directly to `ChatView` for the specified conversation.

---

## Flutter Client: MessageService (Push Trigger)

**File:** `lib/services/message_service.dart`

### `_createMessageNotification()`

Called after every `sendMessage()`. Handles both directions:

```dart
if (senderType == 'customer') {
  // Customer → Seller
  // 1. Look up customer name
  // 2. Create SellerNotification (in-app)
  SellerNotificationService.instance.createNewMessage(...);
  // 3. Trigger FCM push
  _triggerPushNotification(...);
} else {
  // Seller → Customer
  // DB trigger handles in-app notification
  // Only trigger FCM push
  _triggerPushNotification(...);
}
```

### `_triggerPushNotification()`

Fire-and-forget — failures don't block the message send:

```dart
void _triggerPushNotification({...}) {
  _client
      .from('conversations')
      .select('store_id, stores(name)')
      .eq('id', conversationId)
      .maybeSingle()
      .then((conv) async {
    final storeName = conv['stores']?['name'] ?? 'Store';
    await _client.functions.invoke('send-message-push', body: {
      'conversation_id': conversationId,
      'sender_id': senderId,
      'sender_type': senderType,
      'body': body,
      'store_name': storeName,
    });
  }).catchError((e) {
    debugPrint('[MessageService] Push notification trigger failed: $e');
  });
}
```

---

## Token Management

### Storage strategy

**One token per user** — stored in `device_tokens` with `customer_id` as the user reference (the column name is `customer_id` but it stores any user ID, both customers and sellers).

### Token storage flow

```dart
Future<void> _storeToken(String token) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return;

  // 1. Insert the fresh token (critical write)
  await Supabase.instance.client.from('device_tokens').insert({
    'customer_id': userId,
    'fcm_token': token,
    'platform': platform,
    'updated_at': DateTime.now().toIso8601String(),
  });

  // 2. Best-effort cleanup: delete any OTHER stale tokens for this user
  await Supabase.instance.client
      .from('device_tokens')
      .delete()
      .eq('customer_id', userId)
      .neq('fcm_token', token);
}
```

**Why insert-first-then-clean?** This pattern ensures the fresh token is always stored even if the cleanup fails. The reverse (delete-then-insert) risks losing the token if the insert fails after the delete.

### Token rotation

FCM tokens rotate periodically (e.g., on app reinstall, token refresh). The `onTokenRefresh` listener handles this:

```dart
_tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) {
  _storeToken(newToken);
});
```

### Stale token cleanup

The Edge Function also cleans up tokens that FCM reports as `UNREGISTERED`:

```typescript
if (error.includes("UNREGISTERED")) {
  // Signal to remove this token
  return false;
}
// ...
if (invalidTokens.length > 0) {
  await supabase.from("device_tokens").delete().in("fcm_token", invalidTokens);
}
```

---

## Notification Title Logic

The notification title must show **who sent the message** from the recipient's perspective:

| Direction | Recipient | Title shows | Source |
|-----------|-----------|-------------|--------|
| Seller → Customer | Customer | Store name | `stores.name` |
| Customer → Seller | Seller | Customer name | `profiles.full_name` |

### Implementation

**Edge Function** (server-side, for background/killed notifications):

```typescript
let senderProfileName: string | null = null;
if (payload.sender_type === "customer" && payload.sender_id) {
  const { data: senderProfile } = await supabase
    .from("profiles")
    .select("full_name")
    .eq("id", payload.sender_id)
    .single();
  senderProfileName = senderProfile?.full_name ?? null;
}

const title = payload.sender_type === "customer"
  ? (senderProfileName ?? "Customer")
  : storeName;
```

**Flutter client** (for foreground notifications):

```dart
final senderName = data['sender_name'] as String? ?? data['store_name'] as String? ?? 'Store';
_showForegroundNotification(title: senderName, body: body, data: data);
```

### Data payload fields

```dart
{
  "type": "new_message",
  "conversation_id": "uuid",
  "sender_name": "Dynamic sender name (customer name or store name)",
  "store_name": "Always the store name (for deep link navigation)",
  "body": "Message preview"
}
```

- `sender_name` — dynamic, used for notification title
- `store_name` — always the store name, used for navigation label and backwards compatibility

---

## Bugs We Fixed & Lessons Learned

### Bug 1: pg_net extension not installed

**Symptom:** Every message INSERT failed with "failed tap to retry"  
**Root cause:** The `on_new_message_push` database trigger called `net.http_post()` via pg_net, but pg_net was never installed in the database  
**Fix:** Dropped the `on_new_message_push` trigger and `call_push_edge_function()` function. Push notifications now rely on client-side triggering via `_triggerPushNotification()` in MessageService  
**Lesson:** Always verify database extensions exist before using them in triggers

### Bug 2: Stale FCM tokens

**Symptom:** Edge Function reports "Sent 2/2 notifications" but nothing arrives on the device  
**Root cause:** The `_storeToken()` method used `onConflict: 'customer_id,fcm_token'` which created new rows when the token changed, leading to accumulation of stale tokens. FCM was sending to old tokens that no longer belong to the current app instance  
**Fix:** Changed to insert-first-then-clean pattern: insert the fresh token, then best-effort delete any other tokens for this user  
**Lesson:** FCM tokens rotate frequently. Always upsert or replace, never just append

### Bug 3: Notification title always showed store name

**Symptom:** Seller received notification with title "demo_storeName" instead of the customer's name  
**Root cause:** The `data` payload always included `store_name` as the title source. The Flutter client read `data['store_name']` for the foreground notification title, ignoring the dynamic title set in the Edge Function's `notification.title` field  
**Fix:** Added `sender_name` field to the data payload (dynamic based on direction). Flutter client reads `data['sender_name']` instead of `data['store_name']`  
**Lesson:** The `notification` block in FCM is only used by the OS for background/killed display. Foreground handlers read from `data`, so the correct name must be in both places

### Bug 4: Scoping bug in Edge Function

**Symptom:** `senderProfile` was referenced outside its declaration scope in TypeScript  
**Root cause:** `senderProfile` was declared inside an `if` block but referenced later for `senderName`  
**Fix:** Declared `senderProfileName` before the if-block, populated it inside  
**Lesson:** Watch out for block scoping in TypeScript/Deno — variables declared with `const` inside `if` blocks are not accessible outside

### Bug 5: desugar_jdk_libs version mismatch

**Symptom:** Build failed with "desugar_jdk_libs version must be 2.1.4 or above"  
**Root cause:** `flutter_local_notifications` v18+ requires desugar_jdk_libs >= 2.1.4, but the project had 2.0.4  
**Fix:** Updated `android/app/build.gradle` to use `com.android.tools:desugar_jdk_libs:2.1.4`  
**Lesson:** Check dependency requirements when adding new packages — Flutter plugins often have Android/iOS version requirements

### Bug 6: Missing notification channel

**Symptom:** Notifications silently failed on Android 8+  
**Root cause:** `flutter_local_notifications` v22+ requires explicit `NotificationChannel` creation before `show()` works  
**Fix:** Added explicit channel creation via `AndroidFlutterLocalNotificationsPlugin.createNotificationChannel()`  
**Lesson:** Android notification channels are mandatory since Android 8.0 (API 26). Always create the channel before showing notifications

### Bug 7: ListTile background color warning

**Symptom:** Repeated "ListTile background color or ink splashes may be invisible" warnings  
**Root cause:** `ListTile` wrapped in a `Container(color: ...)` without a `Material` ancestor  
**Fix:** Used `ListTile`'s built-in `tileColor` property instead of wrapping in a colored `Container`  
**Lesson:** Use `tileColor` on `ListTile` rather than wrapping in a colored `Container`

---

## File Reference

### Core push notification files

| File | Purpose |
|------|---------|
| `supabase/functions/send-message-push/index.ts` | Edge Function — sends FCM push via HTTP v1 API |
| `lib/services/push_notification_service.dart` | Flutter service — token management, foreground display, tap handling |
| `lib/services/message_service.dart` | Flutter service — triggers push after message send |
| `lib/main.dart` | App entry — initializes Firebase, registers background handler |
| `supabase/migrations/20260714_push_notifications.sql` | DB migration — device_tokens table, notification trigger |

### Configuration files

| File | Purpose |
|------|---------|
| `android/app/google-services.json` | Firebase Android config |
| `lib/firebase_options.dart` | FlutterFire CLI-generated config |
| `android/app/build.gradle` | Android build config (desugar, minSdk, Google Services plugin) |
| `pubspec.yaml` | Flutter dependencies (firebase_core, firebase_messaging, flutter_local_notifications) |

### Related messaging files

| File | Purpose |
|------|---------|
| `lib/screens/chat/chat_view.dart` | Chat UI — calls `MessageService.sendMessage()` |
| `lib/providers/message_provider.dart` | State management for conversations/messages |
| `lib/screens/seller/seller_inbox_screen.dart` | Seller inbox with unread indicators |
| `lib/screens/customer/customer_inbox_screen.dart` | Customer inbox with unread indicators |
| `lib/widgets/floating_message_button.dart` | Floating chat button with unread badge |
| `lib/services/seller_notification_service.dart` | In-app notifications for sellers |
| `lib/providers/seller_notification_provider.dart` | State management for seller notifications |

---

## Environment Variables & Secrets

### Supabase Edge Function secrets

Set via Supabase CLI:

```bash
# Firebase service account JSON, base64-encoded
supabase secrets set FCM_SERVICE_ACCOUNT_KEY=$(base64 -w 0 carcarunitedfootwear-firebase-adminsdk-fbsvc-3a9079e27c.json)

# Firebase project ID
supabase secrets set FIREBASE_PROJECT_ID=carcarunitedfootwear
```

The service account JSON contains:
- `project_id`: `carcarunitedfootwear`
- `private_key`: RSA key for signing JWTs
- `client_email`: `firebase-adminsdk-fbsvc@carcarunitedfootwear.iam.gserviceaccount.com`

### Flutter environment

No special env vars needed — Firebase config is in `google-services.json` and `firebase_options.dart`.

---

## Testing & Verification

### Test customer → seller notification

1. Run app on emulator as **seller** (user `0787bc07-a5e5-4919-86fb-fd930b9c93e1`)
2. Background the app (press Home)
3. On another device/emulator, log in as **customer** (`3ee96df2-64df-40b4-85a0-916a2703a0ec`)
4. Send a message to the seller
5. **Expected:** Seller's device shows push notification with **customer's name** as title
6. Tap notification → opens ChatView for that conversation

### Test seller → customer notification

1. Run app on emulator as **customer**
2. Background the app
3. On another device, log in as **seller**
4. Send a message to the customer
5. **Expected:** Customer's device shows push notification with **store name** as title

### Verify foreground notifications

1. Keep the app **open** (foreground)
2. Have the other party send a message
3. **Expected:** In-app notification banner appears at the top of the screen

### Check Edge Function logs

```bash
# View recent logs
supabase functions logs send-message-push
```

Look for:
- `[FCM] Sent 1/1 notifications for conversation <uuid>` — success
- `[FCM] No device tokens for customer/seller: <uuid>` — token missing
- `[FCM] Send failed: <error>` — FCM API error

### Check device tokens in database

```sql
SELECT id, customer_id, platform, left(fcm_token, 30) as token_prefix, updated_at
FROM device_tokens
ORDER BY updated_at DESC;
```

---

## Troubleshooting

### "Sent 0/1 notifications" or "No device tokens found"

**Cause:** The recipient's FCM token is not stored in `device_tokens`  
**Fix:** Restart the app to re-register the token. Check that `PushNotificationService.instance.init()` runs for BOTH customer and seller roles

### "Sent 1/1" but no notification appears

**Cause:** Token mismatch — FCM sent to a stale token  
**Fix:** Restart the app (forces fresh token registration). Check the Flutter console for `[Push] Token stored for user: <id>` to verify the current token

### Build fails with "desugar_jdk_libs version"

**Cause:** `flutter_local_notifications` requires desugar_jdk_libs >= 2.1.4  
**Fix:** Update `android/app/build.gradle`: `com.android.tools:desugar_jdk_libs:2.1.4`

### Notification title shows wrong name

**Cause:** The `sender_name` field is missing from the FCM data payload  
**Fix:** Redeploy the Edge Function: `supabase functions deploy send-message-push --no-verify-jwt`

### Messages fail to send ("failed tap to retry")

**Cause:** A database trigger is failing (e.g., missing pg_net extension)  
**Fix:** Check for triggers on the `messages` table that call `net.http_post()`. Drop them if pg_net is not installed

### Foreground notifications don't show

**Cause:** Notification channel not created on Android 8+  
**Fix:** The `_showForegroundNotification()` method should create the channel explicitly. Check `push_notification_service.dart` for `createNotificationChannel()` call
