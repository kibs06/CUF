import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/notification_formatters.dart';

/// Handles all FCM push notification logic:
/// - Token registration & refresh
/// - Permission requests
/// - Foreground message display (local notification)
/// - Background/terminated tap handling (deep link)
/// - Device token storage in Supabase
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  StreamSubscription? _foregroundSub;
  StreamSubscription? _tokenRefreshSub;

  /// Navigation callback for message notifications — set by shell widgets.
  /// Signature: (String conversationId, String storeName)
  void Function(String conversationId, String storeName)? onNavigateToChat;

  /// Generic navigation callback for all non-message notification types.
  /// Signature: (String screen, String? referenceId)
  /// The shell widget wires this to route by screen name.
  void Function(String screen, String? referenceId)? onNavigateToScreen;

  /// Buffer for initial message from cold start (before callback is set)
  RemoteMessage? _pendingInitialMessage;
  /// Buffer for initial non-message notification from cold start
  // TODO: If seller shell sets onNavigateToScreen while customer shell is active,
  // the callback could route to the wrong screen. Acceptable for v1.
  RemoteMessage? _pendingInitialNotification;

  // ── Initialization ──────────────────────────────────────────────

  /// Initialize Firebase Messaging, request permissions, register token,
  /// and set up foreground/background handlers.
  ///
  /// Call once at app startup, after `Firebase.initializeApp()`.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // 1. Request permission (required on iOS, Android 13+)
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (kDebugMode) {
        debugPrint('[Push] Permission status: ${settings.authorizationStatus}');
      }

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        if (kDebugMode) debugPrint('[Push] Permission denied by user');
        return;
      }

      // 2. Initialize local notifications (for foreground display)
      await _initLocalNotifications();

      // Ensure the message channel exists NOW, before any background push
      // arrives. Android 8+ silently drops FCM notifications whose
      // channel_id doesn't exist in the app — creating it lazily on first
      // foreground message means a fresh install's background push would
      // be dropped. Create eagerly so the channel is always present.
      await _ensureMessageChannel();

      // 3. Get and store the initial FCM token
      final token = await _messaging.getToken();
      if (token != null) {
        await _storeToken(token);
        if (kDebugMode) {
          debugPrint('[Push] FCM token: ${token.substring(0, 20)}...');
          debugPrint('[Push] ═══════════════════════════════════════');
          debugPrint('[Push] Full FCM token (copy for Firebase Console):');
          debugPrint('[Push] $token');
          debugPrint('[Push] ═══════════════════════════════════════');
        }
      }

      // 4. Listen for token refreshes
      _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) {
        _storeToken(newToken);
        if (kDebugMode) debugPrint('[Push] Token refreshed');
      });

      // 5. Handle foreground messages
      _foregroundSub = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // 6. Handle notification tap when app was backgrounded
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // 7. Handle notification tap from cold start (app was terminated)
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        final type = initialMessage.data['type'] as String?;
        if (type == 'new_message') {
          _pendingInitialMessage = initialMessage;
        } else {
          _pendingInitialNotification = initialMessage;
        }
        _tryConsumePendingMessage();
      }

      if (kDebugMode) debugPrint('[Push] Initialization complete');
    } catch (e) {
      if (kDebugMode) debugPrint('[Push] Initialization failed: $e');
    }
  }

  /// Called when navigation callbacks are set (e.g. from shell widgets).
  /// If there's a buffered cold-start message, handle it now.
  void _tryConsumePendingMessage() {
    if (_pendingInitialMessage != null && onNavigateToChat != null) {
      final msg = _pendingInitialMessage!;
      _pendingInitialMessage = null;
      _handleNotificationTap(msg);
    }
    if (_pendingInitialNotification != null && onNavigateToScreen != null) {
      final msg = _pendingInitialNotification!;
      _pendingInitialNotification = null;
      _handleNotificationTap(msg);
    }
  }

  // ── Local Notifications ─────────────────────────────────────────

  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false, // Already requested via FCM
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (response) {
        // User tapped the local notification
        if (response.payload != null) {
          try {
            final data = jsonDecode(response.payload!) as Map<String, dynamic>;
            final type = data['type'] as String?;
            if (type == 'new_message') {
              final conversationId = data['conversation_id'] as String?;
              final senderName = data['sender_name'] as String? ?? data['store_name'] as String? ?? 'Store';
              if (conversationId != null) {
                onNavigateToChat?.call(conversationId, senderName);
              }
            } else {
              final screen = data['screen'] as String?;
              final referenceId = data['referenceId'] as String?;
              if (screen != null) {
                onNavigateToScreen?.call(screen, referenceId);
              }
            }
          } catch (_) {}
        }
      },
    );
  }

  /// Show a local notification when a message arrives while the app is in foreground.
  Future<void> _showForegroundNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      if (kDebugMode) print('[Push] Creating notification channel if needed...');
      // Explicitly create the notification channel (required for Android 8+)
      await _ensureMessageChannel();
      if (kDebugMode) print('[Push] Notification channel created/verified');

      const androidDetails = AndroidNotificationDetails(
        'cufmai_messages',
        'Messages',
        channelDescription: 'New message notifications from stores',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (kDebugMode) print('[Push] Showing local notification (id=$notificationId)...');
      await _localNotifications.show(
        id: notificationId,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
        payload: jsonEncode(data),
      );
      if (kDebugMode) print('[Push] ✅ Local notification shown successfully');
    } catch (e, st) {
      if (kDebugMode) {
        print('[Push] ❌ Failed to show local notification: $e');
        print('[Push] Stack trace: $st');
      }
    }
  }

  // ── Notification Channels ───────────────────────────────────────

  /// Ensure the message notification channel exists (Android 8+).
  /// Idempotent — safe to call repeatedly.
  Future<void> _ensureMessageChannel() async {
    try {
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'cufmai_messages',
            'Messages',
            description: 'New message notifications from stores',
            importance: Importance.high,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) print('[Push] Failed to ensure notification channel: $e');
    }
  }

  // ── Message Handlers ────────────────────────────────────────────

  /// Called when a message arrives while the app is in the foreground.
  void _handleForegroundMessage(RemoteMessage message) {
    if (kDebugMode) {
      print('[Push] ═══════════════════════════════════════');
      print('[Push] FOREGROUND MESSAGE RECEIVED');
      print('[Push] ID: ${message.messageId}');
      print('[Push] Notification title: ${message.notification?.title}');
      print('[Push] Notification body: ${message.notification?.body}');
      print('[Push] Data: ${message.data}');
      print('[Push] ═══════════════════════════════════════');
    }

    final data = message.data;
    final notificationTitle = message.notification?.title ?? data['title'] as String? ?? 'Notification';
    final notificationBody = message.notification?.body ?? data['body'] as String? ?? '';

    // Show local notification banner for all types
    _showForegroundNotification(
      title: notificationTitle,
      body: notificationBody,
      data: data,
    );
  }

  /// Called when user taps a notification (backgrounded or cold start).
  void _handleNotificationTap(RemoteMessage message) {
    if (kDebugMode) {
      debugPrint('[Push] Notification tapped: ${message.messageId}');
    }

    final data = message.data;
    final type = data['type'] as String?;

    // Message notifications → route via onNavigateToChat
    if (type == 'new_message') {
      final conversationId = data['conversation_id'] as String?;
      final storeName = data['store_name'] as String? ?? 'Store';
      if (conversationId != null) {
        onNavigateToChat?.call(conversationId, storeName);
      }
      return;
    }

    // All other notification types → route via onNavigateToScreen
    final screen = data['screen'] as String?;
    final referenceId = data['referenceId'] as String?;
    if (screen != null && onNavigateToScreen != null) {
      onNavigateToScreen!.call(screen, referenceId);
    }
  }

  // ── OS App Badge ────────────────────────────────────────────────

  /// Update the OS app icon badge to reflect the current unread count.
  /// Called whenever the in-app unread count changes (new realtime row,
  /// mark-as-read, delete, etc.) so the badge doesn't lag until the
  /// next push arrives.
  Future<void> updateAppBadge(int unreadCount) async {
    try {
      if (unreadCount > 0) {
        await AppBadgePlus.updateBadge(unreadCount);
      } else {
        await AppBadgePlus.updateBadge(0);
      }
      if (kDebugMode) {
        print('[Push] App badge updated: ${formatBadgeCount(unreadCount)}');
      }
    } catch (e) {
      if (kDebugMode) print('[Push] Failed to update app badge: $e');
    }
  }

  // ── Token Management ────────────────────────────────────────────

  /// Store the FCM token in Supabase `device_tokens` table.
  /// Uses upsert on `customer_id` only — one token per user.
  /// When the token rotates (which happens frequently), this replaces
  /// the old token instead of inserting a new row.
  Future<void> _storeToken(String token) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

    try {
      // Upsert — if the same (customer_id, fcm_token) row exists, update it
      // instead of throwing a duplicate key error (23505).
      await Supabase.instance.client.from('device_tokens').upsert(
        {
          'customer_id': userId,
          'fcm_token': token,
          'platform': platform,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'customer_id,fcm_token',
      );
      // Best-effort cleanup: delete any OTHER stale tokens for this user.
      // If this fails, we still have the fresh token stored.
      await Supabase.instance.client
          .from('device_tokens')
          .delete()
          .eq('customer_id', userId)
          .neq('fcm_token', token);
      if (kDebugMode) print('[Push] Token stored for user: $userId (token: ${token.substring(0, 20)}...)');
    } catch (e) {
      if (kDebugMode) print('[Push] Failed to store token: $e');
    }
  }

  /// Remove the current device's token on logout (optional but good practice).
  Future<void> removeToken() async {
    final token = await _messaging.getToken();
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (token == null || userId == null) return;

    try {
      await Supabase.instance.client
          .from('device_tokens')
          .delete()
          .eq('customer_id', userId)
          .eq('fcm_token', token);
      if (kDebugMode) debugPrint('[Push] Token removed for user: $userId');
    } catch (e) {
      if (kDebugMode) debugPrint('[Push] Failed to remove token: $e');
    }
  }

  // ── Cleanup ─────────────────────────────────────────────────────

  void dispose() {
    _foregroundSub?.cancel();
    _tokenRefreshSub?.cancel();
  }
}
