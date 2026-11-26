import 'dart:async';

import 'package:anonymoke/core/theme/app_theme.dart';
import 'package:anonymoke/core/widgets/app_surfaces.dart';
import 'package:anonymoke/core/widgets/loading_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Object?> backEvent(
  WidgetTester tester,
  String method, [
  Map<String, Object?>? arguments,
]) async {
  final result = Completer<ByteData?>();
  const codec = StandardMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.backGesture.name,
    codec.encodeMethodCall(MethodCall(method, arguments)),
    result.complete,
  );
  final data = await result.future;
  return data == null ? null : codec.decodeEnvelope(data);
}

void main() {
  for (final width in [320.0, 430.0]) {
    testWidgets('header stays fixed while content scrolls at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 700);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: PinnedTabBody(
              header: const Text(
                'Safety center',
                style: TextStyle(fontSize: 26),
              ),
              child: ListView(
                children: List.generate(
                  30,
                  (i) => SizedBox(height: 70, child: Text('Item $i')),
                ),
              ),
            ),
          ),
        ),
      );
      final header = tester.getRect(find.byKey(const Key('pinned-tab-header')));
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const Key('pinned-tab-header'))),
        header,
      );
      expect(find.text('Safety center').hitTestable(), findsOneWidget);
      expect(find.text('Item 0').hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'shimmer respects reduced motion and can settle without an active ticker',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const Scaffold(
              body: ContentSkeleton(content: SkeletonContent.matches),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonBox), findsWidgets);
      final first = tester.widget<ShaderMask>(find.byType(ShaderMask));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.widget<ShaderMask>(find.byType(ShaderMask)), same(first));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loading shapes are replaced by content and dispose their animation',
    (tester) async {
      var loading = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: loading
                    ? const ContentSkeleton(content: SkeletonContent.safety)
                    : const Text('Safety ready'),
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ShaderMask), findsOneWidget);
      update(() => loading = false);
      await tester.pumpAndSettle();
      expect(find.byType(ShaderMask), findsNothing);
      expect(find.text('Safety ready'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelled Android back keeps the page; a committed gesture pops once',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: AppTheme.dark().copyWith(platform: TargetPlatform.android),
          home: const Scaffold(body: Text('Safety parent')),
        ),
      );
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const AppRouteSurface(
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Text('Blocked people page'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester.getRect(find.text('Blocked people page'));
      const start = <String, Object?>{
        'touchOffset': <double>[0, 200],
        'progress': 0.0,
        'swipeEdge': 0,
      };
      expect(await backEvent(tester, 'startBackGesture', start), false);
      await backEvent(tester, 'updateBackGestureProgress', {
        ...start,
        'progress': .65,
      });
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(find.text('Blocked people page')), before);
      expect(find.text('Safety parent').hitTestable(), findsNothing);
      await backEvent(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('Blocked people page'), findsOneWidget);
      expect(navigator.currentState!.canPop(), true);
      await backEvent(tester, 'startBackGesture', start);
      await backEvent(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('Blocked people page'), findsNothing);
      expect(find.text('Safety parent').hitTestable(), findsOneWidget);
      expect(navigator.currentState!.canPop(), false);
      expect(tester.takeException(), isNull);
    },
  );
}
