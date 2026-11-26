import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authLinkStreamProvider = Provider<Stream<Uri>>(
  (_) => AppLinks().uriLinkStream,
);
final magicLinkIntentProvider =
    NotifierProvider<MagicLinkIntentController, MagicLinkIntent?>(
      MagicLinkIntentController.new,
    );

class MagicLinkIntent {
  const MagicLinkIntent(this.token);
  final String token;
  @override
  String toString() => 'MagicLinkIntent';
}

class MagicLinkIntentController extends Notifier<MagicLinkIntent?> {
  String? _lastToken;
  @override
  MagicLinkIntent? build() => null;

  static String? tokenFromUri(Uri uri) {
    const httpsHost = String.fromEnvironment(
      'AUTH_LINK_HOST',
      defaultValue: 'api.anonymoke.co.ke',
    );
    final customLink =
        uri.scheme == 'anonymoke' &&
        uri.host == 'auth' &&
        uri.path == '/magic-link';
    final httpsLink =
        httpsHost.isNotEmpty &&
        uri.scheme == 'https' &&
        uri.host == httpsHost &&
        {'/auth/magic-link', '/auth/magic-link/'}.contains(uri.path);
    if ((!customLink && !httpsLink) || uri.userInfo.isNotEmpty || uri.hasPort) {
      return null;
    }
    try {
      final Map<String, List<String>> parameters;
      if (uri.hasFragment) {
        if (!httpsLink || uri.hasQuery) return null;
        parameters = Uri(query: uri.fragment).queryParametersAll;
      } else {
        parameters = uri.queryParametersAll;
      }
      final tokens = parameters['token'];
      if (parameters.length != 1 || tokens == null || tokens.length != 1) {
        return null;
      }
      return RegExp(r'^[A-Za-z0-9_-]{20,200}$').hasMatch(tokens.single)
          ? tokens.single
          : null;
    } on FormatException {
      return null;
    }
  }

  bool receive(Uri uri) {
    final token = tokenFromUri(uri);
    if (token == null || token == _lastToken) return false;
    _lastToken = token;
    state = MagicLinkIntent(token);
    return true;
  }

  MagicLinkIntent? take() {
    final intent = state;
    state = null;
    return intent;
  }
}
