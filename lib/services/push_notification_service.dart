import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// Navigation callback — set by main.dart or the root widget.
  /// Signature: (String conversationId, String storeName)
  void Function(String conversationId, String storeName)? onNavigateToChat;

  /// Buffer for initial message from cold start (before callback is set)
  RemoteMessage? _pendingInitialMessage;

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
        // Buffer the message — will be consumed when callback is set
        _pendingInitialMessage = initialMessage;
        _tryConsumePendingMessage();
      }

      if (kDebugMode) debugPrint('[Push] Initialization complete');
    } catch (e) {
      if (kDebugMode) debugPrint('[Push] Initialization failed: $e');
    }
  }

  /// Called when the navigation callback is set (e.g. from CustomerHomeScreen).
  /// If there's a buffered cold-start message, handle it now.
  void _tryConsumePendingMessage() {
    if (_pendingInitialMessage != null && onNavigateToChat != null) {
      final msg = _pendingInitialMessage!;
      _pendingInitialMessage = null;
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
            final conversationId = data['conversation_id'] as String?;
            // Use sender_name for navigation label (dynamic per direction)
            final senderName = data['sender_name'] as String? ?? data['store_name'] as String? ?? 'Store';
            if (conversationId != null) {
              onNavigateToChat?.call(conversationId, senderName);
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
      print('[Push] Creating notification channel if needed...');
      // Explicitly create the notification channel (required for Android 8+)
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'solevision_messages',
            'Messages',
            description: 'New message notifications from stores',
            importance: Importance.high,
          ),
        );
        print('[Push] Notification channel created/verified');
      }

      const androidDetails = AndroidNotificationDetails(
        'solevision_messages',
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
      print('[Push] Showing local notification (id=$notificationId)...');
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
      print('[Push] ✅ Local notification shown successfully');
    } catch (e, st) {
      print('[Push] ❌ Failed to show local notification: $e');
      print('[Push] Stack trace: $st');
    }
  }

  // ── Message Handlers ────────────────────────────────────────────

  /// Called when a message arrives while the app is in the foreground.
  void _handleForegroundMessage(RemoteMessage message) {
    // Use print() not debugPrint() so it shows in release builds too
    print('[Push] ═══════════════════════════════════════');
    print('[Push] FOREGROUND MESSAGE RECEIVED');
    print('[Push] ID: ${message.messageId}');
    print('[Push] Notification title: ${message.notification?.title}');
    print('[Push] Notification body: ${message.notification?.body}');
    print('[Push] Data: ${message.data}');
    print('[Push] ═══════════════════════════════════════');

    final data = message.data;
    final type = data['type'] as String?;

    // Only handle new_message notifications
    if (type != 'new_message') {
      print('[Push] Skipping: type is "$type" (not new_message)');
      return;
    }

    final conversationId = data['conversation_id'] as String?;
    // Use sender_name for the title (dynamic: store name for customer, customer name for seller)
    final senderName = data['sender_name'] as String? ?? data['store_name'] as String? ?? 'Store';
    final body = data['body'] as String? ?? 'New message';

    if (conversationId == null) {
      print('[Push] Skipping: conversation_id is null');
      return;
    }

    print('[Push] Showing foreground notification: title=$senderName, body=$body');
    // Show local notification banner
    _showForegroundNotification(
      title: senderName,
      body: body,
      data: data,
    );
  }

  /// Called when user taps a notification (backgrounded or cold start).
  void _handleNotificationTap(RemoteMessage message) {
    if (kDebugMode) {
      debugPrint('[Push] Notification tapped: ${message.messageId}');
    }

    final data = message.data;
    final conversationId = data['conversation_id'] as String?;
    final storeName = data['store_name'] as String? ?? 'Store';

    if (conversationId != null) {
      onNavigateToChat?.call(conversationId, storeName);
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
      // 1. Insert the fresh token first — this is the critical write.
      await Supabase.instance.client.from('device_tokens').insert(
        {
          'customer_id': userId,
          'fcm_token': token,
          'platform': platform,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );
      // 2. Best-effort cleanup: delete any OTHER stale tokens for this user.
      //    If this fails, we still have the fresh token stored.
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
