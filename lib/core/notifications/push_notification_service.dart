import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import 'push_notification_platform.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService(
    this._api, {
    this.canRegister,
    this.accountId,
    PushMessagingClient? messaging,
    PushNotificationDisplay? display,
    this.retryDelay = const Duration(seconds: 10),
  }) : _messaging = messaging ?? FirebasePushMessagingClient(),
       _display = display ?? NativePushNotificationDisplay();

  final ApiClient _api;
  final bool Function()? canRegister;
  final String? Function()? accountId;
  final PushMessagingClient _messaging;
  final PushNotificationDisplay _display;
  final Duration retryDelay;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  void Function(RemoteMessage)? _onTap, _onEvent;
  String? _currentToken, _registeredToken, _registeredAccount;
  Timer? _retry;
  Future<void>? _initializing, _registering;
  bool _initialized = false, _localReady = false, _disposed = false;
  bool _registerAgain = false;
  int _generation = 0, _failures = 0;

  bool get _eligible => !_disposed && canRegister?.call() != false;
  String? get _owner => accountId == null ? 'session' : accountId!();

  void _trace(String code) {
    // Never log tokens, notification bodies, or account details.
    debugPrint('AnonymoKe push: $code');
  }

  Future<void> initialize({
    required void Function(RemoteMessage) onTap,
    void Function(RemoteMessage)? onEvent,
  }) {
    _onTap = onTap;
    _onEvent = onEvent;
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  Future<void> _initialize() async {
    if (_disposed) return;
    if (!_localReady) {
      try {
        final initial = await _display.initialize(
          (data) => _onTap?.call(RemoteMessage(data: data)),
        );
        _localReady = true;
        if (initial != null) _onTap?.call(RemoteMessage(data: initial));
      } catch (_) {
        _trace('display_setup_unavailable');
      }
    }
    if (_disposed) return;
    if (!_initialized) {
      _subscriptions.add(
        _messaging.tokenRefreshes.listen((token) {
          _currentToken = token;
          _registeredToken = null;
          unawaited(registerCurrentToken());
        }, onError: (Object _) => _scheduleRetry()),
      );
      _subscriptions.add(
        _messaging.messages.listen((message) {
          if (!_eligible || _owner == null) return;
          _onEvent?.call(message);
          if (_localReady) {
            unawaited(
              _display.show(message).catchError((Object _) {
                _trace('foreground_display_unavailable');
              }),
            );
          }
        }),
      );
      _subscriptions.add(
        _messaging.openedMessages.listen((message) => _onTap?.call(message)),
      );
      _initialized = true;
      try {
        await _messaging.requestPermission();
      } catch (_) {
        _trace('permission_request_unavailable');
      }
      try {
        final initial = await _messaging.initialMessage();
        if (initial != null) _onTap?.call(initial);
      } catch (_) {
        _trace('initial_notification_unavailable');
      }
    }
    await registerCurrentToken();
  }

  Future<void> registerCurrentToken({bool refresh = false}) {
    if (!_eligible || _owner == null) return Future.value();
    if (refresh) {
      _currentToken = null;
      _registeredToken = null;
    }
    if (_registering != null) {
      _registerAgain = true;
      return _registering!;
    }
    _registering = _register().whenComplete(() {
      _registering = null;
      if (_registerAgain) {
        _registerAgain = false;
        unawaited(registerCurrentToken());
      }
    });
    return _registering!;
  }

  Future<void> _register() async {
    final generation = _generation;
    final owner = _owner;
    bool current() => _eligible && generation == _generation && owner == _owner;
    try {
      if (!await _messaging.permissionGranted()) {
        _retry?.cancel();
        return;
      }
      final token = _currentToken ?? await _messaging.registrationToken();
      if (!current()) return;
      if (token == null || token.isEmpty) {
        _scheduleRetry();
        return;
      }
      _currentToken = token;
      if (_registeredToken == token && _registeredAccount == owner) return;
      await _api.registerDeviceToken(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
      );
      if (!current()) return;
      _registeredToken = token;
      _registeredAccount = owner;
      _failures = 0;
      _retry?.cancel();
      _trace('device_registered');
    } catch (_) {
      if (current()) {
        _trace('registration_retry_scheduled');
        _scheduleRetry();
      }
    }
  }

  void _scheduleRetry() {
    if (!_eligible || _owner == null || (_retry?.isActive ?? false)) return;
    final multiplier = 1 << _failures.clamp(0, 5);
    _failures++;
    _retry = Timer(
      retryDelay * multiplier,
      () => unawaited(registerCurrentToken()),
    );
  }

  Future<void> unregisterCurrentToken() async {
    _generation++;
    _retry?.cancel();
    _registerAgain = false;
    final token = _currentToken;
    // A late registration must finish before the device is disabled on logout.
    await _registering;
    _currentToken = _registeredToken = _registeredAccount = null;
    try {
      if (token != null && token.isNotEmpty) {
        await _api.unregisterDeviceToken(token);
      }
    } catch (_) {
      _trace('device_cleanup_unavailable');
    }
    try {
      await _display.clear();
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    _onTap = _onEvent = null;
    _generation++;
    _retry?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }
}
