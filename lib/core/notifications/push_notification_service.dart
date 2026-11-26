import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../network/api_client.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService(this._api, {this.canRegister});

  static const _channel = AndroidNotificationChannel(
    'anonymoke_events',
    'AnonymoKE updates',
    description: 'Matches, messages, reveals, and safety updates.',
    importance: Importance.high,
  );

  final ApiClient _api;
  final bool Function()? canRegister;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  void Function(RemoteMessage message)? _onTap;
  String? _currentToken;
  bool _initialized = false;

  Future<void> initialize({
    required void Function(RemoteMessage) onTap,
    void Function(RemoteMessage)? onEvent,
  }) async {
    if (_initialized) return;
    _initialized = true;
    _onTap = onTap;

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        final raw = response.payload;
        if (raw == null || raw.isEmpty) return;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            _onTap?.call(
              RemoteMessage(
                data: decoded.map((key, value) => MapEntry(key, '$value')),
              ),
            );
          }
        } on FormatException {
          // Ignore malformed local-notification payloads.
        }
      },
    );

    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen((message) {
      onEvent?.call(message);
      _showForegroundNotification(message);
    });
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _onTap?.call(message),
    );

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) _onTap?.call(initialMessage);

    // onRegistered only fires for registrations that happen after this
    // listener is attached. FCM auto-init usually registers the device before
    // we get here, so the current token must also be fetched explicitly.
    _messaging.onRegistered.listen(_registerToken);
    _messaging.onTokenRefresh.listen(_registerToken);
    await registerCurrentToken();
  }

  Future<void> registerCurrentToken() async {
    if (canRegister?.call() == false) return;
    String? token = _currentToken;
    if (token == null || token.isEmpty) {
      try {
        token = await _messaging.getToken();
      } on FirebaseException {
        // No token yet (no Google services, or APNs not ready on iOS).
        // onRegistered / onTokenRefresh will deliver it later.
        return;
      }
    }
    if (token != null && token.isNotEmpty) await _registerToken(token);
  }

  Future<void> unregisterCurrentToken() async {
    final token = _currentToken;
    if (token == null || token.isEmpty) return;
    try {
      await _api.unregisterDeviceToken(token);
      _currentToken = null;
    } on ApiException {
      // Logout should not fail just because notification cleanup is unavailable.
    }
  }

  Future<void> _registerToken(String token) async {
    _currentToken = token;
    if (canRegister?.call() == false) return;
    try {
      await _api.registerDeviceToken(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
      );
    } on ApiException {
      // Registration is retried after auth and on the next token refresh.
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? _titleFor(message.data['type']);
    final body = notification?.body ?? 'You have a new AnonymoKE update.';
    await _local.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  String _titleFor(String? type) {
    return switch (type) {
      'like.received' => 'Someone likes you',
      'match.created' => 'New match',
      'chat.message' => 'New message',
      'reveal.requested' => 'Reveal request',
      'reveal.accepted' => 'Mutual reveal',
      'reveal.declined' => 'Reveal update',
      'safety.panic' => 'Safety alert',
      _ => 'AnonymoKE update',
    };
  }
}
