import 'package:anonymoke/core/theme/verified_badge.dart';
import 'package:anonymoke/features/home/presentation/widgets/discovery_deck.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpDeck(
  WidgetTester tester,
  GlobalKey<DiscoveryDeckState> key,
  List<int> commits,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 340,
          child: DiscoveryDeck(
            key: key,
            itemId: 1,
            onSwipe: commits.add,
            nextChild: const ColoredBox(color: Colors.green),
            child: const ColoredBox(key: ValueKey('front'), color: Colors.blue),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('short drag returns smoothly without committing a swipe', (
    tester,
  ) async {
    final key = GlobalKey<DiscoveryDeckState>();
    final commits = <int>[];
    await pumpDeck(tester, key, commits);
    final front = find.byKey(const ValueKey('front'));
    final restingX = tester.getTopLeft(front).dx;
    final gesture = await tester.startGesture(tester.getCenter(front));
    await gesture.moveBy(const Offset(35, 0));
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(commits, isEmpty);
    expect(tester.getTopLeft(front).dx, closeTo(restingX, .1));
    expect(tester.takeException(), isNull);
  });

  for (final direction in [-1, 1]) {
    testWidgets(
      'committed drag $direction continues forward without snapping back',
      (tester) async {
        final key = GlobalKey<DiscoveryDeckState>();
        final commits = <int>[];
        await pumpDeck(tester, key, commits);
        final front = find.byKey(const ValueKey('front'));
        final gesture = await tester.startGesture(tester.getCenter(front));
        await gesture.moveBy(Offset(direction * 130, 0));
        await tester.pump(const Duration(milliseconds: 150));
        var previousX = tester.getTopLeft(front).dx * direction;
        await gesture.up();
        await tester.pump();
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final currentX = tester.getTopLeft(front).dx * direction;
          expect(currentX, greaterThanOrEqualTo(previousX));
          previousX = currentX;
        }
        expect(commits, isEmpty);
        await tester.pumpAndSettle();
        expect(commits, [direction]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('rapid button taps produce only one swipe', (tester) async {
    final key = GlobalKey<DiscoveryDeckState>();
    final commits = <int>[];
    await pumpDeck(tester, key, commits);
    key.currentState!.swipe(1);
    key.currentState!.swipe(1);
    key.currentState!.swipe(-1);
    await tester.pumpAndSettle();
    expect(commits, [1]);
  });

  testWidgets('verified seal is compact and scalloped with a white tick', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: VerifiedBadge())),
    );
    expect(tester.getSize(find.byType(VerifiedBadge)), const Size(20, 20));
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    final tick = tester.widget<Icon>(find.byIcon(Icons.check_rounded));
    expect(tick.color, Colors.white);
  });
}
