import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anonymoke/core/auth/auth_controller.dart';
import 'package:anonymoke/core/auth/session.dart';
import 'package:anonymoke/core/network/api_client.dart';
import 'package:anonymoke/core/routing/app_router.dart';
import 'package:anonymoke/core/theme/app_theme.dart';
import 'package:anonymoke/features/onboarding/application/about_you_validation.dart';
import 'package:anonymoke/features/onboarding/application/onboarding_controller.dart';
import 'package:anonymoke/features/onboarding/application/photo_controller.dart';
import 'package:anonymoke/features/onboarding/application/consent_documents.dart';
import 'package:image_picker/image_picker.dart';
import 'package:anonymoke/features/home/presentation/profile_device.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'discover_live_test.dart' show MemoryStore;

class OnboardingAuth extends AuthController {
  static Session session(String id) => Session(
    userId: id,
    accessToken: id,
    refreshToken: 'refresh',
    accessExpiresAt: DateTime(2027),
    refreshExpiresAt: DateTime(2027),
    isOnboarded: false,
  );
  @override
  AuthState build() => AuthState(session: session('owner-a'));
  void switchAccount() => state = AuthState(session: session('owner-b'));
}

class OnboardingApi extends ApiClient {
  OnboardingApi()
    : super(store: MemoryStore(), baseUrl: 'https://api.test/api/v1');
  final calls = <String>[];
  final profiles = <Map<String, dynamic>>[];
  final preferences = <List<String>>[];
  final consentWrites = <Map<String, dynamic>>[];
  Completer<void>? firstConsent;
  @override
  Future<void> recordConsent({
    required String type,
    required String version,
    required bool granted,
  }) async {
    calls.add('consent:$type');
    consentWrites.add({'type': type, 'version': version, 'granted': granted});
    if (calls.length == 1) await firstConsent?.future;
  }

  @override
  Future<void> updateProfile(Map<String, dynamic> values) async {
    calls.add('profile');
    profiles.add(Map.of(values));
  }

  @override
  Future<void> updatePreferences(List<String> values) async {
    calls.add('preferences');
    preferences.add(List.of(values));
  }
}

Uint8List fixturePixel() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jN1sAAAAASUVORK5CYII=',
);

class ReadyPhotoDraft extends PhotoDraft {
  ReadyPhotoDraft()
    : super(privateBytes: fixturePixel(), blurredBytes: fixturePixel());
  @override
  Future<MediaAssetSummary> validateOnServer(
    ApiClient api, {
    required void Function() checkCurrent,
    required Future<void> Function(Duration) delay,
  }) async {
    checkCurrent();
    return const MediaAssetSummary(
      id: '00000000-0000-4000-8000-000000000001',
      kind: 'avatar',
      status: 'ready',
    );
  }
}

class ReadyPhotoController extends OnboardingPhotoController {
  @override
  OnboardingPhotoState build() {
    super.build();
    return ref.read(authControllerProvider).session?.userId == 'owner-a'
        ? OnboardingPhotoState(draft: ReadyPhotoDraft(), saved: true)
        : const OnboardingPhotoState();
  }
}

void seedValid(OnboardingController controller) {
  controller.setAlias('My own alias');
  controller.setGender('W');
  controller.setBirthDate('14 / 03 / 1999');
  controller.setHeight('168');
  controller.setTermsConsent(true);
  controller.setPrivacyConsent(true);
  controller.setSensitiveConsent(true);
  controller.setLocationConsent(true);
  controller.setTargetGenders(['ALL']);
}

ProviderContainer containerFor(
  ApiClient api, {
  ProfileDevice Function()? device,
  ProfilePlayer Function()? player,
  bool readyPhoto = true,
  Future<PhotoDraft> Function(XFile)? prepare,
  Future<void> Function(Duration)? photoDelay,
  ConsentDocuments documents = const ConsentDocuments(
    termsUrl: 'https://legal.test/terms',
    privacyUrl: 'https://legal.test/privacy',
    version: 'test-2026-11',
  ),
  Future<bool> Function(Uri)? documentLauncher,
}) => ProviderContainer(
  overrides: [
    apiClientProvider.overrideWithValue(api),
    authControllerProvider.overrideWith(OnboardingAuth.new),
    consentDocumentsProvider.overrideWithValue(documents),
    if (documentLauncher != null)
      consentDocumentLauncherProvider.overrideWithValue(documentLauncher),
    onboardingTodayProvider.overrideWithValue(() => DateTime(2026, 11, 15)),
    if (device != null) profileDeviceProvider.overrideWithValue(device),
    if (player != null) profilePlayerProvider.overrideWithValue(player),
    if (readyPhoto)
      onboardingPhotoProvider.overrideWith(ReadyPhotoController.new),
    if (prepare != null) photoPreparerProvider.overrideWithValue(prepare),
    if (photoDelay != null)
      photoPollDelayProvider.overrideWithValue(photoDelay),
  ],
);

Future<(ProviderContainer, OnboardingApi, GoRouter)> openAbout(
  WidgetTester tester, {
  bool valid = true,
  double width = 390,
  double scale = 1,
  double keyboard = 0,
  ProfileDevice Function()? device,
  ProfilePlayer Function()? player,
  OnboardingApi? apiOverride,
  bool readyPhoto = true,
  Future<PhotoDraft> Function(XFile)? prepare,
  Future<void> Function(Duration)? photoDelay,
  ConsentDocuments documents = const ConsentDocuments(
    termsUrl: 'https://legal.test/terms',
    privacyUrl: 'https://legal.test/privacy',
    version: 'test-2026-11',
  ),
  Future<bool> Function(Uri)? documentLauncher,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  final api = apiOverride ?? OnboardingApi();
  final container = containerFor(
    api,
    device: device,
    player: player,
    readyPhoto: readyPhoto,
    prepare: prepare,
    photoDelay: photoDelay,
    documents: documents,
    documentLauncher: documentLauncher,
  );
  final controller = container.read(onboardingControllerProvider.notifier);
  controller.setAlias('');
  controller.setGender('');
  controller.setBirthDate(null);
  controller.setHeight('');
  if (valid) seedValid(controller);
  final router = container.read(routerProvider);
  router.go('/onboarding/1');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    container.dispose();
    tester.view.reset();
  });
  return (container, api, router);
}

Future<void> continueAbout(WidgetTester tester) async {
  await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Continue'));
  await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
  await tester.pumpAndSettle();
}

String fieldText(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

void main() {
  test(
    'dates reject calendar rollover and use the actual eighteenth birthday',
    () {
      expect(AboutYouValidation.parseDate('31 / 02 / 1999'), isNull);
      expect(AboutYouValidation.parseDate('29 / 02 / 1999'), isNull);
      expect(
        AboutYouValidation.parseDate('29 / 02 / 2000'),
        DateTime(2000, 2, 29),
      );
      expect(AboutYouValidation.parseDate('2000-02-31'), isNull);
      expect(
        AboutYouValidation.dateError('2008-11-15', DateTime(2026, 11, 15)),
        isNull,
      );
      expect(
        AboutYouValidation.dateError('2008-11-16', DateTime(2026, 11, 15)),
        contains('18 or older'),
      );
      expect(
        AboutYouValidation.dateError('2027-01-01', DateTime(2026, 11, 15)),
        contains('future'),
      );
      expect(
        AboutYouValidation.dateError('1925-11-16', DateTime(2026, 11, 15)),
        isNull,
      );
      expect(
        AboutYouValidation.dateError('1925-11-15', DateTime(2026, 11, 15)),
        contains('100'),
      );
      expect(
        AboutYouValidation.age(DateTime(2008, 2, 29), DateTime(2026, 2, 28)),
        17,
      );
      expect(
        AboutYouValidation.age(DateTime(2008, 2, 29), DateTime(2026, 3, 1)),
        18,
      );
    },
  );

  testWidgets('blank form stays on step one and does not send personal data', (
    tester,
  ) async {
    final (_, api, router) = await openAbout(tester, valid: false);
    await continueAbout(tester);
    expect(find.text('Choose your gender.'), findsOneWidget);
    expect(find.textContaining('characters for your alias'), findsOneWidget);
    expect(find.text('Enter a valid date as DD / MM / YYYY.'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/onboarding/1');
    expect(api.calls, isEmpty);
  });

  testWidgets(
    'computed age appears inside DOB only and helper has no hardcoded age',
    (tester) async {
      await openAbout(tester);
      expect(find.text('Age 27'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('about-birth-date')),
          matching: find.text('Age 27'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'You must be 18 or older. Others see your age, never your birthday.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'users type their own alias and Shuffle offers a different valid name',
    (tester) async {
      final (container, _, _) = await openAbout(tester);
      await tester.enterText(
        find.byKey(const Key('about-alias')),
        'Starry Soul',
      );
      expect(container.read(onboardingControllerProvider).alias, 'Starry Soul');
      await tester.tap(find.text('Shuffle'));
      await tester.pump();
      final first = fieldText(tester, 'about-alias');
      expect(first, isNot('Starry Soul'));
      expect(AboutYouValidation.aliasError(first), isNull);
      expect(first, matches(RegExp(r'^[A-Za-z]+ [A-Za-z]+ \d{4}$')));
      await tester.tap(find.text('Shuffle'));
      await tester.pump();
      expect(fieldText(tester, 'about-alias'), isNot(first));
    },
  );

  testWidgets('one-character alias cannot advance', (tester) async {
    final (_, _, router) = await openAbout(tester);
    await tester.enterText(find.byKey(const Key('about-alias')), 'a');
    await continueAbout(tester);
    expect(find.textContaining('characters for your alias'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/onboarding/1');
  });

  testWidgets('gender is required even when all other fields are valid', (
    tester,
  ) async {
    final (container, _, router) = await openAbout(tester, valid: false);
    await tester.enterText(
      find.byKey(const Key('about-alias')),
      'My own alias',
    );
    await tester.enterText(
      find.byKey(const Key('about-birth-date')),
      '14/03/1999',
    );
    await continueAbout(tester);
    expect(find.text('Choose your gender.'), findsOneWidget);
    expect(container.read(onboardingControllerProvider).gender, '');
    expect(router.routeInformationProvider.value.uri.path, '/onboarding/1');
  });

  for (final date in [
    '31/02/1999',
    '29/02/1999',
    '16/11/2008',
    '01/01/2027',
    '15/11/1925',
  ]) {
    testWidgets('invalid or ineligible DOB $date cannot advance', (
      tester,
    ) async {
      final (_, api, router) = await openAbout(tester);
      await tester.enterText(find.byKey(const Key('about-birth-date')), date);
      await continueAbout(tester);
      expect(router.routeInformationProvider.value.uri.path, '/onboarding/1');
      expect(api.calls, isEmpty);
      if (date == '31/02/1999' || date == '29/02/1999') {
        expect(find.textContaining('Age '), findsNothing);
      }
    });
  }

  testWidgets(
    'exactly eighteen can continue without transmitting DOB before consent',
    (tester) async {
      final (container, api, router) = await openAbout(tester);
      await tester.enterText(
        find.byKey(const Key('about-birth-date')),
        '15/11/2008',
      );
      await continueAbout(tester);
      expect(router.routeInformationProvider.value.uri.path, '/onboarding/2');
      expect(
        container.read(onboardingControllerProvider).birthDate,
        '2008-11-15',
      );
      expect(api.calls, isEmpty);
    },
  );

  for (final height in ['99', '251']) {
    testWidgets('out-of-range height $height cannot advance', (tester) async {
      final (_, _, router) = await openAbout(tester);
      await tester.enterText(find.byKey(const Key('about-height')), height);
      await continueAbout(tester);
      expect(
        find.text('Enter a height between 100 and 250 cm.'),
        findsOneWidget,
      );
      expect(router.routeInformationProvider.value.uri.path, '/onboarding/1');
    });
  }

  testWidgets(
    'optional height clears correctly and back navigation restores the draft',
    (tester) async {
      final (container, api, router) = await openAbout(tester);
      await tester.enterText(
        find.byKey(const Key('about-alias')),
        'My custom name',
      );
      await tester.enterText(find.byKey(const Key('about-height')), '');
      await continueAbout(tester);
      expect(router.routeInformationProvider.value.uri.path, '/onboarding/2');
      expect(container.read(onboardingControllerProvider).heightCm, isNull);
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'about-alias'), 'My custom name');
      expect(fieldText(tester, 'about-birth-date'), '14 / 03 / 1999');
      expect(fieldText(tester, 'about-height'), '');
      expect(container.read(onboardingControllerProvider).gender, 'W');
      expect(api.calls, isEmpty);
    },
  );

  testWidgets(
    'DOB picker limits dates to adults and cancel preserves the typed value',
    (tester) async {
      await openAbout(tester);
      await tester.tap(find.byTooltip('Choose date of birth'));
      await tester.pumpAndSettle();
      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(picker.firstDate, DateTime(1925, 11, 16));
      expect(picker.lastDate, DateTime(2008, 11, 15));
      expect(picker.initialDate, DateTime(1999, 3, 14));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'about-birth-date'), '14 / 03 / 1999');
    },
  );

  testWidgets(
    'switching accounts removes the previous private draft from the form',
    (tester) async {
      final (container, _, _) = await openAbout(tester);
      (container.read(authControllerProvider.notifier) as OnboardingAuth)
          .switchAccount();
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'about-alias'), '');
      expect(container.read(onboardingControllerProvider).alias, '');
      expect(
        fieldText(tester, 'about-birth-date'),
        AboutYouValidation.displayDate(const OnboardingState().birthDate),
      );
    },
  );

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets(
      'small screen at text scale $scale can scroll to Continue with keyboard open',
      (tester) async {
        await openAbout(tester, width: 320, scale: scale, keyboard: 300);
        await tester.enterText(
          find.byKey(const Key('about-alias')),
          'Quiet Moon',
        );
        await tester.pumpAndSettle();
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

  test(
    'final submission revalidates step one and makes no writes for invalid draft',
    () async {
      final api = OnboardingApi();
      final container = containerFor(api);
      addTearDown(container.dispose);
      final controller = container.read(onboardingControllerProvider.notifier);
      seedValid(controller);
      controller.setBirthDate('31/02/1999');
      await expectLater(
        controller.complete(),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'profile_required'),
        ),
      );
      expect(api.calls, isEmpty);
    },
  );

  test(
    'canonical date and explicit null height are saved only after final consent',
    () async {
      final api = OnboardingApi();
      final container = containerFor(api);
      addTearDown(container.dispose);
      final controller = container.read(onboardingControllerProvider.notifier);
      seedValid(controller);
      controller.setHeight('');
      await controller.complete();
      expect(api.calls, [
        'consent:terms',
        'consent:privacy',
        'consent:sensitive_data',
        'consent:location',
        'consent:voice',
        'profile',
      ]);
      expect(api.profiles.single['birth_date'], '1999-03-14');
      expect(api.profiles.single.containsKey('height_cm'), isTrue);
      expect(api.profiles.single['height_cm'], isNull);
    },
  );

  test(
    'an account switch during saving prevents remaining writes and stale draft updates',
    () async {
      final api = OnboardingApi()..firstConsent = Completer<void>();
      final container = containerFor(api);
      addTearDown(container.dispose);
      final controller = container.read(onboardingControllerProvider.notifier);
      seedValid(controller);
      final saving = controller.complete();
      final expectation = expectLater(
        saving,
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'session_changed'),
        ),
      );
      (container.read(authControllerProvider.notifier) as OnboardingAuth)
          .switchAccount();
      api.firstConsent!.complete();
      await expectation;
      expect(api.calls, ['consent:terms']);
      expect(container.read(onboardingControllerProvider).alias, '');
      expect(container.read(onboardingControllerProvider).isSaving, isFalse);
      expect(container.read(onboardingControllerProvider).error, isNull);
    },
  );

  test(
    'duplicate final submissions cannot create duplicate requests',
    () async {
      final api = OnboardingApi()..firstConsent = Completer<void>();
      final container = containerFor(api);
      addTearDown(container.dispose);
      final controller = container.read(onboardingControllerProvider.notifier);
      seedValid(controller);
      final saving = controller.complete();
      final duplicate = controller.complete();
      expect(identical(saving, duplicate), isTrue);
      expect(api.calls, ['consent:terms']);
      api.firstConsent!.complete();
      await Future.wait([saving, duplicate]);
      expect(api.profiles, hasLength(1));
      expect(api.preferences, isEmpty);
    },
  );
}
