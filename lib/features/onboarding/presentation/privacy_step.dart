import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/build_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../application/consent_documents.dart';
import '../application/onboarding_controller.dart';
import '../application/voice_controller.dart';

class PrivacyStep extends ConsumerStatefulWidget {
  const PrivacyStep({required this.onContinue, super.key});
  final Future<void> Function() onContinue;
  @override
  ConsumerState<PrivacyStep> createState() => _PrivacyStepState();
}

class _PrivacyStepState extends ConsumerState<PrivacyStep> {
  String? _error;
  int? _reviewStep;
  bool _reauthenticate = false;
  bool _submitting = false, _openingDocument = false;

  Future<void> _openDocument(bool terms) async {
    if (_openingDocument) return;
    final documents = ref.read(consentDocumentsProvider);
    final uri = terms ? documents.terms : documents.privacy;
    _openingDocument = true;
    try {
      if (uri == null || !await openConsentDocument(context, ref, uri)) {
        if (mounted) {
          setState(() {
            _error = 'This document is unavailable. Please try again later.';
            _reviewStep = null;
            _reauthenticate = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not open the document. Please try again.';
          _reviewStep = null;
          _reauthenticate = false;
        });
      }
    } finally {
      _openingDocument = false;
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
      _reviewStep = null;
      _reauthenticate = false;
    });
    try {
      await widget.onContinue();
    } catch (error) {
      if (mounted) {
        final code = error is ApiException ? error.code : 'network_error';
        setState(() {
          _error = _message(code);
          _reauthenticate = const {
            'session_changed',
            'session_expired',
            'refresh_token_invalid',
          }.contains(code);
          _reviewStep = switch (code) {
            'profile_required' || 'profile_content_not_allowed' => 1,
            'matching_preferences_required' ||
            'age_preference_range_invalid' ||
            'distance_preference_range_invalid' => 2,
            'voice_recording_in_progress' ||
            'audio_duration_invalid' ||
            'audio_invalid' ||
            'media_processing_unavailable' => 3,
            _ => null,
          };
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _message(String code) => switch (code) {
    'profile_required' =>
      'Review your alias, date of birth and gender in Step 1.',
    'profile_content_not_allowed' =>
      'Your alias needs a change. Avoid contact details or requests for money.',
    'matching_preferences_required' ||
    'age_preference_range_invalid' ||
    'distance_preference_range_invalid' =>
      'Review who you want to meet in Step 2.',
    'terms_privacy_consent_required' ||
    'terms_consent_required' ||
    'privacy_consent_required' =>
      'Read and accept the Terms and Privacy Policy to continue.',
    'sensitive_data_consent_required' => 'Allow matching details to continue.',
    'location_consent_required' =>
      'Allow approximate location processing to continue.',
    'consent_documents_unavailable' =>
      'The Terms and Privacy Policy are not available yet. Please try again later.',
    'voice_recording_in_progress' => 'Finish or skip your recording in Step 3.',
    'audio_duration_invalid' || 'audio_invalid' =>
      'Your voice capsule could not be accepted. Re-record it or skip voice in Step 3.',
    'media_processing_unavailable' =>
      'Your voice capsule could not be processed. Try again or skip voice in Step 3.',
    'photo_processing_pending' =>
      'Your photo is still being checked. Wait a moment, then try again.',
    'session_changed' || 'session_expired' || 'refresh_token_invalid' =>
      'Your session changed. Sign in again to continue.',
    'rate_limited' => 'Too many attempts. Wait a moment, then try again.',
    _ =>
      'Could not finish setting up your profile. Your choices are kept here. Please try again.',
  };

  Widget _card({
    required String id,
    required String title,
    required String body,
    required bool value,
    required ValueChanged<bool>? onChanged,
    bool isRequired = true,
    Widget? links,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          CheckboxListTile(
            key: Key('consent-$id'),
            value: value,
            onChanged: onChanged == null ? null : (v) => onChanged(v ?? false),
            activeColor: AppColors.accent,
            checkColor: Colors.white,
            side: const BorderSide(color: AppColors.strongLine, width: 1.5),
            checkboxShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            title: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: title),
                  TextSpan(
                    text: isRequired ? ' *' : '  Optional',
                    style: TextStyle(
                      color: isRequired ? AppColors.danger : AppColors.muted,
                      fontSize: isRequired ? 16 : 12,
                      fontWeight: isRequired
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    semanticsLabel: isRequired ? ', required' : ', optional',
                  ),
                ],
              ),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                body,
                style: const TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ),
          ?links,
        ],
      ),
    ),
  );

  Widget _body(OnboardingState draft, bool enabled) {
    final controller = ref.read(onboardingControllerProvider.notifier);
    final voice = ref.watch(onboardingVoiceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your privacy choices',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontSize: 28,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Nothing is switched on without your yes. Change any of this later in Settings.',
          style: TextStyle(
            color: AppColors.secondaryText,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        _card(
          id: 'location',
          title: 'Location',
          body:
              'To show people near you. We keep only an approximate area, never your exact spot.',
          value: draft.locationConsent,
          onChanged: enabled ? controller.setLocationConsent : null,
        ),
        _card(
          id: 'matching',
          title: 'Matching details',
          body:
              'Your gender and who you want to meet. Used only to match you, kept private, never shown.',
          value: draft.sensitiveConsent,
          onChanged: enabled ? controller.setSensitiveConsent : null,
        ),
        _card(
          id: 'voice',
          title: 'Voice capsule',
          isRequired: false,
          body: voice.saved && voice.capsule != null
              ? 'Let us store and play your 15-second voice note to people you appear to.'
              : 'Let us store and play a voice capsule when you add one. You can leave this off.',
          value: draft.voiceConsent,
          onChanged: enabled ? controller.setVoiceConsent : null,
        ),
        _card(
          id: 'legal',
          title: 'Terms and Privacy Policy',
          body:
              'I agree to the Terms of Use and Privacy Policy. I am 18 or older. I will not ask anyone for money, fare or airtime.',
          value: draft.termsConsent && draft.privacyConsent,
          onChanged: enabled ? controller.setLegalConsent : null,
          links: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 4,
                children: [
                  for (final terms in [true, false])
                    TextButton.icon(
                      key: Key(
                        terms ? 'consent-terms-link' : 'consent-privacy-link',
                      ),
                      onPressed: enabled ? () => _openDocument(terms) : null,
                      icon: const Icon(Icons.open_in_new_rounded, size: 14),
                      label: Text(terms ? 'Read Terms' : 'Privacy Policy'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.accentSoft,
                        textStyle: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(fontSize: 12),
                        minimumSize: const Size(48, 44),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const Text(
          '* Required. Voice is optional.',
          style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
        ),
        if (voice.saved && voice.capsule != null && !draft.voiceConsent) ...[
          const SizedBox(height: 12),
          const Text(
            'Your recording stays on this device and will not be uploaded. It is removed from the app when setup finishes.',
            style: TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
        if (!demoMode && !ref.watch(consentDocumentsProvider).isConfigured) ...[
          const SizedBox(height: 16),
          const Text(
            'The Terms and Privacy Policy are not available yet. Please try again later.',
            style: TextStyle(color: AppColors.coral, fontSize: 13, height: 1.4),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              key: const Key('privacy-error'),
              style: const TextStyle(
                color: AppColors.coral,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          if (_reviewStep != null)
            TextButton(
              onPressed: enabled
                  ? () => context.go('/onboarding/$_reviewStep')
                  : null,
              child: Text('Review Step $_reviewStep'),
            ),
          if (_reauthenticate)
            TextButton(
              onPressed: enabled ? () => context.go('/auth') : null,
              child: const Text('Sign in again'),
            ),
        ],
      ],
    );
  }

  Widget _footer(OnboardingState draft, bool enabled) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: AppColors.teal, size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Next step later: verify with a quick selfie before your first reveal.',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      ElevatedButton(
        key: const Key('privacy-finish'),
        onPressed:
            enabled &&
                draft.requiredConsentsGranted &&
                (demoMode || ref.watch(consentDocumentsProvider).isConfigured)
            ? _submit
            : null,
        child: draft.isSaving || _submitting
            ? Semantics(
                liveRegion: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        draft.saveMessage ?? 'Saving your choices...',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              )
            : const Text(
                'Finish and start swiping',
                textAlign: TextAlign.center,
              ),
      ),
    ],
  );

  Widget _centered(Widget child, EdgeInsets padding) => Padding(
    padding: padding,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: child,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingControllerProvider);
    final enabled = !draft.isSaving && !_submitting;
    return LayoutBuilder(
      builder: (context, constraints) {
        final body = _centered(
          _body(draft, enabled),
          const EdgeInsets.fromLTRB(24, 24, 24, 20),
        );
        final footer = _centered(
          _footer(draft, enabled),
          const EdgeInsets.fromLTRB(24, 16, 24, 24),
        );
        if (constraints.maxHeight >= 660 &&
            MediaQuery.textScalerOf(context).scale(14) < 21) {
          return Column(
            children: [
              Expanded(child: SingleChildScrollView(child: body)),
              footer,
            ],
          );
        }
        return SingleChildScrollView(child: Column(children: [body, footer]));
      },
    );
  }
}
