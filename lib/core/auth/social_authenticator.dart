import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../network/api_client.dart';

String googleSignInFailureCode(GoogleSignInExceptionCode code) =>
    switch (code) {
      GoogleSignInExceptionCode.canceled => 'google_sign_in_incomplete',
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        'provider_not_configured',
      _ => 'social_sign_in_failed',
    };

final socialAuthenticatorProvider = Provider<SocialAuthenticator>(
  (_) => NativeSocialAuthenticator(),
);

abstract class SocialAuthenticator {
  bool get supportsGoogle;
  bool get supportsApple;
  Future<String> credential(String provider);
  Future<void> signOut() async {}
}

class NativeSocialAuthenticator extends SocialAuthenticator {
  Future<void>? _googleInitialization;
  @override
  bool get supportsGoogle =>
      !kIsWeb &&
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
      }.contains(defaultTargetPlatform);
  @override
  bool get supportsApple =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<String> credential(String provider) async {
    try {
      if (provider == 'google' && supportsGoogle) {
        const serverId = String.fromEnvironment(
          'GOOGLE_WEB_CLIENT_ID',
          defaultValue:
              '441811643862-eekavq3aeaa7nbigi5omagv354a482h0.apps.googleusercontent.com',
        );
        const iosId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
        final google = GoogleSignIn.instance;
        _googleInitialization ??= google.initialize(
          serverClientId: serverId.isEmpty ? null : serverId,
          clientId: iosId.isEmpty ? null : iosId,
        );
        await _googleInitialization;
        final account = await google.authenticate();
        final token = account.authentication.idToken;
        if (token == null || token.isEmpty) {
          throw const ApiException('social_token_missing');
        }
        return token;
      }
      if (provider == 'apple' && supportsApple) {
        if (!await SignInWithApple.isAvailable()) {
          throw const ApiException('provider_unavailable');
        }
        final result = await SignInWithApple.getAppleIDCredential(
          scopes: [AppleIDAuthorizationScopes.email],
        );
        final token = result.identityToken;
        if (token == null || token.isEmpty) {
          throw const ApiException('social_token_missing');
        }
        return token;
      }
      throw const ApiException('unsupported_provider');
    } on GoogleSignInException catch (error) {
      // Android may report OAuth configuration failures as cancellation after account selection.
      throw ApiException(googleSignInFailureCode(error.code));
    } on SignInWithAppleAuthorizationException catch (error) {
      throw ApiException(
        error.code == AuthorizationErrorCode.canceled
            ? 'sign_in_cancelled'
            : 'social_sign_in_failed',
      );
    } on SignInWithAppleNotSupportedException {
      throw const ApiException('provider_unavailable');
    } on PlatformException {
      throw const ApiException('social_sign_in_failed');
    }
  }

  @override
  Future<void> signOut() async {
    if (_googleInitialization != null) {
      await _googleInitialization;
      await GoogleSignIn.instance.signOut();
    }
  }
}
