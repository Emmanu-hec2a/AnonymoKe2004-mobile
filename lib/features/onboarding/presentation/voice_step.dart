import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/voice_controller.dart';

class VoiceStep extends ConsumerStatefulWidget {
  const VoiceStep({required this.onContinue, super.key});
  final Future<void> Function() onContinue;
  @override
  ConsumerState<VoiceStep> createState() => _VoiceStepState();
}

class _VoiceStepState extends ConsumerState<VoiceStep>
    with WidgetsBindingObserver {
  late final OnboardingVoiceController _controller;
  late final Object _lease;
  bool _advancing = false;
  @override
  void initState() {
    super.initState();
    _controller = ref.read(onboardingVoiceProvider.notifier);
    _lease = _controller.attach();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.detach(_lease);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(
      _controller.setForeground(_lease, state == AppLifecycleState.resumed),
    );
  }

  Future<void> _continue({bool skip = false}) async {
    if (_advancing) return;
    setState(() => _advancing = true);
    try {
      await _controller.stopPreview();
      if (skip) {
        await _controller.discard();
      } else if (!_controller.saveDraft()) {
        return;
      }
      if (mounted) await widget.onContinue();
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  Widget _recordButton(OnboardingVoiceState voice) => SizedBox(
    width: 72,
    height: 72,
    child: IconButton.filled(
      key: const Key('voice-record'),
      tooltip: voice.recording ? 'Stop recording' : 'Start recording',
      onPressed: voice.busy || _advancing
          ? null
          : () => voice.recording ? _controller.stop() : _controller.start(),
      style: IconButton.styleFrom(
        backgroundColor: AppColors.coral,
        foregroundColor: AppColors.ink,
        shape: const CircleBorder(),
      ),
      icon: voice.busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              voice.recording ? Icons.stop_rounded : Icons.mic_none_rounded,
              size: 32,
            ),
    ),
  );
  Widget _controls(OnboardingVoiceState voice) {
    final enabled =
        voice.capsule != null && !voice.busy && !voice.recording && !_advancing;
    final again = OutlinedButton(
      onPressed: enabled ? _controller.start : null,
      child: const Text('Re-record'),
    );
    final preview = OutlinedButton(
      key: const Key('voice-preview'),
      onPressed: enabled ? _controller.preview : null,
      child: Text(voice.playing ? 'Stop preview' : 'Preview'),
    );
    if (MediaQuery.textScalerOf(context).scale(14) >= 21) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _recordButton(voice)),
          const SizedBox(height: 12),
          again,
          const SizedBox(height: 8),
          preview,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: again),
        const SizedBox(width: 12),
        _recordButton(voice),
        const SizedBox(width: 12),
        Expanded(child: preview),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final voice = ref.watch(onboardingVoiceProvider);
    final milliseconds = voice.recording
        ? voice.elapsedMs
        : voice.capsule?.durationMs ?? 0;
    final seconds = voice.recording
        ? milliseconds ~/ 1000
        : (milliseconds / 1000).ceil();
    final progress = (milliseconds / 15000).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle(
                  'Record your voice capsule',
                  subtitle:
                      '15 seconds. Say hi and tell people what you are like.',
                ),
                const SizedBox(height: 30),
                Center(
                  child: Semantics(
                    label: voice.recording
                        ? 'Recording, $seconds of 15 seconds'
                        : 'Voice capsule, $seconds of 15 seconds',
                    child: ExcludeSemantics(
                      child: SizedBox(
                        width: 202,
                        height: 202,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const SizedBox.expand(
                              child: CircularProgressIndicator(
                                value: 1,
                                strokeWidth: 7,
                                color: AppColors.line,
                              ),
                            ),
                            SizedBox.expand(
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 7,
                                color: AppColors.coral,
                                strokeCap: StrokeCap.round,
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (voice.recording) ...[
                                      const Icon(
                                        Icons.circle,
                                        color: AppColors.coral,
                                        size: 8,
                                      ),
                                      const SizedBox(width: 7),
                                    ],
                                    Text(
                                      voice.recording
                                          ? 'RECORDING'
                                          : voice.capsule != null
                                          ? 'RECORDED'
                                          : 'READY',
                                      textScaler: TextScaler.noScaling,
                                      style: TextStyle(
                                        color:
                                            voice.capsule != null ||
                                                voice.recording
                                            ? AppColors.coral
                                            : AppColors.muted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: .8,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '0:${seconds.toString().padLeft(2, '0')}',
                                  textScaler: TextScaler.noScaling,
                                  style: const TextStyle(
                                    fontSize: 42,
                                    fontWeight: FontWeight.w800,
                                    height: .95,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                const Text(
                                  'of 0:15 max',
                                  textScaler: TextScaler.noScaling,
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Center(
                  child: CustomPaint(
                    size: const Size(240, 58),
                    painter: _VoiceWaveform(
                      voice.levels,
                      voice.recording || voice.capsule != null,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _controls(voice),
                if (voice.capsule != null) ...[
                  const SizedBox(height: 10),
                  const Center(
                    child: Text(
                      'Preview plays your original recording.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Disguise my voice',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'A voice can identify you. Pitch-shift it before sharing.',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Checkbox(
                        key: const Key('voice-disguise'),
                        value: voice.disguise,
                        onChanged: voice.recording || voice.busy || _advancing
                            ? null
                            : (value) => _controller.setDisguise(value ?? true),
                        activeColor: AppColors.accent,
                        checkColor: Colors.white,
                      ),
                    ],
                  ),
                ),
                if (voice.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error(voice.error!),
                        style: const TextStyle(
                          color: AppColors.coral,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    key: const Key('voice-save'),
                    onPressed:
                        voice.capsule == null ||
                            voice.recording ||
                            voice.busy ||
                            _advancing
                        ? null
                        : _continue,
                    child: const Text('Save capsule'),
                  ),
                ),
                const SizedBox(height: 12),
                const Center(
                  child: Text(
                    'Your recording stays on this phone for now. Choose whether to share it in your privacy choices.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
                Center(
                  child: TextButton(
                    key: const Key('voice-skip'),
                    onPressed: voice.recording || voice.busy || _advancing
                        ? null
                        : () => _continue(skip: true),
                    child: const Text('Skip for now'),
                  ),
                ),
                const Center(
                  child: Text(
                    'Only people you appear to can hear a shared capsule. Delete it any time in Settings.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _error(String code) => switch (code) {
    'microphone_permission_denied' =>
      'Microphone access was denied. Allow it in your phone settings to record, or skip for now.',
    'voice_too_short' => 'Record for at least half a second, then try again.',
    'recording_interrupted' =>
      'Recording was interrupted. Preview what was captured or re-record.',
    'preview_failed' =>
      'Could not play this recording. Try again or re-record.',
    _ => 'Could not record your voice. Try again or skip for now.',
  };
}

class _VoiceWaveform extends CustomPainter {
  const _VoiceWaveform(this.levels, this.active);
  final List<double> levels;
  final bool active;
  @override
  void paint(Canvas canvas, Size size) {
    const count = 28;
    final paint = Paint()
      ..color = (active ? AppColors.accentSoft : AppColors.line)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < count; index++) {
      final sample = index < levels.length ? levels[index] : .04;
      final height = sample * (size.height - 4);
      final x = (index + .5) * size.width / count;
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveform oldDelegate) =>
      oldDelegate.levels != levels || oldDelegate.active != active;
}
