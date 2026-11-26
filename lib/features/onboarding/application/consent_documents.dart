import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../legal/domain/legal_document.dart';
import '../../legal/presentation/legal_document_screen.dart';

final consentDocumentsProvider = Provider<ConsentDocuments>(
  (_) => const ConsentDocuments(
    termsUrl: String.fromEnvironment('TERMS_URL', defaultValue: '/legal/terms'),
    privacyUrl: String.fromEnvironment(
      'PRIVACY_POLICY_URL',
      defaultValue: '/legal/privacy',
    ),
    version: String.fromEnvironment(
      'CONSENT_VERSION',
      defaultValue: LegalDocumentKind.version,
    ),
  ),
);

final consentDocumentLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (_) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

Future<bool> openConsentDocument(
  BuildContext context,
  WidgetRef ref,
  Uri uri,
) async {
  final kind = LegalDocumentKind.forUri(uri);
  if (kind != null) {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        settings: RouteSettings(name: kind.path),
        builder: (_) => LegalDocumentScreen(document: kind),
      ),
    );
    return true;
  }
  if (ConsentDocuments.httpsUri(uri.toString()) == null) return false;
  return ref.read(consentDocumentLauncherProvider)(uri);
}

class ConsentDocuments {
  const ConsentDocuments({
    required this.termsUrl,
    required this.privacyUrl,
    required this.version,
  });

  const ConsentDocuments.bundled()
    : termsUrl = '/legal/terms',
      privacyUrl = '/legal/privacy',
      version = LegalDocumentKind.version;

  final String termsUrl, privacyUrl, version;

  static Uri? httpsUri(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? uri
        : null;
  }

  Uri? _uri(String value, LegalDocumentKind kind) =>
      value == kind.path ? Uri(path: kind.path) : httpsUri(value);

  Uri? get terms => _uri(termsUrl, LegalDocumentKind.terms);
  Uri? get privacy => _uri(privacyUrl, LegalDocumentKind.privacy);

  bool get usesBundledDocuments =>
      termsUrl == LegalDocumentKind.terms.path ||
      privacyUrl == LegalDocumentKind.privacy.path;

  bool get isConfigured =>
      terms != null &&
      privacy != null &&
      version.trim().isNotEmpty &&
      version.length <= 64 &&
      (!usesBundledDocuments || version == LegalDocumentKind.version);
}
