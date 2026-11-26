import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../onboarding/application/consent_documents.dart';

class ConsentDocumentLinks extends ConsumerStatefulWidget {
  const ConsentDocumentLinks({super.key});

  @override
  ConsumerState<ConsentDocumentLinks> createState() =>
      _ConsentDocumentLinksState();
}

class _ConsentDocumentLinksState extends ConsumerState<ConsentDocumentLinks> {
  bool _opening = false;
  String? _error;

  Future<void> _open(bool terms) async {
    if (_opening) return;
    final documents = ref.read(consentDocumentsProvider);
    final uri = terms ? documents.terms : documents.privacy;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      if (uri == null || !await openConsentDocument(context, ref, uri)) {
        if (mounted) {
          setState(
            () => _error = 'This document is unavailable. Please try again.',
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not open the document. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          TextButton.icon(
            key: const Key('policy-terms-link'),
            onPressed: _opening ? null : () => _open(true),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Terms of Use'),
          ),
          TextButton.icon(
            key: const Key('policy-privacy-link'),
            onPressed: _opening ? null : () => _open(false),
            icon: const Icon(Icons.privacy_tip_outlined, size: 18),
            label: const Text('Privacy Policy'),
          ),
        ],
      ),
      if (_error != null)
        Text(
          _error!,
          style: const TextStyle(color: AppColors.coral, height: 1.4),
        ),
    ],
  );
}
