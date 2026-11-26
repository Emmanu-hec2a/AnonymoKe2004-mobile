import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/config/build_config.dart';
import '../../../core/network/api_client.dart';
import 'about_you_validation.dart';
import 'preferences_validation.dart';
import 'voice_controller.dart';
import 'photo_controller.dart';
import 'consent_documents.dart';

const _notProvided = Object();

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );

class OnboardingState {
  const OnboardingState({
    this.alias = '',
    this.gender = demoMode ? 'W' : '',
    this.birthDate = demoMode ? '1999-03-14' : null,
    this.heightCm = demoMode ? 168 : null,
    this.targetGenders = demoMode ? const ['M'] : const [],
    this.minAge = demoMode ? 24 : 18,
    this.maxAge = demoMode ? 34 : 35,
    this.maxDistanceKm = 15,
    this.locationConsent = false,
    this.sensitiveConsent = false,
    this.voiceConsent = false,
    this.termsConsent = false,
    this.privacyConsent = false,
    this.isSaving = false,
    this.error,
    this.saveMessage,
  });

  final String alias;
  final String gender;
  final String? birthDate;
  final int? heightCm;
  final List<String> targetGenders;
  final int minAge;
  final int maxAge;
  final int maxDistanceKm;
  final bool locationConsent;
  final bool sensitiveConsent;
  final bool voiceConsent;
  final bool termsConsent;
  final bool privacyConsent;
  final bool isSaving;
  final String? error;
  final String? saveMessage;

  bool get requiredConsentsGranted =>
      locationConsent && sensitiveConsent && termsConsent && privacyConsent;

  OnboardingState copyWith({
    String? alias,
    String? gender,
    Object? birthDate = _notProvided,
    Object? heightCm = _notProvided,
    List<String>? targetGenders,
    int? minAge,
    int? maxAge,
    int? maxDistanceKm,
    bool? locationConsent,
    bool? sensitiveConsent,
    bool? voiceConsent,
    bool? termsConsent,
    bool? privacyConsent,
    bool? isSaving,
    String? error,
    String? saveMessage,
  }) {
    return OnboardingState(
      alias: alias ?? this.alias,
      gender: gender ?? this.gender,
      birthDate: identical(birthDate, _notProvided)
          ? this.birthDate
          : birthDate as String?,
      heightCm: identical(heightCm, _notProvided)
          ? this.heightCm
          : heightCm as int?,
      targetGenders: targetGenders ?? this.targetGenders,
      minAge: minAge ?? this.minAge,
      maxAge: maxAge ?? this.maxAge,
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
      locationConsent: locationConsent ?? this.locationConsent,
      sensitiveConsent: sensitiveConsent ?? this.sensitiveConsent,
      voiceConsent: voiceConsent ?? this.voiceConsent,
      termsConsent: termsConsent ?? this.termsConsent,
      privacyConsent: privacyConsent ?? this.privacyConsent,
      isSaving: isSaving ?? this.isSaving,
      error: error,
      saveMessage: saveMessage,
    );
  }
}

class OnboardingController extends Notifier<OnboardingState> {
  static const _adjectives = [
    'Quiet',
    'Velvet',
    'Golden',
    'Mellow',
    'Kindred',
    'Amber',
    'Curious',
    'Soft',
    'Hidden',
    'Gentle',
    'Brave',
    'Cosmic',
    'Playful',
    'Radiant',
    'Witty',
    'Silver',
    'Clever',
    'Dreamy',
    'Sunny',
    'Serene',
    'Vivid',
    'Lucky',
    'Jolly',
    'Warm',
  ];
  static const _nouns = [
    'Comet',
    'Echo',
    'Spark',
    'Orbit',
    'Muse',
    'Moon',
    'Bloom',
    'Rebel',
    'Rhythm',
    'Melody',
    'Firefly',
    'Starlight',
    'Aurora',
    'Sonnet',
    'Beat',
    'Clover',
    'Flame',
    'Ripple',
    'Petal',
    'Whisper',
    'Wonder',
    'Ember',
    'Daydream',
    'Charm',
  ];
  final _random = Random();
  int _generation = 0;
  Future<void>? _submission;
  ApiClient get _api => ref.read(apiClientProvider);

  @override
  OnboardingState build() {
    ref.watch(apiClientProvider);
    ref.watch(authControllerProvider.select((s) => s.session?.userId));
    _generation++;
    _submission = null;
    return const OnboardingState();
  }

  void setAlias(String value) => state = state.copyWith(alias: value.trim());

  String shuffleAlias() {
    String alias;
    do {
      alias =
          '${_adjectives[_random.nextInt(_adjectives.length)]} ${_nouns[_random.nextInt(_nouns.length)]} ${1000 + _random.nextInt(9000)}';
    } while (alias == state.alias);
    state = state.copyWith(alias: alias);
    return alias;
  }

  void setGender(String value) => state = state.copyWith(gender: value);

  void setBirthDate(String? value) {
    final date = AboutYouValidation.parseDate(value);
    state = state.copyWith(
      birthDate: date == null ? null : AboutYouValidation.isoDate(date),
    );
  }

  void setHeight(String value) {
    state = state.copyWith(heightCm: int.tryParse(value.trim()));
  }

  void setTargetGenders(List<String> values) {
    state = state.copyWith(targetGenders: List.unmodifiable(values));
  }

  void setAgeRange(int minAge, int maxAge) {
    state = state.copyWith(minAge: minAge, maxAge: maxAge);
  }

  void setDistance(int value) => state = state.copyWith(maxDistanceKm: value);

  void setLocationConsent(bool value) {
    if (!state.isSaving) state = state.copyWith(locationConsent: value);
  }

  void setSensitiveConsent(bool value) {
    if (!state.isSaving) state = state.copyWith(sensitiveConsent: value);
  }

  void setVoiceConsent(bool value) {
    if (!state.isSaving) state = state.copyWith(voiceConsent: value);
  }

  void setTermsConsent(bool value) {
    if (!state.isSaving) state = state.copyWith(termsConsent: value);
  }

  void setPrivacyConsent(bool value) {
    if (!state.isSaving) state = state.copyWith(privacyConsent: value);
  }

  void setLegalConsent(bool value) {
    if (!state.isSaving) {
      state = state.copyWith(termsConsent: value, privacyConsent: value);
    }
  }

  Future<void> complete() => _submit(preview: false);
  Future<void> completePreview() => _submit(preview: true);

  Future<void> _submit({required bool preview}) {
    if (_submission != null) return _submission!;
    late final Future<void> submission;
    submission = _complete(preview: preview).whenComplete(() {
      if (identical(_submission, submission)) _submission = null;
    });
    _submission = submission;
    return submission;
  }

  Future<void> _complete({required bool preview}) async {
    if (preview && !demoMode) throw const ApiException('preview_unavailable');
    if (state.isSaving) return;
    final draft = state;
    final voice = ref.read(onboardingVoiceProvider);
    final capsule = voice.saved ? voice.capsule : null;
    if (voice.recording || voice.busy) {
      throw const ApiException('voice_recording_in_progress');
    }
    final generation = _generation;
    final ownerId = ref.read(authControllerProvider).session?.userId;
    final today = ref.read(onboardingTodayProvider)();
    if (AboutYouValidation.aliasError(draft.alias) != null ||
        !['M', 'W', 'NB'].contains(draft.gender) ||
        AboutYouValidation.dateError(draft.birthDate, today) != null ||
        AboutYouValidation.heightError(draft.heightCm?.toString()) != null) {
      throw const ApiException('profile_required');
    }
    if (PreferencesValidation.gendersError(draft.targetGenders) != null) {
      throw const ApiException('matching_preferences_required');
    }
    if (PreferencesValidation.agesError(draft.minAge, draft.maxAge) != null) {
      throw const ApiException('age_preference_range_invalid');
    }
    if (PreferencesValidation.distanceError(draft.maxDistanceKm) != null) {
      throw const ApiException('distance_preference_range_invalid');
    }
    final photoState = ref.read(onboardingPhotoProvider);
    final photo = photoState.saved ? photoState.draft : null;
    if (photoState.busy || photo == null) {
      throw const ApiException('photo_required');
    }
    if (!draft.termsConsent || !draft.privacyConsent) {
      throw const ApiException('terms_privacy_consent_required');
    }
    if (!draft.sensitiveConsent) {
      throw const ApiException('sensitive_data_consent_required');
    }
    if (!draft.locationConsent) {
      throw const ApiException('location_consent_required');
    }
    final documents = ref.read(consentDocumentsProvider);
    if (!preview && !documents.isConfigured) {
      throw const ApiException('consent_documents_unavailable');
    }
    if (!preview && ownerId == null) {
      throw const ApiException('session_expired');
    }

    state = state.copyWith(isSaving: true, error: null);
    bool stillCurrentAccount() =>
        ref.mounted &&
        generation == _generation &&
        ref.read(authControllerProvider).session?.userId == ownerId;
    void checkCurrentAccount() {
      if (!stillCurrentAccount()) throw const ApiException('session_changed');
    }

    void checkCurrentPhoto() {
      checkCurrentAccount();
      final current = ref.read(onboardingPhotoProvider);
      if (!identical(current.draft, photo) || !current.saved || current.busy) {
        throw const ApiException('photo_changed');
      }
    }

    try {
      if (preview) {
        await ref.read(onboardingVoiceProvider.notifier).clearAfterCompletion();
        checkCurrentAccount();
        await ref.read(onboardingPhotoProvider.notifier).clearAfterCompletion();
        checkCurrentAccount();
        state = state.copyWith(isSaving: false);
        return;
      }
      await _recordConsents(draft, documents.version, checkCurrentAccount);
      checkCurrentAccount();
      state = state.copyWith(
        isSaving: true,
        saveMessage: 'Checking your photo…',
      );
      late MediaAssetSummary acceptedPhoto;
      try {
        acceptedPhoto = await photo.validateOnServer(
          _api,
          checkCurrent: checkCurrentPhoto,
          delay: ref.read(photoPollDelayProvider),
        );
      } on ApiException catch (error) {
        if (stillCurrentAccount() &&
            const {
              'exactly_one_face_required',
              'avatar_invalid',
              'avatar_format_invalid',
              'avatar_dimensions_invalid',
              'avatar_still_photo_required',
              'media_size_invalid',
              'media_content_type_invalid',
              'photo_validation_failed',
              'photo_not_ready',
            }.contains(error.code)) {
          ref.read(onboardingPhotoProvider.notifier).reject(photo, error.code);
        }
        rethrow;
      }
      checkCurrentAccount();
      if (draft.voiceConsent && capsule != null) {
        state = state.copyWith(
          isSaving: true,
          saveMessage: 'Saving your voice capsule…',
        );
        final result = await capsule.upload.send(
          _api,
          checkCurrent: checkCurrentAccount,
        );
        checkCurrentAccount();
        if (result.status == 'rejected') {
          throw ApiException(result.rejectionCode);
        }
        if (!['ready', 'processing'].contains(result.status)) {
          throw const ApiException('media_processing_unavailable');
        }
      }
      checkCurrentPhoto();
      state = state.copyWith(
        isSaving: true,
        saveMessage: 'Saving your profile…',
      );
      await _api.updateProfile({
        'alias': draft.alias,
        'gender': draft.gender,
        'birth_date': draft.birthDate,
        'height_cm': draft.heightCm,
        'min_age_pref': draft.minAge,
        'max_age_pref': draft.maxAge,
        'max_distance_km': draft.maxDistanceKm,
        'target_genders': draft.targetGenders,
        'is_discoverable': true,
        'onboarding_photo_upload_id': acceptedPhoto.id,
      });
      checkCurrentAccount();
      await ref.read(onboardingVoiceProvider.notifier).clearAfterCompletion();
      checkCurrentAccount();
      await ref.read(onboardingPhotoProvider.notifier).clearAfterCompletion();
      checkCurrentAccount();
      state = state.copyWith(isSaving: false, error: null);
      ref.read(authControllerProvider.notifier).markOnboarded(ownerId!);
    } on ApiException catch (error) {
      if (stillCurrentAccount()) {
        if (error.code == 'photo_not_ready') {
          ref.read(onboardingPhotoProvider.notifier).reject(photo, error.code);
        }
        state = state.copyWith(isSaving: false, error: error.code);
      }
      rethrow;
    } catch (_) {
      if (stillCurrentAccount()) {
        state = state.copyWith(isSaving: false, error: 'network_error');
      }
      rethrow;
    }
  }

  Future<void> _recordConsents(
    OnboardingState draft,
    String version,
    void Function() checkCurrentAccount,
  ) async {
    checkCurrentAccount();
    await _api.recordConsent(
      type: 'terms',
      version: version,
      granted: draft.termsConsent,
    );
    checkCurrentAccount();
    await _api.recordConsent(
      type: 'privacy',
      version: version,
      granted: draft.privacyConsent,
    );
    checkCurrentAccount();
    await _api.recordConsent(
      type: 'sensitive_data',
      version: version,
      granted: draft.sensitiveConsent,
    );
    checkCurrentAccount();
    await _api.recordConsent(
      type: 'location',
      version: version,
      granted: draft.locationConsent,
    );
    checkCurrentAccount();
    await _api.recordConsent(
      type: 'voice',
      version: version,
      granted: draft.voiceConsent,
    );
  }
}
