import 'dart:async';

import 'package:anonymoke/core/auth/auth_controller.dart';
import 'package:anonymoke/core/network/api_client.dart';
import 'package:anonymoke/features/onboarding/application/onboarding_controller.dart';
import 'package:anonymoke/features/onboarding/application/preferences_validation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'discover_live_test.dart' show MemoryStore, Adapter, jsonResponse;
import 'onboarding_about_you_test.dart'
    show
        OnboardingApi,
        OnboardingAuth,
        containerFor,
        seedValid,
        openAbout,
        continueAbout;

Future<(ProviderContainer, OnboardingApi, GoRouter)> openPreferences(
  WidgetTester tester, {
  List<String> targets = const [],
  int minimum = 24,
  int maximum = 34,
  int distance = 15,
  double width = 390,
  double scale = 1,
}) async {
  final result = await openAbout(tester, width: width, scale: scale);
  final (container, _, router) = result;
  final controller = container.read(onboardingControllerProvider.notifier);
  controller.setTargetGenders(targets);
  controller.setAgeRange(minimum, maximum);
  controller.setDistance(distance);
  router.go('/onboarding/2');
  await tester.pumpAndSettle();
  return result;
}

Future<void> choose(WidgetTester tester, String code) async {
  final chip = find.byKey(Key('meet-$code'));
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

class RetryOnboardingApi extends OnboardingApi {
  bool fail = true;
  int attempts = 0;
  @override
  Future<void> updateProfile(Map<String, dynamic> values) async {
    attempts++;
    if (fail) throw const ApiException('network_error', 503);
    await super.updateProfile(values);
  }
}

void main() {
  testWidgets('Show me requires an explicit selection before advancing', (
    tester,
  ) async {
    final (_, api, router) = await openPreferences(tester);
    expect(
      tester
          .widgetList<FilterChip>(find.byType(FilterChip))
          .every((chip) => !chip.selected),
      isTrue,
    );
    await continueAbout(tester);
    expect(find.text('Choose who you would like to meet.'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/onboarding/2');
    expect(api.calls, isEmpty);
    await choose(tester, 'M');
    expect(find.text('Choose who you would like to meet.'), findsNothing);
    await continueAbout(tester);
    expect(router.routeInformationProvider.value.uri.path, '/onboarding/3');
    expect(api.calls, isEmpty);
  });

  for (final code in ['M', 'W', 'NB', 'ALL']) {
    testWidgets('selection $code is stored in the private draft only', (
      tester,
    ) async {
      final (container, api, _) = await openPreferences(tester);
      await choose(tester, code);
      expect(container.read(onboardingControllerProvider).targetGenders, [
        code,
      ]);
      expect(
        tester.widget<FilterChip>(find.byKey(Key('meet-$code'))).selected,
        isTrue,
      );
      expect(api.calls, isEmpty);
    });
  }

  testWidgets(
    'multiple specific genders can be selected and removed independently',
    (tester) async {
      final (container, _, router) = await openPreferences(tester);
      await choose(tester, 'M');
      await choose(tester, 'W');
      expect(container.read(onboardingControllerProvider).targetGenders, [
        'M',
        'W',
      ]);
      await choose(tester, 'M');
      expect(container.read(onboardingControllerProvider).targetGenders, ['W']);
      await choose(tester, 'W');
      expect(
        container.read(onboardingControllerProvider).targetGenders,
        isEmpty,
      );
      await continueAbout(tester);
      expect(router.routeInformationProvider.value.uri.path, '/onboarding/2');
    },
  );

  testWidgets(
    'Everyone clears specific selections and a specific choice replaces Everyone',
    (tester) async {
      final (container, _, _) = await openPreferences(
        tester,
        targets: ['M', 'W'],
      );
      await choose(tester, 'ALL');
      expect(container.read(onboardingControllerProvider).targetGenders, [
        'ALL',
      ]);
      expect(
        tester.widget<FilterChip>(find.byKey(const Key('meet-M'))).selected,
        isFalse,
      );
      await choose(tester, 'NB');
      expect(container.read(onboardingControllerProvider).targetGenders, [
        'NB',
      ]);
      expect(
        tester.widget<FilterChip>(find.byKey(const Key('meet-ALL'))).selected,
        isFalse,
      );
      await choose(tester, 'ALL');
      await choose(tester, 'ALL');
      expect(
        container.read(onboardingControllerProvider).targetGenders,
        isEmpty,
      );
      await continueAbout(tester);
      expect(find.text('Choose who you would like to meet.'), findsOneWidget);
    },
  );

  testWidgets(
    'age slider can be dragged beyond forty to the real upper limit',
    (tester) async {
      final (container, api, _) = await openPreferences(tester, targets: ['M']);
      final slider = find.byKey(const Key('meet-age-range'));
      await tester.ensureVisible(slider);
      final rect = tester.getRect(slider);
      final initialEnd = Offset(
        rect.left + 24 + (rect.width - 48) * (34 - 18) / 82,
        rect.center.dy,
      );
      final gesture = await tester.startGesture(initialEnd);
      await gesture.moveTo(Offset(rect.right - 24, rect.center.dy));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(container.read(onboardingControllerProvider).maxAge, 100);
      expect(find.text('24 to 100'), findsOneWidget);
      expect(api.calls, isEmpty);
    },
  );

  testWidgets(
    'older adult ranges restore accurately instead of crashing the slider',
    (tester) async {
      await openPreferences(tester, targets: ['NB'], minimum: 55, maximum: 85);
      final slider = tester.widget<RangeSlider>(
        find.byKey(const Key('meet-age-range')),
      );
      expect(slider.values, const RangeValues(55, 85));
      expect(find.text('55 to 85'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'distance dragging reaches both supported limits with matching labels',
    (tester) async {
      final (container, api, _) = await openPreferences(
        tester,
        targets: ['ALL'],
      );
      final slider = find.byKey(const Key('meet-distance'));
      await tester.ensureVisible(slider);
      await tester.drag(slider, const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(container.read(onboardingControllerProvider).maxDistanceKm, 50);
      expect(find.text('Within 50 km'), findsOneWidget);
      await tester.drag(slider, const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(container.read(onboardingControllerProvider).maxDistanceKm, 1);
      expect(find.text('Within 1 km'), findsOneWidget);
      expect(api.calls, isEmpty);
    },
  );

  testWidgets(
    'returning through steps one and three preserves all matching choices',
    (tester) async {
      final (container, api, router) = await openPreferences(
        tester,
        targets: ['W', 'NB'],
        minimum: 45,
        maximum: 85,
        distance: 50,
      );
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(find.text('About you'), findsOneWidget);
      await continueAbout(tester);
      expect(find.text('45 to 85'), findsOneWidget);
      expect(find.text('Within 50 km'), findsOneWidget);
      await continueAbout(tester);
      expect(router.routeInformationProvider.value.uri.path, '/onboarding/3');
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(container.read(onboardingControllerProvider).targetGenders, [
        'W',
        'NB',
      ]);
      expect(find.text('45 to 85'), findsOneWidget);
      expect(find.text('Within 50 km'), findsOneWidget);
      expect(api.calls, isEmpty);
    },
  );

  testWidgets(
    'switching accounts clears matching choices and resets the screen',
    (tester) async {
      final (container, api, _) = await openPreferences(
        tester,
        targets: ['W', 'NB'],
        minimum: 55,
        maximum: 85,
        distance: 50,
      );
      (container.read(authControllerProvider.notifier) as OnboardingAuth)
          .switchAccount();
      await tester.pumpAndSettle();
      const defaults = OnboardingState();
      expect(
        container.read(onboardingControllerProvider).targetGenders,
        defaults.targetGenders,
      );
      expect(
        find.text('${defaults.minAge} to ${defaults.maxAge}'),
        findsOneWidget,
      );
      expect(find.text('Within 15 km'), findsOneWidget);
      expect(api.calls, isEmpty);
    },
  );

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets(
      'step two stays readable and scrollable at 320 width and text scale $scale',
      (tester) async {
        await openPreferences(
          tester,
          targets: ['ALL'],
          width: 320,
          scale: scale,
        );
        await tester.ensureVisible(
          find.widgetWithText(ElevatedButton, 'Continue'),
        );
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(ElevatedButton, 'Continue').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('invalid restored values remain editable and cannot advance', (
    tester,
  ) async {
    final (container, api, router) = await openPreferences(
      tester,
      targets: ['M'],
      minimum: 17,
      maximum: 101,
      distance: 0,
    );
    expect(tester.takeException(), isNull);
    await continueAbout(tester);
    expect(
      find.text('Choose an age range between 18 and 100.'),
      findsOneWidget,
    );
    expect(find.text('Choose a distance between 1 and 50 km.'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/onboarding/2');
    final controller = container.read(onboardingControllerProvider.notifier);
    controller.setAgeRange(18, 100);
    controller.setDistance(1);
    await tester.pumpAndSettle();
    await continueAbout(tester);
    expect(router.routeInformationProvider.value.uri.path, '/onboarding/3');
    expect(api.calls, isEmpty);
  });

  final invalidDrafts = <String, void Function(OnboardingController)>{
    'empty genders': (c) => c.setTargetGenders([]),
    'Everyone mixed with specific genders': (c) =>
        c.setTargetGenders(['ALL', 'M']),
    'unknown genders': (c) => c.setTargetGenders(['unknown']),
    'duplicate genders': (c) => c.setTargetGenders(['W', 'W']),
    'underage minimum': (c) => c.setAgeRange(17, 35),
    'reversed age range': (c) => c.setAgeRange(36, 35),
    'age above limit': (c) => c.setAgeRange(18, 101),
    'zero distance': (c) => c.setDistance(0),
    'distance above limit': (c) => c.setDistance(51),
  };
  for (final invalid in invalidDrafts.entries) {
    test(
      'final save rejects ${invalid.key} before making any network requests',
      () async {
        final api = OnboardingApi();
        final container = containerFor(api);
        addTearDown(container.dispose);
        final controller = container.read(
          onboardingControllerProvider.notifier,
        );
        seedValid(controller);
        invalid.value(controller);
        await expectLater(controller.complete(), throwsA(isA<ApiException>()));
        expect(api.calls, isEmpty);
      },
    );
  }

  test(
    'network contract saves gender, age and distance in one profile PATCH after consents',
    () async {
      final calls = <RequestOptions>[];
      final api = ApiClient(
        store: MemoryStore(),
        baseUrl: 'https://api.test/api/v1',
      );
      api.dio.httpClientAdapter = Adapter((request) {
        calls.add(request);
        return jsonResponse({});
      });
      final container = containerFor(api);
      addTearDown(container.dispose);
      final controller = container.read(onboardingControllerProvider.notifier);
      seedValid(controller);
      controller.setTargetGenders(['W', 'NB']);
      controller.setAgeRange(45, 85);
      controller.setDistance(50);
      await controller.complete();
      expect(calls.map((request) => request.method), [
        'POST',
        'POST',
        'POST',
        'POST',
        'POST',
        'PATCH',
      ]);
      expect(calls.last.path, '/me/profile/');
      expect(calls.last.data, containsPair('target_genders', ['W', 'NB']));
      expect(calls.last.data, containsPair('min_age_pref', 45));
      expect(calls.last.data, containsPair('max_age_pref', 85));
      expect(calls.last.data, containsPair('max_distance_km', 50));
      expect(
        calls.where((request) => request.path == '/me/preferences/'),
        isEmpty,
      );
    },
  );

  test(
    'final save keeps a consistent snapshot if choices change while consent requests are pending',
    () async {
      final api = OnboardingApi()..firstConsent = Completer<void>();
      final container = containerFor(api);
      addTearDown(container.dispose);
      final controller = container.read(onboardingControllerProvider.notifier);
      seedValid(controller);
      controller.setTargetGenders(['NB']);
      controller.setAgeRange(45, 85);
      controller.setDistance(50);
      final saving = controller.complete();
      controller.setTargetGenders(['M']);
      controller.setAgeRange(18, 25);
      controller.setDistance(1);
      api.firstConsent!.complete();
      await saving;
      expect(api.profiles.single['target_genders'], ['NB']);
      expect(api.profiles.single['min_age_pref'], 45);
      expect(api.profiles.single['max_age_pref'], 85);
      expect(api.profiles.single['max_distance_km'], 50);
      expect(api.preferences, isEmpty);
    },
  );

  test('failed atomic save retains choices and can be retried', () async {
    final api = RetryOnboardingApi();
    final container = containerFor(api);
    addTearDown(container.dispose);
    final controller = container.read(onboardingControllerProvider.notifier);
    seedValid(controller);
    controller.setTargetGenders(['W', 'NB']);
    controller.setAgeRange(45, 85);
    controller.setDistance(50);
    await expectLater(controller.complete(), throwsA(isA<ApiException>()));
    expect(container.read(onboardingControllerProvider).isSaving, isFalse);
    expect(container.read(onboardingControllerProvider).targetGenders, [
      'W',
      'NB',
    ]);
    expect(container.read(onboardingControllerProvider).error, 'network_error');
    api.fail = false;
    await controller.complete();
    expect(api.attempts, 2);
    expect(api.profiles, hasLength(1));
    expect(api.preferences, isEmpty);
    expect(container.read(onboardingControllerProvider).error, isNull);
  });

  test(
    'toggle choices never changes the source list or combines Everyone with a specific choice',
    () {
      const source = ['ALL'];
      expect(PreferencesValidation.toggleGender(source, 'W'), ['W']);
      expect(source, ['ALL']);
      expect(
        () => PreferencesValidation.toggleGender(source, 'unknown'),
        throwsArgumentError,
      );
    },
  );
}
