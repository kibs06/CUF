# Following Feature — Architecture Documentation

**Version:** 1.1.0  
**Last Updated:** July 20, 2026  
**Target:** AI assistants working on SoleVision (Flutter + Supabase)

---

## 1. Overview

The **Following** feature allows customers to follow stores they like. Following a store:
- Adds it to a "Following" list accessible from the customer's Profile screen
- Enables quick messaging to the store owner
- Displays the customer's following count on their profile
- Displays follower count on the store's public profile

The feature follows a **single-provider, optimistic-with-rollback** pattern — one `FollowProvider` instance owns all follow state, shared across three screens.

---

## 2. Database Schema

### Table: `store_follows`

```sql
CREATE TABLE store_follows (
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  store_id   UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, store_id)  -- unique constraint prevents duplicate follows
);
```

**RLS Policies:**
- **SELECT:** Public (anyone can see follower counts)
- **INSERT:** `auth.uid() = user_id` (users can only follow as themselves)
- **DELETE:** `auth.uid() = user_id` (users can only unfollow themselves)

**Key queries against this table:**
| Purpose | Query |
|---|---|
| Check if user follows a store | `SELECT store_id FROM store_follows WHERE user_id = ? AND store_id = ?` |
| Get followed stores (with details) | `SELECT created_at, stores(id, name, ...) FROM store_follows JOIN stores ON ... WHERE user_id = ?` |
| Get follower count for a store | `SELECT count(*) FROM store_follows WHERE store_id = ?` |
| Get following count for a user | `SELECT count(*) FROM store_follows WHERE user_id = ?` |

---

## 3. File Map

| Layer | File | Purpose |
|---|---|---|
| **Model** | `lib/models/followed_store.dart` | Data class for a followed store (storeId, name, logoUrl, tagline, color, followedAt, followerCount) |
| **Service** | `lib/services/store_service.dart` | All Supabase calls: `followStore`, `unfollowStore`, `toggleFollow`, `isFollowingAsync`, `getFollowedStores`, `getFollowerCounts`, `getFollowerCount`, `getFollowingCount` |
| **Provider** | `lib/providers/follow_provider.dart` | `FollowProvider` — single source of truth for follow state, optimistic toggle with rollback, reconciliation |
| **UI — Profile** | `lib/screens/shared/profile_screen.dart` | Shows tappable "N Following" stat under role badge |
| **UI — Dialog** | `lib/screens/shared/following_list_dialog.dart` | Centered modal listing followed stores, swipe gestures, unfollow, message |
| **UI — Store** | `lib/screens/store/store_profile_screen.dart` | Follower count in stats row, animated Follow button |
| **Registration** | `lib/main.dart` | Registers `FollowProvider` in `MultiProvider`, wires `loadForUser` on session restore + login hook, `reset` on logout |

---

## 4. Architecture Flow

### 4.1 State Management Pattern

```
┌─────────────────────────────────────────────────────┐
│                    FollowProvider                     │
│  (single instance, registered at app root)           │
│                                                      │
│  _followedStoreIds: Set<String>  ← fast lookup       │
│  followingCount: int             ← displayed in UI   │
│  _followedStores: List<FollowedStore> ← dialog data  │
│  _isLoaded: bool                 ← loading gate      │
│  _errorMessage: String?          ← error state       │
│                                                      │
│  Methods:                                            │
│    loadForUser(userId)  → fetch from DB              │
│    reconcileCount(userId) → re-sync count from DB    │
│    toggle(storeId)      → optimistic + rollback      │
│    reset()              → clear on logout            │
│    isFollowing(storeId) → read-only check            │
└─────────────────────────────────────────────────────┘
         │                    │                    │
    ┌────▼────┐         ┌────▼────┐         ┌────▼────┐
    │ Profile │         │ Dialog  │         │  Store  │
    │ Screen  │         │         │         │ Profile │
    │ watch() │         │ watch() │         │ watch() │
    └─────────┘         └─────────┘         └─────────┘
```

All three screens call `context.watch<FollowProvider>()` — toggling in any screen instantly reflects everywhere via `notifyListeners()`.

### 4.2 Initialization Sequence

```
App Start
  │
  ├─ MultiProvider creates FollowProvider(StoreService.instance)
  │
  └─ addPostFrameCallback (main.dart)
       │
       ├─ If user already logged in (session restore):
       │    followProvider.loadForUser(userId)
       │
       ├─ auth.onLoginHook = (userId) {
       │    followProvider.loadForUser(userId);
       │  }
       │
       └─ auth.onLogoutHook = () {
            followProvider.reset();
          }
```

### 4.3 Follow/Unfollow Toggle Flow

```
User taps Follow button
  │
  ├─ FollowProvider.toggle(storeId)
  │    │
  │    ├─ OPTIMISTIC UPDATE (synchronous, before any network call):
  │    │    - Add/remove storeId from _followedStoreIds
  │    │    - Increment/decrement followingCount (clamped to >= 0)
  │    │    - notifyListeners() → UI updates instantly
  │    │
  │    ├─ NETWORK CALL: await StoreService.toggleFollow(storeId)
  │    │    │
  │    │    ├─ StoreService checks isFollowingAsync() → DB query
  │    │    ├─ If was following: unfollowStore() → DELETE from store_follows
  │    │    └─ If not following: followStore() → UPSERT into store_follows
  │    │
  │    ├─ ON SUCCESS:
  │    │    - Re-fetch followedStores list (for dialog consistency)
  │    │    - Reconcile followingCount with DB truth (getFollowingCount)
  │    │    - notifyListeners()
  │    │
  │    └─ ON FAILURE (catch):
  │         - ROLLBACK: reverse the optimistic update
  │         - Clamp followingCount >= 0
  │         - notifyListeners()
  │         - rethrow → caller shows SnackBar error
```

### 4.4 Reconciliation

The provider reconciles against the DB in two places:
1. **On dialog open** (`FollowingListDialog.initState`): calls `reconcileCount(userId)` to fix any drift
2. **After successful toggle**: re-queries `getFollowingCount` to set the exact DB count

This prevents accumulated optimistic drift from causing negative or incorrect counts.

---

## 5. Service Layer Details

### StoreService — Follow Methods

```dart
// ─── FOLLOW / UNFOLLOW ───────────────────────────────────────

Future<void> followStore(String storeId) async {
  // Idempotent upsert — safe to call multiple times.
  // ignoreDuplicates handles race conditions from rapid double-taps.
  await _client.from('store_follows').upsert(
    {'user_id': userId, 'store_id': storeId},
    onConflict: 'user_id,store_id',
    ignoreDuplicates: true,
  );
}

Future<void> unfollowStore(String storeId) async {
  await _client
      .from('store_follows')
      .delete()
      .eq('user_id', userId)
      .eq('store_id', storeId);
}

Future<bool> isFollowingAsync(String storeId) async {
  final data = await _client
      .from('store_follows')
      .select('store_id')
      .eq('user_id', userId)
      .eq('store_id', storeId)
      .maybeSingle();
  return data != null;
}

Future<void> toggleFollow(String storeId) async {
  final following = await isFollowingAsync(storeId);
  if (following) {
    await unfollowStore(storeId);
  } else {
    await followStore(storeId);
  }
}

// ─── QUERIES ─────────────────────────────────────────────────

Future<int> getFollowingCount(String userId) async {
  // Source of truth for following count
  final response = await _client
      .from('store_follows')
      .select('store_id')
      .eq('user_id', userId)
      .count(CountOption.exact);
  return response.count;
}

Future<int> getFollowerCount(String storeId) async {
  // Source of truth for follower count (shown on store profile)
  final response = await _client
      .from('store_follows')
      .select('user_id')
      .eq('store_id', storeId)
      .count(CountOption.exact);
  return response.count;
}

Future<List<FollowedStore>> getFollowedStores(String userId) async {
  // Joined query: store_follows + stores table
  // Returns store details needed for the Following dialog
  final data = await _client
      .from('store_follows')
      .select('created_at, stores(id, name, logo_url, tagline, brand_color)')
      .eq('user_id', userId)
      .order('created_at', ascending: false);

  // Batched follower counts to avoid N+1
  final storeIds = data.map((r) => r['stores']['id'] as String).toList();
  final counts = await getFollowerCounts(storeIds);

  return data.map((r) {
    final store = r['stores'];
    return FollowedStore(
      storeId: store['id'],
      name: store['name'],
      logoUrl: store['logo_url'],
      tagline: store['tagline'],
      color: store['brand_color'],
      followedAt: DateTime.parse(r['created_at']),
      followerCount: counts[store['id']] ?? 0,
    );
  }).toList();
}

Future<Map<String, int>> getFollowerCounts(List<String> storeIds) async {
  // Single batched query for multiple stores' follower counts
  final data = await _client
      .from('store_follows')
      .select('store_id')
      .inFilter('store_id', storeIds);
  final counts = <String, int>{};
  for (final row in data) {
    final id = row['store_id'] as String;
    counts[id] = (counts[id] ?? 0) + 1;
  }
  return counts;
}
```

---

## 6. UI Components

### 6.1 Profile Screen — Following Stat

**Location:** `lib/screens/shared/profile_screen.dart` → `_buildFollowingStat()`

Displays a tappable row under the role badge:
```
     12 Following ▸
```

- Uses `context.watch<FollowProvider>()` to read `followingCount`
- Opens `FollowingListDialog` on tap
- Shows "0 Following" even when count is 0 (tappable, opens empty-state dialog)

### 6.2 Following List Dialog

**Location:** `lib/screens/shared/following_list_dialog.dart`

Centered modal dialog with three states:
1. **Loading:** 3 shimmer skeleton rows
2. **Error:** Error icon + message + "Try Again" retry button
3. **Empty:** "You're not following any stores yet" + "Browse Stores" button
4. **Content:** Scrollable list of followed stores

**Each row features swipe gestures (flutter_slidable):**
- **Swipe right → Unfollow:** Gmail-style auto-commit with undo snackbar (4s duration)
- **Swipe left → Message:** Reveals a "Message" button (tap to confirm, no auto-trigger)
- **Tap row → Navigate:** Closes dialog, opens `StoreProfileScreen`

**Unfollow flow in dialog:**
1. Row animates out via `DismissiblePane`
2. `FollowProvider.toggle()` called (optimistic)
3. On success: shows "Unfollowed {name} · UNDO" snackbar
4. On failure: re-fetches list, shows error snackbar

### 6.3 Store Profile — Follow Button

**Location:** `lib/screens/store/store_profile_screen.dart` → `_FollowButton`

Extracted into its own `StatefulWidget` with:
- **Scale bounce animation:** 1.0 → 1.12 → 1.0 (220ms) on tap
- **AnimatedSwitcher:** Smooth cross-fade between "Follow" and "Following ✓"
- **Haptic feedback:** `HapticFeedback.lightImpact()` on tap
- **Double-tap guard:** `_isLoading` flag prevents concurrent toggles
- **DB reconciliation:** After follow/unfollow, re-fetches true follower count from DB after 500ms

**Follower count display:** Shown in the stats row as `"{count} followers"` with proper singular/plural.

---

## 7. Data Integrity Mechanisms

### 7.1 Idempotent Writes
`followStore()` uses Supabase `upsert` with `onConflict: 'user_id,store_id'` and `ignoreDuplicates: true`. Rapid double-taps cannot create duplicate rows.

### 7.2 Optimistic Updates with Rollback
`FollowProvider.toggle()`:
1. Updates local state synchronously (before network)
2. Calls the network
3. On success: reconciles count with DB
4. On failure: reverses the exact same local change, rethrows error

### 7.3 Count Clamping
`followingCount = math.max(0, followingCount + delta)` — structurally prevents negative counts regardless of upstream bugs.

### 7.4 Periodic Reconciliation
- **Dialog open:** `reconcileCount(userId)` queries `getFollowingCount` and overwrites local count
- **After toggle:** `getFollowingCount` called to sync exact DB value

### 7.5 Error State Tracking
`FollowProvider.errorMessage` captures load failures. `FollowingListDialog` shows an error UI with retry button instead of an infinite skeleton.

---

## 8. Known Issues / Future Improvements

| Issue | Status | Notes |
|---|---|---|
| No unique constraint migration yet | ⚠️ Missing | The code uses `upsert` with `onConflict` but the actual DB constraint should be added via migration |
| 500ms reconciliation delay in StoreProfileScreen | ⚠️ Tradeoff | Fragile — could miss if DB propagation is slow |
| No concurrent-tap protection on dialog rows | ⚠️ Minor | Rapid swipes on multiple rows could fire parallel toggles |
| Error state in dialog doesn't show specific error message | ⚠️ Minor | Always shows "Could not load followed stores" regardless of error type |
| No accessibility long-press fallback for swipe actions | ⚠️ Minor | Users who can't swipe have no alternative way to unfollow/message |

---

## 9. Testing Checklist

- [ ] Follow a store → row exists in `store_follows` table (verify via DB)
- [ ] Follow → hot restart → still shows "Following" (confirms write succeeded)
- [ ] Open Following dialog → loads without infinite skeleton
- [ ] Open Following dialog with broken query → shows error + retry
- [ ] Rapid double-tap Follow/Unfollow 10x → count matches actual DB rows, never negative
- [ ] Unfollow from dialog → count decrements, row removed, undo works
- [ ] Unfollow from store profile → count decrements, button reverts to "Follow"
- [ ] Follow from dialog → store profile shows updated follower count
- [ ] Follow from store profile → profile screen count updates
- [ ] Logout → FollowProvider resets, no stale data for next user
- [ ] Swipe right on dialog row → auto-deletes with undo snackbar
- [ ] Swipe left on dialog row → reveals Message button, tapping opens chat

---

## 10. Screen Navigation Map

```
ProfileScreen
  └─ taps "N Following"
       └─ FollowingListDialog (modal)
            ├─ taps row → Navigator.pop + StoreProfileScreen(storeId)
            ├─ swipes left → Message button → MessageService.getOrCreateConversation → ChatView
            └─ swipes right → Unfollow (+ undo snackbar)

StoreProfileScreen
  └─ Follow/Following button → FollowProvider.toggle()
  └─ Message Seller button → MessageService.getOrCreateConversation → ChatView
```
