import 'dart:async';
import 'dart:convert';

import 'package:anonymoke/app.dart';
import 'package:anonymoke/core/auth/auth_controller.dart';
import 'package:anonymoke/core/auth/magic_link_intent.dart';
import 'package:anonymoke/core/auth/session.dart';
import 'package:anonymoke/core/auth/social_authenticator.dart';
import 'package:anonymoke/core/config/build_config.dart';
import 'package:anonymoke/core/network/api_client.dart';
import 'package:anonymoke/core/routing/app_router.dart';
import 'package:anonymoke/core/storage/session_store.dart';
import 'package:anonymoke/core/theme/app_theme.dart';
import 'package:anonymoke/features/auth/presentation/auth_screen.dart';
import 'package:anonymoke/features/onboarding/application/consent_documents.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'discover_live_test.dart' show Adapter;

const linkToken = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG';
const anotherToken = 'anotherOneTimeLinkToken0123456789ABCDEF';
final authNow = DateTime.utc(2026, 11, 15, 12);
Session authSession({String owner = 'owner', bool onboarded = false}) =>
    Session(
      userId: owner,
      accessToken: 'access-$owner',
      refreshToken: 'refresh-$owner',
      accessExpiresAt: authNow.add(const Duration(hours: 1)),
      refreshExpiresAt: authNow.add(const Duration(days: 30)),
      isOnboarded: onboarded,
    );

class AuthStore extends SessionStore {
  AuthStore() : super(const FlutterSecureStorage());
  Session? saved;
  Completer<void>? saveWait;
  bool failSave = false;
  int saves = 0, clears = 0;
  @override
  Future<String?> accessToken() async => saved?.accessToken;
  @override
  Future<String?> refreshToken() async => saved?.refreshToken;
  @override
  Future<void> saveSession(Session session) async {
    saves++;
    await saveWait?.future;
    saved = session;
    if (failSave) throw StateError('secure store write failed');
  }

  @override
  Future<void> clear() async {
    clears++;
    saved = null;
  }
}

class Social extends SocialAuthenticator {
  final calls = <String>[];
  String? error;
  Completer<void>? wait;
  bool appleAvailable = true;
  @override
  bool get supportsGoogle => true;
  @override
  bool get supportsApple => appleAvailable;
  @override
  Future<String> credential(String provider) async {
    calls.add(provider);
    await wait?.future;
    if (error != null) throw ApiException(error!);
    return 'native-$provider-id-token';
  }
}

class AuthApi extends ApiClient {
  AuthApi(AuthStore store)
    : super(store: store, baseUrl: 'https://api.test/api/v1');
  final emails = <String>[], tokens = <String>[];
  final credentials = <Map<String, String>>[];
  Session result = authSession();
  Completer<void>? requestWait, verifyWait, restoreWait;
  String? requestError, verifyError, restoreError;
  int restores = 0;
  MagicLinkDelivery delivery = const MagicLinkDelivery();
  @override
  Future<MagicLinkDelivery> requestMagicLink(String email) async {
    emails.add(email);
    await requestWait?.future;
    if (requestError != null) throw ApiException(requestError!);
    return delivery;
  }

  @override
  Future<Session> verifyMagicLink(String token) async {
    tokens.add(token);
    await verifyWait?.future;
    if (verifyError != null) throw ApiException(verifyError!);
    return result;
  }

  @override
  Future<Session> verifySocialCredential({
    required String provider,
    required String credential,
  }) async {
    credentials.add({'provider': provider, 'credential': credential});
    if (verifyError != null) throw ApiException(verifyError!);
    return result;
  }

  @override
  Future<Session> refreshSessionForRestore() async {
    restores++;
    await restoreWait?.future;
    if (restoreError != null) throw ApiException(restoreError!);
    return result;
  }

  @override
  Future<void> logout(String refreshToken) async {}
}

class DeferredAuthAdapter implements HttpClientAdapter {
  final started = Completer<void>();
  final response = Completer<ResponseBody>();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    started.complete();
    return response.future;
  }

  @override
  void close({bool force = false}) {}
}

class AuthHarness {
  AuthHarness() {
    api = AuthApi(store);
    container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        sessionStoreProvider.overrideWithValue(store),
        socialAuthenticatorProvider.overrideWithValue(social),
        authClockProvider.overrideWithValue(() => now),
        pushNotificationServiceProvider.overrideWith(
          (_) => throw StateError('Push unavailable'),
        ),
        consentDocumentsProvider.overrideWithValue(
          const ConsentDocuments(
            termsUrl: 'https://legal.test/terms',
            privacyUrl: 'https://legal.test/privacy',
            version: 'v1',
          ),
        ),
        consentDocumentLauncherProvider.overrideWithValue((_) async => true),
      ],
    );
  }
  final store = AuthStore();
  final social = Social();
  DateTime now = authNow;
  late final AuthApi api;
  late final ProviderContainer container;
  AuthController get controller =>
      container.read(authControllerProvider.notifier);
  AuthState get state => container.read(authControllerProvider);
}

GoRouter authRouter({String initial = '/auth'}) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
    GoRoute(
      path: '/auth/verify',
      builder: (_, _) => const MagicLinkVerifyScreen(),
    ),
    GoRoute(
      path: '/onboarding/1',
      builder: (_, _) => const Scaffold(body: Text('Onboarding destination')),
    ),
    GoRoute(
      path: '/app/discover',
      builder: (_, _) => const Scaffold(body: Text('Discover destination')),
    ),
    GoRoute(
      path: '/away',
      builder: (_, _) => const Scaffold(body: Text('Another screen')),
    ),
  ],
);

Future<(AuthHarness, GoRouter)> openAuth(
  WidgetTester tester, {
  AuthHarness? harness,
  double scale = 1,
  double width = 390,
  double keyboard = 0,
  String initial = '/auth',
}) async {
  final h = harness ?? AuthHarness();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  final router = authRouter(initial: initial);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: h.container,
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
    h.container.dispose();
    tester.view.reset();
  });
  return (h, router);
}

Future<void> tapAuth(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'Google SDK cancellation has visible feedback because configuration failures share that code',
    () {
      expect(
        googleSignInFailureCode(GoogleSignInExceptionCode.canceled),
        'google_sign_in_incomplete',
      );
      expect(
        authErrorMessage(
          googleSignInFailureCode(GoogleSignInExceptionCode.canceled),
        ),
        'Google sign-in was not completed. Try again or use email.',
      );
      expect(
        googleSignInFailureCode(
          GoogleSignInExceptionCode.clientConfigurationError,
        ),
        'provider_not_configured',
      );
    },
  );

  testWidgets(
    'Google account-picker failure is visible and a successful retry can sign in',
    (tester) async {
      final h = AuthHarness();
      h.social.error = 'google_sign_in_incomplete';
      await openAuth(tester, harness: h);
      await tapAuth(tester, 'auth-google');
      expect(
        find.text('Google sign-in was not completed. Try again or use email.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('auth-error')), findsOneWidget);
      expect(h.api.credentials, isEmpty);
      expect(h.store.saved, isNull);
      expect(h.state.isLoading, isFalse);
      h.social.error = null;
      await tapAuth(tester, 'auth-google');
      expect(find.text('Onboarding destination'), findsOneWidget);
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'returning to sign-in validates an existing in-memory session',
    () async {
      final h = AuthHarness();
      addTearDown(h.container.dispose);
      await h.controller.verifyMagicLink(linkToken);
      h.api.restoreError = 'refresh_token_invalid';
      expect(await h.controller.restoreSession(), isNull);
      expect(h.state.session, isNull);
      expect(h.store.saved, isNull);
    },
  );
  for (final replacingAccount in [false, true]) {
    test(
      'a background refresh cannot overwrite ${replacingAccount ? "a new login" : "logout"}',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        final store = SessionStore(const FlutterSecureStorage());
        await store.saveSession(authSession());
        final api = ApiClient(store: store, baseUrl: 'https://api.test/api/v1');
        final adapter = DeferredAuthAdapter();
        api.dio.httpClientAdapter = adapter;
        final refreshing = api.refreshSession();
        final check = expectLater(
          refreshing,
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              'auth_operation_cancelled',
            ),
          ),
        );
        await adapter.started.future;
        if (replacingAccount) {
          await store.saveSession(authSession(owner: 'new-account'));
        } else {
          await store.clear();
        }
        final old = authSession();
        adapter.response.complete(
          ResponseBody.fromString(
            jsonEncode({
              'user_id': old.userId,
              'access_token': old.accessToken,
              'refresh_token': old.refreshToken,
              'access_expires_at': old.accessExpiresAt.toIso8601String(),
              'refresh_expires_at': old.refreshExpiresAt.toIso8601String(),
              'is_onboarded': false,
            }),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          ),
        );
        await check;
        expect(
          await store.refreshToken(),
          replacingAccount ? 'refresh-new-account' : null,
        );
      },
    );
  }
  test('emails are validated before any request', () async {
    final h = AuthHarness();
    addTearDown(h.container.dispose);
    for (final email in [
      '',
      'word',
      'person@',
      'a@@mail.com',
      'a b@mail.com',
    ]) {
      await expectLater(
        h.controller.requestMagicLink(email),
        throwsA(isA<ApiException>()),
      );
    }
    expect(h.api.emails, isEmpty);
    expect(authEmailError('person+test@gmail.com'), isNull);
  });

  test(
    'request normalization, configured cooldown and expiry are preserved',
    () async {
      final h = AuthHarness();
      addTearDown(h.container.dispose);
      h.api.delivery = const MagicLinkDelivery(
        resendAfterSeconds: 90,
        expiresInSeconds: 300,
      );
      await h.controller.requestMagicLink('  Person@Example.com  ');
      expect(h.api.emails, ['person@example.com']);
      expect(h.state.resendSeconds(h.now), 90);
      expect(h.state.linkExpiresSeconds, 300);
      await expectLater(
        h.controller.requestMagicLink('person@example.com'),
        throwsA(isA<ApiException>()),
      );
      h.now = h.now.add(const Duration(seconds: 90));
      await h.controller.requestMagicLink('person@example.com');
      expect(h.api.emails, hasLength(2));
      expect(h.store.saved, isNull);
    },
  );

  test('repeated email requests cannot overlap', () async {
    final h = AuthHarness();
    addTearDown(h.container.dispose);
    h.api.requestWait = Completer<void>();
    final first = h.controller.requestMagicLink('person@example.com');
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      h.controller.requestMagicLink('other@example.com'),
      throwsA(isA<ApiException>()),
    );
    h.api.requestWait!.complete();
    await first;
    expect(h.api.emails, ['person@example.com']);
  });

  for (final provider in ['google', 'apple', 'email']) {
    test(
      '$provider accepts only the backend session and saves it securely',
      () async {
        final h = AuthHarness();
        addTearDown(h.container.dispose);
        h.api.result = authSession(owner: provider, onboarded: true);
        final result = provider == 'email'
            ? await h.controller.verifyMagicLink(linkToken)
            : await h.controller.signInWithSocial(provider);
        expect(result.userId, provider);
        expect(h.store.saved, same(result));
        expect(h.state.session!.isOnboarded, isTrue);
        expect(h.state.isLoading, isFalse);
        if (provider != 'email') {
          expect(h.api.credentials.single, {
            'provider': provider,
            'credential': 'native-$provider-id-token',
          });
        }
      },
    );
  }

  test(
    'native cancellation does not call the backend or create a session',
    () async {
      final h = AuthHarness();
      addTearDown(h.container.dispose);
      h.social.error = 'sign_in_cancelled';
      await expectLater(
        h.controller.signInWithSocial('google'),
        throwsA(isA<ApiException>()),
      );
      expect(h.api.credentials, isEmpty);
      expect(h.store.saved, isNull);
      expect(h.state.isLoading, isFalse);
      expect(authErrorMessage(h.state.error), isEmpty);
    },
  );

  test('a failed credential never creates a local session', () async {
    final h = AuthHarness();
    addTearDown(h.container.dispose);
    h.api.verifyError = 'social_token_invalid';
    await expectLater(
      h.controller.signInWithSocial('apple'),
      throwsA(isA<ApiException>()),
    );
    expect(h.store.saved, isNull);
    expect(h.state.session, isNull);
  });

  test(
    'a late sign-in response after logout cannot resurrect the session',
    () async {
      final h = AuthHarness();
      addTearDown(h.container.dispose);
      h.api.verifyWait = Completer<void>();
      final signingIn = h.controller.verifyMagicLink(linkToken);
      final check = expectLater(signingIn, throwsA(isA<ApiException>()));
      await Future<void>.delayed(Duration.zero);
      await h.controller.logout();
      h.api.verifyWait!.complete();
      await check;
      expect(h.store.saved, isNull);
      expect(h.state.session, isNull);
    },
  );

  test('logout is ordered after an in-flight secure write', () async {
    final h = AuthHarness();
    addTearDown(h.container.dispose);
    h.store.saveWait = Completer<void>();
    final signingIn = h.controller.verifyMagicLink(linkToken);
    final check = expectLater(signingIn, throwsA(isA<ApiException>()));
    await Future<void>.delayed(Duration.zero);
    expect(h.store.saves, 1);
    final loggingOut = h.controller.logout();
    h.store.saveWait!.complete();
    await Future.wait([check, loggingOut]);
    expect(h.store.saved, isNull);
    expect(h.state.session, isNull);
  });

  test(
    'storage failure clears a partial write and cannot report success',
    () async {
      final h = AuthHarness();
      addTearDown(h.container.dispose);
      h.store.failSave = true;
      await expectLater(
        h.controller.verifyMagicLink(linkToken),
        throwsA(isA<ApiException>()),
      );
      expect(h.store.saved, isNull);
      expect(h.state.error, 'secure_storage_unavailable');
      expect(h.state.session, isNull);
    },
  );

  test(
    'session restoration is shared and invalid refresh credentials are cleared',
    () async {
      final h = AuthHarness();
      addTearDown(h.container.dispose);
      h.store.saved = authSession();
      h.api.restoreWait = Completer<void>();
      h.api.restoreError = 'refresh_token_invalid';
      final one = h.controller.restoreSession(),
          two = h.controller.restoreSession();
      expect(identical(one, two), isTrue);
      await Future<void>.delayed(Duration.zero);
      h.api.restoreWait!.complete();
      expect(await one, isNull);
      expect(await two, isNull);
      expect(h.api.restores, 1);
      expect(h.store.saved, isNull);
    },
  );

  test(
    'logout invalidates a delayed restore before it reaches secure storage',
    () async {
      final h = AuthHarness();
      addTearDown(h.container.dispose);
      h.store.saved = authSession();
      h.api.restoreWait = Completer<void>();
      final restore = h.controller.restoreSession();
      await Future<void>.delayed(Duration.zero);
      await h.controller.logout();
      h.api.restoreWait!.complete();
      expect(await restore, isNull);
      expect(h.store.saved, isNull);
    },
  );

  test('owned HTTPS links accept fragment tokens and legacy query tokens', () {
    // Uri normalizes an explicit default HTTPS port to the same trusted origin.
    expect(
      MagicLinkIntentController.tokenFromUri(
        Uri.parse(
          'https://api.anonymoke.co.ke:443/auth/magic-link#token=$linkToken',
        ),
      ),
      linkToken,
    );
    for (final path in ['/auth/magic-link', '/auth/magic-link/']) {
      for (final separator in ['#', '?']) {
        expect(
          MagicLinkIntentController.tokenFromUri(
            Uri.parse(
              'https://api.anonymoke.co.ke$path${separator}token=$linkToken',
            ),
          ),
          linkToken,
        );
      }
    }
  });

  test('HTTPS links reject ambiguous credentials and untrusted origins', () {
    for (final uri in [
      'http://api.anonymoke.co.ke/auth/magic-link#token=$linkToken',
      'https://api.anonymoke.co.ke.evil.test/auth/magic-link#token=$linkToken',
      'https://api.anonymoke.co.ke/other#token=$linkToken',
      'https://api.anonymoke.co.ke/auth/magic-link#token=short',
      'https://api.anonymoke.co.ke/auth/magic-link#token=$linkToken&token=$anotherToken',
      'https://api.anonymoke.co.ke/auth/magic-link#token=$linkToken&next=elsewhere',
      'https://api.anonymoke.co.ke/auth/magic-link?token=$linkToken#token=$anotherToken',
      'https://api.anonymoke.co.ke/auth/magic-link?#token=$linkToken',
      'https://api.anonymoke.co.ke/auth/magic-link#token=$linkToken%0A',
      'https://api.anonymoke.co.ke/auth/magic-link#token=$linkToken%00',
      'https://user@api.anonymoke.co.ke/auth/magic-link#token=$linkToken',
      'https://api.anonymoke.co.ke:8443/auth/magic-link#token=$linkToken',
    ]) {
      expect(
        MagicLinkIntentController.tokenFromUri(Uri.parse(uri)),
        isNull,
        reason: uri,
      );
    }
  });

  test('the same token is consumed once across HTTPS and custom links', () {
    final h = AuthHarness();
    addTearDown(h.container.dispose);
    final links = h.container.read(magicLinkIntentProvider.notifier);
    expect(
      links.receive(
        Uri.parse(
          'https://api.anonymoke.co.ke/auth/magic-link#token=$linkToken',
        ),
      ),
      isTrue,
    );
    expect(links.take()?.token, linkToken);
    expect(
      links.receive(Uri.parse('anonymoke://auth/magic-link?token=$linkToken')),
      isFalse,
    );
    expect(links.take(), isNull);
  });

  test('only the expected magic-link origin and token shape are accepted', () {
    expect(
      MagicLinkIntentController.tokenFromUri(
        Uri.parse('anonymoke://auth/magic-link?token=$linkToken'),
      ),
      linkToken,
    );
    for (final uri in [
      'https://attacker.test/auth/magic-link?token=$linkToken',
      'anonymoke://other/magic-link?token=$linkToken',
      'anonymoke://auth/other?token=$linkToken',
      'anonymoke://auth/magic-link?token=short',
      'anonymoke://auth/magic-link?token=$linkToken&token=$anotherToken',
      'anonymoke://user:pass@auth/magic-link?token=$linkToken',
      'anonymoke://auth/magic-link?token=$linkToken#fragment',
    ]) {
      expect(MagicLinkIntentController.tokenFromUri(Uri.parse(uri)), isNull);
    }
  });

  test(
    'initial/stream duplicate links are consumed only once and do not stringify the secret',
    () {
      final h = AuthHarness();
      addTearDown(h.container.dispose);
      final links = h.container.read(magicLinkIntentProvider.notifier);
      final uri = Uri.parse('anonymoke://auth/magic-link?token=$linkToken');
      expect(links.receive(uri), isTrue);
      expect(links.take().toString(), isNot(contains(linkToken)));
      expect(links.receive(uri), isFalse);
      expect(links.take(), isNull);
    },
  );

  test(
    'auth API failures do not trigger token refresh or attach old Authorization',
    () async {
      final store = AuthStore()..saved = authSession();
      final api = ApiClient(store: store, baseUrl: 'https://api.test/api/v1');
      final calls = <RequestOptions>[];
      api.dio.httpClientAdapter = Adapter((request) {
        calls.add(request);
        return ResponseBody.fromString(
          jsonEncode({
            'error': {'code': 'magic_link_invalid'},
          }),
          401,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });
      await expectLater(
        api.verifyMagicLink(linkToken),
        throwsA(isA<ApiException>()),
      );
      expect(calls, hasLength(1));
      expect(calls.single.headers, isNot(contains('Authorization')));
    },
  );

  testWidgets('invalid email stays on auth and never sends a request', (
    tester,
  ) async {
    final (h, router) = await openAuth(tester);
    await tester.enterText(find.byKey(const Key('auth-email')), 'not-an-email');
    await tapAuth(tester, 'auth-send');
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/auth');
    expect(h.api.emails, isEmpty);
    expect(find.text('Magic-link token'), findsNothing);
  });

  testWidgets(
    'email request leads to a real inbox screen and resend cooldown',
    (tester) async {
      final (h, router) = await openAuth(tester);
      await tester.enterText(
        find.byKey(const Key('auth-email')),
        'person@example.com',
      );
      await tapAuth(tester, 'auth-send');
      expect(router.routeInformationProvider.value.uri.path, '/auth/verify');
      expect(find.text('person@example.com'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('auth-resend')))
            .onPressed,
        isNull,
      );
      h.now = h.now.add(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 60));
      await tapAuth(tester, 'auth-resend');
      expect(h.api.emails, hasLength(2));
    },
  );

  for (final onboarded in [false, true]) {
    testWidgets(
      'native Google login routes correctly for onboarded=$onboarded',
      (tester) async {
        final h = AuthHarness();
        h.api.result = authSession(onboarded: onboarded);
        await openAuth(tester, harness: h);
        await tapAuth(tester, 'auth-google');
        expect(
          find.text(
            onboarded ? 'Discover destination' : 'Onboarding destination',
          ),
          findsOneWidget,
        );
        expect(
          h.api.credentials.single['credential'],
          'native-google-id-token',
        );
      },
    );
  }

  testWidgets(
    'a valid link signs in without a token field or token in the route',
    (tester) async {
      final (h, router) = await openAuth(tester);
      h.container
          .read(magicLinkIntentProvider.notifier)
          .receive(Uri.parse('anonymoke://auth/magic-link?token=$linkToken'));
      router.go('/auth/verify');
      await tester.pumpAndSettle();
      expect(h.api.tokens, [linkToken]);
      expect(find.text('Onboarding destination'), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.toString(),
        isNot(contains(linkToken)),
      );
    },
  );

  testWidgets(
    'signed-in accounts require confirmation before using another link',
    (tester) async {
      final h = AuthHarness();
      await h.controller.verifyMagicLink(linkToken);
      h.container
          .read(magicLinkIntentProvider.notifier)
          .receive(
            Uri.parse('anonymoke://auth/magic-link?token=$anotherToken'),
          );
      await openAuth(tester, harness: h, initial: '/auth/verify');
      expect(find.text('Use this sign-in link?'), findsOneWidget);
      expect(h.api.tokens, [linkToken]);
      await tester.ensureVisible(find.text('Keep current account'));
      await tester.tap(find.text('Keep current account'));
      await tester.pumpAndSettle();
      expect(h.api.tokens, [linkToken]);
      expect(h.container.read(magicLinkIntentProvider), isNull);
    },
  );

  testWidgets(
    'expired links show a recovery message without exposing provider internals',
    (tester) async {
      final h = AuthHarness();
      h.api.verifyError = 'magic_link_invalid';
      h.container
          .read(magicLinkIntentProvider.notifier)
          .receive(Uri.parse('anonymoke://auth/magic-link?token=$linkToken'));
      await openAuth(tester, harness: h, initial: '/auth/verify');
      expect(
        find.textContaining('expired or was already used'),
        findsOneWidget,
      );
      expect(find.textContaining(linkToken), findsNothing);
      expect(h.store.saved, isNull);
    },
  );

  testWidgets(
    'cancelled social login is quiet and all controls become usable again',
    (tester) async {
      final h = AuthHarness();
      h.social.error = 'sign_in_cancelled';
      await openAuth(tester, harness: h);
      await tapAuth(tester, 'auth-apple');
      expect(find.byKey(const Key('auth-error')), findsNothing);
      expect(
        tester
            .widget<ElevatedButton>(find.byKey(const Key('auth-send')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('email provider failures stay on auth with an actionable error', (
    tester,
  ) async {
    final h = AuthHarness();
    h.api.requestError = 'email_delivery_unavailable';
    final (_, router) = await openAuth(tester, harness: h);
    await tester.enterText(
      find.byKey(const Key('auth-email')),
      'person@example.com',
    );
    await tapAuth(tester, 'auth-send');
    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/auth');
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets(
      'auth remains usable at 320 width with keyboard and text scale $scale',
      (tester) async {
        await openAuth(tester, scale: scale, width: 320, keyboard: 260);
        await tester.enterText(
          find.byKey(const Key('auth-email')),
          'test@example.com',
        );
        await tester.ensureVisible(find.byKey(const Key('auth-send')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('auth-send')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Demo preview visibility follows the build flag', (tester) async {
    final (h, _) = await openAuth(tester);
    expect(
      find.byKey(const Key('auth-demo')),
      demoMode ? findsOneWidget : findsNothing,
    );
    if (demoMode) {
      await tapAuth(tester, 'auth-demo');
      expect(find.text('Onboarding destination'), findsOneWidget);
    }
    expect(h.api.emails, isEmpty);
    expect(h.store.saved, isNull);
  });

  test('native provider availability follows the platform', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final native = NativeSocialAuthenticator();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(native.supportsGoogle, isTrue);
    expect(native.supportsApple, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(native.supportsApple, isTrue);
  });

  for (final https in [false, true]) {
    testWidgets(
      'app link listener handles ${https ? "HTTPS" : "custom"} links without leaking the token to routing',
      (tester) async {
        final h = AuthHarness();
        final stream = StreamController<Uri>.broadcast();
        final router = authRouter();
        final container = ProviderContainer(
          parent: h.container,
          overrides: [
            authLinkStreamProvider.overrideWithValue(stream.stream),
            routerProvider.overrideWithValue(router),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const AnonymoKEApp(),
          ),
        );
        await tester.pumpAndSettle();
        final link = Uri.parse(
          https
              ? 'https://api.anonymoke.co.ke/auth/magic-link#token=$linkToken'
              : 'anonymoke://auth/magic-link?token=$linkToken',
        );
        stream.add(link);
        await tester.pumpAndSettle();
        stream.add(link);
        await tester.pumpAndSettle();
        expect(h.api.tokens, [linkToken]);
        expect(find.text('Onboarding destination'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(stream.close);
        router.dispose();
        container.dispose();
        h.container.dispose();
      },
    );
  }
}
