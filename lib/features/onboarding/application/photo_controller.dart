import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_client.dart';
import '../../home/presentation/profile_device.dart';

final photoPreparerProvider = Provider<Future<PhotoDraft> Function(XFile)>(
  (_) => preparePhoto,
);
final photoPollDelayProvider = Provider<Future<void> Function(Duration)>(
  (_) =>
      (duration) => Future<void>.delayed(duration),
);
final onboardingPhotoProvider =
    NotifierProvider<OnboardingPhotoController, OnboardingPhotoState>(
      OnboardingPhotoController.new,
    );
const _unchanged = Object();

class PhotoDraft {
  PhotoDraft({required this.privateBytes, required this.blurredBytes})
    : upload = ProfileUpload(
        file: XFile.fromData(
          privateBytes,
          mimeType: 'image/png',
          name: 'profile.png',
        ),
        kind: 'avatar',
      );
  final Uint8List privateBytes, blurredBytes;
  final ProfileUpload upload;
  Future<void> release() async {
    await MemoryImage(privateBytes).evict();
    await MemoryImage(blurredBytes).evict();
  }

  Future<MediaAssetSummary> validateOnServer(
    ApiClient api, {
    required void Function() checkCurrent,
    required Future<void> Function(Duration) delay,
  }) async {
    var result = await upload.send(api, checkCurrent: checkCurrent);
    checkCurrent();
    if (result.id.isEmpty ||
        result.id != upload.uploadId ||
        result.kind != 'avatar') {
      throw const ApiException('photo_validation_failed');
    }
    final uploadId = result.id;
    final waiting = Stopwatch()..start();
    for (
      var attempt = 0;
      result.status == 'processing' && attempt < 15;
      attempt++
    ) {
      await delay(const Duration(seconds: 2));
      checkCurrent();
      final remaining = const Duration(seconds: 30) - waiting.elapsed;
      if (remaining <= Duration.zero) {
        throw const ApiException('photo_processing_pending');
      }
      result = await api
          .mediaUploadStatus(uploadId)
          .timeout(
            remaining,
            onTimeout: () =>
                throw const ApiException('photo_processing_pending'),
          );
      checkCurrent();
      if (result.id != uploadId || result.kind != 'avatar') {
        throw const ApiException('photo_validation_failed');
      }
    }
    if (result.status == 'rejected') {
      throw ApiException(
        result.rejectionCode.isEmpty
            ? 'photo_validation_failed'
            : result.rejectionCode,
      );
    }
    if (result.status != 'ready') {
      throw const ApiException('photo_processing_pending');
    }
    return result;
  }
}

Future<PhotoDraft> preparePhoto(XFile file) async {
  final size = await file.length();
  if (size == 0 || size > 10485760) {
    throw const ApiException('photo_size_invalid');
  }
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty || bytes.length > 10485760) {
    throw const ApiException('photo_size_invalid');
  }
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image, tiny, blurred;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width, height = descriptor.height;
    if (math.min(width, height) < 200 ||
        math.max(width, height) > 8000 ||
        width * height > 32000000) {
      throw const ApiException('avatar_dimensions_invalid');
    }
    final scale = math.min(1.0, 1600 / math.max(width, height));
    codec = await descriptor.instantiateCodec(
      targetWidth: (width * scale).round(),
      targetHeight: (height * scale).round(),
    );
    if (codec.frameCount != 1) {
      throw const ApiException('avatar_still_photo_required');
    }
    image = (await codec.getNextFrame()).image;
    final original = await image.toByteData(format: ui.ImageByteFormat.png);
    if (original == null) throw const ApiException('photo_invalid');
    final side = math.min(image.width, image.height).toDouble();
    final square = ui.Rect.fromLTWH(
      (image.width - side) / 2,
      (image.height - side) / 2,
      side,
      side,
    );
    tiny = await _raster(
      48,
      (canvas) => canvas.drawImageRect(
        image!,
        square,
        const ui.Rect.fromLTWH(0, 0, 48, 48),
        ui.Paint()..filterQuality = ui.FilterQuality.low,
      ),
    );
    blurred = await _raster(
      48,
      (canvas) => canvas.drawImage(
        tiny!,
        ui.Offset.zero,
        ui.Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: 3.5,
            sigmaY: 3.5,
            tileMode: ui.TileMode.clamp,
          ),
      ),
    );
    final preview = await blurred.toByteData(format: ui.ImageByteFormat.png);
    if (preview == null) throw const ApiException('photo_invalid');
    return PhotoDraft(
      privateBytes: original.buffer.asUint8List(
        original.offsetInBytes,
        original.lengthInBytes,
      ),
      blurredBytes: preview.buffer.asUint8List(
        preview.offsetInBytes,
        preview.lengthInBytes,
      ),
    );
  } on ApiException {
    rethrow;
  } catch (_) {
    throw const ApiException('photo_invalid');
  } finally {
    blurred?.dispose();
    tiny?.dispose();
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

Future<ui.Image> _raster(int size, void Function(ui.Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(size, size);
  } finally {
    picture.dispose();
  }
}

class OnboardingPhotoState {
  const OnboardingPhotoState({
    this.draft,
    this.busy = false,
    this.saved = false,
    this.rejected = false,
    this.error,
  });
  final PhotoDraft? draft;
  final bool busy, saved, rejected;
  final String? error;
  OnboardingPhotoState copyWith({
    Object? draft = _unchanged,
    bool? busy,
    bool? saved,
    bool? rejected,
    String? error,
  }) => OnboardingPhotoState(
    draft: identical(draft, _unchanged) ? this.draft : draft as PhotoDraft?,
    busy: busy ?? this.busy,
    saved: saved ?? this.saved,
    rejected: rejected ?? this.rejected,
    error: error,
  );
}

class OnboardingPhotoController extends Notifier<OnboardingPhotoState> {
  int _generation = 0;
  PhotoDraft? _owned;
  bool _active = false;
  Object? _lease;
  @override
  OnboardingPhotoState build() {
    ref.watch(authControllerProvider.select((value) => value.session?.userId));
    _generation++;
    _owned = null;
    _active = false;
    final resources = <PhotoDraft>{};
    ref.onDispose(() {
      for (final draft in resources) {
        unawaited(draft.release().catchError((Object _) {}));
      }
    });
    _track = resources;
    return const OnboardingPhotoState();
  }

  late Set<PhotoDraft> _track;
  Object attach() {
    _active = true;
    return _lease = Object();
  }

  void detach(Object lease) {
    if (!identical(_lease, lease)) return;
    _active = false;
    final generation = ++_generation;
    scheduleMicrotask(() {
      if (ref.mounted && generation == _generation) {
        state = state.copyWith(busy: false, error: state.error);
      }
    });
  }

  Future<void> pick(ImageSource source) async {
    if (state.busy || !_active) return;
    final generation = _generation, lease = _lease;
    bool current() =>
        ref.mounted &&
        generation == _generation &&
        identical(lease, _lease) &&
        _active;
    final device = ref.read(profileDeviceProvider)();
    final prepare = ref.read(photoPreparerProvider);
    state = state.copyWith(busy: true);
    try {
      final file = await device.pickPhoto(source);
      if (file == null || !current()) return;
      final draft = await prepare(file);
      if (!current()) {
        await draft.release();
        return;
      }
      final previous = _owned;
      _owned = draft;
      _track.add(draft);
      state = state.copyWith(draft: draft, saved: false, rejected: false);
      if (previous != null) {
        _track.remove(previous);
        unawaited(previous.release().catchError((Object _) {}));
      }
    } on ApiException catch (error) {
      if (current()) state = state.copyWith(error: error.code);
    } on PlatformException catch (error) {
      if (current()) {
        state = state.copyWith(
          error:
              error.code.contains('denied') || error.code.contains('restricted')
              ? 'photo_permission_denied'
              : 'photo_access_failed',
        );
      }
    } catch (_) {
      if (current()) state = state.copyWith(error: 'photo_access_failed');
    } finally {
      // A camera/gallery operation is allowed to background the app. Route/account
      // changes discard its result, while returning normally accepts it.
      if (ref.mounted &&
          generation == _generation &&
          identical(lease, _lease)) {
        state = state.copyWith(busy: false, error: state.error);
      }
      unawaited(device.dispose().catchError((Object _) {}));
    }
  }

  bool saveDraft() {
    if (state.draft == null || state.busy || state.rejected) return false;
    state = state.copyWith(saved: true);
    return true;
  }

  Future<void> remove() async {
    if (state.busy) return;
    final draft = _owned;
    _owned = null;
    state = const OnboardingPhotoState();
    if (draft != null) {
      _track.remove(draft);
      await draft.release().catchError((Object _) {});
    }
  }

  Future<void> clearAfterCompletion() async {
    await remove();
  }

  void reject(PhotoDraft expected, String code) {
    if (identical(state.draft, expected)) {
      state = state.copyWith(saved: false, rejected: true, error: code);
    }
  }
}
