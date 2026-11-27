import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_client.dart';
import 'tab_refresh.dart';

final profileProvider =
    NotifierProvider.autoDispose<ProfileController, ProfileState>(
      ProfileController.new,
    );

class ProfileState {
  const ProfileState({
    this.profile,
    this.entitlements = const [],
    this.media = const [],
    this.error,
    this.perksError,
    this.mediaError,
    this.visibilitySaving = false,
  });
  final ProfileSummary? profile;
  final List<EntitlementSummary> entitlements;
  final List<MediaAssetSummary> media;
  final String? error, perksError, mediaError;
  final bool visibilitySaving;

  ProfileState withProfile(ProfileSummary? value, {bool saving = false}) =>
      ProfileState(
        profile: value,
        entitlements: entitlements,
        media: media,
        error: error,
        perksError: perksError,
        mediaError: mediaError,
        visibilitySaving: saving,
      );
}

class ProfileController extends Notifier<ProfileState> {
  Future<void>? _running;
  bool _active = true;
  int _stableTicks = 0;
  int _epoch = 0;
  @override
  ProfileState build() {
    ref.watch(apiClientProvider);
    ref.watch(authControllerProvider.select((s) => s.session?.userId));
    _epoch++;
    _running = null;
    _stableTicks = 0;
    final timer = Timer.periodic(const Duration(seconds: 15), (_) {
      final pending = state.media.any(
        (item) => const {
          'pending',
          'uploading',
          'uploaded',
          'queued',
          'processing',
        }.contains(item.status),
      );
      if (_active) {
        _stableTicks++;
        if (pending || _stableTicks >= 8) unawaited(refresh());
      }
    });
    ref.onDispose(timer.cancel);
    Future.microtask(() {
      if (ref.mounted) unawaited(refresh());
    });
    return const ProfileState();
  }

  void setActive(bool value) {
    if (_active == value) return;
    _active = value;
    if (value) unawaited(refresh());
  }

  Future<void> refresh() {
    if (state.visibilitySaving) return Future<void>.value();
    if (_running != null) return _running!;
    late final Future<void> next;
    next = _load(_epoch).whenComplete(() {
      if (identical(_running, next)) _running = null;
    });
    _running = next;
    return next;
  }

  Future<void> setDiscoverable(bool visible) async {
    if (state.visibilitySaving) return;
    final previous = state;
    final profile = previous.profile;
    if (profile == null) throw const ApiException('profile_unavailable');
    final epoch = ++_epoch;
    state = previous.withProfile(
      profile.withDiscoverability(visible),
      saving: true,
    );
    try {
      await ref.read(apiClientProvider).updateProfile({
        'is_discoverable': visible,
      });
      if (!ref.mounted || epoch != _epoch) return;
      state = state.withProfile(profile.withDiscoverability(visible));
      unawaited(afterMutation());
    } catch (_) {
      if (ref.mounted && epoch == _epoch) state = previous;
      rethrow;
    }
  }

  Future<void> afterMutation() async {
    ref.read(discoveryRefreshSignal.notifier).notify();
    await _running;
    if (ref.mounted) await refresh();
  }

  Future<void> _load(int epoch) async {
    final api = ref.read(apiClientProvider);
    final previous = state;
    String? perksError, mediaError;
    final perks = api.entitlements().catchError((Object _) {
      perksError = 'Premium details could not be refreshed.';
      return previous.entitlements;
    });
    final media = api.mediaStatus().catchError((Object _) {
      mediaError = 'Upload status could not be refreshed.';
      return previous.media;
    });
    try {
      final profile = await api.profile();
      if (!ref.mounted || epoch != _epoch) return;
      state = ProfileState(
        profile: profile,
        entitlements: state.entitlements,
        media: state.media,
      );
      final entitlements = await perks;
      final assets = await media;
      if (!ref.mounted || epoch != _epoch) return;
      _stableTicks = 0;
      state = ProfileState(
        profile: profile,
        entitlements: entitlements,
        media: assets,
        perksError: perksError,
        mediaError: mediaError,
      );
    } catch (e) {
      await perks;
      await media;
      if (!ref.mounted || epoch != _epoch) return;
      state = ProfileState(
        profile: e is ApiException && e.statusCode == 401
            ? null
            : state.profile,
        entitlements: state.entitlements,
        media: state.media,
        error: e is ApiException && e.statusCode == 401
            ? 'session_expired'
            : 'Could not refresh your profile. Try again.',
      );
    }
  }
}

String profileError(String code) => switch (code) {
  'sensitive_data_consent_required' =>
    'Review your matching details consent first.',
  'location_consent_required' => 'Review your location consent first.',
  'voice_consent_required' => 'Enable voice capsule consent before recording.',
  'profile_content_not_allowed' =>
    'Remove contact details, payment requests or commercial content.',
  'interests_invalid' => 'Choose up to 10 interests, each 2–24 characters.',
  'interests_duplicate' => 'That interest is already added.',
  'alias_invalid' => 'Enter an alias with 2–40 characters.',
  'age_preference_range_invalid' => 'Choose an age range between 18 and 100.',
  'media_storage_unavailable' || 'erasure_temporarily_unavailable' =>
    'Storage is temporarily unavailable. Please try again.',
  'media_too_large' =>
    'Choose a photo under 10 MB or an audio clip under 5 MB.',
  'microphone_permission_denied' =>
    'Allow microphone access in your phone settings to record.',
  'media_upload_expired' => 'Your upload expired. Tap Upload to try again.',
  'exactly_one_face_required' => 'Choose a clear photo showing just your face.',
  'audio_duration_invalid' => 'Record a voice capsule of 15 seconds or less.',
  'rate_limited' || 'throttled' => 'Please wait before trying again.',
  _ => 'Could not complete this request. Please try again.',
};
