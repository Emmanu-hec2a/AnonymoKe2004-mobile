import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_client.dart';
import '../../home/presentation/profile_device.dart';

final onboardingVoiceProvider =
    NotifierProvider<OnboardingVoiceController, OnboardingVoiceState>(
      OnboardingVoiceController.new,
    );
const _unset = Object();

class VoiceCapsule {
  VoiceCapsule({
    required this.file,
    required this.durationMs,
    required this.disguise,
    required this.waveform,
  }) : upload = ProfileUpload(file: file, kind: 'audio', disguise: disguise);
  final XFile file;
  final int durationMs;
  final bool disguise;
  final List<double> waveform;
  final ProfileUpload upload;
}

class OnboardingVoiceState {
  const OnboardingVoiceState({
    this.capsule,
    this.elapsedMs = 0,
    this.recording = false,
    this.busy = false,
    this.playing = false,
    this.disguise = true,
    this.saved = false,
    this.levels = const [],
    this.error,
  });
  final VoiceCapsule? capsule;
  final int elapsedMs;
  final bool recording, busy, playing, disguise, saved;
  final List<double> levels;
  final String? error;
  OnboardingVoiceState copyWith({
    Object? capsule = _unset,
    int? elapsedMs,
    bool? recording,
    bool? busy,
    bool? playing,
    bool? disguise,
    bool? saved,
    List<double>? levels,
    String? error,
  }) => OnboardingVoiceState(
    capsule: identical(capsule, _unset)
        ? this.capsule
        : capsule as VoiceCapsule?,
    elapsedMs: elapsedMs ?? this.elapsedMs,
    recording: recording ?? this.recording,
    busy: busy ?? this.busy,
    playing: playing ?? this.playing,
    disguise: disguise ?? this.disguise,
    saved: saved ?? this.saved,
    levels: levels ?? this.levels,
    error: error,
  );
}

class _CaptureSession {
  _CaptureSession(this.makeDevice, this.makePlayer);
  final ProfileDevice Function() makeDevice;
  final ProfilePlayer Function() makePlayer;
  ProfileDevice? _device;
  ProfilePlayer? _player;
  ProfileDevice get device => _device ??= makeDevice();
  ProfilePlayer get player => _player ??= makePlayer();
  Timer? ticker, deadline;
  StreamSubscription<double>? amplitude;
  StreamSubscription<bool>? interruptions;
  bool closed = false, active = false, foreground = true;
  int elapsedMs = 0, previewGeneration = 0;
  Future<void> _tail = Future.value();
  Future<void>? _closing;
  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void cancelRecordingTimers() {
    ticker?.cancel();
    deadline?.cancel();
  }

  void cancelMonitors() {
    final samples = amplitude, events = interruptions;
    amplitude = null;
    interruptions = null;
    if (samples != null) unawaited(samples.cancel().catchError((Object _) {}));
    if (events != null) unawaited(events.cancel().catchError((Object _) {}));
  }

  Future<void> pause() async {
    previewGeneration++;
    await _player?.pause();
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    closed = true;
    active = false;
    cancelRecordingTimers();
    return _closing = () async {
      cancelMonitors();
      await pause().catchError((Object _) {});
      await run(() async {
        try {
          await _device?.dispose();
        } finally {
          await _player?.dispose();
        }
      });
    }();
  }
}

class OnboardingVoiceController extends Notifier<OnboardingVoiceState> {
  late _CaptureSession _session;
  @override
  OnboardingVoiceState build() {
    ref.watch(authControllerProvider.select((value) => value.session?.userId));
    final session = _session = _CaptureSession(
      ref.watch(profileDeviceProvider),
      ref.watch(profilePlayerProvider),
    );
    ref.onDispose(() {
      unawaited(session.close().catchError((Object _) {}));
    });
    return const OnboardingVoiceState();
  }

  bool _current(_CaptureSession session) =>
      ref.mounted && identical(session, _session) && !session.closed;
  Object attach() {
    _session.active = true;
    return _session;
  }

  void detach(Object lease) {
    if (!identical(lease, _session)) return;
    _session.active = false;
    scheduleMicrotask(() {
      if (_current(lease as _CaptureSession)) unawaited(suspend());
    });
  }

  Future<void> setForeground(Object lease, bool foreground) async {
    if (!identical(lease, _session)) return;
    _session.foreground = foreground;
    if (!foreground) await suspend();
  }

  Future<void> suspend() async {
    final session = _session;
    if (!_current(session)) return;
    await stop();
    await stopPreview();
  }

  Future<void> start() async {
    final session = _session;
    if (!_current(session) ||
        !session.active ||
        !session.foreground ||
        state.busy ||
        state.recording) {
      return;
    }
    state = state.copyWith(busy: true);
    try {
      await stopPreview();
      await session.run(() async {
        if (session.closed || !session.active || !session.foreground) return;
        await session.device.startRecording();
        if (!_current(session) || !session.active || !session.foreground) {
          await session.device.stopRecording();
          return;
        }
        session.elapsedMs = 0;
        state = state.copyWith(
          capsule: null,
          elapsedMs: 0,
          recording: true,
          saved: false,
          levels: const [],
        );
        session.amplitude = session.device.amplitudes.listen((db) {
          if (!_current(session) || !state.recording || !db.isFinite) return;
          final levels = [...state.levels, ((db + 60) / 60).clamp(.04, 1.0)];
          state = state.copyWith(
            levels: List.unmodifiable(
              levels.length > 28 ? levels.sublist(levels.length - 28) : levels,
            ),
          );
        }, onError: (Object _) {});
        session.interruptions = session.device.recordingInterruptions.listen(
          (_) {
            if (_current(session) && state.recording) {
              unawaited(stop(interrupted: true));
            }
          },
          onError: (Object _) {
            if (_current(session)) unawaited(stop(interrupted: true));
          },
        );
        session.ticker = Timer.periodic(const Duration(milliseconds: 100), (
          timer,
        ) {
          if (!_current(session) || !state.recording) return;
          session.elapsedMs = (timer.tick * 100).clamp(0, 15000);
          state = state.copyWith(elapsedMs: session.elapsedMs);
        });
        session.deadline = Timer(const Duration(seconds: 15), () {
          if (_current(session)) unawaited(stop());
        });
      });
    } on ApiException catch (error) {
      if (_current(session)) state = state.copyWith(error: error.code);
    } catch (_) {
      if (_current(session)) state = state.copyWith(error: 'recording_failed');
    } finally {
      if (_current(session)) {
        state = state.copyWith(busy: false, error: state.error);
      }
    }
  }

  Future<void> stop({bool interrupted = false}) async {
    final session = _session;
    if (!_current(session) || !state.recording) return;
    session.cancelRecordingTimers();
    state = state.copyWith(recording: false, busy: true);
    try {
      // Stopping the microphone must not wait for visual stream cleanup.
      session.cancelMonitors();
      final file = await session.run(() => session.device.stopRecording());
      if (!_current(session)) return;
      if (file == null || session.elapsedMs < 500 || await file.length() == 0) {
        throw const ApiException('voice_too_short');
      }
      if (!_current(session)) return;
      final capsule = VoiceCapsule(
        file: file,
        durationMs: session.elapsedMs,
        disguise: state.disguise,
        waveform: state.levels,
      );
      state = state.copyWith(
        capsule: capsule,
        error: interrupted ? 'recording_interrupted' : null,
      );
    } on ApiException catch (error) {
      if (_current(session)) {
        state = state.copyWith(capsule: null, error: error.code);
      }
    } catch (_) {
      if (_current(session)) {
        state = state.copyWith(capsule: null, error: 'recording_failed');
      }
    } finally {
      if (_current(session)) {
        state = state.copyWith(busy: false, error: state.error);
      }
    }
  }

  void setDisguise(bool value) {
    if (state.busy || state.recording) return;
    final capsule = state.capsule;
    state = state.copyWith(
      disguise: value,
      saved: false,
      capsule: capsule == null
          ? null
          : VoiceCapsule(
              file: capsule.file,
              durationMs: capsule.durationMs,
              disguise: value,
              waveform: capsule.waveform,
            ),
    );
  }

  bool saveDraft() {
    if (state.capsule == null || state.recording || state.busy) return false;
    state = state.copyWith(saved: true);
    return true;
  }

  Future<void> preview() async {
    final session = _session, capsule = state.capsule;
    if (!_current(session) ||
        capsule == null ||
        state.recording ||
        state.busy ||
        !session.active ||
        !session.foreground) {
      return;
    }
    if (state.playing) {
      await stopPreview();
      return;
    }
    final generation = ++session.previewGeneration;
    state = state.copyWith(playing: true);
    try {
      await session.player.play(capsule.file.path, local: true);
    } catch (_) {
      if (_current(session) && generation == session.previewGeneration) {
        state = state.copyWith(error: 'preview_failed');
      }
    } finally {
      if (_current(session) && generation == session.previewGeneration) {
        state = state.copyWith(playing: false, error: state.error);
      }
    }
  }

  Future<void> stopPreview() async {
    final session = _session;
    try {
      await session.pause();
    } catch (_) {}
    if (_current(session)) {
      state = state.copyWith(playing: false, error: state.error);
    }
  }

  Future<void> discard() async {
    final session = _session;
    if (state.busy) return;
    await suspend();
    if (!_current(session)) return;
    state = state.copyWith(busy: true);
    try {
      await session.run(() async {
        await session._device?.dispose();
        session._device = null;
      });
      if (_current(session)) state = const OnboardingVoiceState();
    } finally {
      if (_current(session)) {
        state = state.copyWith(busy: false, error: state.error);
      }
    }
  }

  Future<void> clearAfterCompletion() async {
    final session = _session;
    try {
      await session.close();
    } catch (_) {
      /* A local cleanup failure must not report a committed server save as failed. */
    } finally {
      if (ref.mounted && identical(_session, session)) ref.invalidateSelf();
    }
  }
}
