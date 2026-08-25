import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/foundation.dart';
import 'sound_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  // If message contains notification payload, Android OS automatically renders it in tray.
  // We ONLY show a local notification for data-only messages to prevent double notifications.
  if (message.notification == null && message.data.isNotEmpty) {
    try {
      const AndroidInitializationSettings initSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(const InitializationSettings(android: initSettings));

      final title = message.data['title'] ?? '🚨 New Order Alert';
      final body = message.data['body'] ?? 'You have a new order!';

      await plugin.show(
        (message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000),
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel',
            'High Importance Notifications',
            channelDescription: 'MeenMart order notifications',
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            enableVibration: true,
            fullScreenIntent: true,
            visibility: NotificationVisibility.public,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Background notification display error: $e');
    }
  }
  debugPrint('[BG] Handled background message: ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  bool _fcmConfigured = false;
  final SoundService _soundService = SoundService();
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _messageSub;

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('Firebase messaging init notice: $e');
    }

    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (e) {
      debugPrint('Timezone init notice: $e');
    }

    try {
      const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);

      await _flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (details) {
          debugPrint('Notification clicked: ${details.payload}');
        },
      );

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        description: 'This channel is used for important store order notifications.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      const AndroidNotificationChannel defaultChannel = AndroidNotificationChannel(
        'meenmart_orders_channel',
        'Store Order Notifications',
        description: 'Order alerts and status updates.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      // Create high importance notification channels on Android
      final androidPlugin = _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(channel);
        await androidPlugin.createNotificationChannel(defaultChannel);
        await androidPlugin.requestNotificationsPermission();
      }
    } catch (e) {
      debugPrint('Notification channel init notice: $e');
    }

    // Setup FCM Foreground & Token Sync
    await _setupFcm();

    // Schedule 7:00 AM daily shift notification
    _scheduleShiftReminderSafely();
    _isInitialized = true;
  }

  Future<void> _setupFcm() async {
    if (_fcmConfigured) return;

    try {
      final messaging = FirebaseMessaging.instance;

      // Request permissions
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: true,
        provisional: false,
        sound: true,
      );
      debugPrint('FCM Authorization status: ${settings.authorizationStatus}');

      // Sync Token
      final token = await messaging.getToken();
      if (token != null) {
        _syncTokenToSupabase(token);
      }

      // Cancel prior subscriptions if any
      await _tokenSub?.cancel();
      await _messageSub?.cancel();

      // Listen for token refreshes
      _tokenSub = messaging.onTokenRefresh.listen((newToken) {
        _syncTokenToSupabase(newToken);
      });

      // Subscribe to operational topics for broadcast alerts
      try {
        await messaging.subscribeToTopic('all_partners');
        await messaging.subscribeToTopic('store_orders');
      } catch (subErr) {
        debugPrint('FCM topic subscription notice: $subErr');
      }

      // Foreground message listener - Only alert on New Orders & Cancelled Orders
      _messageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got a message whilst in the foreground: ${message.data}');
        final data = message.data;
        final type = (data['type'] ?? data['event'] ?? '').toString().toLowerCase();
        final status = (data['status'] ?? '').toString().toLowerCase();

        final isNew = type.contains('new') || type.contains('order') || status == 'new_order' || status == 'placed';
        final isCancel = type.contains('cancel') || status == 'cancelled';

        final title = message.notification?.title ?? data['title'] ?? (isNew ? '🚨 New Order Alert' : 'MeenMart Alert');
        final body = message.notification?.body ?? data['body'] ?? 'Check live orders pipeline.';

        if (type.isEmpty || isNew || isCancel) {
          showNotification(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: title,
            body: body,
          );
          if (isCancel) {
            _soundService.playAlertChime();
          } else {
            _soundService.playNewOrderAlert();
          }
        }
      });
      _fcmConfigured = true;
    } catch (e) {
      debugPrint('FCM setup notice: $e');
    }
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    String? bigText,
    String? summaryText,
  }) async {
    if (!_isInitialized) await init();

    final StyleInformation? styleInformation = (bigText != null && bigText.isNotEmpty)
        ? BigTextStyleInformation(
            bigText,
            contentTitle: title,
            summaryText: summaryText ?? 'MeenMart Order Alert',
            htmlFormatBigText: false,
            htmlFormatContentTitle: false,
            htmlFormatSummaryText: false,
          )
        : null;

    final AndroidNotificationDetails androidNotificationDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      channelDescription: 'This channel is used for important store order notifications.',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      visibility: NotificationVisibility.public,
      ticker: 'MeenMart Order Alert',
      styleInformation: styleInformation,
    );
    final NotificationDetails notificationDetails = NotificationDetails(android: androidNotificationDetails);
    
    await _flutterLocalNotificationsPlugin.show(id, title, body, notificationDetails, payload: payload);
  }

  /// High-level rich notification for NEW ORDERS (Direct clean details, no verbose headings)
  Future<void> showNewOrderNotification({
    required dynamic orderId,
    required String orderRef,
    required double totalPrice,
    required String customerName,
    required String location,
    required String itemsSummary,
  }) async {
    final int notifId = (orderId.toString().hashCode.abs() % 100000);
    final title = '🚨 New Order $orderRef • ₹${totalPrice.toStringAsFixed(0)}';
    final shortBody = '$customerName • $location • $itemsSummary';
    final bigText = '$customerName (₹${totalPrice.toStringAsFixed(0)})\n$location\n$itemsSummary';

    await showNotification(
      id: notifId,
      title: title,
      body: shortBody,
      bigText: bigText,
      summaryText: 'New Order Alert',
      payload: orderId.toString(),
    );
    _soundService.playNewOrderAlert();
  }

  /// High-level rich notification for CANCELLED ORDERS (Direct clean details, no verbose headings)
  Future<void> showCancelledOrderNotification({
    required dynamic orderId,
    required String orderRef,
    required double totalPrice,
    required String customerName,
    required String location,
    required String reason,
  }) async {
    final int notifId = ((orderId.toString().hashCode.abs() + 1) % 100000);
    final title = '❌ Order Cancelled: $orderRef';
    final shortBody = '$customerName • $reason • ₹${totalPrice.toStringAsFixed(0)}';
    final bigText = '$customerName (₹${totalPrice.toStringAsFixed(0)})\n$location\n$reason';

    await showNotification(
      id: notifId,
      title: title,
      body: shortBody,
      bigText: bigText,
      summaryText: 'Order Cancellation Alert',
      payload: orderId.toString(),
    );
    _soundService.playAlertChime();
  }

  Future<void> sendTestNotification() async {
    if (!_isInitialized) await init();
    await showNewOrderNotification(
      orderId: 999,
      orderRef: 'MM-01',
      totalPrice: 650,
      customerName: 'Balaji R',
      location: 'Lighthouse Kuppam, Pazhaverkadu',
      itemsSummary: 'Vanjaram 1 kg (Curry Cut), Prawns 500g',
    );
  }

  /// Force refresh and sync FCM token to Supabase for the current logged in user
  Future<void> syncCurrentToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token != null) {
        await _syncTokenToSupabase(token);
      }
    } catch (e) {
      debugPrint('Error syncing current FCM token: $e');
    }
  }

  Future<void> _syncTokenToSupabase(String token) async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user != null) {
        await client.from('store_staff').update({'fcm_token': token}).eq('auth_id', user.id);
      }
    } catch (e) {
      debugPrint('Sync FCM token to Supabase notice: $e');
    }
  }

  /// Daily 7:00 AM Morning Shift Notification
  Future<void> showShiftStartNotification() async {
    await showNotification(
      id: 700,
      title: '🌅 Morning Shift Started • 07:00 AM',
      body: 'Time to clock in and start today\'s fish market operations!',
      bigText: '🌅 Morning Shift Started • 07:00 AM\nWelcome Store Partner! Please clock in to start store operations and live market supply.',
      summaryText: 'Morning Shift Alert',
      payload: 'shift_start',
    );
    _soundService.playAlertChime();
  }

  void _scheduleShiftReminderSafely() {
    scheduleDailyCheckInReminder().catchError((e) {
      debugPrint('Schedule shift reminder notice: $e');
    });
  }

  Future<void> scheduleDailyCheckInReminder() async {
    try {
      final now = tz.TZDateTime.now(tz.local);
      var scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, 7, 0);
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      const AndroidNotificationDetails androidNotificationDetails = AndroidNotificationDetails(
        'meenmart_shift_reminder_channel',
        'Morning Shift Reminders',
        channelDescription: 'Daily 7:00 AM morning shift start reminders for store staff',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      );
      
      const NotificationDetails notificationDetails = NotificationDetails(android: androidNotificationDetails);

      await _flutterLocalNotificationsPlugin.zonedSchedule(
        700, // ID for 7:00 AM shift reminder
        '🌅 Morning Shift Started • 07:00 AM',
        'Time to clock in and start today\'s fish market operations!',
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );

      // Schedule 5:00 PM shift end reminder
      var endScheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, 17, 0);
      if (endScheduledDate.isBefore(now)) {
        endScheduledDate = endScheduledDate.add(const Duration(days: 1));
      }

      await _flutterLocalNotificationsPlugin.zonedSchedule(
        701, // ID for 5:00 PM shift end reminder
        '🌆 Shift Completed • 05:00 PM',
        'Store operations shift completed. Please clock out and review today\'s summary!',
        endScheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );

      debugPrint('Daily 7:00 AM & 5:00 PM Shift Notifications scheduled successfully');
    } catch (e) {
      debugPrint('Error scheduling shift notifications: $e');
    }
  }
}
