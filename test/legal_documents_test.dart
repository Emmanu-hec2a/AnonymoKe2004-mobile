import 'package:anonymoke/app.dart';
import 'package:anonymoke/core/theme/app_theme.dart';
import 'package:anonymoke/features/home/presentation/profile_sheets.dart';
import 'package:anonymoke/features/home/presentation/reference_tabs.dart';
import 'package:anonymoke/features/legal/domain/legal_document.dart';
import 'package:anonymoke/features/legal/presentation/legal_document_screen.dart';
import 'package:anonymoke/features/onboarding/application/consent_documents.dart';
import 'package:anonymoke/features/onboarding/application/onboarding_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'onboarding_about_you_test.dart' as onboarding;
import 'profile_live_test.dart' as profile;

class RetryBundle extends CachingAssetBundle {
  bool fail = true;

  @override
  Future<String> loadString(String key, {bool cache = true}) {
    if (fail) return Future.error(StateError('asset_unavailable'));
    return rootBundle.loadString(key);
  }

  @override
  Future<ByteData> load(String key) => rootBundle.load(key);
}

class ConsentTrackingApi extends profile.ProfileApi {
  final consentWrites = <String>[];

  @override
  Future<void> recordConsent({
    required String type,
    required String version,
    required bool granted,
  }) async {
    consentWrites.add(type);
    await super.recordConsent(type: type, version: version, granted: granted);
  }
}

Future<void> settleLegal(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() async {
    for (final kind in LegalDocumentKind.values) {
      await rootBundle.loadString(kind.assetPath);
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('bundled documents have a matching bounded consent revision', () {
    const documents = ConsentDocuments.bundled();
    expect(documents.isConfigured, isTrue);
    expect(documents.version, '2026-11-16');
    expect(documents.terms, Uri(path: '/legal/terms'));
    expect(documents.privacy, Uri(path: '/legal/privacy'));
    expect(
      const ConsentDocuments(
        termsUrl: '/legal/terms',
        privacyUrl: '/legal/privacy',
        version: 'older-revision',
      ).isConfigured,
      isFalse,
    );
    for (final url in ['/legal/unknown', '/legal/terms?redirect=elsewhere']) {
      expect(
        ConsentDocuments(
          termsUrl: url,
          privacyUrl: '/legal/privacy',
          version: LegalDocumentKind.version,
        ).isConfigured,
        isFalse,
      );
    }
  });

  for (final kind in LegalDocumentKind.values) {
    test('bundled ${kind.title} retains every paragraph and section', () async {
      final source = await rootBundle.loadString(kind.assetPath);
      final document = LegalDocumentContent.parse(kind, source);
      expect(document.sections.length, kind.sectionCount);
      final bodyLines = source
          .split('\n')
          .skip(2)
          .map((line) => line.trim())
          .where(
            (line) =>
                line.isNotEmpty &&
                !line.startsWith('Effective Date:') &&
                !line.startsWith('Last Updated:'),
          );
      expect(document.blocks.map((block) => block.text), bodyLines);
      expect(source, isNot(contains('\u200b')));
      expect(source, isNot(contains('\ufffd')));
      if (kind == LegalDocumentKind.terms) {
        expect(source, contains('legal@anonymoke.co.ke'));
        expect(document.sections.last.text, '11. Contact Information');
      } else {
        expect(source, contains('privacy@anonymoke.co.ke'));
        expect(source, contains('Last Updated: November 16, 2026'));
        expect(
          document.sections.last.text,
          '8. Your Rights Under the Kenya Data Protection Act',
        );
      }
    });
  }

  testWidgets(
    'signed-out auth opens bundled policies without an external browser',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            consentDocumentsProvider.overrideWithValue(
              const ConsentDocuments.bundled(),
            ),
            consentDocumentLauncherProvider.overrideWithValue(
              (_) async => throw StateError('External launch is not expected'),
            ),
          ],
          child: const AnonymoKEApp(),
        ),
      );
      await settleLegal(tester);
      for (final label in ['Terms', 'Privacy Policy']) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await settleLegal(tester);
        expect(find.byType(LegalDocumentScreen), findsOneWidget);
        expect(find.text('Effective Date: November 16, 2026'), findsOneWidget);
        await tester.tap(find.byKey(const Key('legal-back')));
        await settleLegal(tester);
        expect(find.text('Send magic link'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'onboarding policy reading preserves the draft and leaves consent unchecked',
    (tester) async {
      final (container, api, router) = await onboarding.openAbout(
        tester,
        documents: const ConsentDocuments.bundled(),
      );
      final controller = container.read(onboardingControllerProvider.notifier);
      controller.setLegalConsent(false);
      final alias = container.read(onboardingControllerProvider).alias;
      router.go('/onboarding/5');
      await settleLegal(tester);
      for (final name in ['terms', 'privacy']) {
        final link = find.byKey(Key('consent-$name-link'));
        await tester.ensureVisible(link);
        await tester.tap(link);
        await settleLegal(tester);
        expect(find.byType(LegalDocumentScreen), findsOneWidget);
        await tester.tap(find.byKey(const Key('legal-back')));
        await settleLegal(tester);
      }
      final draft = container.read(onboardingControllerProvider);
      expect(draft.alias, alias);
      expect(draft.termsConsent, isFalse);
      expect(draft.privacyConsent, isFalse);
      expect(api.calls, isEmpty);
    },
  );

  test(
    'onboarding sends the bundled document revision on explicit acceptance',
    () async {
      final api = onboarding.OnboardingApi();
      final container = onboarding.containerFor(
        api,
        documents: const ConsentDocuments.bundled(),
      );
      addTearDown(container.dispose);
      onboarding.seedValid(
        container.read(onboardingControllerProvider.notifier),
      );
      await container.read(onboardingControllerProvider.notifier).complete();
      expect(api.consentWrites, hasLength(5));
      expect(
        api.consentWrites.every((item) => item['version'] == '2026-11-16'),
        isTrue,
      );
    },
  );

  testWidgets('Profile policies open without changing consent records', (
    tester,
  ) async {
    final api = ConsentTrackingApi();
    await profile.open(tester, api);
    await profile.tap(tester, 'Privacy and consents');
    expect(find.byType(ProfileConsentSheet), findsOneWidget);
    await tester.tap(find.byKey(const Key('policy-privacy-link')));
    await settleLegal(tester);
    expect(find.byType(LegalDocumentScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('legal-back')));
    await settleLegal(tester);
    expect(find.byType(ProfileConsentSheet), findsOneWidget);
    expect(api.consentWrites, isEmpty);
  });

  testWidgets('Demo Profile also exposes the supplied policies', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: ReferenceProfileScreen()),
        ),
      ),
    );
    await settleLegal(tester);
    await tester.ensureVisible(find.text('Privacy and consents'));
    await tester.tap(find.text('Privacy and consents'));
    await settleLegal(tester);
    await tester.tap(find.byKey(const Key('policy-terms-link')));
    await settleLegal(tester);
    expect(find.byType(LegalDocumentScreen), findsOneWidget);
    expect(find.text('ANONYMOKE TERMS OF USE'), findsOneWidget);
  });

  testWidgets('missing document shows a recoverable error', (tester) async {
    final bundle = RetryBundle();
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: bundle,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const LegalDocumentScreen(document: LegalDocumentKind.privacy),
        ),
      ),
    );
    await settleLegal(tester);
    expect(
      find.text('Could not load this document. Try again.'),
      findsOneWidget,
    );
    bundle.fail = false;
    await tester.tap(find.text('Try again'));
    await settleLegal(tester);
    expect(find.text('ANONYMOKE PRIVACY POLICY'), findsOneWidget);
    expect(find.byKey(const Key('legal-contents')), findsOneWidget);
  });

  for (final kind in LegalDocumentKind.values) {
    testWidgets(
      '${kind.title} remains readable at narrow width and large text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: LegalDocumentScreen(document: kind),
          ),
        );
        await settleLegal(tester);
        expect(find.byKey(const Key('legal-body')), findsOneWidget);
        await tester.tap(find.byKey(const Key('legal-contents')));
        await settleLegal(tester);
        final last = kind == LegalDocumentKind.terms
            ? '11. Contact Information'
            : '8. Your Rights Under the Kenya Data Protection Act';
        final section = find.widgetWithText(ListTile, last);
        await tester.scrollUntilVisible(
          section,
          400,
          scrollable: find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(section);
        await settleLegal(tester);
        expect(find.text('Contents'), findsNothing);
        expect(find.text(last).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
