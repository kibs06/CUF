# Session Log — July 14, 2026

**Date:** July 14, 2026  
**Duration:** ~6 hours  
**Focus:** Badge live-update reliability, seller notification consistency, message push notifications feature (investigated + scaffolded + reverted)

---

## Executive Summary

This session tackled the **messaging badge reliability problem** — the floating chat button's unread count badge only updated on hot reload, not during normal usage. The root cause was a combination of: (1) the realtime subscription being set up *after* the initial load (so a failed load killed the subscription), (2) no on-tap refresh safety net, and (3) no concurrency guard on refresh operations.

Three interconnected fixes were applied:
1. **`refreshInbox()` method** on `MessageProvider` — force-refreshes conversations + unread counts from DB on tap
2. **Subscription-before-load ordering** — ensures the realtime listener is always active, even if the initial load fails
3. **Concurrency guard** — prevents redundant parallel DB queries when `refreshInbox()` is called while a load is already in progress

The same pattern was then applied to the **seller notification badge** for consistency.

Additionally, the session investigated and scaffolded a **message push notifications feature** (FCM + in-app banner), then **reverted all changes** at the user's request to defer the feature.

Two git commits were made:
- `d839fcb` — FloatingMessageButton crash fix (dead code removal) + markConversationRead RPC fix
- `2be8d5f` — Badge live update (refreshOnTap, subscription-before-load, concurrency guard)

---

## Timeline

### 1. Badge Live Update Fix — Investigation (~10:00 AM)

**Bug Report:** The unread count badge on `FloatingMessageButton` only reflects the correct value after a full hot reload. During normal usage, sending/receiving messages or opening a conversation does not update the badge in real time.

**Root Cause Analysis:**
- The `MessageProvider.loadConversationsForCustomer()` method was called *before* `subscribeToInbox()` in `CustomerHomeScreen._loadConversations()`
- If the initial load failed (network error, etc.), the subscription was never created — so no future Realtime events would be caught
- No on-tap refresh existed — the badge relied entirely on Realtime events, which could be missed during brief connectivity drops

**Files Investigated:**
- `lib/providers/message_provider.dart` — conversation loading, unread count calculation, Realtime subscriptions
- `lib/widgets/floating_message_button.dart` — badge display, quick-preview sheet trigger
- `lib/screens/customer/customer_home_screen.dart` — conversation loading lifecycle

---

### 2. Badge Live Update Fix — Implementation (~11:00 AM)

Three changes were made across three files:

#### Fix A: `MessageProvider.refreshInbox()` (message_provider.dart)

Added a `refreshInbox()` method that force-refreshes conversations and unread counts from the database. This is called on tap (before opening the quick-preview sheet) as a safety net.

```dart
/// Force-refresh conversations and unread counts from the database.
/// Called on tap (before opening quick-preview sheet) as a safety net
/// to guarantee the badge and sheet reflect the true current state,
/// even if a Realtime event was missed.
Future<void> refreshInbox() async {
  if (_customerId == null || _isLoadingConversations) return;
  await loadConversationsForCustomer(_customerId!);
}
```

Key details:
- Stores `_customerId` when `loadConversationsForCustomer()` is called (set once, reused by `refreshInbox()`)
- `_customerId` is cleared in `reset()` for logout cleanup
- Concurrency guard: early-returns if `_isLoadingConversations` is already true — prevents redundant parallel DB queries

#### Fix B: Refresh-on-Tap (floating_message_button.dart)

`_showQuickPreview()` now calls `provider.refreshInbox()` before opening the sheet, with `mounted`/`context.mounted` guards:

```dart
Future<void> _showQuickPreview() async {
  final provider = context.read<MessageProvider>();
  await provider.refreshInbox();
  if (!mounted) return;
  if (!context.mounted) return;
  showModalBottomSheet(...);
}
```

#### Fix C: Subscription-Before-Load (customer_home_screen.dart)

`_loadConversations()` now sets up the realtime subscription **before** the initial load:

```dart
Future<void> _loadConversations() async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null || !mounted) return;
  final msgProvider = context.read<MessageProvider>();
  // Always set up the realtime subscription first, even if the initial
  // load fails — so the badge updates when messages arrive.
  msgProvider.subscribeToInbox(customerId: userId);
  try {
    await msgProvider.loadConversationsForCustomer(userId);
  } catch (e) {
    debugPrint('[CustomerHome] Failed to load conversations: $e');
  }
}
```

**Code Review:** Passed — all three changes verified correct by `code-reviewer-mimo`.

---

### 3. Badge Live Update Fix — Commit (~12:00 PM)

```
commit 2be8d5f
fix: badge live update — refreshOnTap, subscription-before-load, concurrency guard

- Add refreshInbox() to MessageProvider with _customerId stored by loadConversationsForCustomer
- FloatingMessageButton._showQuickPreview() now calls refreshInbox() before opening sheet
- CustomerHomeScreen sets up realtime subscription before initial load (previously lost if load failed)
- refreshInbox() early-returns if already loading (concurrency guard)
- _customerId cleared in reset()
```

---

### 4. Seller Notification Badge Consistency (~12:30 PM)

**Request:** Apply the same `refreshInbox` pattern to the seller notification badge in `SellerDashboardScreen` for consistency.

**Investigation:**
- `SellerNotificationProvider` already had a direct `.stream()` subscription on the `seller_notifications` table (more robust than the customer-side approach)
- `_storeId` guard in `init()` already prevented duplicate subscriptions
- Missing: a `refreshNotifications()` method and refresh-on-tap

**Changes Made:**

#### seller_notification_provider.dart

Added `refreshNotifications()` with concurrency guard:

```dart
Future<void> refreshNotifications() async {
  if (_storeId == null || _isLoading) return;
  await loadUnreadCount();
}
```

#### seller_dashboard_screen.dart

1. **Subscription-before-load** in `_loadDashboard()`:
```dart
// Set up subscription first (init is idempotent for same storeId)
final notifProv = context.read<SellerNotificationProvider>();
notifProv.init(id);
// Initialize message provider for inbox badge
final msgProv = context.read<MessageProvider>();
msgProv.subscribeToInbox(storeId: id);
msgProv.loadConversationsForStore(id);
```

2. **Refresh-on-tap** for notification bell:
```dart
onPressed: () async {
  await notifProvider.refreshNotifications();
  if (!mounted || !context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const SellerNotificationCenterScreen()),
  );
},
```

**Code Review:** Passed — concurrency guard, subscription-before-load ordering, and mounted guards all verified correct.

---

### 5. Message Push Notifications Feature — Investigation (~1:00 PM)

**Request:** Implement message push notifications + in-app banner for the customer side.

**Step 0 Investigation Results:**

| Component | Status |
|-----------|--------|
| `notifications` table | Has `category` PG enum — **NO `message` type** |
| `NotificationCategory` Dart enum | Mirrors PG enum exactly — no `message` |
| `message_service.dart` | Line ~600 tries to insert `category: 'message'` — **silently fails** (invalid enum) |
| INSERT RLS on `notifications` | **None** — client-side inserts blocked |
| `metadata`/payload column | **Does not exist** — no way to store `conversationId` |
| `firebase_messaging` | **Not in pubspec.yaml** |
| `firebase_core` | **Not in pubspec.yaml** |
| `google-services.json` | **Does not exist** |
| `GoogleService-Info.plist` | **Does not exist** |
| FCM device token storage | **No table or code** |
| Background/foreground handlers | **None** |

**Key Finding:** Zero push notification infrastructure exists. Building real push requires Firebase project credentials.

**Decision:** Phase 1 (fix broken notification system + add message type) can be done immediately. Phase 2 (real push notifications) requires Firebase. User chose: **Phase 1 + scaffold Phase 2**.

---

### 6. Message Push Notifications — Implementation (~1:30 PM)

#### Phase 1: SQL Migration

Created `supabase/migrations/20260714_message_notifications.sql`:
- Added `'message'` to `notification_category` PG enum
- Added `metadata JSONB` column to `notifications` table
- Added INSERT RLS policy for authenticated users
- Enabled Realtime on `notifications` table
- Created `customer_device_tokens` table (for future FCM)
- Created `notify_on_new_message` DB trigger — fires on `messages` insert where `sender_type = 'seller'`, creates a customer notification with `category = 'message'` and `metadata` containing `conversationId`, `storeName`, `senderId`

#### Phase 1: Dart Model Updates

- `notification_category.dart`: Added `message` to enum and label function
- `app_notification.dart`: Added `metadata` field, convenience getters (`conversationId`, `storeName`, `senderId`), `fromMap` parsing

#### Phase 1: Service Fixes

- `message_service.dart`: Replaced broken client-side `_createMessageNotification` (which used invalid enum value `'message'` and had no INSERT RLS) with a clean version that only handles seller notifications — customer notifications now handled by the DB trigger

#### Phase 1: Screen Updates

- `notifications_screen.dart`: Added `ChatView` import, updated `_handleTap` to navigate to `ChatView` for message notifications (instead of `OrderTrackingScreen`), added `'message'` case to icon/color maps

#### Phase 2: FCM Packages

- Added `firebase_messaging` and `firebase_core` to `pubspec.yaml` via `flutter pub add`

#### Phase 2: PushNotificationService Scaffold

Created `lib/services/push_notification_service.dart`:
- Singleton pattern (`PushNotificationService.instance`)
- `init()` method — requests permission, gets FCM token, sets up foreground handler, sets up notification tap handler
- Foreground handler: checks if user is already in the target conversation (suppresses banner if so), shows in-app `MessageBanner` otherwise
- Notification tap handler: navigates to `ChatView` for the tapped conversation
- Background message handler registered via top-level function (required by FCM)

#### Phase 2: In-App Banner Widget

Created `lib/widgets/message_banner.dart`:
- `MessageBannerController` — manages overlay entry lifecycle
- `MessageBanner` widget — slides in from top, auto-dismisses after 5s, shows store name + message preview
- Matches design system: Off-White Suede surface, Burnished Clay accent, DM Sans body, rounded corners

#### Phase 2: Wiring

- `main.dart`: Added `PushNotificationService.instance.init()` after Supabase init
- `customer_home_screen.dart`: Added `_initPushNotifications()` — sets up Realtime subscription on `notifications` table for foreground messages, creates `MessageBannerController`, handles foreground notification events

**Code Review:** Found issues — dead code in `push_notification_service.dart`, confusing `_bannerController2` naming, redundant `MessageBanner.show()` static method. All fixed before revert.

---

### 7. Message Push Notifications — Revert (~3:00 PM)

**Request:** Revert all changes from the push notifications feature.

**Files Deleted:**
- `lib/services/push_notification_service.dart`
- `lib/widgets/message_banner.dart`
- `supabase/migrations/20260714_message_notifications.sql`

**Files Reverted:**
- `notification_category.dart` — removed `'message'` from enum
- `app_notification.dart` — removed `metadata` field and convenience getters
- `message_service.dart` — restored broken `_createMessageNotification` (pre-existing bug)
- `notifications_screen.dart` — removed `ChatView` import, message tap handling, `'message'` case
- `customer_home_screen.dart` — removed push notification imports, `_messageBannerController`, `_initPushNotifications()`, `ChatView` import
- `main.dart` — removed `PushNotificationService` import and `init()`
- `pubspec.yaml` — removed `firebase_messaging` and `firebase_core` packages

**Code Review:** Verified clean revert — no dangling references, earlier badge fixes preserved, no compile errors.

---

### 8. Android Package Name Lookup (~3:30 PM)

**Request:** Get the exact Android package name for Firebase configuration.

**Result:** `com.solevision.app` (from `android/app/build.gradle` `applicationId` field)

---

## Files Modified/Created This Session

### Committed Files (2 commits)

| File | Commit | Purpose |
|------|--------|---------|
| `lib/providers/message_provider.dart` | `2be8d5f` | Added `_customerId`, `refreshInbox()`, concurrency guard, `reset()` cleanup |
| `lib/widgets/floating_message_button.dart` | `2be8d5f` | Added refresh-on-tap in `_showQuickPreview()` with mounted guards |
| `lib/screens/customer/customer_home_screen.dart` | `2be8d5f` | Subscription-before-load ordering in `_loadConversations()` |
| `lib/services/message_service.dart` | `d839fcb` | Removed dead code from FloatingMessageButton, use RPC for markConversationRead |
| `lib/widgets/floating_message_button.dart` | `d839fcb` | Removed `_refreshUnreadCount()`, `_connectivitySub`, `_wasOffline`, `_previousUnreadCount` |

### Uncommitted Modified Files (from prior session work)

| File | Purpose |
|------|---------|
| `lib/constants/app_constants.dart` | MapTiler API key moved to constants |
| `lib/main.dart` | ConnectivityService init, Google Fonts runtime fetching enabled |
| `lib/screens/customer/add_edit_address_screen.dart` | MapTiler key reference updated |
| `lib/screens/customer/my_orders_screen.dart` | Connectivity-aware loading + NoInternetView |
| `lib/screens/seller/manage_orders_screen.dart` | Confirmation dialog, race-condition guard, connectivity refresh |
| `lib/screens/seller/manage_products_screen.dart` | Connectivity-aware refresh |
| `lib/screens/seller/order_detail_screen.dart` | Full order detail with status update dialog + chat |
| `lib/screens/seller/seller_dashboard_screen.dart` | Notification bell refresh-on-tap, subscription-before-load |
| `lib/screens/seller/seller_shell.dart` | Shell navigation updates |
| `lib/screens/store/store_profile_screen.dart` | Store profile updates |
| `lib/services/product_service.dart` | Product service updates |
| `lib/services/supabase_service.dart` | Seller notification integration |
| `lib/widgets/seller/seller_order_card.dart` | Order card updates |
| `pubspec.yaml` | Package updates |
| `pubspec.lock` | Lock file sync |

### Untracked New Files (from prior session work)

| File | Purpose |
|------|---------|
| `lib/providers/chat_attachment_provider.dart` | Chat attachment state management |
| `lib/providers/message_provider.dart` | (tracked, modified this session) |
| `lib/providers/seller_notification_provider.dart` | Seller notification state |
| `lib/screens/customer/customer_inbox_screen.dart` | Customer inbox screen |
| `lib/screens/seller/seller_inbox_screen.dart` | Seller inbox screen |
| `lib/screens/seller/seller_notification_center_screen.dart` | Seller notification center |
| `lib/services/connectivity_service.dart` | Network reachability service |
| `lib/services/message_service.dart` | (tracked, modified this session) |
| `lib/services/seller_notification_service.dart` | Seller notification CRUD |
| `lib/widgets/chat/` | Chat UI widgets (ChatView, etc.) |
| `lib/widgets/connectivity_banner.dart` | Mid-session connection loss banner |
| `lib/widgets/no_internet_view.dart` | Offline state view |
| `supabase/migrations/20260713_messaging.sql` | Messaging tables + RLS |
| `supabase/migrations/20260713_seller_notifications.sql` | Seller notifications table |
| `supabase/migrations/messaging_attachments_schema.sql` | Message attachments |

### Deleted Files (this session — reverted push notifications)

| File | Purpose |
|------|---------|
| `lib/services/push_notification_service.dart` | FCM service scaffold (reverted) |
| `lib/widgets/message_banner.dart` | In-app banner widget (reverted) |
| `supabase/migrations/20260714_message_notifications.sql` | Message notification migration (reverted) |

---

## Git History This Session

| Commit | Message | Files Changed |
|--------|---------|---------------|
| `2be8d5f` | fix: badge live update — refreshOnTap, subscription-before-load, concurrency guard | 3 files |
| `d839fcb` | fix: remove dead code from FloatingMessageButton + use RPC for markConversationRead | 2 files |

---

## Key Decisions

1. **Subscription-before-load ordering** — Setting up the Realtime subscription *before* the initial data load ensures the listener is always active, even if the load fails. This is the correct pattern for any screen that needs to react to live data.

2. **Refresh-on-tap as safety net** — Realtime events can be missed during brief connectivity drops. Calling `refreshInbox()` before showing the quick-preview sheet guarantees the badge and list reflect the true current state. The concurrency guard prevents redundant parallel queries.

3. **Same pattern for seller notifications** — Applied the identical refresh-on-tap + subscription-before-load pattern to `SellerNotificationProvider` and `SellerDashboardScreen` for consistency across both sides of the app.

4. **Push notifications deferred** — The message push notifications feature was fully investigated, scaffolded (Phase 1 + Phase 2), then reverted at the user's request. The investigation results and architecture decisions are documented here for future reference.

5. **DB trigger for customer notifications** — The push notifications investigation revealed that `message_service.dart` was trying to insert notifications client-side with an invalid enum value (`'message'` not in `notification_category`). The correct approach is a DB trigger (`notify_on_new_message`) that fires on `messages` insert, which was designed but reverted with the rest of the feature.

---

## Technical Deep Dive: Badge Live Update Architecture

### Before This Session

```
CustomerHomeScreen._loadConversations()
  → msgProvider.loadConversationsForCustomer(userId)  // loads data
  → msgProvider.subscribeToInbox(customerId: userId)   // sets up subscription
```

**Problem:** If `loadConversationsForCustomer` fails (network error), `subscribeToInbox` is never called — no Realtime events are caught, badge never updates.

### After This Session

```
CustomerHomeScreen._loadConversations()
  → msgProvider.subscribeToInbox(customerId: userId)   // subscription FIRST
  → msgProvider.loadConversationsForCustomer(userId)   // then load

FloatingMessageButton._showQuickPreview()
  → provider.refreshInbox()                            // force refresh before showing sheet
  → showModalBottomSheet(...)
```

**Benefits:**
1. Subscription is always set up, even if initial load fails
2. Tap triggers a fresh DB fetch — guarantees current state
3. Concurrency guard prevents redundant parallel queries
4. `mounted`/`context.mounted` guards prevent setState after disposal

### Data Flow

```
Realtime event (new message / mark-as-read)
  → MessageProvider.subscribeToInbox callback
  → loadConversationsForCustomer() reloads from DB
  → _perConversationUnreadCounts updated
  → totalUnreadCount recalculated
  → notifyListeners() triggers UI rebuild
  → FloatingMessageButton rebuilds with new badge count

User taps floating button
  → refreshInbox() force-refreshes from DB
  → Same data flow as above
  → Quick-preview sheet opens with fresh data
```

---

## Pre-Existing Bugs Discovered (Not Fixed — Deferred)

| Bug | Location | Impact |
|-----|----------|--------|
| `'message'` not in `notification_category` enum | `message_service.dart` line ~600 | Customer message notifications silently fail to create |
| No INSERT RLS on `notifications` table | Supabase migration | Client-side notification inserts blocked by RLS |
| No `metadata`/`payload` column on `notifications` | Supabase migration | No way to store `conversationId` for deep-linking |
| No push notification infrastructure | Project-wide | No FCM, no device tokens, no background handlers |

These were all designed to be fixed by the push notifications feature (which was reverted). They remain as known issues.

---

## Remaining Issues

| Issue | Status | Priority |
|-------|--------|----------|
| Push notifications not implemented | ⏸️ Deferred (reverted) | High |
| `'message'` enum bug in notification creation | ⚠️ Pre-existing | Medium |
| No INSERT RLS on notifications table | ⚠️ Pre-existing | Medium |
| Floating button badge depends on Realtime reliability | ✅ Mitigated (refreshOnTap) | Low |
| Seller notification bell depends on Realtime reliability | ✅ Mitigated (refreshOnTap) | Low |
| `Skipped 63 frames!` on first render | ⚠️ Cosmetic | Medium |
| Supabase credentials in source code | ⚠️ Security risk | High |

---

## Next Steps for User

1. **Commit all uncommitted changes** — The working directory has significant uncommitted changes across 15+ files (messaging system, connectivity service, seller notifications, order management improvements). These should be committed before starting new work.

2. **Re-implement push notifications when ready** — The investigation results and architecture decisions from this session are documented above. When Firebase project credentials are available, the feature can be re-implemented using the same design (DB trigger for customer notifications, FCM for background push, in-app banner for foreground).

3. **Fix the pre-existing `'message'` enum bug** — The `message_service.dart` file tries to insert `category: 'message'` which is not a valid enum value. This should be fixed independently of the push notifications feature — either by adding `'message'` to the enum (and properly implementing the notification creation) or by removing the broken code path.

4. **Move credentials to environment variables** — Before making the repo public, move Supabase URL and anon key to `--dart-define` or `.env` files.

---

*Session documented by Buffy (Codebuff AI Assistant)*  
*July 14, 2026*
