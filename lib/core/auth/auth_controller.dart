import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../network/api_client.dart';
import '../notifications/push_notification_service.dart';
import '../storage/session_store.dart';
import 'session.dart';
import 'social_authenticator.dart';

final sessionStoreProvider = Provider<SessionStore>(
  (_) => SessionStore(
    const FlutterSecureStorage(
      aOptions: AndroidOptions(migrateWithBackup: true, resetOnError: false),
    ),
  ),
);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(store: ref.watch(sessionStoreProvider)),
);

final pushNotificationServiceProvider = Provider<PushNotificationService>(
  (ref) => PushNotificationService(
    ref.watch(apiClientProvider),
    canRegister: () =>
        ref.mounted && ref.read(authControllerProvider).session != null,
  ),
);

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

final authClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

enum AuthAction { restore, email, verify, google, apple, logout }

const _unchanged = Object();

class AuthState {
  const AuthState({
    this.session,
    this.isLoading = false,
    this.error,
    this.action,
    this.pendingEmail,
    this.resendAt,
    this.linkExpiresSeconds = 600,
  });
  final Session? session;
  final bool isLoading;
  final String? error, pendingEmail;
  final AuthAction? action;
  final DateTime? resendAt;
  final int linkExpiresSeconds;

  int resendSeconds(DateTime now) {
    final milliseconds = resendAt?.difference(now).inMilliseconds ?? 0;
    return milliseconds > 0 ? (milliseconds / 1000).ceil() : 0;
  }

  AuthState copyWith({
    Object? session = _unchanged,
    bool? isLoading,
    String? error,
    AuthAction? action,
    String? pendingEmail,
    DateTime? resendAt,
    int? linkExpiresSeconds,
  }) => AuthState(
    session: identical(session, _unchanged)
        ? this.session
        : session as Session?,
    isLoading: isLoading ?? this.isLoading,
    error: error,
    action: action,
    pendingEmail: pendingEmail ?? this.pendingEmail,
    resendAt: resendAt ?? this.resendAt,
    linkExpiresSeconds: linkExpiresSeconds ?? this.linkExpiresSeconds,
  );
}

String? authEmailError(String input) {
  final value = input.trim();
  if (value.isEmpty) return 'Enter your email address.';
  if (value.length > 254 ||
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
    return 'Enter a valid email address.';
  }
  return null;
}

String authErrorMessage(String? code) => switch (code) {
  'email_invalid' => 'Enter a valid email address.',
  'magic_link_invalid' =>
    'This sign-in link has expired or was already used. Request a new one.',
  'email_delivery_unavailable' || 'resend_not_configured' =>
    'Email sign-in is temporarily unavailable. Try Google or try again later.',
  'magic_link_cooldown' => 'Wait a moment before requesting another link.',
  'provider_not_configured' ||
  'provider_unavailable' ||
  'unsupported_provider' =>
    'This sign-in option is unavailable right now. Try email instead.',
  'google_sign_in_incomplete' =>
    'Google sign-in was not completed. Try again or use email.',
  'social_email_not_verified' || 'external_email_not_verified' =>
    'Use an account with a verified email address, or sign in by email.',
  'social_token_invalid' || 'social_token_missing' || 'social_sign_in_failed' =>
    'Could not finish signing in. Please try again or use email.',
  'user_not_active' =>
    'This account is unavailable. Contact support if you think this is a mistake.',
  'rate_limited' => 'Too many attempts. Wait a moment, then try again.',
  'secure_storage_unavailable' =>
    'Could not securely save your session on this device. Please try again.',
  'auth_response_invalid' =>
    'Sign-in could not be completed. Please try again later.',
  'sign_in_cancelled' || 'auth_operation_cancelled' || 'auth_in_progress' => '',
  _ => 'Could not connect. Check your internet connection and try again.',
};

class AuthController extends Notifier<AuthState> {
  int _epoch = 0;
  Future<Session?>? _restoration;
  Future<void> _storageWrites = Future.value();
  ApiClient get _api => ref.read(apiClientProvider);
  SessionStore get _store => ref.read(sessionStoreProvider);

  @override
  AuthState build() {
    ref.watch(apiClientProvider);
    ref.watch(sessionStoreProvider);
    _epoch++;
    _restoration = null;
    return const AuthState();
  }

  bool _current(int epoch) => ref.mounted && _epoch == epoch;
  void _check(int epoch) {
    if (!_current(epoch)) throw const ApiException('auth_operation_cancelled');
  }

  int _begin(AuthAction action) {
    if (state.isLoading) throw const ApiException('auth_in_progress');
    final epoch = ++_epoch;
    state = state.copyWith(isLoading: true, action: action);
    return epoch;
  }

  Future<void> _write(Future<void> Function() operation) {
    final result = _storageWrites.then((_) => operation());
    _storageWrites = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> waitForRestoration() async {
    await _restoration;
  }

  Future<void> requestMagicLink(String email) async {
    if (authEmailError(email) != null) {
      throw const ApiException('email_invalid');
    }
    await waitForRestoration();
    final normalized = email.trim().toLowerCase();
    if (state.pendingEmail == normalized &&
        state.resendSeconds(ref.read(authClockProvider)()) > 0) {
      throw const ApiException('magic_link_cooldown');
    }
    final epoch = _begin(AuthAction.email);
    try {
      final delivery = await _api.requestMagicLink(normalized);
      _check(epoch);
      state = state.copyWith(
        isLoading: false,
        pendingEmail: normalized,
        resendAt: ref
            .read(authClockProvider)()
            .add(Duration(seconds: delivery.resendAfterSeconds)),
        linkExpiresSeconds: delivery.expiresInSeconds,
      );
    } catch (error) {
      if (_current(epoch)) {
        state = state.copyWith(
          isLoading: false,
          error: error is ApiException ? error.code : 'network_error',
        );
      }
      rethrow;
    }
  }

  Future<Session> verifyMagicLink(String token) =>
      _authenticate(AuthAction.verify, (check) async {
        if (!RegExp(r'^[A-Za-z0-9_-]{20,200}$').hasMatch(token)) {
          throw const ApiException('magic_link_invalid');
        }
        check();
        return _api.verifyMagicLink(token);
      });

  Future<Session> signInWithSocial(String provider) => _authenticate(
    provider == 'apple' ? AuthAction.apple : AuthAction.google,
    (check) async {
      if (!{'google', 'apple'}.contains(provider)) {
        throw const ApiException('unsupported_provider');
      }
      final token = await ref
          .read(socialAuthenticatorProvider)
          .credential(provider);
      check();
      return _api.verifySocialCredential(provider: provider, credential: token);
    },
  );

  Future<Session> verifySocialCredential({
    required String provider,
    required String credential,
  }) => _authenticate(
    provider == 'apple' ? AuthAction.apple : AuthAction.google,
    (check) async {
      if (!{'google', 'apple'}.contains(provider)) {
        throw const ApiException('unsupported_provider');
      }
      check();
      return _api.verifySocialCredential(
        provider: provider,
        credential: credential,
      );
    },
  );

  Future<Session> _authenticate(
    AuthAction action,
    Future<Session> Function(void Function()) operation,
  ) async {
    await waitForRestoration();
    final epoch = _begin(action);
    try {
      final session = await operation(() => _check(epoch));
      _check(epoch);
      if (session.userId.isEmpty ||
          session.accessToken.isEmpty ||
          session.refreshToken.isEmpty ||
          !session.refreshExpiresAt.isAfter(ref.read(authClockProvider)())) {
        throw const ApiException('auth_response_invalid');
      }
      await _persist(session, epoch);
      _check(epoch);
      state = AuthState(session: session);
      unawaited(_registerPush(session.userId));
      return session;
    } catch (error) {
      if (_current(epoch)) {
        state = state.copyWith(
          isLoading: false,
          error: error is ApiException
              ? error.code
              : error is FormatException
              ? 'auth_response_invalid'
              : 'network_error',
        );
      }
      rethrow;
    }
  }

  Future<void> _registerPush(String owner) async {
    try {
      if (ref.mounted && state.session?.userId == owner) {
        await ref.read(pushNotificationServiceProvider).registerCurrentToken();
      }
    } catch (_) {
      // Push registration is retried separately and must not undo a valid login.
    }
  }

  Future<void> _persist(Session session, int epoch) => _write(() async {
    _check(epoch);
    try {
      await _store.saveSession(session);
    } catch (_) {
      await _store.clear().catchError((Object _) {});
      if (_current(epoch)) {
        state = const AuthState(error: 'secure_storage_unavailable');
      }
      throw const ApiException('secure_storage_unavailable');
    }
  });

  Future<Session?> restoreSession() {
    if (_restoration != null) return _restoration!;
    if (state.isLoading) return Future.value(null);
    late final Future<Session?> restoration;
    restoration = _restore().whenComplete(() {
      if (identical(_restoration, restoration)) _restoration = null;
    });
    _restoration = restoration;
    return restoration;
  }

  Future<Session?> _restore() async {
    final epoch = _begin(AuthAction.restore);
    try {
      final refresh = await _store.refreshToken();
      _check(epoch);
      if (refresh == null || refresh.isEmpty) {
        state = state.copyWith(session: null, isLoading: false);
        return null;
      }
      final session = await _api.refreshSessionForRestore();
      _check(epoch);
      await _persist(session, epoch);
      _check(epoch);
      state = AuthState(session: session);
      unawaited(_registerPush(session.userId));
      return session;
    } catch (error) {
      if (_current(epoch)) {
        if (error is ApiException && error.code == 'refresh_token_invalid') {
          await _write(() => _store.clear()).catchError((Object _) {});
        }
        if (_current(epoch)) {
          state = AuthState(
            error:
                error is ApiException &&
                    error.code == 'secure_storage_unavailable'
                ? error.code
                : null,
          );
        }
      }
      return null;
    }
  }

  Future<void> logout() async {
    final session = state.session;
    final epoch = ++_epoch;
    _store.invalidateSession();
    state = const AuthState(isLoading: true, action: AuthAction.logout);
    try {
      try {
        await ref
            .read(pushNotificationServiceProvider)
            .unregisterCurrentToken();
      } catch (_) {}
      if (session != null) await _api.logout(session.refreshToken);
    } finally {
      if (_current(epoch)) {
        await _write(() => _store.clear());
        try {
          await ref.read(socialAuthenticatorProvider).signOut();
        } catch (_) {}
        if (_current(epoch)) state = const AuthState();
      }
    }
  }

  void markOnboarded(String ownerId) {
    final session = state.session;
    if (session != null && session.userId == ownerId) {
      state = state.copyWith(session: session.withOnboarded(true));
    }
  }

  Future<void> clearDeletedAccount() async {
    ++_epoch;
    _store.invalidateSession();
    state = const AuthState();
    await _write(() => _store.clear());
  }
}
