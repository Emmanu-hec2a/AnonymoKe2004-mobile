import 'dart:async';
import 'package:anonymoke/core/network/api_client.dart';
import 'package:anonymoke/features/home/presentation/widgets/discovery_deck.dart';
import 'package:anonymoke/features/home/presentation/tab_refresh.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'discover_live_test.dart'
    show FakeApi, FakeLocation, firstCard, secondCard, pumpDiscover;

class PagedApi extends FakeApi {
  final cursors = <String?>[];
  final decisions = <String>[];
  bool failPage = false, empty = false, duplicate = false;
  @override
  Future<DiscoveryPage> discoveryPage({
    String? cursor,
    int? maxDistanceKm,
    int? minAge,
    int? maxAge,
  }) async {
    cursors.add(cursor);
    if (empty) return const DiscoveryPage(items: []);
    if (cursor != null && failPage) throw const ApiException('network_error');
    if (cursor == null) {
      return const DiscoveryPage(items: [firstCard], nextCursor: 'page-two');
    }
    return DiscoveryPage(items: [if (duplicate) firstCard, secondCard]);
  }

  @override
  Future<SwipeOutcome> swipe({
    required String profileId,
    required String action,
    String? clientSwipeId,
  }) {
    decisions.add('$profileId:$action');
    return super.swipe(
      profileId: profileId,
      action: action,
      clientSwipeId: clientSwipeId,
    );
  }
}

String current(WidgetTester tester) =>
    tester.widget<DiscoveryDeck>(find.byType(DiscoveryDeck)).itemId as String;
Future<void> browse(WidgetTester tester, int direction) async {
  final deck = tester.state<DiscoveryDeckState>(find.byType(DiscoveryDeck));
  deck.browse(direction);
  await tester.pumpAndSettle();
}

class SlowPageApi extends PagedApi {
  final page = Completer<DiscoveryPage>();
  @override
  Future<DiscoveryPage> discoveryPage({
    String? cursor,
    int? maxDistanceKm,
    int? minAge,
    int? maxAge,
  }) async {
    cursors.add(cursor);
    if (cursor == null) {
      return const DiscoveryPage(
        items: [firstCard, secondCard],
        nextCursor: 'slow',
      );
    }
    return page.future;
  }
}

void main() {
  testWidgets(
    'a fresh server feed restores a like withdrawn outside Discover',
    (tester) async {
      final api = PagedApi();
      await pumpDiscover(tester, api, FakeLocation());
      await tester.tap(find.byIcon(Icons.favorite).last);
      await tester.pumpAndSettle();
      expect(current(tester), secondCard.profileId);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DiscoveryDeck)),
      );
      container.read(discoveryRefreshSignal.notifier).notify();
      await tester.pumpAndSettle();
      expect(current(tester), firstCard.profileId);
      expect(api.decisions, ['first:like']);
    },
  );
  testWidgets('resuming beyond the first page preserves browsing position', (
    tester,
  ) async {
    final api = PagedApi();
    await pumpDiscover(tester, api, FakeLocation());
    await browse(tester, -1);
    await tester.pump(const Duration(seconds: 31));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(current(tester), secondCard.profileId);
    expect(api.cursors, [null, 'page-two']);
    expect(api.swipes, isEmpty);
  });
  testWidgets(
    'left and right browse paginated profiles without recording decisions',
    (tester) async {
      final api = PagedApi();
      await pumpDiscover(tester, api, FakeLocation());
      await browse(tester, 1);
      expect(current(tester), firstCard.profileId);
      await tester.drag(find.byType(DiscoveryDeck), const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(current(tester), secondCard.profileId);
      expect(api.cursors, [null, 'page-two']);
      await tester.drag(find.byType(DiscoveryDeck), const Offset(180, 0));
      await tester.pumpAndSettle();
      expect(current(tester), firstCard.profileId);
      expect(api.swipes, isEmpty);
      expect(api.decisions, isEmpty);
    },
  );
  testWidgets(
    'failed pagination keeps cached profiles available and retries its cursor',
    (tester) async {
      final api = PagedApi()..failPage = true;
      await pumpDiscover(tester, api, FakeLocation());
      await browse(tester, -1);
      expect(find.text('More profiles could not load'), findsOneWidget);
      await tester.tap(find.text('Previous profile'));
      await tester.pumpAndSettle();
      expect(current(tester), firstCard.profileId);
      api.failPage = false;
      await browse(tester, -1);
      await tester.tap(find.text('Retry loading profiles'));
      await tester.pumpAndSettle();
      expect(current(tester), secondCard.profileId);
      expect(api.cursors, [null, 'page-two', 'page-two']);
      expect(api.swipes, isEmpty);
    },
  );
  testWidgets('slow prefetch never blocks cached browsing or sends decisions', (
    tester,
  ) async {
    final api = SlowPageApi();
    await pumpDiscover(tester, api, FakeLocation());
    expect(api.cursors, [null, 'slow']);
    expect(api.page.isCompleted, isFalse);
    await browse(tester, -1);
    expect(current(tester), secondCard.profileId);
    await browse(tester, 1);
    expect(current(tester), firstCard.profileId);
    expect(api.decisions, isEmpty);
    api.page.complete(const DiscoveryPage(items: []));
    await tester.pumpAndSettle();
  });
  testWidgets(
    'network boundary releases the gesture and allows browsing back',
    (tester) async {
      final api = SlowPageApi();
      await pumpDiscover(tester, api, FakeLocation());
      await browse(tester, -1);
      final deck = tester.state<DiscoveryDeckState>(find.byType(DiscoveryDeck));
      deck.browse(-1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text('Loading more profiles'), findsOneWidget);
      expect(api.page.isCompleted, isFalse);
      await tester.tap(find.text('Previous profile'));
      await tester.pump();
      expect(current(tester), secondCard.profileId);
      api.page.complete(const DiscoveryPage(items: []));
      await tester.pumpAndSettle();
      expect(api.decisions, isEmpty);
    },
  );
  testWidgets(
    'only the heart sends a like and the liked card cannot be browsed back to',
    (tester) async {
      final api = PagedApi()..duplicate = true;
      await pumpDiscover(tester, api, FakeLocation());
      await tester.tap(find.byIcon(Icons.favorite).last);
      await tester.pumpAndSettle();
      expect(api.decisions, ['first:like']);
      expect(current(tester), secondCard.profileId);
      await browse(tester, 1);
      expect(current(tester), secondCard.profileId);
      expect(api.decisions, ['first:like']);
    },
  );
  testWidgets(
    'browsing to the end offers undecided profiles again and saved likes',
    (tester) async {
      final api = PagedApi();
      await pumpDiscover(tester, api, FakeLocation());
      await browse(tester, -1);
      await browse(tester, -1);
      expect(find.text('Browse again'), findsOneWidget);
      expect(find.text('View likes sent'), findsOneWidget);
      await tester.tap(find.text('Browse again'));
      await tester.pumpAndSettle();
      expect(current(tester), firstCard.profileId);
      expect(api.swipes, isEmpty);
    },
  );
  testWidgets('X records a pass and an empty initial feed explains filters', (
    tester,
  ) async {
    final api = PagedApi();
    await pumpDiscover(tester, api, FakeLocation());
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();
    expect(api.decisions, ['first:pass']);
    await tester.pumpWidget(const SizedBox());
    await pumpDiscover(tester, PagedApi()..empty = true, FakeLocation());
    expect(find.text('No profiles match your preferences yet'), findsOneWidget);
    expect(find.text('Browse again'), findsNothing);
  });
}
