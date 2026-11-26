import 'dart:async';
import 'dart:typed_data';

import 'package:anonymoke/core/auth/auth_controller.dart';
import 'package:anonymoke/core/network/api_client.dart';
import 'package:anonymoke/features/home/presentation/profile_device.dart';
import 'package:anonymoke/features/onboarding/application/onboarding_controller.dart';
import 'package:anonymoke/features/onboarding/application/voice_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'onboarding_about_you_test.dart'
    show OnboardingApi, OnboardingAuth, openAbout;

class Capture extends ProfileDevice {
  int starts = 0, stops = 0, disposals = 0;
  bool deny = false, empty = false;
  Completer<void>? permission;
  final amplitude = StreamController<double>.broadcast();
  final interrupted = StreamController<bool>.broadcast();
  @override
  Stream<double> get amplitudes => amplitude.stream;
  @override
  Stream<bool> get recordingInterruptions => interrupted.stream;
  @override
  Future<XFile?> pickPhoto(ImageSource source) async => null;
  @override
  Future<void> startRecording() async {
    await permission?.future;
    if (deny) throw const ApiException('microphone_permission_denied');
    starts++;
  }

  @override
  Future<XFile?> stopRecording() async {
    stops++;
    return XFile.fromData(
      Uint8List(empty ? 0 : 32),
      name: 'voice.m4a',
      path: '/local/voice-$starts.m4a',
      mimeType: 'audio/mp4',
    );
  }

  @override
  Future<void> dispose() async {
    disposals++;
    await amplitude.close();
    await interrupted.close();
  }
}

class Preview extends ProfilePlayer {
  int plays = 0, pauses = 0, disposals = 0;
  String? source;
  bool? local;
  bool fail = false;
  Completer<void>? playing;
  @override
  Future<void> play(String source, {bool local = false}) async {
    if (fail) throw StateError('player unavailable');
    plays++;
    this.source = source;
    this.local = local;
    await (playing = Completer<void>()).future;
  }

  @override
  Future<void> pause() async {
    pauses++;
    if (playing?.isCompleted == false) playing!.complete();
  }

  @override
  Future<void> dispose() async {
    disposals++;
    await pause();
  }
}

class VoiceApi extends OnboardingApi {
  int tickets = 0, puts = 0, completions = 0;
  bool? disguise;
  bool failComplete = false, reject = false;
  Completer<void>? ticketWait;
  @override
  Future<Map<String, dynamic>> requestMediaUpload({
    required String kind,
    required String contentType,
    required int sizeBytes,
    bool disguiseVoice = true,
  }) async {
    calls.add('ticket');
    tickets++;
    disguise = disguiseVoice;
    await ticketWait?.future;
    return {
      'upload_id': 'upload-$tickets',
      'upload_url': 'https://storage.test/upload',
    };
  }

  @override
  Future<void> putMedia(Map<String, dynamic> ticket, List<int> bytes) async {
    calls.add('put');
    puts++;
  }

  @override
  Future<MediaAssetSummary> completeMediaUpload(String id) async {
    calls.add('complete:$id');
    completions++;
    if (failComplete) throw const ApiException('network_error', 503);
    return MediaAssetSummary(
      id: id,
      kind: 'audio',
      status: reject ? 'rejected' : 'processing',
      rejectionCode: reject ? 'audio_duration_invalid' : '',
    );
  }
}

class VoiceHarness {
  VoiceHarness(
    this.container,
    this.api,
    this.capture,
    this.player,
    this.router,
  );
  final ProviderContainer container;
  final VoiceApi api;
  final Capture capture;
  final Preview player;
  final GoRouter router;
  OnboardingVoiceController get voice =>
      container.read(onboardingVoiceProvider.notifier);
  OnboardingVoiceState get state => container.read(onboardingVoiceProvider);
  OnboardingController get onboarding =>
      container.read(onboardingControllerProvider.notifier);
}

Future<VoiceHarness> openVoice(
  WidgetTester tester, {
  Capture? capture,
  Preview? player,
  VoiceApi? api,
  double width = 390,
  double scale = 1,
}) async {
  capture ??= Capture();
  player ??= Preview();
  api ??= VoiceApi();
  final recorder = capture, preview = player;
  final (container, _, router) = await openAbout(
    tester,
    device: () => recorder,
    player: () => preview,
    apiOverride: api,
    width: width,
    scale: scale,
  );
  router.go('/onboarding/3');
  await tester.pumpAndSettle();
  return VoiceHarness(container, api, recorder, preview, router);
}

Future<void> record(
  WidgetTester tester, {
  Duration duration = const Duration(seconds: 2),
  bool stop = true,
}) async {
  await tester.ensureVisible(find.byKey(const Key('voice-record')));
  await tester.tap(find.byKey(const Key('voice-record')));
  await tester.pump();
  await tester.pump(duration);
  if (stop) {
    await tester.tap(find.byKey(const Key('voice-record')));
    await tester.pumpAndSettle();
  }
}

Future<void> saveDraft(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('voice-save')));
  await tester.tap(find.byKey(const Key('voice-save')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a delayed microphone permission response after an account switch is stopped and discarded',
    (tester) async {
      final device = Capture()..permission = Completer<void>();
      final h = await openVoice(tester, capture: device);
      await tester.tap(find.byKey(const Key('voice-record')));
      await tester.pump();
      (h.container.read(authControllerProvider.notifier) as OnboardingAuth)
          .switchAccount();
      await tester.pump();
      device.permission!.complete();
      await tester.pumpAndSettle();
      expect(device.stops, 1);
      expect(device.disposals, 1);
      expect(h.state.capsule, isNull);
      expect(h.state.recording, isFalse);
      expect(h.api.calls, isEmpty);
    },
  );

  testWidgets(
    'backgrounding stops a local preview and does not resume it automatically',
    (tester) async {
      final h = await openVoice(tester);
      await record(tester);
      await tester.tap(find.byKey(const Key('voice-preview')));
      await tester.pump();
      expect(h.state.playing, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(h.state.playing, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(h.player.plays, 1);
    },
  );

  testWidgets(
    'entry has no fake recording and does not request microphone or network access',
    (tester) async {
      final h = await openVoice(tester);
      expect(find.text('READY'), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(find.byKey(const Key('voice-save')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('voice-preview')))
            .onPressed,
        isNull,
      );
      expect(h.capture.starts, 0);
      expect(h.api.calls, isEmpty);
    },
  );

  testWidgets(
    'recording uses microphone samples and saves its actual elapsed time',
    (tester) async {
      final h = await openVoice(tester);
      await record(tester, duration: const Duration(seconds: 9), stop: false);
      h.capture.amplitude.add(-12);
      await tester.pump();
      expect(h.state.recording, isTrue);
      expect(find.text('0:09'), findsOneWidget);
      expect(h.state.levels.last, closeTo(.8, .01));
      await tester.tap(find.byKey(const Key('voice-record')));
      await tester.pumpAndSettle();
      expect(h.state.capsule!.durationMs, 9000);
      expect(h.capture.stops, 1);
      expect(h.api.calls, isEmpty);
    },
  );

  testWidgets('fifteen second deadline stops the recorder exactly once', (
    tester,
  ) async {
    final h = await openVoice(tester);
    await record(tester, duration: const Duration(seconds: 15), stop: false);
    await tester.pumpAndSettle();
    expect(h.capture.stops, 1);
    expect(h.state.recording, isFalse);
    expect(h.state.capsule!.durationMs, 15000);
    expect(find.text('0:15'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(h.capture.stops, 1);
  });

  testWidgets('permission denial remains recoverable through Skip for now', (
    tester,
  ) async {
    final h = await openVoice(tester, capture: Capture()..deny = true);
    await tester.tap(find.byKey(const Key('voice-record')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Microphone access was denied'), findsOneWidget);
    expect(h.state.capsule, isNull);
    await tester.ensureVisible(find.byKey(const Key('voice-skip')));
    await tester.tap(find.byKey(const Key('voice-skip')));
    await tester.pumpAndSettle();
    expect(h.router.routeInformationProvider.value.uri.path, '/onboarding/4');
    expect(h.api.calls, isEmpty);
  });

  testWidgets(
    'backgrounding stops capture and preview until the user starts again',
    (tester) async {
      final h = await openVoice(tester);
      await record(tester, stop: false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(h.capture.stops, 1);
      expect(h.state.recording, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(h.capture.starts, 1);
    },
  );

  testWidgets(
    'leaving the voice step stops recording without losing the captured local draft',
    (tester) async {
      final h = await openVoice(tester);
      await record(tester, stop: false);
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(h.state.recording, isFalse);
      expect(h.capture.stops, 1);
      expect(h.state.capsule, isNotNull);
      expect(h.api.calls, isEmpty);
    },
  );

  testWidgets(
    'permission completing after backgrounding cannot leave a hidden recording running',
    (tester) async {
      final device = Capture()..permission = Completer<void>();
      final h = await openVoice(tester, capture: device);
      await tester.tap(find.byKey(const Key('voice-record')));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      device.permission!.complete();
      await tester.pumpAndSettle();
      expect(h.state.recording, isFalse);
      expect(device.stops, 1);
      expect(h.state.capsule, isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );

  testWidgets(
    'recorder interruptions stop capture and explain what was retained',
    (tester) async {
      final h = await openVoice(tester);
      await record(tester, stop: false);
      h.capture.interrupted.add(true);
      await tester.pumpAndSettle();
      expect(h.capture.stops, 1);
      expect(h.state.capsule, isNotNull);
      expect(find.textContaining('Recording was interrupted'), findsOneWidget);
    },
  );

  testWidgets('Preview plays the local original and can be stopped', (
    tester,
  ) async {
    final h = await openVoice(tester);
    await record(tester);
    await tester.tap(find.byKey(const Key('voice-preview')));
    await tester.pump();
    expect(h.player.plays, 1);
    expect(h.player.source, '/local/voice-1.m4a');
    expect(h.player.local, isTrue);
    expect(h.state.playing, isTrue);
    expect(find.text('Preview plays your original recording.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice-preview')));
    await tester.pumpAndSettle();
    expect(h.state.playing, isFalse);
    expect(h.api.calls, isEmpty);
  });

  testWidgets('preview errors retain the recording for retry', (tester) async {
    final h = await openVoice(tester, player: Preview()..fail = true);
    await record(tester);
    await tester.tap(find.byKey(const Key('voice-preview')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not play this recording'),
      findsOneWidget,
    );
    expect(h.state.capsule, isNotNull);
    expect(h.state.playing, isFalse);
  });

  testWidgets('re-recording replaces the capsule and stops an active preview', (
    tester,
  ) async {
    final h = await openVoice(tester);
    await record(tester);
    await tester.tap(find.byKey(const Key('voice-preview')));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Re-record'));
    await tester.pump();
    expect(h.state.recording, isTrue);
    expect(h.state.playing, isFalse);
    expect(h.state.capsule, isNull);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.byKey(const Key('voice-record')));
    await tester.pumpAndSettle();
    expect(h.state.capsule!.file.path, '/local/voice-2.m4a');
    expect(h.state.capsule!.durationMs, 3000);
  });

  testWidgets(
    'disguise checkbox changes the capsule choice without uploading anything',
    (tester) async {
      final h = await openVoice(tester);
      await record(tester);
      await tester.ensureVisible(find.byKey(const Key('voice-disguise')));
      await tester.tap(find.byKey(const Key('voice-disguise')));
      await tester.pumpAndSettle();
      expect(h.state.capsule!.disguise, isFalse);
      expect(h.api.calls, isEmpty);
    },
  );

  testWidgets(
    'Save capsule retains a draft through step four and back without any upload',
    (tester) async {
      final h = await openVoice(tester);
      await record(tester);
      await saveDraft(tester);
      expect(h.router.routeInformationProvider.value.uri.path, '/onboarding/4');
      expect(h.state.saved, isTrue);
      expect(h.capture.disposals, 0);
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(find.text('0:02'), findsOneWidget);
      expect(h.api.calls, isEmpty);
    },
  );

  testWidgets(
    'Skip clears a recorded capsule and releases its temporary files',
    (tester) async {
      final h = await openVoice(tester);
      await record(tester);
      await tester.ensureVisible(find.byKey(const Key('voice-skip')));
      await tester.tap(find.byKey(const Key('voice-skip')));
      await tester.pumpAndSettle();
      expect(h.state.capsule, isNull);
      expect(h.capture.disposals, 1);
      expect(h.api.calls, isEmpty);
    },
  );

  for (final empty in [false, true]) {
    testWidgets(
      'short or empty recording (empty=$empty) cannot be saved as a capsule',
      (tester) async {
        final h = await openVoice(tester, capture: Capture()..empty = empty);
        await record(
          tester,
          duration: Duration(milliseconds: empty ? 1000 : 100),
        );
        expect(h.state.capsule, isNull);
        expect(find.textContaining('Record for at least'), findsOneWidget);
        expect(
          tester
              .widget<ElevatedButton>(find.byKey(const Key('voice-save')))
              .onPressed,
          isNull,
        );
      },
    );
  }

  testWidgets(
    'account changes remove the private draft and release recorder resources',
    (tester) async {
      final h = await openVoice(tester);
      await record(tester);
      (h.container.read(authControllerProvider.notifier) as OnboardingAuth)
          .switchAccount();
      await tester.pumpAndSettle();
      expect(h.state.capsule, isNull);
      expect(h.capture.disposals, 1);
      expect(h.api.calls, isEmpty);
    },
  );

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets(
      'voice controls remain readable at 320 width and text scale $scale',
      (tester) async {
        await openVoice(tester, width: 320, scale: scale);
        await record(tester);
        await tester.ensureVisible(find.byKey(const Key('voice-skip')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('voice-skip')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'final consent uploads the saved choice before completing the profile',
    (tester) async {
      final h = await openVoice(tester);
      await record(tester);
      h.voice.setDisguise(false);
      h.voice.saveDraft();
      h.onboarding.setVoiceConsent(true);
      await h.onboarding.complete();
      await tester.pumpAndSettle();
      expect(h.api.calls, [
        'consent:terms',
        'consent:privacy',
        'consent:sensitive_data',
        'consent:location',
        'consent:voice',
        'ticket',
        'put',
        'complete:upload-1',
        'profile',
      ]);
      expect(h.api.disguise, isFalse);
      expect(h.capture.disposals, 1);
      expect(h.state.capsule, isNull);
    },
  );

  testWidgets('declining voice consent never uploads the local draft', (
    tester,
  ) async {
    final h = await openVoice(tester);
    await record(tester);
    h.voice.saveDraft();
    h.onboarding.setVoiceConsent(false);
    await h.onboarding.complete();
    await tester.pumpAndSettle();
    expect(h.api.tickets, 0);
    expect(h.api.puts, 0);
    expect(h.capture.disposals, 1);
  });

  testWidgets(
    'an unsaved recording is never uploaded even when voice consent is granted',
    (tester) async {
      final h = await openVoice(tester);
      await record(tester);
      h.onboarding.setVoiceConsent(true);
      await h.onboarding.complete();
      await tester.pumpAndSettle();
      expect(h.api.tickets, 0);
    },
  );

  testWidgets(
    'ambiguous completion failure retries the same upload without sending bytes again',
    (tester) async {
      final h = await openVoice(tester, api: VoiceApi()..failComplete = true);
      await record(tester);
      h.voice.saveDraft();
      h.onboarding.setVoiceConsent(true);
      await expectLater(h.onboarding.complete(), throwsA(isA<ApiException>()));
      expect(h.api.profiles, isEmpty);
      expect(h.state.capsule, isNotNull);
      h.api.failComplete = false;
      await h.onboarding.complete();
      await tester.pumpAndSettle();
      expect(h.api.tickets, 1);
      expect(h.api.puts, 1);
      expect(h.api.completions, 2);
      expect(h.api.profiles, hasLength(1));
    },
  );

  testWidgets('rejected media cannot be reported as successful onboarding', (
    tester,
  ) async {
    final h = await openVoice(tester, api: VoiceApi()..reject = true);
    await record(tester);
    h.voice.saveDraft();
    h.onboarding.setVoiceConsent(true);
    await expectLater(
      h.onboarding.complete(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          'audio_duration_invalid',
        ),
      ),
    );
    expect(h.api.profiles, isEmpty);
    expect(h.state.capsule, isNotNull);
  });

  testWidgets(
    'switching accounts while obtaining an upload ticket prevents sending audio bytes',
    (tester) async {
      final h = await openVoice(
        tester,
        api: VoiceApi()..ticketWait = Completer<void>(),
      );
      await record(tester);
      h.voice.saveDraft();
      h.onboarding.setVoiceConsent(true);
      final saving = h.onboarding.complete();
      final check = expectLater(
        saving,
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'session_changed'),
        ),
      );
      await tester.pump();
      expect(h.api.tickets, 1);
      (h.container.read(authControllerProvider.notifier) as OnboardingAuth)
          .switchAccount();
      h.api.ticketWait!.complete();
      await check;
      await tester.pumpAndSettle();
      expect(h.api.puts, 0);
      expect(h.api.profiles, isEmpty);
    },
  );

  testWidgets(
    'active recording cannot be finalized through a deep link or repeated submit',
    (tester) async {
      final h = await openVoice(tester);
      await record(tester, stop: false);
      await expectLater(
        h.onboarding.complete(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'voice_recording_in_progress',
          ),
        ),
      );
      expect(h.api.calls, isEmpty);
    },
  );
}
