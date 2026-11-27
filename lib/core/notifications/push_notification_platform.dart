import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

abstract class PushMessagingClient {
  Future<bool> requestPermission();
  Future<bool> permissionGranted();
  Future<String?> registrationToken();
  Stream<String> get tokenRefreshes;
  Stream<RemoteMessage> get messages;
  Stream<RemoteMessage> get openedMessages;
  Future<RemoteMessage?> initialMessage();
}

class FirebasePushMessagingClient implements PushMessagingClient {
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  bool _allowed(NotificationSettings settings) =>
      settings.authorizationStatus == AuthorizationStatus.authorized ||
      settings.authorizationStatus == AuthorizationStatus.provisional;
  @override
  Future<bool> requestPermission() async => _allowed(
    await _messaging.requestPermission(alert: true, badge: true, sound: true),
  );
  @override
  Future<bool> permissionGranted() async =>
      _allowed(await _messaging.getNotificationSettings());

  // Admin SDK 6.x sends registration tokens. FlutterFire 17's onRegistered
  // emits installation IDs, which must not be stored as registration tokens.
  @override
  Future<String?> registrationToken() =>
      // ignore: deprecated_member_use
      _messaging.getToken();
  @override
  // ignore: deprecated_member_use
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;
  @override
  Stream<RemoteMessage> get messages => FirebaseMessaging.onMessage;
  @override
  Stream<RemoteMessage> get openedMessages =>
      FirebaseMessaging.onMessageOpenedApp;
  @override
  Future<RemoteMessage?> initialMessage() => _messaging.getInitialMessage();
}

abstract class PushNotificationDisplay {
  Future<Map<String, dynamic>?> initialize(
    void Function(Map<String, dynamic>) onTap,
  );
  Future<void> show(RemoteMessage message);
  Future<void> clear();
}

class NativePushNotificationDisplay implements PushNotificationDisplay {
  static const channel = AndroidNotificationChannel(
    'anonymoke_events',
    'AnonymoKe updates',
    description: 'Matches, messages, reveals, and safety updates.',
    importance: Importance.high,
  );
  final _local = FlutterLocalNotificationsPlugin();

  Map<String, dynamic>? _decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final value = jsonDecode(payload);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> initialize(
    void Function(Map<String, dynamic>) onTap,
  ) async {
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_anonymoke'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final data = _decode(response.payload);
        if (data != null) onTap(data);
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: false,
          badge: false,
          sound: false,
        );
    final launch = await _local.getNotificationAppLaunchDetails();
    return launch?.didNotificationLaunchApp == true
        ? _decode(launch?.notificationResponse?.payload)
        : null;
  }

  @override
  Future<void> show(RemoteMessage message) async {
    await _local.show(
      (message.messageId ?? jsonEncode(message.data)).hashCode & 0x7fffffff,
      message.notification?.title ?? 'AnonymoKe update',
      message.notification?.body ?? 'Open AnonymoKe to see your update.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_anonymoke',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  @override
  Future<void> clear() => _local.cancelAll();
}
