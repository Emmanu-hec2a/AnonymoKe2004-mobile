import 'dart:async';

import 'package:anonymoke/core/network/api_client.dart';
import 'package:anonymoke/core/notifications/push_notification_service.dart';
import 'package:anonymoke/core/notifications/push_notification_platform.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'discover_live_test.dart' show MemoryStore;

class PushApi extends ApiClient {
  PushApi() : super(store: MemoryStore(), baseUrl: 'https://api.test/api/v1');
  final registered = <String>[], removed = <String>[];
  bool fail = false;
  Completer<void>? waiting;
  @override
  Future<void> registerDeviceToken({
    required String token,
    required String platform,
    String? appVersion,
  }) async {
    registered.add(token);
    await waiting?.future;
    if (fail) throw const ApiException('network_error');
  }

  @override
  Future<void> unregisterDeviceToken(String token) async {
    removed.add(token);
  }
}

class PushClient extends PushMessagingClient {
  final tokens = StreamController<String>.broadcast();
  final foreground = StreamController<RemoteMessage>.broadcast();
  final opened = StreamController<RemoteMessage>.broadcast();
  bool allowed = true, failToken = false;
  int reads = 0;
  String? token = 'real-fcm-registration-token';
  RemoteMessage? initial;
  @override
  Future<bool> requestPermission() async => allowed;
  @override
  Future<bool> permissionGranted() async => allowed;
  @override
  Future<String?> registrationToken() async {
    reads++;
    if (failToken) throw StateError('APNs not ready yet');
    return token;
  }

  @override
  Stream<String> get tokenRefreshes => tokens.stream;
  @override
  Stream<RemoteMessage> get messages => foreground.stream;
  @override
  Stream<RemoteMessage> get openedMessages => opened.stream;
  @override
  Future<RemoteMessage?> initialMessage() async => initial;
  void close() {
    tokens.close();
    foreground.close();
    opened.close();
  }
}

class Display extends PushNotificationDisplay {
  Map<String, dynamic>? initial;
  bool fail = false;
  int shown = 0, clears = 0;
  @override
  Future<Map<String, dynamic>?> initialize(
    void Function(Map<String, dynamic>) onTap,
  ) async {
    if (fail) throw StateError('display unavailable');
    return initial;
  }

  @override
  Future<void> show(RemoteMessage message) async {
    shown++;
  }

  @override
  Future<void> clear() async {
    clears++;
  }
}

void main() {
  late PushApi api;
  late PushClient client;
  late Display display;
  late PushNotificationService service;
  String? owner;
  final taps = <RemoteMessage>[];
  setUp(() {
    api = PushApi();
    client = PushClient();
    display = Display();
    owner = 'first';
    taps.clear();
    service = PushNotificationService(
      api,
      messaging: client,
      display: display,
      canRegister: () => owner != null,
      accountId: () => owner,
      retryDelay: const Duration(seconds: 1),
    );
  });
  tearDown(() {
    service.dispose();
    client.close();
  });

  testWidgets('existing token registers without waiting for a refresh event', (
    tester,
  ) async {
    await service.initialize(onTap: taps.add);
    expect(api.registered, [client.token]);
    await service.initialize(onTap: taps.add);
    expect(api.registered, hasLength(1));
  });
  testWidgets('temporary API failure retries without reopening the app', (
    tester,
  ) async {
    api.fail = true;
    await service.initialize(onTap: taps.add);
    api.fail = false;
    await tester.pump(const Duration(seconds: 1));
    expect(api.registered, [client.token, client.token]);
    await tester.pump(const Duration(seconds: 10));
    expect(api.registered, hasLength(2));
  });
  testWidgets('APNs or token not ready retries instead of silently giving up', (
    tester,
  ) async {
    client.failToken = true;
    await service.initialize(onTap: taps.add);
    client.failToken = false;
    await tester.pump(const Duration(seconds: 1));
    expect(api.registered, [client.token]);
  });
  testWidgets(
    'startup before auth registers after sign-in and token rotation',
    (tester) async {
      owner = null;
      await service.initialize(onTap: taps.add);
      expect(api.registered, isEmpty);
      owner = 'first';
      await service.registerCurrentToken();
      client.tokens.add('rotated-fcm-token');
      await tester.pump();
      expect(api.registered, [client.token, 'rotated-fcm-token']);
    },
  );
  testWidgets('denied permissions recover when allowed from system settings', (
    tester,
  ) async {
    client.allowed = false;
    await service.initialize(onTap: taps.add);
    expect(api.registered, isEmpty);
    client.allowed = true;
    await service.registerCurrentToken(refresh: true);
    expect(api.registered, [client.token]);
  });
  testWidgets('local display setup failure cannot block registration', (
    tester,
  ) async {
    display.fail = true;
    await service.initialize(onTap: taps.add);
    expect(api.registered, [client.token]);
    display.fail = false;
    await service.initialize(onTap: taps.add);
  });
  testWidgets(
    'foreground event and banner run exactly once after repeated init',
    (tester) async {
      var events = 0;
      for (var i = 0; i < 3; i++) {
        await service.initialize(onTap: taps.add, onEvent: (_) => events++);
      }
      client.foreground.add(
        const RemoteMessage(data: {'type': 'chat.message'}),
      );
      await tester.pump();
      expect(events, 1);
      expect(display.shown, 1);
      owner = null;
      client.foreground.add(
        const RemoteMessage(data: {'type': 'chat.message'}),
      );
      await tester.pump();
      expect(display.shown, 1);
    },
  );
  testWidgets(
    'terminated local-notification launch opens its destination once',
    (tester) async {
      display.initial = {'type': 'safety.panic'};
      await service.initialize(onTap: taps.add);
      await service.initialize(onTap: taps.add);
      expect(taps.map((m) => m.data['type']), ['safety.panic']);
    },
  );
  testWidgets('FCM terminated and background taps are handled', (tester) async {
    client.initial = const RemoteMessage(data: {'type': 'match.created'});
    await service.initialize(onTap: taps.add);
    client.opened.add(const RemoteMessage(data: {'type': 'safety.safe'}));
    await tester.pump();
    expect(taps.map((m) => m.data['type']), ['match.created', 'safety.safe']);
  });
  testWidgets('logout cancels retries and clears device notifications', (
    tester,
  ) async {
    api.fail = true;
    await service.initialize(onTap: taps.add);
    owner = null;
    await service.unregisterCurrentToken();
    await tester.pump(const Duration(seconds: 60));
    expect(api.registered, hasLength(1));
    expect(api.removed, [client.token]);
    expect(display.clears, 1);
  });
  testWidgets('late registration finishes before logout disables the device', (
    tester,
  ) async {
    api.waiting = Completer<void>();
    final init = service.initialize(onTap: taps.add);
    await tester.pump();
    owner = null;
    final logout = service.unregisterCurrentToken();
    expect(api.removed, isEmpty);
    api.waiting!.complete();
    await init;
    await logout;
    expect(api.removed, [client.token]);
  });
  testWidgets('same device is registered for a new account', (tester) async {
    await service.initialize(onTap: taps.add);
    owner = 'second';
    await service.registerCurrentToken();
    expect(api.registered, [client.token, client.token]);
  });
}
