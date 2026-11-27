import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import '../../../core/network/api_client.dart';

abstract class ProfileDevice {
  Future<XFile?> pickPhoto(ImageSource source);
  Future<XFile?> recoverPhoto() async => null;
  Future<void> startRecording();
  Future<XFile?> stopRecording();
  Stream<double> get amplitudes => const Stream.empty();
  Stream<bool> get recordingInterruptions => const Stream.empty();
  Future<void> dispose();
}

final profileDeviceProvider = Provider<ProfileDevice Function()>(
  (_) => NativeProfileDevice.new,
);

class NativeProfileDevice implements ProfileDevice {
  NativeProfileDevice({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;
  AudioRecorder? _recorder;
  final _recordPaths = <String>[];
  bool _disposed = false;
  @override
  Stream<double> get amplitudes => _recorder == null
      ? const Stream.empty()
      : _recorder!
            .onAmplitudeChanged(const Duration(milliseconds: 100))
            .map((value) => value.current);
  @override
  Stream<bool> get recordingInterruptions => _recorder == null
      ? const Stream.empty()
      : _recorder!
            .onStateChanged()
            .where((value) => value != RecordState.record)
            .map((_) => true);
  @override
  Future<XFile?> pickPhoto(ImageSource source) async {
    return _picker.pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
      requestFullMetadata: false,
    );
  }

  @override
  Future<XFile?> recoverPhoto() async {
    if (!Platform.isAndroid) return null;
    final lost = await _picker.retrieveLostData();
    return lost.files?.isNotEmpty == true ? lost.files!.first : null;
  }

  @override
  Future<void> startRecording() async {
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) {
      throw const ApiException('microphone_permission_denied');
    }
    if (_disposed) throw const ApiException('recording_cancelled');
    final path =
        '${(await getTemporaryDirectory()).path}/anonymoke-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
    if (_disposed) throw const ApiException('recording_cancelled');
    _recordPaths.add(path);
    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 96000,
        sampleRate: 48000,
        numChannels: 1,
      ),
      path: path,
    );
  }

  @override
  Future<XFile?> stopRecording() async {
    final path = await _recorder?.stop();
    return path == null ? null : XFile(path, mimeType: 'audio/mp4');
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _recorder?.dispose();
    for (final path in _recordPaths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }
}

abstract class ProfilePlayer {
  Future<void> play(String source, {bool local = false});
  Future<void> pause();
  Future<void> dispose();
}

final profilePlayerProvider = Provider<ProfilePlayer Function()>(
  (_) => NativeProfilePlayer.new,
);

class NativeProfilePlayer implements ProfilePlayer {
  AudioPlayer? _player;
  @override
  Future<void> play(String source, {bool local = false}) async {
    final player = _player ??= AudioPlayer();
    if (local) {
      await player.setFilePath(source);
    } else {
      await player.setUrl(source);
    }
    await player.play();
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
  }

  @override
  Future<void> dispose() async {
    await _player?.dispose();
  }
}

class ProfileUpload {
  ProfileUpload({required this.file, required this.kind, this.disguise = true});
  final XFile file;
  final String kind;
  final bool disguise;
  Map<String, dynamic>? _ticket;
  bool _uploaded = false;
  String? _rejected;
  Future<MediaAssetSummary>? _sending;
  String? get uploadId => _ticket?['upload_id'] as String?;
  Future<MediaAssetSummary> send(
    ApiClient api, {
    void Function()? checkCurrent,
  }) {
    if (_sending != null) return _sending!;
    late final Future<MediaAssetSummary> operation;
    operation = _send(api, checkCurrent: checkCurrent).whenComplete(() {
      if (identical(_sending, operation)) _sending = null;
    });
    return _sending = operation;
  }

  Future<MediaAssetSummary> _send(
    ApiClient api, {
    void Function()? checkCurrent,
  }) async {
    if (_rejected != null) throw ApiException(_rejected!);
    checkCurrent?.call();
    final size = await file.length();
    if (size <= 0 || size > (kind == 'avatar' ? 10485760 : 5242880)) {
      throw const ApiException('media_too_large');
    }
    final bytes = await file.readAsBytes();
    checkCurrent?.call();
    var type = 'audio/mp4';
    if (kind == 'avatar') {
      type = bytes.length > 8 && bytes[0] == 137 && bytes[1] == 80
          ? 'image/png'
          : bytes.length > 12 && bytes[8] == 87 && bytes[9] == 69
          ? 'image/webp'
          : 'image/jpeg';
    }
    _ticket ??= await api.requestMediaUpload(
      kind: kind,
      contentType: type,
      sizeBytes: bytes.length,
      disguiseVoice: disguise,
    );
    checkCurrent?.call();
    try {
      if (!_uploaded) {
        await api.putMedia(_ticket!, bytes);
        _uploaded = true;
      }
      checkCurrent?.call();
      final result = await api.completeMediaUpload(
        _ticket!['upload_id'] as String,
      );
      if (result.status == 'rejected') {
        _rejected = result.rejectionCode.isEmpty
            ? 'photo_validation_failed'
            : result.rejectionCode;
      }
      return result;
    } on ApiException catch (e) {
      if (e.code == 'media_upload_expired') {
        _ticket = null;
        _uploaded = false;
      }
      rethrow;
    }
  }
}

// The OS Save File picker requests an explicit destination; no share sheet or auto-send.
final profileExportProvider =
    Provider<Future<bool> Function(Map<String, dynamic>)>(
      (_) => (payload) async {
        return await const MethodChannel(
              'anonymoke/files',
            ).invokeMethod<bool>('saveJson', {
              'filename': 'anonymoke-data.json',
              'contents': const JsonEncoder.withIndent('  ').convert(payload),
            }) ??
            false;
      },
    );
