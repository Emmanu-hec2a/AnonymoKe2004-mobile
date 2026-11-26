import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'dart:io';

import 'package:anonymoke/core/theme/app_theme.dart';
import 'package:anonymoke/features/home/presentation/reference_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpTab(
  WidgetTester tester,
  Widget screen, {
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 844),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: screen,
            bottomNavigationBar: NavigationBar(
              selectedIndex: screen is ReferenceSafetyScreen
                  ? 2
                  : screen is ReferenceProfileScreen
                  ? 3
                  : 0,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  label: 'Discover',
                ),
                NavigationDestination(
                  icon: Icon(Icons.forum_outlined),
                  label: 'Matches',
                ),
                NavigationDestination(
                  icon: Icon(Icons.verified_user_outlined),
                  label: 'Safety',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (screen is ReferenceDiscoverScreen) {
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/branding/anonymoke-header-logo.jpeg'),
        tester.element(find.byType(Scaffold)),
      ),
    );
    await tester.pumpAndSettle();
  }
}

void expectReadable(WidgetTester tester, String label, {int maxLines = 2}) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: label.length),
  );
  final lines = boxes.map((box) => box.top).toSet();
  expect(paragraph.constraints.maxWidth, greaterThan(100), reason: label);
  expect(lines.length, lessThanOrEqualTo(maxLines), reason: label);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Use the same Roboto font as the phone instead of the test-only Ahem font.
    final config = File('.dart_tool/package_config.json').absolute;
    final packages = jsonDecode(config.readAsStringSync())['packages'] as List;
    final flutter = packages.firstWhere((item) => item['name'] == 'flutter');
    final root = flutter['rootUri'] as String;
    final flutterUri = config.uri.resolve(root.endsWith('/') ? root : '$root/');
    final font = File.fromUri(
      flutterUri.resolve(
        '../../bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      ),
    );
    await (FontLoader('Roboto')
          ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync()))))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets('Safety verification text keeps its width at $width', (
      tester,
    ) async {
      await pumpTab(tester, const ReferenceSafetyScreen(), width: width);
      expect(tester.takeException(), isNull);
      expectReadable(tester, 'Get verified');
      expectReadable(tester, 'Needed before your first reveal.');
    });

    testWidgets('Profile summary text keeps its width at $width', (
      tester,
    ) async {
      await pumpTab(tester, const ReferenceProfileScreen(), width: width);
      expect(tester.takeException(), isNull);
      expectReadable(tester, 'Weekly Premium');
      expectReadable(tester, 'My voice capsule');
    });
  }

  for (final screen in [
    const ReferenceSafetyScreen(),
    const ReferenceProfileScreen(),
  ]) {
    testWidgets('${screen.runtimeType} supports larger text', (tester) async {
      await pumpTab(tester, screen, width: 360, textScale: 1.3);
      expect(tester.takeException(), isNull);
      expectReadable(
        tester,
        screen is ReferenceSafetyScreen ? 'Get verified' : 'My voice capsule',
      );
    });
  }

  testWidgets('demo profile pause persists across tabs and can be resumed', (
    tester,
  ) async {
    await pumpTab(tester, const ReferenceProfileScreen());
    await tester.scrollUntilVisible(find.text('Pause my profile'), 180);
    await tester.tap(find.text('Pause my profile'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, true);
    await pumpTab(tester, const ReferenceDiscoverScreen());
    expect(find.text('Your profile is paused.'), findsOneWidget);
    await tester.tap(find.text('Resume my profile'));
    await tester.pumpAndSettle();
    expect(find.text('Your profile is paused.'), findsNothing);
    await pumpTab(tester, const ReferenceProfileScreen());
    await tester.scrollUntilVisible(find.text('Pause my profile'), 180);
    expect(tester.widget<Switch>(find.byType(Switch)).value, false);
  });

  for (final entry in <String, Widget>{
    'safety': const ReferenceSafetyScreen(),
    'profile': const ReferenceProfileScreen(),
    'discover': const ReferenceDiscoverScreen(),
  }.entries) {
    testWidgets('${entry.key} visual regression', (tester) async {
      await pumpTab(tester, entry.value);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/${entry.key}.png'),
      );
    });
  }
}
