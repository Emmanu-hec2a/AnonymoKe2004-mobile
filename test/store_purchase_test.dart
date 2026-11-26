import 'package:anonymoke/core/network/api_client.dart';
import 'package:anonymoke/core/theme/app_theme.dart';
import 'package:anonymoke/features/home/presentation/reference_tabs.dart';
import 'package:anonymoke/core/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'discover_live_test.dart' show MemoryStore;

class StoreApi extends ApiClient {
  StoreApi() : super(store: MemoryStore(), baseUrl: 'https://api.test/api/v1');
  final statuses = <String>['pending', 'pending', 'completed'];
  int? failureCode;
  int polls = 0;
  @override
  Future<List<StoreProduct>> storeProducts() async => const [
    StoreProduct(
      code: 'boost-single',
      name: 'Profile Boost',
      priceKes: 50,
      kind: 'boost',
    ),
  ];
  @override
  Future<Map<String, dynamic>> createPurchase({
    required String productCode,
    required String phone,
    required String idempotencyKey,
  }) async => {'id': 'purchase-1', 'status': 'pending'};
  @override
  Future<PurchaseStatus> purchaseStatus(String purchaseId) async {
    polls++;
    final status = statuses.length > 1 ? statuses.removeAt(0) : statuses.first;
    return PurchaseStatus(
      id: purchaseId,
      status: status,
      resultCode: failureCode,
    );
  }
}

Future<void> pumpStore(WidgetTester tester, StoreApi api) async {
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/boost',
    routes: [
      GoRoute(
        path: '/boost',
        builder: (_, _) => const Scaffold(body: Text('Boost screen')),
      ),
      GoRoute(
        path: '/store',
        builder: (_, _) =>
            const Scaffold(body: ReferenceStoreScreen(initialProduct: 1)),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  router.push('/store');
  await tester.pumpAndSettle();
}

/// Pumps in small steps until [text] is on screen; snackbars queue behind
/// the "prompt sent" one, so exact timings are fragile.
Future<void> pumpUntilVisible(WidgetTester tester, String text) async {
  for (var i = 0; i < 40; i++) {
    if (find.text(text).evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 250));
  }
  fail('"$text" never appeared');
}

Future<void> pay(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), '0712345678');
  await tester.tap(find.textContaining('with M-PESA'));
  await tester.pump();
}

void main() {
  testWidgets('a confirmed purchase closes the store with a thank you', (
    tester,
  ) async {
    final api = StoreApi();
    await pumpStore(tester, api);
    await pay(tester);
    await tester.pump();
    expect(find.text('Waiting for M-PESA confirmation…'), findsOneWidget);
    await tester.pump(ReferenceStoreScreen.pollInterval);
    await tester.pump();
    expect(find.text('Waiting for M-PESA confirmation…'), findsOneWidget);
    await tester.pump(ReferenceStoreScreen.pollInterval);
    await tester.pump(ReferenceStoreScreen.pollInterval);
    await tester.pumpAndSettle();
    expect(api.polls, 3);
    expect(find.text('Payment confirmed. Thank you.'), findsOneWidget);
    expect(find.text('Boost screen'), findsOneWidget);
  });

  testWidgets('a cancelled prompt is explained and the store stays open', (
    tester,
  ) async {
    final api = StoreApi()
      ..statuses.replaceRange(0, 3, ['failed'])
      ..failureCode = 1032;
    await pumpStore(tester, api);
    await pay(tester);
    await pumpUntilVisible(tester, 'You cancelled the M-PESA request.');
    expect(api.polls, 1);
    expect(find.text('You cancelled the M-PESA request.'), findsOneWidget);
    expect(find.text('Boost screen'), findsNothing);
    expect(find.textContaining('with M-PESA'), findsOneWidget);
  });
}
