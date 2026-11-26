import 'dart:async';

import 'package:anonymoke/core/auth/auth_controller.dart';
import 'package:anonymoke/core/config/build_config.dart';
import 'package:anonymoke/core/network/api_client.dart';
import 'package:anonymoke/core/theme/app_theme.dart';
import 'package:anonymoke/features/onboarding/application/consent_documents.dart';
import 'package:anonymoke/features/onboarding/application/onboarding_controller.dart';
import 'package:anonymoke/features/onboarding/presentation/onboarding_shell.dart';
import 'package:anonymoke/features/onboarding/presentation/privacy_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'onboarding_about_you_test.dart'
    show OnboardingApi, OnboardingAuth, containerFor, seedValid, openAbout;

const missingDocuments = ConsentDocuments(
  termsUrl: '',
  privacyUrl: '',
  version: 'test',
);

class RetryApi extends OnboardingApi {
  bool fail = true;
  @override
  Future<void> updateProfile(Map<String, dynamic> values) async {
    if (fail) throw const ApiException('network_error');
    await super.updateProfile(values);
  }
}

void main() {
  test('no privacy choice is preselected, including in Demo', () {
    const draft = OnboardingState();
    expect(draft.locationConsent, isFalse);
    expect(draft.sensitiveConsent, isFalse);
    expect(draft.voiceConsent, isFalse);
    expect(draft.termsConsent, isFalse);
    expect(draft.privacyConsent, isFalse);
    expect(draft.requiredConsentsGranted, isFalse);
  });

  test(
    'legal configuration requires HTTPS documents and a bounded version',
    () {
      for (final url in [
        '',
        'http://legal.test/terms',
        'javascript:alert(1)',
        'https://user:secret@legal.test/terms',
      ]) {
        expect(
          ConsentDocuments(
            termsUrl: url,
            privacyUrl: 'https://legal.test/privacy',
            version: 'v1',
          ).isConfigured,
          isFalse,
        );
      }
      for (final version in ['', ' ', 'x' * 65]) {
        expect(
          ConsentDocuments(
            termsUrl: 'https://legal.test/terms',
            privacyUrl: 'https://legal.test/privacy',
            version: version,
          ).isConfigured,
          isFalse,
        );
      }
      expect(
        const ConsentDocuments(
          termsUrl: 'https://legal.test/terms',
          privacyUrl: 'https://legal.test/privacy',
          version: 'v1',
        ).isConfigured,
        isTrue,
      );
    },
  );

  for (final choice in ['terms', 'privacy', 'matching', 'location']) {
    test('missing $choice consent prevents all writes', () async {
      final api = OnboardingApi();
      final container = containerFor(api);
      addTearDown(container.dispose);
      final controller = container.read(onboardingControllerProvider.notifier);
      seedValid(controller);
      switch (choice) {
        case 'terms':
          controller.setTermsConsent(false);
        case 'privacy':
          controller.setPrivacyConsent(false);
        case 'matching':
          controller.setSensitiveConsent(false);
        case 'location':
          controller.setLocationConsent(false);
      }
      await expectLater(controller.complete(), throwsA(isA<ApiException>()));
      expect(api.calls, isEmpty);
      expect(
        container.read(authControllerProvider).session!.isOnboarded,
        isFalse,
      );
    });
  }

  test(
    'missing policy documents prevent a live save before any write',
    () async {
      final api = OnboardingApi();
      final container = containerFor(api, documents: missingDocuments);
      addTearDown(container.dispose);
      final controller = container.read(onboardingControllerProvider.notifier);
      seedValid(controller);
      await expectLater(
        controller.complete(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'consent_documents_unavailable',
          ),
        ),
      );
      expect(api.calls, isEmpty);
    },
  );

  test(
    'final save records the displayed version and optional voice refusal',
    () async {
      final api = OnboardingApi();
      final container = containerFor(api);
      addTearDown(container.dispose);
      final controller = container.read(onboardingControllerProvider.notifier);
      seedValid(controller);
      await controller.complete();
      expect(api.consentWrites, hasLength(5));
      expect(
        api.consentWrites.every((c) => c['version'] == 'test-2026-11'),
        isTrue,
      );
      expect(api.consentWrites.last, containsPair('granted', false));
      expect(
        container.read(authControllerProvider).session!.isOnboarded,
        isTrue,
      );
      expect(
        container.read(authControllerProvider).session!.accessToken,
        'owner-a',
      );
    },
  );

  test('consent cannot change partway through a submission', () async {
    final api = OnboardingApi()..firstConsent = Completer<void>();
    final container = containerFor(api);
    addTearDown(container.dispose);
    final controller = container.read(onboardingControllerProvider.notifier);
    seedValid(controller);
    final saving = controller.complete();
    controller.setLocationConsent(false);
    controller.setSensitiveConsent(false);
    controller.setLegalConsent(false);
    controller.setVoiceConsent(true);
    expect(
      container.read(onboardingControllerProvider).requiredConsentsGranted,
      isTrue,
    );
    expect(container.read(onboardingControllerProvider).voiceConsent, isFalse);
    api.firstConsent!.complete();
    await saving;
    expect(api.consentWrites.last['granted'], isFalse);
  });

  test(
    'a failed save retains choices and only a successful retry marks onboarding complete',
    () async {
      final api = RetryApi();
      final container = containerFor(api);
      addTearDown(container.dispose);
      final controller = container.read(onboardingControllerProvider.notifier);
      seedValid(controller);
      await expectLater(controller.complete(), throwsA(isA<ApiException>()));
      expect(
        container.read(authControllerProvider).session!.isOnboarded,
        isFalse,
      );
      expect(container.read(onboardingControllerProvider).isSaving, isFalse);
      expect(
        container.read(onboardingControllerProvider).requiredConsentsGranted,
        isTrue,
      );
      api.fail = false;
      await controller.complete();
      expect(api.profiles, hasLength(1));
      expect(
        container.read(authControllerProvider).session!.isOnboarded,
        isTrue,
      );
    },
  );

  testWidgets('whole cards toggle explicit consent and voice is optional', (
    tester,
  ) async {
    final (container, api, router) = await openAbout(tester);
    final controller = container.read(onboardingControllerProvider.notifier);
    controller.setLocationConsent(false);
    controller.setSensitiveConsent(false);
    controller.setLegalConsent(false);
    router.go('/onboarding/5');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ElevatedButton>(find.byKey(const Key('privacy-finish')))
          .onPressed,
      isNull,
    );
    for (final id in ['location', 'matching', 'legal']) {
      final tile = find.byKey(Key('consent-$id'));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }
    expect(
      container.read(onboardingControllerProvider).requiredConsentsGranted,
      isTrue,
    );
    expect(container.read(onboardingControllerProvider).voiceConsent, isFalse);
    expect(
      tester
          .widget<ElevatedButton>(find.byKey(const Key('privacy-finish')))
          .onPressed,
      isNotNull,
    );
    expect(api.calls, isEmpty);
    router.go('/onboarding/4');
    await tester.pumpAndSettle();
    router.go('/onboarding/5');
    await tester.pumpAndSettle();
    expect(
      container.read(onboardingControllerProvider).requiredConsentsGranted,
      isTrue,
    );
  });

  testWidgets(
    'policy links open independently without accepting the legal checkbox',
    (tester) async {
      final launched = <Uri>[];
      final (container, api, router) = await openAbout(
        tester,
        documentLauncher: (uri) async {
          launched.add(uri);
          return true;
        },
      );
      container
          .read(onboardingControllerProvider.notifier)
          .setLegalConsent(false);
      router.go('/onboarding/5');
      await tester.pumpAndSettle();
      for (final id in ['terms', 'privacy']) {
        final link = find.byKey(Key('consent-$id-link'));
        await tester.ensureVisible(link);
        await tester.tap(link);
        await tester.pumpAndSettle();
      }
      expect(launched.map((u) => u.path), ['/terms', '/privacy']);
      expect(
        container.read(onboardingControllerProvider).termsConsent,
        isFalse,
      );
      expect(
        container.read(onboardingControllerProvider).privacyConsent,
        isFalse,
      );
      expect(api.calls, isEmpty);
    },
  );

  testWidgets(
    'failed document opening is recoverable and does not grant consent',
    (tester) async {
      final (container, _, router) = await openAbout(
        tester,
        documentLauncher: (_) async => false,
      );
      container
          .read(onboardingControllerProvider.notifier)
          .setLegalConsent(false);
      router.go('/onboarding/5');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('consent-terms-link')));
      await tester.tap(find.byKey(const Key('consent-terms-link')));
      await tester.pumpAndSettle();
      expect(
        find.text('This document is unavailable. Please try again later.'),
        findsOneWidget,
      );
      expect(
        container.read(onboardingControllerProvider).termsConsent,
        isFalse,
      );
    },
  );

  testWidgets('account changes clear every consent', (tester) async {
    final (container, _, router) = await openAbout(tester);
    router.go('/onboarding/5');
    await tester.pumpAndSettle();
    (container.read(authControllerProvider.notifier) as OnboardingAuth)
        .switchAccount();
    await tester.pumpAndSettle();
    for (final id in ['location', 'matching', 'voice', 'legal']) {
      expect(
        tester.widget<CheckboxListTile>(find.byKey(Key('consent-$id'))).value,
        isFalse,
      );
    }
  });

  testWidgets('missing photo returns to Step 4 without sending consent', (
    tester,
  ) async {
    final (_, api, router) = await openAbout(tester, readyPhoto: false);
    router.go('/onboarding/5');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('privacy-finish')));
    await tester.tap(find.byKey(const Key('privacy-finish')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/onboarding/4');
    expect(api.calls, isEmpty);
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets(
      'privacy choices and finish remain usable at 320 width, short height and scale $scale',
      (tester) async {
        final (_, _, router) = await openAbout(
          tester,
          width: 320,
          scale: scale,
        );
        tester.view.physicalSize = const Size(320, 640);
        router.go('/onboarding/5');
        await tester.pumpAndSettle();
        for (final key in [
          'consent-legal',
          'consent-privacy-link',
          'privacy-finish',
        ]) {
          final control = find.byKey(Key(key));
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(control.hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'final failures show friendly inline errors and preserve choices',
    (tester) async {
      final container = containerFor(OnboardingApi());
      seedValid(container.read(onboardingControllerProvider.notifier));
      var attempts = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: PrivacyStep(
                onContinue: () async {
                  attempts++;
                  throw const ApiException('internal_private_failure_detail');
                },
              ),
            ),
          ),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });
      for (var i = 0; i < 2; i++) {
        await tester.ensureVisible(find.byKey(const Key('privacy-finish')));
        await tester.tap(find.byKey(const Key('privacy-finish')));
        await tester.pumpAndSettle();
      }
      expect(attempts, 2);
      expect(find.byKey(const Key('privacy-error')), findsOneWidget);
      expect(find.textContaining('internal_private'), findsNothing);
      expect(
        container.read(onboardingControllerProvider).requiredConsentsGranted,
        isTrue,
      );
    },
  );

  testWidgets(
    'finish validates the same steps in Demo and only navigates after success',
    (tester) async {
      final api = OnboardingApi();
      final container = containerFor(api);
      seedValid(container.read(onboardingControllerProvider.notifier));
      final router = GoRouter(
        initialLocation: '/onboarding/5',
        routes: [
          GoRoute(
            path: '/onboarding/:step',
            builder: (_, state) =>
                OnboardingShell(step: int.parse(state.pathParameters['step']!)),
          ),
          GoRoute(
            path: '/app/discover',
            builder: (_, _) => const Scaffold(body: Text('Discovery ready')),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        container.dispose();
      });
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('privacy-finish')));
      await tester.tap(find.byKey(const Key('privacy-finish')));
      await tester.pumpAndSettle();
      expect(find.text('Discovery ready'), findsOneWidget);
      if (demoMode) {
        expect(api.calls, isEmpty);
        expect(
          container.read(authControllerProvider).session!.isOnboarded,
          isFalse,
        );
      } else {
        expect(api.profiles, hasLength(1));
        expect(
          container.read(authControllerProvider).session!.isOnboarded,
          isTrue,
        );
      }
    },
  );

  testWidgets('expired sessions offer a direct sign-in recovery action', (
    tester,
  ) async {
    final container = containerFor(OnboardingApi());
    seedValid(container.read(onboardingControllerProvider.notifier));
    final router = GoRouter(
      initialLocation: '/privacy',
      routes: [
        GoRoute(
          path: '/privacy',
          builder: (_, _) => Scaffold(
            body: PrivacyStep(
              onContinue: () async =>
                  throw const ApiException('session_expired'),
            ),
          ),
        ),
        GoRoute(
          path: '/auth',
          builder: (_, _) => const Scaffold(body: Text('Sign-in screen')),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      container.dispose();
    });
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('privacy-finish')));
    await tester.tap(find.byKey(const Key('privacy-finish')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign in again'));
    await tester.tap(find.text('Sign in again'));
    await tester.pumpAndSettle();
    expect(find.text('Sign-in screen'), findsOneWidget);
  });

  if (!demoMode) {
    test('production cannot use the Demo completion bypass', () async {
      final api = OnboardingApi();
      final container = containerFor(api);
      addTearDown(container.dispose);
      seedValid(container.read(onboardingControllerProvider.notifier));
      await expectLater(
        container.read(onboardingControllerProvider.notifier).completePreview(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'preview_unavailable',
          ),
        ),
      );
      expect(api.calls, isEmpty);
    });
  }
}
