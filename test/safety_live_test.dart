import 'package:anonymoke/core/auth/auth_controller.dart';
import 'package:anonymoke/core/network/api_client.dart';
import 'package:anonymoke/core/theme/app_theme.dart';
import 'package:anonymoke/features/home/presentation/safety_controller.dart';
import 'package:anonymoke/features/home/presentation/safety_management_screen.dart';
import 'package:anonymoke/features/home/presentation/safety_screen.dart';
import 'package:anonymoke/features/home/presentation/widgets/safety_hold_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'discover_live_test.dart' show MemoryStore, Adapter, jsonResponse;

const contact = TrustedContact(
  name: 'Trusted friend',
  phoneMasked: '',
  isVerified: false,
  isLinked: true,
  linkedAlias: 'Quiet Comet',
);
DateSafetySession plan({String status = 'active', String? venue}) =>
    DateSafetySession(
      id: 'plan-1',
      status: status,
      startsAt: DateTime.utc(2030, 1, 2, 17),
      venueLabel: venue ?? 'Public cafe',
      checkInDueAt: DateTime.utc(2030, 1, 2, 20),
      shareApproximateLocation: false,
      trustedContactName: 'Trusted friend',
    );
IncomingSafetyAlert incoming(String id, {String status = 'unread'}) =>
    IncomingSafetyAlert(
      id: id,
      status: status,
      ownerAlias: 'Friend $id',
      venueLabel: 'Cafe $id',
      startsAt: DateTime.utc(2030),
      checkInDueAt: DateTime.utc(2030, 1, 1, 2),
      shareApproximateLocation: false,
    );

class SafetyApi extends ApiClient {
  SafetyApi() : super(store: MemoryStore(), baseUrl: 'https://api.test/api/v1');
  SafetyOverview overview = SafetyOverview(
    contact: contact,
    activeDate: plan(),
  );
  Map<String, dynamic> verification = {
    'available': false,
    'verification_level': 'none',
    'attempts': [],
  };
  int reads = 0, starts = 0, safeWrites = 0, retries = 0;
  bool failAlert = false, failReads = false;
  final keys = <String>[];
  final acknowledgements = <String>[];
  final pages = <String?>[];
  @override
  Future<SafetyOverview> safetyOverview() async {
    reads++;
    if (failReads) throw const ApiException('network_error');
    return overview;
  }

  @override
  Future<Map<String, dynamic>> verificationStatus() async => verification;
  @override
  Future<PanicAlert> triggerPanicAlert(String idempotencyKey) async {
    keys.add(idempotencyKey);
    if (failAlert) throw const ApiException('network_error');
    const alert = PanicAlert(
      id: 'alert-1',
      status: 'stored',
      dateSessionId: 'plan-1',
      pushStatus: 'queued',
    );
    overview = SafetyOverview(
      contact: contact,
      activeDate: plan(status: 'panic'),
      recentAlerts: [alert],
    );
    return alert;
  }

  @override
  Future<DateSafetySession> markDateSafe(String id) async {
    safeWrites++;
    overview = const SafetyOverview(contact: contact);
    return plan(status: 'safe');
  }

  @override
  Future<void> acknowledgeSafetyAlert(String id) async {
    acknowledgements.add(id);
    overview = SafetyOverview(
      incomingAlerts: overview.incomingAlerts
          .map(
            (a) =>
                incoming(a.id, status: a.id == id ? 'acknowledged' : a.status),
          )
          .toList(),
    );
  }

  @override
  Future<void> retrySafetyPush(String id) async {
    retries++;
  }

  @override
  Future<Map<String, dynamic>> startIdentityVerification() async {
    starts++;
    return {'launch_url': 'https://links.usesmileid.com/session'};
  }

  @override
  Future<RecordPage<IncomingSafetyAlert>> incomingSafetyAlerts({
    String? cursor,
    bool activeOnly = false,
  }) async {
    pages.add(cursor);
    return RecordPage(
      items: [incoming(cursor == null ? 'first' : 'older')],
      nextCursor: cursor == null ? 'signed-next' : null,
      totalCount: 101,
    );
  }

  @override
  Future<RecordPage<BlockedProfile>> blockedPage({String? cursor}) async {
    pages.add(cursor);
    return RecordPage(
      items: [
        BlockedProfile(
          blockId: cursor ?? 'first',
          profileId: 'other',
          alias: cursor == null ? 'Blocked first' : 'Blocked older',
          createdAt: DateTime.utc(2030),
        ),
      ],
      nextCursor: cursor == null ? 'signed-next' : null,
      totalCount: 101,
    );
  }

  @override
  Future<RecordPage<SafetyReport>> reportsPage({String? cursor}) async =>
      const RecordPage(totalCount: 0);
}

Future<void> open(
  WidgetTester tester,
  SafetyApi api, {
  Widget screen = const BackendSafetyScreen(),
  Size size = const Size(390, 844),
  Future<bool> Function(Uri)? launcher,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        if (launcher != null)
          verificationLauncherProvider.overrideWithValue(launcher),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

Future<void> hold(WidgetTester tester) async {
  final button = find.byType(SafetyHoldButton);
  await tester.ensureVisible(button);
  final gesture = await tester.startGesture(tester.getCenter(button));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 2100));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('short hold, drag and backgrounding cannot send a panic', (
    tester,
  ) async {
    int sends = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafetyHoldButton(
            enabled: true,
            busy: false,
            onSend: () => sends++,
          ),
        ),
      ),
    );
    final button = find.byType(SafetyHoldButton);
    var gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pump(const Duration(seconds: 3));
    expect(sends, 0);
    gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump();
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump(const Duration(seconds: 3));
    await gesture.up();
    expect(sends, 0);
    gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 3));
    await gesture.up();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(sends, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('complete hold sends once and panic can still be marked safe', (
    tester,
  ) async {
    final api = SafetyApi();
    await open(tester, api);
    await hold(tester);
    expect(api.keys, hasLength(1));
    expect(find.text('Alert active'), findsOneWidget);
    await tester.ensureVisible(find.text('I am safe'));
    await tester.tap(find.text('I am safe'));
    await tester.pumpAndSettle();
    expect(api.safeWrites, 1);
    expect(find.text('Alert active'), findsNothing);
  });

  testWidgets('ambiguous failure retries with the same panic key', (
    tester,
  ) async {
    final api = SafetyApi()..failAlert = true;
    await open(tester, api);
    await hold(tester);
    api.failAlert = false;
    await hold(tester);
    expect(api.keys, hasLength(2));
    expect(api.keys[0], api.keys[1]);
  });

  testWidgets('unlinked contact cannot send an alert', (tester) async {
    final api = SafetyApi()..overview = const SafetyOverview();
    await open(tester, api);
    final button = tester.widget<SafetyHoldButton>(
      find.byType(SafetyHoldButton),
    );
    expect(button.enabled, false);
    expect(
      find.text('Link an AnonymoKE trusted contact first.'),
      findsOneWidget,
    );
  });

  testWidgets('every incoming alert has its own acknowledgement action', (
    tester,
  ) async {
    final api = SafetyApi()
      ..overview = SafetyOverview(
        incomingAlerts: [incoming('1'), incoming('2')],
        incomingAlertCount: 2,
      );
    await open(tester, api, size: const Size(390, 1400));
    expect(find.text('Friend 1 needs a check-in'), findsOneWidget);
    expect(find.text('Friend 2 needs a check-in'), findsOneWidget);
    await tester.tap(find.text('I can help').at(1));
    await tester.pumpAndSettle();
    expect(api.acknowledgements, ['2']);
    expect(find.text('I can help'), findsOneWidget);
  });

  testWidgets('push acceptance is described as waiting, not delivery', (
    tester,
  ) async {
    final api = SafetyApi()
      ..overview = SafetyOverview(
        contact: contact,
        activeDate: plan(status: 'panic'),
        recentAlerts: const [
          PanicAlert(
            id: 'a',
            status: 'push_accepted',
            dateSessionId: 'plan-1',
            pushStatus: 'push_accepted',
          ),
        ],
      );
    await open(tester, api, size: const Size(390, 1800));
    expect(
      find.text('Push accepted. Waiting for your contact to acknowledge.'),
      findsOneWidget,
    );
    expect(find.textContaining('delivered'), findsNothing);
  });

  testWidgets('failed push can retry without creating a new panic', (
    tester,
  ) async {
    final api = SafetyApi()
      ..overview = SafetyOverview(
        contact: contact,
        activeDate: plan(status: 'panic'),
        recentAlerts: const [
          PanicAlert(
            id: 'a',
            status: 'stored',
            dateSessionId: 'plan-1',
            pushStatus: 'failed',
          ),
        ],
      );
    await open(tester, api, size: const Size(390, 1800));
    await tester.tap(find.text('Retry push notification'));
    await tester.pumpAndSettle();
    expect(api.retries, 1);
    expect(api.keys, isEmpty);
  });

  testWidgets(
    'polling, foreground event and resume refresh live safety state',
    (tester) async {
      final api = SafetyApi();
      await open(tester, api);
      final initial = api.reads;
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(api.reads, greaterThan(initial));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final paused = api.reads;
      await tester.pump(const Duration(seconds: 21));
      expect(api.reads, paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(api.reads, greaterThan(paused));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(BackendSafetyScreen)),
      );
      final resumed = api.reads;
      container.read(safetyRefreshSignal.notifier).notify();
      await tester.pumpAndSettle();
      expect(api.reads, greaterThan(resumed));
    },
  );

  testWidgets(
    'network failure preserves the last known plan and offers retry',
    (tester) async {
      final api = SafetyApi();
      await open(tester, api);
      api.failReads = true;
      await tester.tap(find.byTooltip('Refresh safety'));
      await tester.pumpAndSettle();
      expect(find.text('Public cafe'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    },
  );

  testWidgets(
    'unconfigured verification cannot grant a badge or start a fake flow',
    (tester) async {
      final api = SafetyApi();
      await open(tester, api, size: const Size(390, 1400));
      expect(
        find.text('Verification is currently unavailable.'),
        findsOneWidget,
      );
      expect(find.text('Start'), findsNothing);
      expect(api.starts, 0);
    },
  );

  testWidgets('Smile ID requires consent and opens the real hosted session', (
    tester,
  ) async {
    final api = SafetyApi()
      ..verification = {
        'available': true,
        'verification_level': 'none',
        'privacy_url': 'https://anonymoke.test/verification-privacy',
        'attempts': [],
      };
    final opened = <Uri>[];
    await open(
      tester,
      api,
      size: const Size(390, 1400),
      launcher: (uri) async {
        opened.add(uri);
        return true;
      },
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(api.starts, 0);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read verification privacy notice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agree and continue'));
    await tester.pumpAndSettle();
    expect(api.starts, 1);
    expect(opened.first.host, 'anonymoke.test');
    expect(opened.last.host, 'links.usesmileid.com');
    expect(find.text('Verified'), findsNothing);
    api.verification = {
      'available': true,
      'verification_level': 'verified',
      'attempts': [],
    };
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('Verified'), findsOneWidget);
  });

  testWidgets('history loads older alerts using the signed cursor', (
    tester,
  ) async {
    final api = SafetyApi();
    await open(tester, api, screen: const SafetyHistorySheet(plans: false));
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(api.pages, [null, 'signed-next']);
    expect(find.text('Friend older needs a check-in'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('Friend older needs a check-in'), findsOneWidget);
    expect(api.pages, [null, 'signed-next']);
  });

  testWidgets('long live plan text remains readable on narrow devices', (
    tester,
  ) async {
    final api = SafetyApi()
      ..overview = SafetyOverview(
        contact: contact,
        activeDate: plan(
          venue:
              'A very long public venue name with directions and a table by the entrance',
        ),
      );
    await open(tester, api, size: const Size(320, 780));
    await tester.scrollUntilVisible(find.text('Get verified'), 180);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text('Get verified')).width, greaterThan(90));
  });

  testWidgets('blocked management loads beyond the first page', (tester) async {
    final api = SafetyApi();
    await open(
      tester,
      api,
      screen: const SafetyManagementScreen(),
      size: const Size(390, 1200),
    );
    final more = find.textContaining('Load more');
    expect(more, findsOneWidget);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(api.pages, [null, 'signed-next']);
    expect(find.text('Blocked older'), findsOneWidget);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.text('Blocked older'), findsOneWidget);
  });

  test(
    'safety API preserves idempotency, explicit consent and pagination',
    () async {
      final api = ApiClient(
        store: MemoryStore(),
        baseUrl: 'https://api.test/api/v1',
      );
      final requests = <Map<String, dynamic>>[];
      api.dio.httpClientAdapter = Adapter((o) {
        requests.add({
          'path': o.path,
          'headers': o.headers,
          'data': o.data,
          'query': o.queryParameters,
        });
        if (o.path.endsWith('/panic/')) {
          return jsonResponse({
            'id': 'a',
            'date_session': 's',
            'status': 'stored',
          });
        }
        if (o.path.endsWith('/start/')) {
          return jsonResponse({'status': 'pending'});
        }
        return jsonResponse({
          'items': [],
          'next_cursor': null,
          'total_count': 101,
        });
      });
      await api.triggerPanicAlert('stable-key');
      await api.startIdentityVerification();
      await api.incomingSafetyAlerts(cursor: 'signed');
      expect((requests[0]['headers'] as Map)['Idempotency-Key'], 'stable-key');
      expect((requests[1]['data'] as Map)['consent'], true);
      expect((requests[2]['query'] as Map)['cursor'], 'signed');
      expect((requests[2]['query'] as Map)['paged'], '1');
    },
  );
}
