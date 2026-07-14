# SoleVision — Real-Time Messaging System

**Last Updated:** July 14, 2026  
**Purpose:** Complete reference for AI agents working on the Seller-Customer messaging feature.  
**Scope:** Covers architecture, data models, realtime subscriptions, optimistic UI, attachment uploads, read receipts, typing indicators, and all known gotchas.

---

## Quick Summary

The messaging system is a **shared widget architecture** — a single `ChatView` widget serves both the seller and customer sides, parameterized by `viewerRole`. All realtime subscriptions, optimistic sends, read receipts, typing indicators, and attachment handling are implemented in shared service/widget files. No role-specific chat code exists.

**Key files:**
| File | Role |
|------|------|
| `lib/services/message_service.dart` | Core service: Message/Conversation models, CRUD, upload, subscriptions, typing, notifications |
| `lib/widgets/chat/chat_view.dart` | Shared chat UI: messages list, bubbles, input bar, attachment picking/sending, full-screen viewers |
| `lib/providers/chat_attachment_provider.dart` | Persists failed attachment messages across widget rebuilds |
| `lib/providers/message_provider.dart` | (If exists) Inbox-level state management |
| `lib/screens/customer/customer_inbox_screen.dart` | Customer inbox — uses `ChatView` with `viewerRole: 'customer'` |
| `lib/screens/seller/seller_inbox_screen.dart` | Seller inbox — uses `ChatView` with `viewerRole: 'seller'` |

---

## Architecture

### Shared Widget Pattern

```
ChatView(conversationId, viewerRole: 'seller' | 'customer', otherPartyName)
├── _loadMessages()          → MessageService.getMessages()
├── _subscribeToMessages()   → MessageService.subscribeToConversation() (realtime)
├── _subscribeToTyping()     → MessageService.subscribeToTyping() (broadcast channel)
├── _sendMessage()           → Optimistic text send with UUID matching
├── _sendAttachmentMessage() → Chunked upload with real progress + optimistic UI
├── _buildMessageBubble()    → Handles text, image, video, sending, failed states
└── _buildInputBar()         → Text field + attachment button + send button
```

Both sides share the same `ChatView` — the only difference is the `viewerRole` parameter which controls:
- Bubble alignment (right for own messages, left for received)
- Read receipt icons (shown only on own messages)
- Sender type in DB inserts (`'customer'` or `'seller'`)
- Typing indicator filtering (shows other party's typing)

### Data Flow

```
User sends message
  │
  ├─→ Optimistic placeholder inserted (isSending=true, isRead=false)
  │
  ├─→ Background: sendMessage() → INSERT INTO messages → UPDATE conversations
  │
  ├─→ Realtime subscription fires (INSERT event)
  │    └─→ Merge logic preserves local-only fields (isSending, sendFailed, localFile, progress)
  │
  ├─→ Server response arrives → Replace placeholder with confirmed Message
  │
  └─→ Recipient opens conversation → markConversationRead() → UPDATE messages SET is_read=true
       └─→ Realtime subscription fires (UPDATE event) → isRead flips to true → ✓✓ appears
```

---

## Data Models

### Message

```dart
class Message {
  // DB-persisted fields
  final String id;                          // UUID (client-generated for optimistic matching)
  final String conversationId;
  final String senderId;
  final String senderType;                  // 'customer' | 'seller'
  final String? body;                       // text content (nullable for attachment-only)
  final String? orderReferenceId;
  final bool isRead;
  final DateTime createdAt;
  final String? attachmentUrl;              // signed URL from Supabase Storage
  final String? attachmentType;             // 'image' | 'video'
  final String? attachmentThumbnailUrl;     // video thumbnail signed URL
  final int? attachmentDurationSeconds;     // video duration
  final int? attachmentSizeBytes;           // file size

  // Local-only fields (NOT persisted to DB)
  final bool isSending;     // true while upload/send is in progress
  final bool sendFailed;    // true if send failed (shows retry UI)
  final File? localFile;    // local file for preview during upload
  final double progress;    // 0.0–1.0 upload progress (real byte-level tracking)

  // Computed properties
  bool get hasAttachment;
  bool get hasBody;
  bool get isImageMessage;
  bool get isVideoMessage;
  String get previewText;   // for inbox list
  String get relativeTime;  // "5m ago", "3h ago", etc.

  // copyWith for efficient progress updates
  Message copyWith({bool? isSending, bool? sendFailed, double? progress, ...});
}
```

### Conversation

```dart
class Conversation {
  final String id;
  final String storeId;
  final String customerId;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final DateTime createdAt;

  // Enriched via joins
  final String? customerName;   // from profiles.full_name
  final String? storeName;      // from stores.name
  final int unreadCount;
}
```

---

## Features Implemented

### 1. Real-Time Message Delivery

**Problem:** Messages didn't appear until manual refresh.

**Solution:** `subscribeToConversation()` uses Supabase Realtime `.stream()` API:
```dart
_client
    .from('messages')
    .stream(primaryKey: ['id'])
    .eq('conversation_id', conversationId)
    .order('created_at', ascending: true)
    .listen((data) { ... });
```

The stream emits the **full filtered message list** after each DB change (INSERT, UPDATE, DELETE). The caller replaces its local list entirely rather than appending individual messages.

### 2. Message Order (Oldest at Top)

**Problem:** Messages appeared in reversed order (newest at top).

**Root cause:** The `.stream()` API doesn't guarantee consistent ordering.

**Solution:** Explicit client-side sort in the listen callback:
```dart
messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
```

**Chat screen rendering:** `ListView.builder` with ascending data, `reverse: false`, auto-scroll to `maxScrollExtent` on load.

### 3. Optimistic Text Send

Text messages appear **immediately** in the sender's UI before the server round-trip:

1. Generate client-side UUID via `const Uuid().v4()`
2. Insert placeholder `Message` with `isSending: true`, `isRead: false`
3. Send to server in background
4. On success: replace placeholder with confirmed server message
5. On failure: mark placeholder as `sendFailed: true` with retry UI

**Why client-side UUID?** The storage path for attachments must match the DB row ID. By generating the UUID on the client, we know the ID before the round-trip completes.

### 4. Optimistic Attachment Send

Same pattern as text, but with additional steps:

1. Insert placeholder with `localFile` reference (shows image/video preview immediately)
2. Upload file via chunked reads with real progress tracking
3. Generate video thumbnail if needed
4. Insert message row with attachment URLs
5. Replace placeholder with confirmed message

### 5. Real Upload Progress (Chunked Reads)

**Problem:** Old implementation used timer-based fake progress (30%→60%→85% jumps).

**Solution:** Real byte-level progress via `RandomAccessFile` chunked reads:

```dart
const chunkSize = 1024 * 1024; // 1 MB
final raf = await file.open(mode: FileMode.read);
int bytesRead = 0;
while (bytesRead < sizeBytes) {
    final chunk = await raf.read(chunkSize);
    allBytes.addAll(chunk);
    bytesRead += chunk.length;
    onProgress?.call((bytesRead / sizeBytes) * 0.85); // 0.0→0.85 during read
}
await raf.close();
// Then uploadBinary (0.85→1.0 during network)
```

**Progress breakdown:**
- `0.0 → 0.85`: File read phase (real byte-level, 1MB chunks)
- `0.85 → 1.0`: Network upload phase via `uploadBinary()`

**UI:** `LinearProgressIndicator` + percentage text (e.g., "42%") on both image and video bubbles during upload.

### 6. Live Read Receipts

- **Single checkmark (✓):** Shown immediately when message is sent (sent but not read by recipient)
- **Double checkmark (✓✓):** Appears live when recipient reads the message

**How it works:**
1. Sender's message has `isRead: false` in the optimistic placeholder
2. Recipient opens conversation → `markConversationRead()` runs: `UPDATE messages SET is_read = true WHERE sender_type = 'other'`
3. Realtime subscription captures the UPDATE event → `isRead` flips to `true` → ✓✓ appears instantly

**Important:** `isRead` represents whether the *current user* has read messages from the *other party*. For the sender's own messages, `isRead` tracks whether the recipient has read them.

### 7. Failed State with Retry

**Text messages:**
- Shows "Failed • Tap to retry" with error icon
- Tap removes the failed message and re-sends by pre-filling the input

**Attachment messages:**
- Shows local file preview with "Tap to retry" overlay
- Tap removes failed message and re-triggers the full upload flow
- SnackBar with actual error message + Retry action button

**Failed messages are persisted** via `ChatAttachmentProvider` so they survive widget rebuilds (navigating away and back).

### 8. Typing Indicators

Uses Supabase **Broadcast Channels** (not the DB):

```dart
_client.channel('typing:$conversationId').sendBroadcastMessage(
    event: 'typing',
    payload: {'sender_id': id, 'sender_type': type, 'is_typing': true},
);
```

- Debounced: typing stop fires 2 seconds after last keystroke
- Only shows typing from the OTHER party (filtered by `senderType`)
- Animated dots with staggered bounce animation

### 9. Reconnection Handling

Listens to `ConnectivityService.isOnlineStream`:
```dart
if (isOnline && _wasOffline && mounted) {
    _loadMessages();        // Re-fetch all messages
    _subscribeToMessages(); // Re-create realtime subscription
}
```

Catches any messages missed during offline periods.

### 10. "New Message ↓" Pill

When the user has scrolled up and a new message arrives:
- Shows a floating pill at the bottom: "↓ New message"
- Tap scrolls to bottom and dismisses the pill
- Auto-dismissed if user scrolls back to bottom naturally
- Tracks "near bottom" as within 150px of `maxScrollExtent`

### 11. HEIC/iOS Photo Handling

iPhone photos often use HEIC format, which the Supabase Storage bucket doesn't allow.

**Solution:** MIME type mapping in `_resolveMimeType()`:
```dart
'heic' || 'heif' => 'image/jpeg', // declares JPEG but bytes are still HEIC
```

Supabase Storage checks the declared MIME type metadata, not file magic bytes, so this works. The upload is validated against allowed types before attempting.

---

## Key Methods Reference

### MessageService

| Method | Purpose |
|--------|---------|
| `getOrCreateConversation(storeId, customerId)` | Find or create a conversation (customer-side only) |
| `getConversationsForStore(storeId)` | Seller inbox list |
| `getConversationsForCustomer(customerId)` | Customer inbox list |
| `getMessages(conversationId, {limit})` | Fetch messages, oldest first |
| `sendMessage(id, conversationId, senderId, senderType, body, ...)` | Insert message + update conversation metadata + create notification |
| `uploadAttachment(conversationId, messageId, filePath, mimeType, onProgress)` | Chunked file read + uploadBinary with real progress |
| `generateVideoThumbnail(conversationId, messageId, videoPath)` | Generate + upload JPEG thumbnail |
| `markConversationRead(conversationId, readerType)` | Mark other party's messages as read |
| `subscribeToConversation(conversationId, onMessagesChanged)` | Realtime subscription for messages table |
| `subscribeToInbox({storeId, customerId}, onUpdate)` | Realtime subscription for conversations table |
| `sendTypingStart/Stop(...)` | Broadcast typing events |
| `subscribeToTyping(...)` | Listen for other party's typing events |

### ChatView

| Method | Purpose |
|--------|---------|
| `_loadMessages()` | Fetch messages + merge with persisted failed messages |
| `_subscribeToMessages()` | Wire up realtime subscription with merge logic |
| `_sendMessage()` | Optimistic text send with UUID matching |
| `_sendAttachmentMessage({caption})` | Optimistic attachment send with chunked upload progress |
| `_retryAttachment(failedMessage)` | Re-trigger upload for a failed attachment |
| `_retryFailedMessage(failedMessage)` | Re-send a failed text message |
| `_resolveMimeType(type, ext)` | Map file extension to allowed MIME type |
| `_buildImageAttachment(message, isOwnMessage)` | Image bubble with sending/failed/normal states |
| `_buildVideoAttachment(message, isOwnMessage)` | Video bubble with thumbnail + play icon + progress |

---

## Subscription Lifecycle

### subscribeToConversation (Messages)

```
ChatView.initState()
  └─→ _subscribeToMessages()
       └─→ MessageService.subscribeToConversation()
            └─→ _client.from('messages').stream(primaryKey: ['id'])
                 .eq('conversation_id', id)
                 .order('created_at', ascending: true)
                 .listen(callback)

ChatView.dispose()
  └─→ _subscription?.cancel()  // Properly unsubscribes
```

### subscribeToInbox (Conversations)

```
InboxScreen.initState()
  └─→ MessageProvider.loadConversations()
       └─→ MessageService.subscribeToInbox()
            └─→ _client.from('conversations').stream(primaryKey: ['id'])
                 .eq(filterColumn, filterValue)
                 .listen(callback)

InboxScreen.dispose()
  └─→ subscription?.cancel()
```

### subscribeToTyping (Broadcast)

```
ChatView.initState()
  └─→ _subscribeToTyping()
       └─→ MessageService.subscribeToTyping()
            └─→ _client.channel('typing:$conversationId')
                 .onBroadcast(event: 'typing', callback: ...)
                 .subscribe()

ChatView.dispose()
  └─→ MessageService.unsubscribeFromTyping(channel)
       └─→ _client.removeChannel(channel)
       └─→ _typingChannels.remove(conversationId)
```

---

## Merge Logic (Realtime + Optimistic)

When the realtime stream fires during an active upload, the merge logic preserves local-only fields:

```dart
// Build map of local-only messages
final localOnly = {
    for (final m in _messages)
        if (m.isSending || m.sendFailed) m.id: m,
};

// Merge: use server data but preserve local state
_messages = messages.map((m) {
    final local = localOnly[m.id];
    if (local != null) {
        return Message(
            // ... all server fields ...
            isSending: local.isSending,   // preserved
            sendFailed: local.sendFailed, // preserved
            localFile: local.localFile,   // preserved
            progress: local.progress,     // preserved
        );
    }
    return m;
}).toList();
```

**Critical:** The merge must preserve ALL local-only fields (`isSending`, `sendFailed`, `localFile`, `progress`). Missing any of these causes bugs like progress resetting to 0 or sending indicators disappearing.

---

## Storage Path Convention

```
message-attachments/{conversation_id}/{message_id}/{filename}
```

- `conversation_id`: UUID of the conversation
- `message_id`: Client-generated UUID (matches the DB row)
- `filename`: `{timestamp}.{ext}` (e.g., `1689345678901.jpg`)

**RLS policies** on the `message-attachments` bucket check `(storage.foldername(name))[1]::uuid` to ensure the uploader has access to the conversation.

**Signed URLs** are generated with 1-year expiry (`365 * 24 * 3600` seconds) so old messages don't break.

---

## Allowed MIME Types

The `message-attachments` bucket accepts:
```
image/jpeg, image/png, image/webp, image/gif
video/mp4, video/quicktime
```

**HEIC handling:** Maps `heic`/`heif` extensions to `image/jpeg` MIME type. This works because Supabase Storage checks the declared metadata, not file magic bytes.

---

## ChatAttachmentProvider

Persists failed attachment messages in memory across widget rebuilds:

```dart
class ChatAttachmentProvider extends ChangeNotifier {
    final Map<String, List<Message>> _failedMessages = {}; // keyed by conversationId

    void addFailedMessage(Message message);
    void removeFailedMessage(String conversationId, String messageId);
    List<Message> mergeWithFailed(List<Message> dbMessages, String conversationId);
}
```

**Why needed:** When `ChatView` is rebuilt (navigation, hot reload), the `_messages` list is cleared. Failed messages that haven't been sent to the DB would be lost without this provider. On `_loadMessages()`, the provider's failed messages are merged back into the list.

---

## Notification Integration

When a message is sent, `_createMessageNotification()` runs:

- **Customer → Seller:** Uses `SellerNotificationService.instance.createNewMessage()` (deduplication built in)
- **Seller → Customer:** Inserts into `notifications` table with category `'message'`

Notifications are fire-and-forget — a notification failure doesn't block the message send.

---

## Gotchas & Known Issues

### ⚠️ DO NOT
- **Don't assume `.stream()` returns sorted data** — always sort client-side
- **Don't append individual messages from the stream** — the stream emits the FULL list, replace entirely
- **Don't forget to cancel subscriptions in `dispose()`** — orphaned listeners cause duplicate inserts and memory leaks
- **Don't set `isRead: true` on optimistic placeholders** — the sender's messages start as unread (recipient hasn't read them yet)
- **Don't use `.upload()` for progress tracking** — the SDK doesn't expose progress callbacks; use chunked reads + `uploadBinary()`
- **Don't skip MIME type validation** — HEIC files from iPhones will be silently rejected by the bucket
- **Don't forget to preserve `progress` in the merge logic** — causes progress bar to reset during upload

### ⚠️ ALWAYS
- **Always generate client-side UUIDs for messages** — needed for storage path matching and optimistic reconciliation
- **Always sort messages ascending (oldest first)** in the query AND client-side
- **Always close the `RandomAccessFile` in a `finally` block** — prevents file handle leaks
- **Always validate MIME types before upload** — throw `UnsupportedError` early with a clear message
- **Always check `mounted` before calling `setState`** — prevents "setState() called after dispose()" errors

### Known Limitations
- HEIC files are declared as JPEG but bytes remain HEIC (works because Supabase checks metadata only)
- Upload progress during the network phase (0.85→1.0) is not byte-accurate — only the read phase is
- No upload speed estimation or ETA display yet
- No file size display on the attachment bubble during upload yet
- Typing indicators use broadcast channels which don't persist — if the recipient isn't in the conversation, they won't see it

---

## Database Schema (messages table)

```sql
CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id),
    sender_id UUID NOT NULL,
    sender_type TEXT NOT NULL CHECK (sender_type IN ('customer', 'seller')),
    body TEXT,
    order_reference_id UUID,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    attachment_url TEXT,
    attachment_type TEXT CHECK (attachment_type IN ('image', 'video')),
    attachment_thumbnail_url TEXT,
    attachment_duration_seconds INTEGER,
    attachment_size_bytes INTEGER
);

-- Realtime publication (required for .stream() to work)
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
```

---

## Testing Checklist

### Realtime Delivery
- [ ] Two devices in same conversation see messages appear live
- [ ] No manual refresh or re-navigation needed
- [ ] Messages appear in correct order (oldest at top)
- [ ] "New message ↓" pill appears when scrolled up
- [ ] Auto-scrolls to bottom when near bottom

### Optimistic Send
- [ ] Text message appears immediately in sender's UI
- [ ] No duplicate messages when realtime event arrives
- [ ] Failed text shows "Failed • Tap to retry"
- [ ] Retry re-sends the message

### Attachment Upload
- [ ] Image shows local preview immediately
- [ ] Progress bar shows real percentage (not fake jumps)
- [ ] Video shows thumbnail + play icon during upload
- [ ] Failed attachment shows "Tap to retry" overlay
- [ ] Retry re-triggers the full upload flow
- [ ] HEIC files from iPhone upload successfully

### Read Receipts
- [ ] Single checkmark (✓) appears immediately on sent message
- [ ] Double checkmark (✓✓) appears when recipient opens conversation
- [ ] Read receipt only shows on own messages (not received)
- [ ] Read receipt hidden during sending/failed states

### Typing Indicators
- [ ] Typing dots appear when other party types
- [ ] Typing stops 2 seconds after last keystroke
- [ ] Only shows other party's typing (not own)
- [ ] Channel properly cleaned up on dispose

### Edge Cases
- [ ] Reconnection after offline: messages re-sync
- [ ] Navigate away and back: failed messages persist
- [ ] Multiple rapid sends: no race conditions
- [ ] Large files (20MB+): progress updates smoothly
- [ ] Empty conversation: shows "Start a conversation" state

---

*SoleVision Messaging System Documentation — July 14, 2026*
