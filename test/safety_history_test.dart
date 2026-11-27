import 'dart:async';
import 'package:anonymoke/core/auth/auth_controller.dart';
import 'package:anonymoke/core/auth/session.dart';
import 'package:anonymoke/core/network/api_client.dart';
import 'package:anonymoke/core/theme/app_theme.dart';
import 'package:anonymoke/features/home/presentation/safety_history_screen.dart';
import 'package:anonymoke/features/home/presentation/safety_screen.dart';
import 'package:anonymoke/features/home/presentation/widgets/safety_completion_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'discover_live_test.dart' show MemoryStore, Adapter, jsonResponse;
import 'safety_live_test.dart' show SafetyApi, contact, plan, open;

DateSafetySession completed(
  String id, {
  String role = 'owner',
  String status = 'safe',
  String alias = 'Velvet Echo',
  String venue = 'Public cafe',
}) => DateSafetySession(
  id: id,
  status: status,
  startsAt: DateTime.utc(2030, 1, 1, 17),
  checkInDueAt: DateTime.utc(2030, 1, 1, 20),
  safeAt: status == 'safe' ? DateTime.utc(2030, 1, 1, 19) : null,
  updatedAt: DateTime.utc(2030, 1, 1, 19),
  venueLabel: venue,
  shareApproximateLocation: false,
  trustedContactName: 'Trusted friend',
  ownerAlias: alias,
  viewerRole: role,
);

class HistoryApi extends SafetyApi {
  final historyReads = <String?>[];
  bool failHistory = false;
  Completer<RecordPage<DateSafetySession>>? waiting;
  List<DateSafetySession>? custom;
  @override
  Future<RecordPage<DateSafetySession>> safetyHistory({String? cursor}) async {
    historyReads.add(cursor);
    if (waiting != null) return waiting!.future;
    if (failHistory) throw const ApiException('network_error');
    if (custom != null) {
      return RecordPage(items: custom!, totalCount: custom!.length);
    }
    return RecordPage(
      items: [
        completed(
          cursor == null ? 'first' : 'older',
          role: cursor == null ? 'owner' : 'trusted_contact',
        ),
      ],
      nextCursor: cursor == null ? 'next-completed' : null,
      totalCount: 2,
    );
  }
}

class HistoryAuth extends AuthController {
  Session session(String user) => Session(
    userId: user,
    accessToken: 'test',
    refreshToken: 'refresh',
    accessExpiresAt: DateTime.utc(2035),
    refreshExpiresAt: DateTime.utc(2035),
    isOnboarded: true,
  );
  @override
  AuthState build() => AuthState(session: session('one'));
  void change() => state = AuthState(session: session('two'));
}

void main() {
  testWidgets(
    'a trusted contact sees an active shared plan before setup tools',
    (tester) async {
      final api = HistoryApi()
        ..overview = SafetyOverview(
          contact: contact,
          sharedPlans: [plan()],
          sharedPlanCount: 1,
        );
      await open(tester, api, size: const Size(390, 1000));
      final shared = tester.getTopLeft(find.byType(SharedPlanCard)).dy;
      final panic = tester.getTopLeft(find.text('Panic button')).dy;
      expect(shared, lessThan(panic));
      expect(find.text('Plans shared with you'), findsOneWidget);
    },
  );

  test('the mobile client explicitly requests the focused overview', () async {
    final api = ApiClient(
      store: MemoryStore(),
      baseUrl: 'https://api.test/api/v1',
    );
    api.dio.httpClientAdapter = Adapter((options) {
      expect(options.path, '/me/safety/');
      expect(options.queryParameters['view'], 'active');
      return jsonResponse({'history_count': 20});
    });
    expect((await api.safetyOverview()).historyCount, 20);
  });

  testWidgets('twenty completed records do not crowd the main Safety tab', (
    tester,
  ) async {
    final api = HistoryApi()
      ..overview = SafetyOverview(
        contact: contact,
        historyCount: 20,
        sharedPlans: List.generate(
          20,
          (i) => completed('plan-$i', role: 'trusted_contact'),
        ),
        recentAlerts: List.generate(
          20,
          (i) => PanicAlert(
            id: 'a-$i',
            status: 'stored',
            dateSessionId: 'plan-$i',
            sessionStatus: 'safe',
          ),
        ),
        incomingAlerts: List.generate(
          20,
          (i) => IncomingSafetyAlert(
            id: 'r-$i',
            dateSessionId: 'plan-$i',
            status: 'unread',
            sessionStatus: 'safe',
            ownerAlias: 'Old friend $i',
            venueLabel: 'Old cafe',
            startsAt: DateTime.utc(2030),
            checkInDueAt: DateTime.utc(2030),
            shareApproximateLocation: false,
          ),
        ),
      );
    await open(tester, api, size: const Size(390, 1400));
    expect(find.byType(IncomingAlertCard), findsNothing);
    expect(find.byType(SharedPlanCard), findsNothing);
    expect(
      find.text('Safe check-in shared with your trusted contact.'),
      findsNothing,
    );
    await tester.scrollUntilVisible(find.text('Safety history'), 250);
    expect(find.text('20 completed plans'), findsOneWidget);
  });
  testWidgets(
    'one safe confirmation can be dismissed without deleting history',
    (tester) async {
      final api = HistoryApi()
        ..overview = SafetyOverview(
          contact: contact,
          historyCount: 20,
          recentCompletion: SafetyCompletion(
            session: completed('latest'),
            expiresInSeconds: 300,
          ),
        );
      await open(tester, api, size: const Size(390, 1400));
      expect(find.byType(SafetyCompletionNotice), findsOneWidget);
      expect(find.text('You checked in safe'), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss safe check-in'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(find.byType(SafetyCompletionNotice), findsNothing);
      expect(api.overview.historyCount, 20);
      expect(api.safeWrites, 0);
    },
  );
  testWidgets(
    'a safe confirmation expires even if polling returns the same record',
    (tester) async {
      final api = HistoryApi()
        ..overview = SafetyOverview(
          contact: contact,
          recentCompletion: SafetyCompletion(
            session: completed('latest'),
            expiresInSeconds: 5,
          ),
        );
      await open(tester, api, size: const Size(390, 1400));
      expect(find.byType(SafetyCompletionNotice), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(find.byType(SafetyCompletionNotice), findsNothing);
    },
  );
  testWidgets(
    'an acknowledged unresolved alert remains visible without a duplicate plan',
    (tester) async {
      final api = HistoryApi()
        ..overview = SafetyOverview(
          contact: contact,
          incomingAlerts: [
            IncomingSafetyAlert(
              id: 'recipient',
              dateSessionId: 'plan-1',
              status: 'acknowledged',
              ownerAlias: 'Friend',
              venueLabel: 'Cafe',
              startsAt: DateTime.utc(2030),
              checkInDueAt: DateTime.utc(2030),
              shareApproximateLocation: false,
            ),
          ],
          sharedPlans: [plan(status: 'panic')],
        );
      await open(tester, api, size: const Size(390, 1400));
      expect(find.text('Friend needs a check-in'), findsOneWidget);
      expect(find.text('You acknowledged this alert.'), findsOneWidget);
      expect(find.byType(SharedPlanCard), findsNothing);
    },
  );
  testWidgets(
    'history has one entry per plan and loads older plans without resetting',
    (tester) async {
      final api = HistoryApi();
      await open(tester, api, screen: const SafetyHistoryScreen());
      expect(find.byType(SafetyHistoryCard), findsOneWidget);
      await tester.tap(find.text('Load older plans'));
      await tester.pumpAndSettle();
      expect(api.historyReads, [null, 'next-completed']);
      expect(find.byType(SafetyHistoryCard), findsNWidgets(2));
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(api.historyReads, [null, 'next-completed']);
      await tester.tap(find.text('Your date plan'));
      await tester.pumpAndSettle();
      expect(find.text('Safe check-in'), findsOneWidget);
      expect(find.text('Shared with'), findsOneWidget);
    },
  );
  testWidgets('history failure has a working retry and empty state', (
    tester,
  ) async {
    final api = HistoryApi()..failHistory = true;
    await open(tester, api, screen: const SafetyHistoryScreen());
    expect(find.text('Try again'), findsOneWidget);
    api.failHistory = false;
    api.custom = [];
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No completed plans yet'), findsOneWidget);
  });
  testWidgets(
    'expired plans are not labelled safe and long details fit a small screen',
    (tester) async {
      final api = HistoryApi()
        ..custom = [
          completed(
            'expired',
            status: 'expired',
            role: 'trusted_contact',
            alias: List.filled(8, 'Long alias').join(' '),
            venue: List.filled(12, 'Public cafe').join(' '),
          ),
        ];
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(
        tester,
        api,
        screen: const SafetyHistoryScreen(),
        size: const Size(320, 900),
      );
      expect(find.text('Ended without a check-in'), findsOneWidget);
      expect(find.text('Checked in safe'), findsNothing);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'an account switch prevents a late private history response from appearing',
    (tester) async {
      final api = HistoryApi()..waiting = Completer();
      late HistoryAuth auth;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            authControllerProvider.overrideWith(() => auth = HistoryAuth()),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const SafetyHistoryScreen(),
          ),
        ),
      );
      await tester.pump();
      auth.change();
      await tester.pump();
      api.waiting!.complete(
        RecordPage(
          items: [
            completed(
              'private',
              role: 'trusted_contact',
              alias: 'Previous account private friend',
            ),
          ],
          totalCount: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Previous account private friend'), findsNothing);
      expect(find.byType(SafetyHistoryCard), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
