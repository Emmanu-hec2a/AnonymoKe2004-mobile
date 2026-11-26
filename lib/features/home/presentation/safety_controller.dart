import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_client.dart';

final safetyRefreshSignal = NotifierProvider<SafetySignal, int>(
  SafetySignal.new,
);

class SafetySignal extends Notifier<int> {
  @override
  int build() => 0;
  void notify() => state++;
}

final safetyProvider =
    NotifierProvider.autoDispose<SafetyController, SafetyState>(
      SafetyController.new,
    );

class SafetyState {
  const SafetyState({
    this.overview,
    this.verification,
    this.error,
    this.verificationError,
  });
  final SafetyOverview? overview;
  final Map<String, dynamic>? verification;
  final String? error;
  final String? verificationError;
}

class SafetyController extends Notifier<SafetyState> {
  Future<void>? _running;
  bool _active = true;
  int _epoch = 0;

  @override
  SafetyState build() {
    ref.watch(authControllerProvider.select((value) => value.session?.userId));
    ref.watch(apiClientProvider);
    _epoch++;
    _running = null;
    ref.listen(safetyRefreshSignal, (_, _) {
      if (_active) unawaited(refresh());
    });
    final timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_active) unawaited(refresh());
    });
    ref.onDispose(timer.cancel);
    Future.microtask(() {
      if (ref.mounted) unawaited(refresh());
    });
    return const SafetyState();
  }

  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    if (active) unawaited(refresh());
  }

  Future<void> refresh() {
    if (_running != null) return _running!;
    late final Future<void> operation;
    operation = _load(_epoch).whenComplete(() {
      if (identical(_running, operation)) _running = null;
    });
    _running = operation;
    return operation;
  }

  Future<void> afterMutation() async {
    await _running;
    if (ref.mounted) await refresh();
  }

  Future<void> _load(int epoch) async {
    final api = ref.read(apiClientProvider);
    String? verificationError;
    final verification = api.verificationStatus().catchError((Object _) {
      verificationError = 'Could not check verification status.';
      return <String, dynamic>{};
    });
    try {
      final overview = await api.safetyOverview();
      if (!ref.mounted || epoch != _epoch) return;
      state = SafetyState(overview: overview, verification: state.verification);
    } on ApiException catch (error) {
      if (ref.mounted && epoch == _epoch) {
        state = SafetyState(
          overview: error.statusCode == 401 ? null : state.overview,
          verification: state.verification,
          error: error.statusCode == 401
              ? 'session_expired'
              : 'Safety tools could not be updated. Pull down to retry.',
        );
      }
    } catch (_) {
      if (ref.mounted && epoch == _epoch) {
        state = SafetyState(
          overview: state.overview,
          verification: state.verification,
          error: 'Safety tools could not be updated. Pull down to retry.',
        );
      }
    }
    final status = await verification;
    if (ref.mounted && epoch == _epoch) {
      state = SafetyState(
        overview: state.overview,
        verification: status,
        error: state.error,
        verificationError: verificationError,
      );
    }
  }
}

String safetyError(String code) => switch (code) {
  'trusted_contact_required' => 'Add a trusted contact first.',
  'trusted_contact_not_linked' =>
    'Link your trusted contact to an active AnonymoKE account first.',
  'trusted_contact_changed' =>
    'Your trusted contact changed. Resolve this date plan, then create a new one.',
  'resolve_date_before_unlink' =>
    'Mark yourself safe or cancel the current plan before changing your trusted contact.',
  'contact_replacement_requires_unlink' =>
    'Unlink the existing account before replacing your trusted contact.',
  'active_date_required' => 'Create a date plan before sending an alert.',
  'active_date_already_exists' =>
    'You already have an open date plan. Refresh to view it.',
  'date_session_not_active' =>
    'This plan has changed. Refresh to see its current status.',
  'mark_safe_to_resolve_panic' =>
    'Mark yourself safe to resolve this panic alert.',
  'invite_code_expired_or_invalid' || 'invite_code_invalid' =>
    'This invite is invalid or expired. Ask for a new code.',
  'location_required' || 'location_consent_required' =>
    'Update your location in Discover, or turn off approximate-area sharing.',
  'verification_provider_unavailable' =>
    'Verification is currently unavailable. Please try again later.',
  'verification_start_in_progress' =>
    'Your verification is starting. Please wait a moment and try again.',
  'sensitive_data_consent_required' =>
    'Review your sensitive-data consent in Profile settings first.',
  'rate_limited' || 'throttled' => 'Please wait before trying again.',
  'session_expired' => 'Your session has expired. Please sign in again.',
  _ => 'Could not complete this request. Check your connection and try again.',
};
